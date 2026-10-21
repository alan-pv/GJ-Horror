class_name CharacterFigure
extends FigureBase
## Figura de un jugador (`player.glb`): sentada o de pie, con animaciones, mirada aditiva,
## aspecto recoloreable y brazos con IK para mover piezas con precisión.
##
## Uso típico:
##   var f := CharacterFigure.new()
##   add_child(f)
##   f.setup(CharacterFigure.random_look(rng))
##   f.play(&"sit_idle")
##   f.set_look(deg_to_rad(40), 0.0)           # mira a su izquierda
##   var target := f.enable_arm_ik(&"R", true)  # mano derecha por IK
##   target.global_position = <muñeca deseada en el mundo>
##
## Origen: suelo bajo el centro del asiento; mira a +Z; la mesa (superficie a 0,72 m)
## empieza a unos 0,35 m por delante. El lado `&"R"` es la derecha DEL PERSONAJE (-X local).

const MODEL_PATH := "res://assets/models/characters/player.glb"
## Animaciones cíclicas (el .glb no trae el flag; se marcan `LOOP_LINEAR` al cargar).
const LOOPS: Array[StringName] = [
	&"sit_idle", &"sit_think", &"sit_nervous", &"sit_write",
	&"sit_cry", &"sit_frozen",
]

## Velocidad (m/s) a la que avanza el rol `walk` con velocidad 1 (ciclo de 1,0 s, paso doble de
## 1,1 m: apoyo 60 %, recorrido del pie 0,66 m). Para caminar a `v` m/s: `play_role(&"walk", rng, v / WALK_SPEED)`.
const WALK_SPEED := 1.1
const WALK_STRIDE := 1.1

## Polo del codo por defecto, en espacio local de la figura, para el brazo derecho (el
## izquierdo es el espejo en X): hacia fuera y un poco atrás, a la altura del hombro (el
## hombro está a ~0,90 m). El codo acaba afuera y por DEBAJO del hombro, pero por encima
## de la mesa (medido con la figura sentada y la muñeca en y=0,74: codo a y>=0,72 y
## antebrazo cruzando el borde, z=0,35, a y>=0,77). Un polo más bajo (p. ej. y=0,5) deja
## el codo a 0,63-0,67 y el antebrazo atraviesa el canto de la mesa.
const POLE_RIGHT := Vector3(-0.80, 1.05, -0.20)

## Gris mate de la piel de los bots (se lee bajo la lámpara cálida y en la penumbra).
const BOT_SKIN := Color(0.46, 0.46, 0.47)

# lado ("L"/"R") -> { ik: TwoBoneIK3D, target: Marker3D, pole: Marker3D }
var _arms: Dictionary = {}


func _model_path() -> String:
	return MODEL_PATH


func _loops() -> Array:
	return LOOPS


## Aspecto aleatorio sobrio (trajes grises, marrones o azules, camisas claras, pieles
## variadas). Devuelve el diccionario que entiende `setup`.
static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var skins := [
		Color(0.93, 0.76, 0.64), Color(0.85, 0.65, 0.50), Color(0.74, 0.54, 0.40),
		Color(0.58, 0.40, 0.29), Color(0.42, 0.28, 0.20), Color(0.30, 0.20, 0.15),
	]
	var suits := [
		Color(0.24, 0.25, 0.28), Color(0.33, 0.34, 0.36), Color(0.20, 0.17, 0.14),
		Color(0.34, 0.26, 0.19), Color(0.16, 0.20, 0.30), Color(0.22, 0.27, 0.36),
		Color(0.19, 0.22, 0.20),
	]
	var shirts := [
		Color(0.86, 0.84, 0.78), Color(0.80, 0.82, 0.84), Color(0.78, 0.72, 0.62),
		Color(0.70, 0.76, 0.82), Color(0.90, 0.88, 0.84),
	]
	var hairs := [
		Color(0.05, 0.04, 0.04), Color(0.16, 0.10, 0.07), Color(0.30, 0.20, 0.12),
		Color(0.48, 0.36, 0.20), Color(0.55, 0.55, 0.55), Color(0.78, 0.76, 0.72),
	]
	var styles := ["short", "short", "long", "bald"]
	var suit: Color = suits[rng.randi() % suits.size()]
	return {
		"skin": skins[rng.randi() % skins.size()],
		"shirt": shirts[rng.randi() % shirts.size()],
		"jacket": suit,
		"pants": suit.darkened(rng.randf_range(0.0, 0.12)),
		"shoes": Color(0.08, 0.06, 0.05).lerp(Color(0.2, 0.12, 0.07), rng.randf()),
		"hair": hairs[rng.randi() % hairs.size()],
		"hair_style": styles[rng.randi() % styles.size()],
	}


## Aspecto de un bot: maniquí gris sin rasgos. Conserva la ropa de `base` (si viene vacío,
## la saca de `random_look(rng)`); la piel, el cabello y los ojos son del mismo gris mate y el
## peinado es "bald". Los ojos son una caja con material `Eyes` dentro de la malla del cuerpo,
## así que se pintan del color de la piel; la nariz y las orejas son geometría de `Skin` y
## quedan como relieve sutil. El cuerpo del humano y el árbitro NO usan esto.
static func bot_look(rng: RandomNumberGenerator, base: Dictionary = {}) -> Dictionary:
	var look: Dictionary = base.duplicate() if not base.is_empty() else random_look(rng)
	look["skin"] = BOT_SKIN
	look["hair"] = BOT_SKIN
	look["eyes"] = BOT_SKIN
	look["hair_style"] = "bald"
	return look


# --- Brazos con IK ------------------------------------------------------------------

## Activa o desactiva el IK del brazo `side` (`&"L"` o `&"R"`, del personaje) y devuelve
## el `Marker3D` OBJETIVO de la muñeca, en espacio MUNDIAL (`top_level`): muévelo con
## `global_position`. La cadena es UpperArm -> Forearm -> Hand y se aplica DESPUÉS de la
## animación y de la mirada, con `influence` 1 por defecto (ver `set_arm_ik_influence`).
## La primera vez que se llama crea el `TwoBoneIK3D` y deja el objetivo en la muñeca actual.
## La orientación del objetivo no se usa: la mano sigue al antebrazo.
func enable_arm_ik(side: StringName, on: bool) -> Marker3D:
	var arm := _arm(side)
	(arm["ik"] as TwoBoneIK3D).active = on
	return arm["target"]


func arm_ik_enabled(side: StringName) -> bool:
	return _arms.has(side) and (_arms[side]["ik"] as TwoBoneIK3D).active


## Fuerza del IK de 0 (solo animación) a 1 (la muñeca va al objetivo). Se puede animar
## con un Tween para entrar y salir del IK sin saltos.
func set_arm_ik_influence(side: StringName, value: float) -> void:
	(_arm(side)["ik"] as TwoBoneIK3D).influence = clampf(value, 0.0, 1.0)


func arm_ik_influence(side: StringName) -> float:
	return (_arm(side)["ik"] as TwoBoneIK3D).influence


## Objetivo de la muñeca del brazo `side` (se crea con el IK, inactivo).
func arm_target(side: StringName) -> Marker3D:
	return _arm(side)["target"]


## Polo del codo (`Marker3D` hijo de la figura, espacio local): el codo se dobla hacia él.
## Por defecto queda hacia fuera, abajo y atrás (`POLE_RIGHT`, espejado para el izquierdo).
## Se puede mover; el agente de manos lo ajusta según la posición de la mesa.
func arm_pole(side: StringName) -> Marker3D:
	return _arm(side)["pole"]


func _arm(side: StringName) -> Dictionary:
	assert(side == &"L" or side == &"R", "side debe ser &\"L\" o &\"R\"")
	if _arms.has(side):
		return _arms[side]
	var target := Marker3D.new()
	target.name = "ObjetivoMano_" + side
	target.top_level = true
	add_child(target)
	var pole := Marker3D.new()
	pole.name = "PoloCodo_" + side
	pole.position = POLE_RIGHT * (Vector3(1, 1, 1) if side == &"R" else Vector3(-1, 1, 1))
	add_child(pole)
	# Objetivo inicial: la muñeca tal como está ahora (en el mundo si ya hay árbol).
	var wrist := bone_global(StringName("Hand." + side))
	if is_inside_tree():
		target.global_position = wrist.origin
	else:
		target.position = wrist.origin

	var ik := TwoBoneIK3D.new()
	ik.name = "IKBrazo_" + side
	_skeleton.add_child(ik)  # después de la mirada: el pecho puede girar antes del IK
	ik.set_setting_count(1)
	ik.set_root_bone_name(0, "UpperArm." + side)
	ik.set_middle_bone_name(0, "Forearm." + side)
	ik.set_end_bone_name(0, "Hand." + side)
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole))
	ik.active = false
	var arm := {"ik": ik, "target": target, "pole": pole}
	_arms[side] = arm
	return arm
