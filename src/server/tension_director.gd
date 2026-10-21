class_name TensionDirector
extends RefCounted
## Director de tensión: decide cuándo ocurre un evento global, cuál y dónde,
## para que todos los clientes lo vean a la vez. Lógica pura (sin nodos):
## quien lo use llama `tick(delta)` y escucha `event_triggered`.
##
## - La frecuencia sube conforme quedan menos jugadores (`set_players_remaining`).
## - Hay una separación mínima entre eventos y nunca se repite el mismo dos veces seguidas.
## - Cada evento tiene su propio tiempo de espera (`EventDef.cooldown`).
## - Solo sortea eventos GLOBAL y DETERRENT; los RIVAL se piden por `MatchServer`.

signal event_triggered(event_id: StringName, origin: Vector3, duration: float)

const EVENT_IDS: Array[StringName] = [
	&"apagon", &"ruido_detras", &"acusacion_ajena", &"eliminacion", &"arbitro_pasa",
	&"cough",
]

## Segundos entre eventos con el salón lleno y con los últimos jugadores.
var interval_full: float = 55.0
var interval_final: float = 16.0
## Separación mínima entre dos eventos, pase lo que pase.
var min_spacing: float = 10.0
## Primer evento: no antes de este tiempo.
var first_delay: float = 20.0
## Mesas decorativas donde pueden ocurrir eventos (centros a ras de suelo).
var table_positions: Array[Vector3] = []
## Dónde está sentado quien oye los eventos y hacia dónde mira (para "detrás").
var listener_pos: Vector3 = Vector3(0.0, 0.0, 0.52)
var listener_forward: Vector3 = Vector3(0.0, 0.0, -1.0)
## Límites del salón en X y Z (mitad del lado) para no sacar un evento por la pared.
var room_half: Vector2 = Vector2(10.0, 12.0)
var enabled: bool = true

var time: float = 0.0
var last_id: StringName = &""
var last_time: float = -1000.0

var _defs: Dictionary = {}
var _ready_at: Dictionary = {}
var _players: int = 2
var _total: int = 2
var _next_at: float = 0.0
var _rng := RandomNumberGenerator.new()


func _init(defs: Array[EventDef] = [], seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	for d in defs:
		_defs[d.id] = d
	_next_at = first_delay * _rng.randf_range(0.8, 1.2)


## Carga las definiciones de `data/events/`.
static func load_defs() -> Array[EventDef]:
	var out: Array[EventDef] = []
	for id in EVENT_IDS:
		var d := load("res://data/events/%s.tres" % id) as EventDef
		if d != null:
			out.append(d)
	return out


func get_def(id: StringName) -> EventDef:
	return _defs.get(id)


func set_players_remaining(remaining: int, total: int) -> void:
	_players = maxi(remaining, 1)
	_total = maxi(total, 1)


## 0 = salón lleno, 1 = quedan los últimos jugadores. Con 1v1 (prototipo) vale 0,5.
func tension() -> float:
	if _total <= 2:
		return 0.5
	return clampf(1.0 - float(_players - 2) / float(_total - 2), 0.0, 1.0)


## Segundos medios entre eventos con la tensión actual.
func current_interval() -> float:
	return maxf(lerpf(interval_full, interval_final, tension()), min_spacing)


func tick(delta: float) -> void:
	time += delta
	if not enabled or time < _next_at:
		return
	var id := _pick()
	if id == &"":
		# Nada disponible (todo en espera): reintenta pronto.
		_next_at = time + 2.0
		return
	fire(id)


## Dispara un evento ya (también lo usa la eliminación real de otra mesa, o la
## depuración). Si no se da origen, se calcula según el evento.
func fire(id: StringName, origin: Variant = null) -> bool:
	var def := get_def(id)
	if def == null:
		return false
	var pos: Vector3 = origin if origin is Vector3 else pick_origin(def)
	last_id = id
	last_time = time
	_ready_at[id] = time + def.cooldown
	_next_at = time + maxf(current_interval() * _rng.randf_range(0.75, 1.25), min_spacing)
	event_triggered.emit(id, pos, def.duration)
	return true


## Eventos que podrían salir ahora.
func candidates() -> Array[EventDef]:
	var out: Array[EventDef] = []
	for id in _defs:
		var d: EventDef = _defs[id]
		if d.kind == EventDef.Kind.RIVAL:
			continue
		if d.id == last_id or d.weight <= 0.0:
			continue
		if time < _ready_at.get(d.id, 0.0) or tension() < d.min_tension:
			continue
		out.append(d)
	return out


func _pick() -> StringName:
	var list := candidates()
	if list.is_empty():
		return &""
	# Orden fijo para que la misma semilla dé la misma secuencia.
	list.sort_custom(func(a: EventDef, b: EventDef) -> bool: return String(a.id) < String(b.id))
	var total := 0.0
	for d in list:
		total += d.weight
	var r := _rng.randf() * total
	for d in list:
		r -= d.weight
		if r <= 0.0:
			return d.id
	return list[list.size() - 1].id


func pick_origin(def: EventDef) -> Vector3:
	match def.origin_mode:
		EventDef.Origin.TABLE:
			if not table_positions.is_empty():
				return table_positions[_rng.randi() % table_positions.size()]
			return _behind(4.0)
		EventDef.Origin.BEHIND:
			return _behind(_rng.randf_range(2.5, 5.0))
		_:
			return Vector3(0.0, 0.0, 0.0)


## Un punto detrás del jugador, con algo de desvío lateral y dentro del salón.
func _behind(dist: float) -> Vector3:
	var fwd := Vector3(listener_forward.x, 0.0, listener_forward.z)
	fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3(0.0, 0.0, -1.0)
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var p := listener_pos - fwd * dist + side * _rng.randf_range(-2.2, 2.2)
	p.y = 0.0
	p.x = clampf(p.x, -room_half.x, room_half.x)
	p.z = clampf(p.z, -room_half.y, room_half.y)
	return p
