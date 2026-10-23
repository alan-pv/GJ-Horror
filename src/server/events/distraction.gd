class_name Distraction
extends RefCounted
## Distracciones que hacen voltear a quien está sentado (bots y figuras de las mesas de fondo).
## Lógica pura: tabla de tipos con su probabilidad base de voltear, cuánto miran y cómo
## (de reojo o de frente), más el sorteo de la reacción (`plan`). La probabilidad real es la
## base multiplicada por el factor de la personalidad (`BotPersonality.turn_factor`).
##
## Los avisos viajan por un grupo (`GROUP`): quien produce el evento llama a `broadcast` y el
## `EventModule` lo reparte a los bots y a las mesas de fondo.
##
## Descartados a propósito (no hacen voltear): lámpara a media luz tras una ejecución,
## banqueta o golpe detrás, puerta, tos o ruido del jugador.
## Se listan en `IGNORED` solo como documentación y prueba; cualquier tipo desconocido vale 0.

## Grupo de nodos que reciben `on_distraction(kind, pos, table)`.
const GROUP := &"distraction_listeners"

## tipo -> {
##   chance:   probabilidad base de voltear (antes del factor de personalidad),
##   strength: 0..1, lo fuerte que llama la atención (acorta el retardo de reacción),
##   look:     segundos que mantiene la mirada en el origen (min, max; se multiplica por `LOOK_SCALE`),
##   glance:   true = de reojo (giro rápido y vuelta pronto),
##   startle:  probabilidad de que además se sobresalte (`sit_startle`),
##   radius:   metros desde el oyente a los que se percibe (0 = todo el salón),
##   speed:    multiplicador de la velocidad de giro de la cabeza.
## }
const SPECS := {
	&"gunshot": {"chance": 0.95, "strength": 1.0, "look": Vector2(2.7, 5.4), "glance": false, "startle": 0.8, "radius": 0.0, "speed": 1.6},
	&"accusation": {"chance": 0.8, "strength": 0.85, "look": Vector2(2.2, 4.7), "glance": false, "startle": 0.75, "radius": 0.0, "speed": 1.4},
	&"blackout": {"chance": 0.8, "strength": 0.9, "look": Vector2(2.7, 5.4), "glance": false, "startle": 0.7, "radius": 0.0, "speed": 1.4},
	&"arbiter_pass": {"chance": 0.45, "strength": 0.3, "look": Vector2(0.4, 0.9), "glance": true, "startle": 0.0, "radius": 3.5, "speed": 2.3},
	&"plea": {"chance": 0.45, "strength": 0.4, "look": Vector2(1.4, 3.2), "glance": false, "startle": 0.0, "radius": 9.0, "speed": 1.0},
	&"flag": {"chance": 0.15, "strength": 0.25, "look": Vector2(1.1, 2.5), "glance": false, "startle": 0.0, "radius": 4.5, "speed": 1.0},
}

const IGNORED: Array[StringName] = [&"dim_lamp", &"stool", &"door", &"player_noise"]

## Factor sobre el tiempo que miran a otro lado (distracciones y vistazos espontáneos de los bots):
## da más margen al jugador para hacer trampa. 1,0 = tiempos de la tabla `SPECS`.
const LOOK_SCALE := 1.25

## Retardo de reacción (s): entre 0,15 (muy fuerte) y 0,45 (débil).
const REACTION_MIN := 0.15
const REACTION_MAX := 0.45


static func has(kind: StringName) -> bool:
	return SPECS.has(kind)


static func spec(kind: StringName) -> Dictionary:
	return SPECS.get(kind, {})


## Probabilidad base de voltear de un tipo (0 si no está en la tabla).
static func chance_of(kind: StringName) -> float:
	return float(spec(kind).get("chance", 0.0))


static func strength_of(kind: StringName) -> float:
	return float(spec(kind).get("strength", 0.5))


static func is_glance(kind: StringName) -> bool:
	return bool(spec(kind).get("glance", false))


static func startle_chance(kind: StringName) -> float:
	return float(spec(kind).get("startle", 0.0))


static func turn_speed(kind: StringName) -> float:
	return float(spec(kind).get("speed", 1.0))


## Probabilidad final: la base por el factor de personalidad, acotada a 0..1.
static func turn_probability(base_chance: float, factor: float) -> float:
	return clampf(base_chance * factor, 0.0, 1.0)


## ¿Se percibe el evento desde `listener` si ocurre en `pos`?
static func in_range(kind: StringName, listener: Vector3, pos: Vector3) -> bool:
	var radius := float(spec(kind).get("radius", 0.0))
	return radius <= 0.0 or listener.distance_to(pos) <= radius


## Segundos hasta empezar a voltear: más corto cuanto más fuerte es el evento.
static func reaction_delay(kind: StringName, rng: RandomNumberGenerator) -> float:
	var base := lerpf(REACTION_MAX, REACTION_MIN, strength_of(kind))
	return clampf(base + rng.randf_range(-0.07, 0.07), REACTION_MIN, REACTION_MAX)


## Segundos que mantiene la mirada en el origen (rango de la tabla por `LOOK_SCALE`).
static func look_seconds(kind: StringName, rng: RandomNumberGenerator) -> float:
	var r: Vector2 = spec(kind).get("look", Vector2(1.0, 3.0))
	return rng.randf_range(r.x, r.y) * LOOK_SCALE


## Sorteo de la reacción de un oyente. `base_chance` < 0 usa la de la tabla. Devuelve
## {turn, delay, seconds, glance, startle, speed}: `turn` dice si voltea; el resto describe cómo.
static func plan(kind: StringName, base_chance: float, factor: float, rng: RandomNumberGenerator) -> Dictionary:
	var base := chance_of(kind) if base_chance < 0.0 else base_chance
	var turn := rng.randf() < turn_probability(base, factor)
	return {
		"turn": turn,
		"delay": reaction_delay(kind, rng),
		"seconds": look_seconds(kind, rng),
		"glance": is_glance(kind),
		"startle": turn and rng.randf() < startle_chance(kind),
		"speed": turn_speed(kind),
	}


## Avisa a todos los oyentes del grupo. `table` = mesa de origen (-1 si ninguna).
static func broadcast(node: Node, kind: StringName, pos: Vector3, table: int = -1) -> void:
	if node == null or not node.is_inside_tree():
		return
	node.get_tree().call_group(GROUP, &"on_distraction", kind, pos, table)
