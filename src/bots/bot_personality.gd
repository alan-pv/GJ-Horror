class_name BotPersonality
extends Resource
## Combinación de parámetros que define cómo juega, se distrae y vigila un bot.

@export var display_name: String = "Bot"
## Nivel de ajedrez. Maia lo usa como entrada; el respaldo, como temperatura.
@export_range(600, 2200, 50) var elo: int = 1200
## Temperatura al muestrear la política (1 = tal cual la predice Maia).
@export_range(0.1, 2.0) var temperature: float = 1.0

@export_group("Tiempo")
## Multiplica el tiempo que piensa cada jugada.
@export_range(0.3, 3.0) var think_time_scale: float = 1.0

@export_group("Atención")
## Probabilidad de voltear ante un evento.
@export_range(0.0, 1.0) var turn_to_event_chance: float = 0.6
## Veces por minuto que mira el salón por su cuenta.
@export_range(0.0, 20.0) var idle_glances_per_minute: float = 3.0
## Segundos que mantiene la vista lejos del tablero.
@export var look_away_seconds: Vector2 = Vector2(1.0, 3.0)
## Velocidad de giro de la cabeza (radianes por segundo).
@export var head_turn_speed: float = 3.5

@export_group("Trampa y vigilancia")
## Probabilidad de intentar una trampa por oportunidad (mayor si va perdiendo).
@export_range(0.0, 1.0) var cheat_chance: float = 0.1
## Probabilidad de notar una trampa que sí vio.
@export_range(0.0, 1.0) var detect_chance: float = 0.7
## Probabilidad por jugada rival de acusar sin razón (baja mucho con cada advertencia propia).
@export_range(0.0, 0.2) var false_accuse_chance: float = 0.01
## Probabilidad de abortar una trampa en curso cuando el rival empieza a mirar.
@export_range(0.0, 1.0) var abort_chance: float = 0.4
## Apetito de riesgo: 0 = prudente (solo trampas sutiles), 1 = audaz (se atreve a robar).
@export_range(0.0, 1.0) var risk_appetite: float = 0.4


## Referencia de `turn_to_event_chance` que equivale a factor 1 (media de las personalidades).
const TURN_REFERENCE := 0.55


## Factor que multiplica la probabilidad base de voltear de cada evento (media ~1).
func turn_factor() -> float:
	return turn_to_event_chance / TURN_REFERENCE
