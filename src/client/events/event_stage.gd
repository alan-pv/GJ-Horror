class_name EventStage
extends Node3D
## Escenografía de los eventos: apagón, banqueta que cae a las espaldas del jugador (único objeto
## de primitivas), y figura que acusa en otra mesa. Las personas son `CharacterFigure` con roles de animación. Los sonidos son espaciales (`AudioStreamPlayer3D`) y
## salen de `EventSounds`.

## Nivel de luz (`blackout_level`) por debajo del cual se considera oscuridad de verdad:
## el servidor deja de contar las trampas como vistas.
const DARK_LEVEL := 0.3

## La sala pasó a oscuridad (`true`) o recuperó la luz (`false`).
signal darkness_changed(dark: bool)

var hall: Hall
## Raíz del juego: da acceso a las mesas de fondo (`bg_tables`) para prestar sus figuras.
var root: GameRoot

# Estado del apagón.
var _blackout_running: bool = false
var _lights: Array = []        # [Light3D, energía base]
var _emissives: Array = []     # [StandardMaterial3D, multiplicador base]
var _cones: Array = []         # [ShaderMaterial, fuerza base]
var _env: Environment
var _env_ambient: float = 0.2
var _dark: bool = false


func setup(p_hall: Hall, env_node: Node) -> void:
	name = "Escenario"
	hall = p_hall
	if env_node is WorldEnvironment:
		_env = (env_node as WorldEnvironment).environment


# --- Audio -----------------------------------------------------------------------

## Reproduce un sonido sintetizado en `pos` (mundo). Si se da `parent`, el
## reproductor lo sigue y se libera al terminar.
func play_sound(key: StringName, pos: Vector3, volume_db: float = 0.0, parent: Node3D = null) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = EventSounds.get_stream(key)
	p.unit_size = 6.0
	p.max_distance = 45.0
	p.volume_db = volume_db
	if parent != null:
		parent.add_child(p)
		p.position = Vector3(0.0, 1.5, 0.0)
	else:
		add_child(p)
		p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	return p


# --- Apagón ----------------------------------------------------------------------

## Las lámparas titilan, se apagan unos segundos y vuelven a encenderse.
func blackout(duration: float) -> void:
	if _blackout_running or hall == null:
		return
	_blackout_running = true
	_collect_lights()
	var tw := create_tween()
	tw.tween_method(_blackout_step, 0.0, 1.0, duration)
	tw.tween_callback(func() -> void: _blackout_running = false)


func _collect_lights() -> void:
	_lights.clear()
	_emissives.clear()
	_cones.clear()
	for n in hall.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		# Las lámparas ya apagadas (p. ej. por una eliminación) se quedan así.
		if l.visible and l.light_energy > 0.001:
			_lights.append([l, l.light_energy])
	var seen := {}
	for n in hall.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var m := mi.material_override
		if m == null or seen.has(m.get_instance_id()):
			continue
		seen[m.get_instance_id()] = true
		if m is StandardMaterial3D and (m as StandardMaterial3D).emission_enabled:
			_emissives.append([m, (m as StandardMaterial3D).emission_energy_multiplier])
		elif m is ShaderMaterial and (m as ShaderMaterial).get_shader_parameter("strength") != null:
			_cones.append([m, float((m as ShaderMaterial).get_shader_parameter("strength"))])
	if _env != null:
		_env_ambient = _env.ambient_light_energy


## ¿Un nivel de luz cuenta como oscuridad (las trampas no se ven)?
static func is_dark_level(level: float) -> bool:
	return level < DARK_LEVEL


func is_dark() -> bool:
	return _dark


## Multiplicador de luz según el avance (0..1): parpadeo, oscuridad y parpadeo de regreso.
static func blackout_level(u: float) -> float:
	if u >= 1.0:
		return 1.0
	var h := fposmod(sin(floorf(u * 55.0) * 12.9898) * 43758.5453, 1.0)
	if u < 0.18:
		return 1.0 if h > 0.5 else 0.06
	if u < 0.8:
		return 0.25 if h > 0.985 else 0.0
	var back := (u - 0.8) / 0.2
	return 1.0 if h < back else 0.05


func _blackout_step(u: float) -> void:
	var m := blackout_level(u)
	var dark := is_dark_level(m)
	if dark != _dark:
		_dark = dark
		darkness_changed.emit(dark)
	for e in _lights:
		if is_instance_valid(e[0]):
			(e[0] as Light3D).light_energy = e[1] * m
	for e in _emissives:
		(e[0] as StandardMaterial3D).emission_energy_multiplier = e[1] * m
	for e in _cones:
		(e[0] as ShaderMaterial).set_shader_parameter("strength", e[1] * m)
	if _env != null:
		_env.ambient_light_energy = lerpf(_env_ambient * 0.15, _env_ambient, m)


# --- Ruido detrás -----------------------------------------------------------------

## Una banqueta que cae y rueda detrás del jugador, con un golpe seco.
func fall_behind(origin: Vector3) -> void:
	var stool := Node3D.new()
	stool.name = "Banqueta"
	add_child(stool)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.09, 0.05)
	mat.roughness = 0.8
	var seat := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.38, 0.04, 0.38)
	seat.mesh = sm
	seat.material_override = mat
	stool.add_child(seat)
	for lx in [-1.0, 1.0]:
		for lz in [-1.0, 1.0]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.04, 0.45, 0.04)
			leg.mesh = lm
			leg.material_override = mat
			leg.position = Vector3(lx * 0.15, -0.24, lz * 0.15)
			stool.add_child(leg)
	var start := Vector3(origin.x, 1.7, origin.z)
	stool.position = start
	stool.rotation = Vector3(0.2, 0.0, -0.1)
	var land := Vector3(origin.x + 0.4, 0.2, origin.z + 0.2)
	var tw := create_tween()
	tw.tween_property(stool, "position:y", land.y, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(stool, "rotation", Vector3(0.5, 0.9, PI * 0.5), 0.42)
	tw.tween_callback(play_sound.bind(&"slam", land, 3.0))
	tw.tween_property(stool, "position:y", land.y + 0.12, 0.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(stool, "position:y", land.y, 0.1).set_ease(Tween.EASE_IN)
	tw.tween_callback(play_sound.bind(&"thud", land, -3.0))
	tw.tween_interval(25.0)
	tw.tween_callback(stool.queue_free)


# --- Figuras --------------------------------------------------------------------------

## Yaw para que un nodo que mira a -Z quede de frente a `to` viendo desde `from`.
static func yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))


## Yaw de una `CharacterFigure` (mira a +Z) para que mire a `to` desde `from`.
static func figure_yaw(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)


## Índice de la mesa más cercana a `origin` (en XZ), o -1.
func _table_index(origin: Vector3) -> int:
	var best := -1
	var best_d := 0.6
	for i in hall.table_count():
		var p := hall.table_position(i)
		var d := Vector2(p.x - origin.x, p.z - origin.z).length()
		if d < best_d:
			best_d = d
			best = i
	return best


## Presta la figura de un asiento libre de la mesa `table` (al azar entre los dos).
## Devuelve {fig, seat, bt} o un diccionario vacío si no hay figura disponible.
func _borrow(table: int) -> Dictionary:
	var bt: BackgroundTable = root.bg_tables.get(table) if root != null else null
	if bt == null:
		return {}
	var order: Array = [0, 1] if randf() < 0.5 else [1, 0]
	for sd in order:
		var f := bt.lend(sd)
		if f != null:
			return {"fig": f, "seat": sd, "bt": bt}
	return {}


## Pausa en este escenario (sobrevive a recargas: devuelve false si ya no está en el árbol).
func _pause(seconds: float) -> bool:
	if not is_inside_tree():
		return false
	await get_tree().create_timer(seconds).timeout
	return is_inside_tree()


## "Cheater!" gritado con voz de 8 bits (`VoiceBlips.Speaker.ACCUSER`). Con `parent` (la
## cabeza de quien grita) o `pos` suena espacial; con `spatial = false` es un reproductor
## plano (la voz del propio jugador). `pitch` baja o sube la voz.
func shout(pos: Vector3, parent: Node3D = null, spatial: bool = true, pitch: float = 1.0) -> Node:
	var stream := VoiceBlips.build(VoiceBlips.Speaker.ACCUSER, "Cheater!")
	if stream == null:
		return null
	var vol := VoiceBlips.volume_db(VoiceBlips.Speaker.ACCUSER)
	var p: Node
	if spatial:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = stream
		p3.unit_size = 6.0
		p3.max_distance = 45.0
		p3.volume_db = vol + 6.0
		p3.pitch_scale = pitch
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = stream
		p2.volume_db = vol
		p2.pitch_scale = pitch
		p2.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
		p = p2
	if spatial and parent != null:
		parent.add_child(p)
		(p as Node3D).position = Vector3(0.0, 1.5, 0.0)
	else:
		add_child(p)
		if spatial:
			(p as Node3D).global_position = pos
	p.connect(&"finished", p.queue_free)
	p.call(&"play")
	return p


# --- Acusación ajena ---------------------------------------------------------------------

## Alguien de otra mesa (una figura real, prestada por su `BackgroundTable`) se queda sentado,
## vuelve la cabeza hacia el jugador con un respingo (`sit_startle`), grita y, pasado el evento,
## recupera su vida ambiental. Sin silla ni levantarse.
func accuser(origin: Vector3, duration: float, toward: Vector3) -> void:
	var table := _table_index(origin)
	var loan := _borrow(table)
	if loan.is_empty():
		# Sin figura libre en esa mesa: solo se oye el grito.
		shout(origin + Vector3(0.0, 1.5, 0.0))
		return
	var f: CharacterFigure = loan.fig
	var seat: int = loan.seat
	var bt: BackgroundTable = loan.bt
	f.look_at_point(toward)
	f.play_role_once(&"sit_startle")
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if is_instance_valid(f):
			shout(f.head_global_position()))
	if not await _pause(maxf(duration, 1.5)):
		return
	if is_instance_valid(f):
		f.set_look(0.0, 0.0)
		f.play_role(&"sit_wait")
	bt.give_back(seat)
