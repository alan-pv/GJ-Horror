class_name EventStage
extends Node3D
## Escenografía de los eventos: apagón, banqueta que cae a las espaldas del jugador (único objeto
## de primitivas), figura que acusa en otra mesa, guardias que se llevan a alguien y la pieza que
## se le cae al rival. Las personas son `CharacterFigure` con roles de animación. Los sonidos son espaciales (`AudioStreamPlayer3D`) y
## salen de `EventSounds`.

const ROOM_MARGIN := 0.8

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


## Presta la figura de un asiento libre de la mesa `table` (`seat` -1 = cualquiera, al azar).
## Devuelve {fig, seat, bt} o un diccionario vacío si no hay figura disponible.
func _borrow(table: int, seat: int = -1) -> Dictionary:
	var bt: BackgroundTable = root.bg_tables.get(table) if root != null else null
	if bt == null:
		return {}
	var order: Array = [seat] if seat >= 0 else ([0, 1] if randf() < 0.5 else [1, 0])
	for sd in order:
		var f := bt.lend(sd)
		if f != null:
			return {"fig": f, "seat": sd, "bt": bt}
	return {}


## Dirección "hacia atrás" de una figura sentada (opuesta a su frente, que es +Z local).
static func back_of(f: Node3D) -> Vector3:
	var b := -f.global_basis.z
	b.y = 0.0
	return b.normalized()


## Mueve `node` en el mundo a `to` en `seconds` (tween en este escenario).
func _slide(node: Node3D, to: Vector3, seconds: float, delay: float = 0.0) -> void:
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(node, "global_position", to, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Gira `f` hasta `yaw` (rad) en `seconds`, tras `delay`.
func _turn_figure(f: Node3D, yaw: float, seconds: float, delay: float = 0.0) -> void:
	var from := f.rotation.y
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(func(u: float) -> void:
		if is_instance_valid(f):
			f.rotation.y = lerp_angle(from, yaw, u), 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE)


## Pausa en este escenario (sobrevive a recargas: devuelve false si ya no está en el árbol).
func _pause(seconds: float) -> bool:
	if not is_inside_tree():
		return false
	await get_tree().create_timer(seconds).timeout
	return is_inside_tree()


# --- Acusación ajena ---------------------------------------------------------------------

## Distancia (m) que se retira la silla al levantarse (los clips suponen >= 0,40).
const CHAIR_BACK := 0.5

## Alguien de otra mesa (una figura real, prestada por su `BackgroundTable`) retira la silla,
## se levanta (`stand_accuse`), señala hacia el jugador, grita, aguanta señalando
## (`stand_accuse_hold`) y se sienta de nuevo (`sit_down`) devolviendo la silla.
func accuser(origin: Vector3, duration: float, toward: Vector3) -> void:
	var table := _table_index(origin)
	var loan := _borrow(table)
	if loan.is_empty():
		# Sin figura libre en esa mesa: solo se oye el grito.
		play_sound(&"shout", origin + Vector3(0.0, 1.5, 0.0), 6.0)
		return
	var f: CharacterFigure = loan.fig
	var seat: int = loan.seat
	var bt: BackgroundTable = loan.bt
	var chair := hall.chair(table, seat)
	var back := back_of(f)
	var chair_home := chair.global_position
	var yaw0 := f.rotation.y
	var yaw := figure_yaw(f.global_position, toward)
	f.set_look(0.0, 0.0)
	# La silla sale hacia atrás mientras sube la pelvis; el cuerpo se vuelve hacia el jugador.
	_slide(chair, chair_home + back * CHAIR_BACK, 0.9, 0.2)
	_turn_figure(f, yaw, 1.0, 0.9)
	get_tree().create_timer(1.7).timeout.connect(func() -> void:
		if is_instance_valid(f):
			play_sound(&"shout", f.head_global_position(), 6.0))
	await f.play_role_once(&"stand_accuse")
	f.play_role(&"stand_accuse_hold")
	if not await _pause(maxf(duration - 1.5, 1.2)):
		return
	# Vuelve a su silla: gira hacia la mesa, la silla entra y se sienta.
	_turn_figure(f, yaw0, 0.7)
	_slide(chair, chair_home, 0.9, 0.6)
	await f.play_role_once(&"sit_down")
	if is_instance_valid(f):
		f.rotation.y = yaw0
		f.play_role(&"sit_wait")
	chair.global_position = chair_home
	bt.give_back(seat)


# --- Eliminación en otra mesa -----------------------------------------------------------

## Aspecto de los guardias: ropa oscura (algo más clara que negro para que se lea en la penumbra), maniquí gris.
static func guard_look(rng: RandomNumberGenerator) -> Dictionary:
	var dark := Color(0.11, 0.11, 0.14)
	return CharacterFigure.bot_look(rng, {
		"skin": CharacterFigure.BOT_SKIN, "shirt": Color(0.16, 0.16, 0.18), "jacket": dark,
		"pants": dark, "shoes": Color(0.05, 0.05, 0.05), "hair": CharacterFigure.BOT_SKIN, "hair_style": "bald",
	})


## Dos guardias (`CharacterFigure` oscuras con `walk`) llegan a la mesa, la figura se levanta
## (`stand_up`, con la silla hacia atrás) y se la llevan entre los dos (`dragged`) hacia la salida
## por los pasillos. Es la salida de los eliminados que no ejecuta el árbitro. `seat_index`: asiento
## del eliminado (-1 = cualquiera).
func drag_away(origin: Vector3, _duration: float, seat_index: int = -1) -> void:
	var table := _table_index(origin)
	var loan := _borrow(table, seat_index)
	if loan.is_empty():
		return
	var victim: CharacterFigure = loan.fig
	var seat: int = loan.seat
	var bt: BackgroundTable = loan.bt
	var chair := hall.chair(table, seat)
	var back := back_of(victim)
	var side := Vector3(back.z, 0.0, -back.x)
	var seat_pos := victim.global_position
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var guards: Array[CharacterFigure] = []
	for i in 2:
		var g := CharacterFigure.new()
		g.name = "Guardia%d" % i
		add_child(g)
		g.setup(guard_look(rng))
		guards.append(g)
	# Llegan por el pasillo de detrás de la silla: A al flanco +, B rodea la silla hacia el flanco -.
	var start := _clamp_room(seat_pos + back * 1.1 + side * 3.2)
	var spot_a := seat_pos + side * 0.62
	var spot_b := seat_pos - side * 0.62
	var behind := seat_pos + back * 0.95
	var dur_a := _walk(guards[0], [start, spot_a])
	var dur_b := _walk(guards[1], [start + side * 0.3, behind, spot_b])
	if not await _pause(maxf(dur_a, dur_b) + 0.1):
		return
	for g in guards:
		g.play(&"walk", 0.2, 0.0)
		g.animation_player().seek(0.0, true)
		g.rotation.y = figure_yaw(g.global_position, seat_pos)
	victim.set_look(0.0, 0.0)
	play_sound(&"struggle", seat_pos, 8.0, victim)
	_slide(chair, chair.global_position + back * CHAIR_BACK, 0.7, 0.1)
	await victim.play_role_once(&"stand_up")
	# Por los pasillos hasta el perímetro, entre los dos guardias.
	var out := Vector3(seat_pos.x, 0.0, seat_pos.z)
	out = out.normalized() if out.length() > 0.5 else Vector3.RIGHT
	var exit := _clamp_room(seat_pos + out * 40.0)
	var path: Array[Vector3] = [seat_pos]
	path.append_array(ArbiterRoutes.route(seat_pos + back * 0.9, exit))
	if path.size() < 2:
		path.append(exit)
	victim.play_role(&"dragged")
	for g in guards:
		g.play_role(&"walk")
	var dur := _walk(victim, path, 0.0)
	_walk(guards[0], path, 0.62)
	_walk(guards[1], path, -0.62)
	play_sound(&"shout", seat_pos, 2.0, victim)
	if not await _pause(dur + 0.2):
		return
	# La silla vuelve vacía; los tres desaparecen en la oscuridad. Quien se llevan no regresa.
	chair.global_position = chair.global_position - back * CHAIR_BACK
	for f in [victim, guards[0], guards[1]]:
		if is_instance_valid(f):
			f.visible = false
	for g in guards:
		g.queue_free()
	bt.take_away(seat)


## Hace caminar a `fig` por `pts` a la velocidad del modelo, con `lateral` m de desvío a la derecha
## del camino. Mira hacia donde avanza. Devuelve la duración (s).
func _walk(fig: CharacterFigure, pts: Array, lateral: float = 0.0) -> float:
	var pos: Array[Vector3] = []
	for p in pts:
		pos.append(Vector3(p.x, 0.0, p.z))
	var lens: Array[float] = [0.0]
	for i in range(1, pos.size()):
		lens.append(lens[i - 1] + pos[i].distance_to(pos[i - 1]))
	var total: float = maxf(lens[lens.size() - 1], 0.01)
	var dur := total / CharacterFigure.WALK_SPEED
	fig.global_position = pos[0]
	var tw := create_tween()
	tw.tween_method(func(u: float) -> void:
		if not is_instance_valid(fig):
			return
		var d := u * total
		var i := 1
		while i < pos.size() - 1 and lens[i] < d:
			i += 1
		var seg := maxf(lens[i] - lens[i - 1], 0.001)
		var k := clampf((d - lens[i - 1]) / seg, 0.0, 1.0)
		var dir := (pos[i] - pos[i - 1]).normalized()
		var right := Vector3(-dir.z, 0.0, dir.x)
		fig.global_position = pos[i - 1].lerp(pos[i], k) + right * lateral
		fig.rotation.y = figure_yaw(Vector3.ZERO, dir), 0.0, 1.0, dur)
	return dur


func _clamp_room(p: Vector3) -> Vector3:
	return Vector3(
		clampf(p.x, -Hall.ROOM_HALF_X + ROOM_MARGIN, Hall.ROOM_HALF_X - ROOM_MARGIN),
		0.0,
		clampf(p.z, -Hall.ROOM_HALF_Z + ROOM_MARGIN, Hall.ROOM_HALF_Z - ROOM_MARGIN))


# --- Pieza que se cae --------------------------------------------------------------------------

## Una pieza se le escapa al rival: cae sobre la mesa junto al tablero, rueda hasta
## el borde y cae al suelo, con un golpe en cada contacto.
func drop_piece(color: int, side: float = -1.0) -> Node3D:
	var piece := PieceFactory.build(ChessPiece.make(color, ChessPiece.BISHOP))
	piece.name = "PiezaCaida"
	add_child(piece)
	var lying := BoardView.TABLE_TOP + 0.018
	# `side` = -1: cae a la derecha del rival (-X; allí se inclina `sit_pick_up`); +1 a su izquierda.
	var start := Vector3(side * 0.27, BoardView.BOARD_TOP + 0.09, -0.33)
	var on_table := Vector3(side * 0.37, lying, -0.14)
	var edge := Vector3(side * 0.62, lying, -0.10)
	var land := Vector3(side * 0.74, 0.02, -0.06)
	piece.position = start
	var tw := create_tween()
	tw.tween_property(piece, "position", on_table, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(piece, "rotation:z", deg_to_rad(-90.0), 0.3)
	tw.tween_callback(play_sound.bind(&"clack", on_table, 2.0))
	tw.tween_property(piece, "position", edge, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(piece, "rotation:x", deg_to_rad(540.0), 0.55)
	tw.tween_property(piece, "position", land, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(piece, "rotation:z", deg_to_rad(-200.0), 0.3)
	tw.tween_callback(play_sound.bind(&"clack", land, 4.0))
	tw.tween_property(piece, "position:y", land.y + 0.04, 0.08).set_ease(Tween.EASE_OUT)
	tw.tween_property(piece, "position:y", land.y, 0.08).set_ease(Tween.EASE_IN)
	tw.tween_interval(40.0)
	tw.tween_callback(func() -> void:
		if is_instance_valid(piece):
			piece.queue_free())
	return piece
