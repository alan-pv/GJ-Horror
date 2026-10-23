class_name StressModel
extends RefCounted
## Modelo del estrés del jugador humano (lógica pura, sin nodos). El valor (0..1) es
## max(piso, picos): el piso lo fijan el reloj, el avance del torneo y el material; los picos
## (disparos, acusaciones, miradas...) se suman, se sostienen un momento y decaen hacia el piso.
## Aparte lleva `shake_trauma`, la energía de la sacudida de cámara (decae rápido).

## Segundos de reloj propio con los que el piso por tiempo vale 0; baja linealmente hasta 0 s.
const CLOCK_CALM := 60.0
## Piso por reloj con 0 s restantes.
const CLOCK_FLOOR_MAX := 0.6
## Piso por avance del torneo en la final.
const TOURNAMENT_FLOOR_MAX := 0.25
## Peones de desventaja de material con los que el piso por material llega a su máximo.
const MATERIAL_FULL_PAWNS := 5.0
const MATERIAL_FLOOR_MAX := 0.15
## Segundos que un pico se mantiene intacto antes de decaer.
const SPIKE_HOLD := 1.5
## Caída del pico por segundo (hacia el piso) una vez pasado el sostenimiento.
const SPIKE_DECAY := 0.08
## Caída de la energía de sacudida por segundo.
const TRAUMA_DECAY := 1.5

# Picos puntuales (cantidad que suman).
const SPIKE_SHOT_TABLE := 0.6
const SPIKE_SHOT_NEAR := 0.35
const SPIKE_SHOT_FAR := 0.15
const SPIKE_FALSE_ACCUSE := 0.3
const SPIKE_RIVAL_WATCHES := 0.25
## El humano empieza una trampa durante el apagón (el apagón por sí solo no estresa).
const SPIKE_CHEAT_IN_BLACKOUT := 0.25
const SPIKE_OTHER_DRAMA := 0.1
const SPIKE_MAJOR_LOST := 0.1
const SPIKE_CHECK := 0.08
# Aportes sostenidos (mientras dure la causa).
const SUSTAIN_ACCUSED := 0.45
const SUSTAIN_ARBITER := 0.15

## Latidos por minuto en calma y con el estrés al máximo.
const BPM_MIN := 60.0
const BPM_MAX := 120.0

## Valor actual (0..1).
var value: float = 0.0
## Energía de sacudida (0..1); la cámara usa su cuadrado.
var shake_trauma: float = 0.0
var floor_value: float = 0.0

var _spike: float = 0.0
var _hold: float = 0.0
## Aportes sostenidos por clave (StringName -> cantidad).
var _sustained: Dictionary = {}


## Piso a partir de las entradas lentas. `players_total` <= 2 cuenta como final.
func set_floor_inputs(clock_remaining: float, players_left: int, players_total: int, material_deficit_pawns: float) -> void:
	floor_value = maxf(maxf(clock_floor(clock_remaining), tournament_floor(players_left, players_total)),
			material_floor(material_deficit_pawns))
	# El piso nunca supera el tope; los tres juntos tampoco se suman (es un máximo).
	floor_value = clampf(floor_value, 0.0, 1.0)


static func clock_floor(remaining: float) -> float:
	return CLOCK_FLOOR_MAX * clampf(1.0 - remaining / CLOCK_CALM, 0.0, 1.0)


## 0 con todos los jugadores; TOURNAMENT_FLOOR_MAX en la final (progreso logarítmico: cada ronda suma igual).
static func tournament_floor(players_left: int, players_total: int) -> float:
	if players_total <= 2 or players_left <= 2:
		return TOURNAMENT_FLOOR_MAX
	var t := 1.0 - log(float(players_left) / 2.0) / log(float(players_total) / 2.0)
	return TOURNAMENT_FLOOR_MAX * clampf(t, 0.0, 1.0)


static func material_floor(deficit_pawns: float) -> float:
	return MATERIAL_FLOOR_MAX * clampf(deficit_pawns / MATERIAL_FULL_PAWNS, 0.0, 1.0)


## Peones de ventaja del rival sobre `color` (negativo si va por delante). Sin reyes.
static func material_deficit(board: BoardState, color: int) -> float:
	var own := 0
	var other := 0
	for p in board.squares:
		if p == ChessPiece.NONE:
			continue
		if ChessPiece.color_of(p) == color:
			own += ChessPiece.value_of(p)
		else:
			other += ChessPiece.value_of(p)
	return float(other - own) / 100.0


## Suma un pico (tope 1) y lo sostiene al menos `hold` segundos.
func add_spike(amount: float, hold: float = SPIKE_HOLD) -> void:
	_spike = minf(_spike + amount, 1.0)
	_hold = maxf(_hold, hold)
	_refresh()


## Aporte que dura mientras la causa siga (acusación pendiente, árbitro cerca); `amount` 0 lo quita.
func set_sustained(key: StringName, amount: float) -> void:
	if amount <= 0.0:
		_sustained.erase(key)
	else:
		_sustained[key] = amount
	_refresh()


## Suma energía de sacudida (tope 1).
func add_shake(amount: float) -> void:
	shake_trauma = minf(shake_trauma + amount, 1.0)


## El jugador fue condenado: el estrés sube a 1 y ya no baja.
func condemn() -> void:
	_spike = 1.0
	_hold = INF
	_refresh()


func step(delta: float) -> void:
	if _hold > 0.0:
		_hold -= delta
	else:
		_spike = maxf(_spike - SPIKE_DECAY * delta, 0.0)
	shake_trauma = maxf(shake_trauma - TRAUMA_DECAY * delta, 0.0)
	_refresh()


func _refresh() -> void:
	var total := _spike
	for k in _sustained:
		total += float(_sustained[k])
	value = clampf(maxf(floor_value, total), 0.0, 1.0)


## Latidos por minuto para un nivel de estrés.
static func bpm(stress: float) -> float:
	return lerpf(BPM_MIN, BPM_MAX, clampf(stress, 0.0, 1.0))


## Forma del latido (0..1) para una fase en ciclos: dos golpes ("lub-dub") por vuelta.
static func heart_pulse(phase: float) -> float:
	var p := fposmod(phase, 1.0)
	var lub := exp(-pow((p - 0.04) / 0.05, 2.0))
	var dub := 0.6 * exp(-pow((p - 0.32) / 0.05, 2.0))
	return clampf(lub + dub, 0.0, 1.0)
