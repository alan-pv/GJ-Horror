class_name EventStage
extends Node3D
## Escenografía de los eventos: apagón, objeto que cae a las espaldas del
## jugador, figura que acusa en otra mesa, guardias que se llevan a alguien y la
## pieza que se le cae al rival. Todo con primitivas (renderer Compatibility) y
## animado con tweens. Los sonidos son espaciales (`AudioStreamPlayer3D`) y
## salen de `EventSounds`.

const ROOM_MARGIN := 0.8
const SKIN := Color(0.50, 0.38, 0.31)

var hall: Hall

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


# --- Figuras de pie ------------------------------------------------------------------

## Figura de pie con brazos articulados en el hombro. Mira hacia -Z local.
## Devuelve {root, head, arm_l, arm_r}.
static func standing_figure(cloth: Color, skin: Color, height_scale: float = 1.0, cap: bool = false, glow: float = 0.5) -> Dictionary:
	var root := Node3D.new()
	var cloth_mat := StandardMaterial3D.new()
	cloth_mat.albedo_color = cloth
	cloth_mat.roughness = 0.9
	# Un poco de brillo propio para que la silueta se lea aun fuera de la luz.
	cloth_mat.emission_enabled = true
	cloth_mat.emission = cloth
	cloth_mat.emission_energy_multiplier = glow
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = skin
	skin_mat.roughness = 0.7
	skin_mat.emission_enabled = true
	skin_mat.emission = skin
	skin_mat.emission_energy_multiplier = glow * 0.6
	var body := Node3D.new()
	body.scale = Vector3(1.0, height_scale, 1.0)
	root.add_child(body)
	var torso := _capsule(0.19, 0.82, cloth_mat, Vector3(0.0, 1.13, 0.0))
	body.add_child(torso)
	for s in [-1.0, 1.0]:
		body.add_child(_capsule(0.08, 0.8, cloth_mat, Vector3(s * 0.1, 0.42, 0.0)))
	var head := Node3D.new()
	head.name = "Cabeza"
	head.position = Vector3(0.0, 1.70, 0.0)
	body.add_child(head)
	var skull := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.105
	sm.height = 0.23
	skull.mesh = sm
	skull.material_override = skin_mat
	head.add_child(skull)
	var nose := MeshInstance3D.new()
	var nm := SphereMesh.new()
	nm.radius = 0.016
	nm.height = 0.032
	nose.mesh = nm
	nose.material_override = skin_mat
	nose.position = Vector3(0.0, -0.01, -0.105)
	head.add_child(nose)
	if cap:
		var hat := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.1
		cm.bottom_radius = 0.115
		cm.height = 0.07
		hat.mesh = cm
		hat.material_override = cloth_mat
		hat.position = Vector3(0.0, 0.1, 0.0)
		head.add_child(hat)
	var arms := []
	for s in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(s * 0.27, 1.46 * height_scale, 0.0)
		root.add_child(pivot)
		pivot.add_child(_capsule(0.045, 0.6, cloth_mat, Vector3(0.0, -0.28, 0.0)))
		arms.append(pivot)
	return {"root": root, "head": head, "arm_l": arms[0], "arm_r": arms[1]}


static func _capsule(radius: float, height: float, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	cm.radial_segments = 12
	cm.rings = 3
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	return mi


## Yaw para que un nodo que mira a -Z quede de frente a `to` viendo desde `from`.
static func yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))


## Mesa decorativa más cercana a `origin` (en XZ), o null.
func _table_near(origin: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := 0.6
	for c in hall.get_children():
		var t := c as Node3D
		if t == null or t.get_node_or_null("Silla") == null:
			continue
		var d := Vector2(t.global_position.x - origin.x, t.global_position.z - origin.z).length()
		if d < best_d:
			best_d = d
			best = t
	return best


## Asiento ocupado de esa mesa: {pos (mundo), seated (figura sentada o null)}.
func _seat_at(origin: Vector3) -> Dictionary:
	var table := _table_near(origin)
	if table == null:
		return {"pos": Vector3(origin.x, 0.0, origin.z), "seated": null}
	for c in table.get_children():
		if c is Node3D and c.get_node_or_null("Cabeza") != null:
			var p := (c as Node3D).global_position
			# Se levanta un poco hacia atrás de la silla, no dentro de la mesa.
			var away := Vector3(p.x - table.global_position.x, 0.0, p.z - table.global_position.z).normalized()
			return {"pos": Vector3(p.x, 0.0, p.z) + away * 0.05, "seated": c}
	return {"pos": table.to_global(Vector3(0.0, 0.0, 0.8)), "seated": null}


# --- Acusación ajena ---------------------------------------------------------------------

## Alguien de otra mesa se levanta, señala hacia el jugador y grita "¡trampa!".
func accuser(origin: Vector3, duration: float, toward: Vector3) -> void:
	var seat := _seat_at(origin)
	var seated: Node3D = seat.seated
	var pos: Vector3 = seat.pos
	var fig := standing_figure(Color(0.46, 0.20, 0.18), SKIN)
	var root: Node3D = fig.root
	add_child(root)
	root.global_position = pos
	root.rotation.y = yaw_to(pos, toward)
	if seated != null:
		seated.visible = false
	root.scale = Vector3(1.0, 0.7, 1.0)
	var tw := create_tween()
	tw.tween_property(root, "scale:y", 1.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(fig.arm_r, "rotation:x", deg_to_rad(105.0), 0.18)
	tw.tween_callback(play_sound.bind(&"shout", pos + Vector3(0.0, 1.5, 0.0), 6.0))
	var hold := maxf(duration - 1.2, 0.5)
	tw.tween_method(_shake_arm.bind(fig.arm_r, root), 0.0, 1.0, hold)
	tw.tween_property(fig.arm_r, "rotation:x", 0.0, 0.3)
	tw.tween_property(root, "scale:y", 0.7, 0.25)
	tw.tween_callback(func() -> void:
		if seated != null and is_instance_valid(seated):
			seated.visible = true
		root.queue_free())


func _shake_arm(u: float, arm: Node3D, body: Node3D) -> void:
	arm.rotation.x = deg_to_rad(105.0 + sin(u * 40.0) * 12.0)
	body.rotation.z = sin(u * 31.0) * 0.04


# --- Eliminación en otra mesa -----------------------------------------------------------

## Dos guardias llegan, sujetan a la figura de la mesa y se la llevan a rastras hacia la oscuridad.
func drag_away(origin: Vector3, duration: float) -> void:
	var seat := _seat_at(origin)
	var seated: Node3D = seat.seated
	var v_pos: Vector3 = seat.pos
	if seated != null:
		# Quien se llevan ya no vuelve a su silla.
		seated.visible = false
	var out_dir := Vector3(v_pos.x, 0.0, v_pos.z)
	out_dir = out_dir.normalized() if out_dir.length() > 0.5 else Vector3(1.0, 0.0, 0.0)
	var start := _clamp_room(v_pos - out_dir * 5.5)
	var exit := _clamp_room(v_pos + out_dir * 40.0)
	var victim := standing_figure(Color(0.46, 0.20, 0.18), SKIN)
	var guard_a := standing_figure(Color(0.035, 0.035, 0.045), Color(0.60, 0.55, 0.50), 1.12, true, 1.6)
	var guard_b := standing_figure(Color(0.035, 0.035, 0.045), Color(0.60, 0.55, 0.50), 1.12, true, 1.6)
	for f in [victim, guard_a, guard_b]:
		add_child(f.root)
	var st := {
		"v": v_pos, "start": start, "exit": exit, "victim": victim,
		"a": guard_a, "b": guard_b, "duration": duration, "grabbed": false,
	}
	_drag_step(0.0, st)
	var tw := create_tween()
	tw.tween_method(_drag_step.bind(st), 0.0, 1.0, duration)
	tw.tween_callback(func() -> void:
		for f in [victim, guard_a, guard_b]:
			f.root.queue_free())


func _clamp_room(p: Vector3) -> Vector3:
	return Vector3(
		clampf(p.x, -Hall.ROOM_HALF_X + ROOM_MARGIN, Hall.ROOM_HALF_X - ROOM_MARGIN),
		0.0,
		clampf(p.z, -Hall.ROOM_HALF_Z + ROOM_MARGIN, Hall.ROOM_HALF_Z - ROOM_MARGIN))


func _drag_step(u: float, st: Dictionary) -> void:
	const WALK_END := 0.3
	const GRAB_END := 0.36
	var v: Vector3 = st.v
	var start: Vector3 = st.start
	var exit: Vector3 = st.exit
	var t: float = u * st.duration
	var walking := u < WALK_END
	var center: Vector3
	var dir: Vector3
	if walking:
		center = start.lerp(v, smoothstep(0.0, 1.0, u / WALK_END))
		dir = (v - start).normalized()
	elif u < GRAB_END:
		center = v
		dir = (v - start).normalized()
	else:
		center = v.lerp(exit, (u - GRAB_END) / (1.0 - GRAB_END))
		dir = (exit - v).normalized()
	var side := Vector3(-dir.z, 0.0, dir.x)
	var victim: Dictionary = st.victim
	var ga: Dictionary = st.a
	var gb: Dictionary = st.b
	var moving := walking or u >= GRAB_END
	var bob := absf(sin(t * 6.5)) * 0.045 if moving else 0.0

	if walking:
		# Los guardias avanzan; la víctima sigue de pie, sin enterarse.
		ga.root.global_position = center + side * 0.4 - dir * 0.2 + Vector3(0.0, bob, 0.0)
		gb.root.global_position = center - side * 0.4 - dir * 0.2 + Vector3(0.0, bob, 0.0)
		victim.root.global_position = v
		victim.root.rotation.y = yaw_to(v, start)
	else:
		if not st.grabbed:
			st.grabbed = true
			play_sound(&"struggle", v, 8.0, victim.root)
			play_sound(&"shout", v, 2.0, victim.root)
		ga.root.global_position = center + side * 0.42 + Vector3(0.0, bob, 0.0)
		gb.root.global_position = center - side * 0.42 + Vector3(0.0, bob, 0.0)
		victim.root.global_position = center + Vector3(0.0, bob * 0.4, 0.0)
		# La víctima va de espaldas al camino, echada hacia atrás y forcejeando.
		victim.root.rotation = Vector3(0.0, yaw_to(center, center - dir), sin(t * 14.0) * 0.18)
		victim.arm_l.rotation.x = 2.3 + sin(t * 17.0) * 0.5
		victim.arm_r.rotation.x = 2.3 + sin(t * 13.0 + 1.0) * 0.5
	var yaw := yaw_to(Vector3.ZERO, dir)
	ga.root.rotation.y = yaw
	gb.root.rotation.y = yaw
	var grip := 0.0 if walking else 1.2
	ga.arm_l.rotation.x = grip
	gb.arm_r.rotation.x = grip


# --- Pieza que se cae --------------------------------------------------------------------------

## Una pieza se le escapa al rival: cae sobre la mesa junto al tablero, rueda hasta
## el borde y cae al suelo, con un golpe en cada contacto.
func drop_piece(color: int) -> void:
	var piece := PieceFactory.build(ChessPiece.make(color, ChessPiece.BISHOP))
	piece.name = "PiezaCaida"
	add_child(piece)
	var lying := BoardView.TABLE_TOP + 0.018
	var start := Vector3(0.27, BoardView.BOARD_TOP + 0.09, -0.33)
	var on_table := Vector3(0.37, lying, -0.14)
	var edge := Vector3(0.62, lying, -0.10)
	var land := Vector3(0.74, 0.02, -0.06)
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
	tw.tween_callback(piece.queue_free)
