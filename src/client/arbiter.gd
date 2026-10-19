class_name Arbiter
extends Node3D
## El árbitro: figura de pie y de pocas palabras que espera en la oscuridad,
## al borde del salón. Al acusar camina hasta la mesa dentro de
## `config.arbiter_delay`, mira el tablero, anuncia el veredicto con un gesto
## y vuelve a su sitio. También puede pasar despacio detrás de un punto
## (`pass_behind`), lo que usa el director de eventos como disuasivo: mientras
## está cerca (`is_near`) las trampas se ven.
##
## Es puramente visual; el veredicto lo decide el servidor.

enum State { IDLE, WALKING, AT_TABLE, GESTURE, PASSING }

## Dónde espera, en la penumbra, y dónde se planta junto a la mesa.
const HOME := Vector3(-1.6, 0.0, -4.6)
const TABLE_SPOT := Vector3(-1.05, 0.0, 0.12)
const WALK_SPEED := 1.35
const HIP_HEIGHT := 0.84

var state: State = State.IDLE
var root: GameRoot

var _gen: int = 0
var _head: Node3D
var _body: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _step: float = 0.0
var _body_base_y: float = 0.0
var _lantern: OmniLight3D


## Arma la figura y la deja en su sitio de espera. `p_root` puede ser null (pruebas).
func setup(p_root: GameRoot) -> void:
	name = "Arbitro"
	root = p_root
	_build()
	position = HOME
	_face_toward(Vector3.ZERO, true)
	if root != null:
		root.server.accusation_started.connect(_on_accusation_started)
		root.server.accusation_resolved.connect(_on_accusation_resolved)


# --- API pública -------------------------------------------------------------------

## Terminó la ejecución de quien estaba en `seat` (0 = blancas, 1 = negras) de la mesa `table`
## (índice de `HallLayout`; la del humano es `HallLayout.HUMAN_TABLE`).
signal executed(table: int, seat: int)


## Encola la ejecución del perdedor sentado en (`table`, `seat`): el árbitro irá a
## esa mesa y le disparará. Contrato de la oleada 2 (R8 lo implementa; hoy es un
## esbozo que avisa en el siguiente fotograma).
func request_execution(table: int, seat: int) -> void:
	executed.emit.call_deferred(table, seat)


## ¿Quedan ejecuciones o una acusación por atender? La ronda no termina mientras sea true.
func has_pending_work() -> bool:
	return false


## Camina despacio por detrás de `target` (p. ej. la silla del jugador): entra
## por un lado, cruza a lo largo de `seconds` y luego vuelve a su sitio.
## Se ignora si ya está ocupado con una acusación.
func pass_behind(target: Vector3, seconds: float) -> void:
	if state == State.WALKING or state == State.AT_TABLE or state == State.GESTURE:
		return
	_gen += 1
	var gen := _gen
	state = State.PASSING
	# "Detrás" es alejándose de la mesa; el cruce es perpendicular a esa dirección.
	var out := Vector3(target.x, 0.0, target.z)
	out = Vector3(0.0, 0.0, 1.0) if out.length() < 0.2 else out.normalized()
	var side := Vector3(-out.z, 0.0, out.x)
	var mid := Vector3(target.x, 0.0, target.z) + out * 0.9
	# Entra por el lado de su sitio (-x) y sale por el contrario, sin cruzar la mesa.
	var a := mid + side * 1.3
	var b := mid - side * 1.3
	await _walk_to(a, maxf(position.distance_to(a) / (WALK_SPEED * 1.3), 0.5), gen)
	if gen != _gen or not is_inside_tree():
		return
	await _walk_to(b, maxf(seconds, 0.5), gen)
	if gen != _gen or not is_inside_tree():
		return
	# Vuelve rodeando la mesa por el lado de salida (sin atravesar al rival).
	var around := [Vector3(b.x + 0.7, 0.0, 0.0), Vector3(b.x + 0.7, 0.0, -3.2), HOME]
	for p: Vector3 in around:
		await _walk_to(p, position.distance_to(p) / (WALK_SPEED * 1.3), gen)
		if gen != _gen or not is_inside_tree():
			return
	_face_toward(Vector3.ZERO, true)
	state = State.IDLE


## ¿Está a menos de `radius` metros (en el plano del suelo) de `point`?
func is_near(point: Vector3, radius: float) -> bool:
	var here := global_position if is_inside_tree() else position
	var d := Vector2(here.x - point.x, here.z - point.z)
	return d.length() <= radius


# --- Acusaciones ---------------------------------------------------------------------

func _on_accusation_started(_accuser: int) -> void:
	if not is_inside_tree():
		return
	_gen += 1
	var gen := _gen
	state = State.WALKING
	# Llega justo antes de que el servidor resuelva.
	var delay := root.config.arbiter_delay
	var seconds := maxf(delay - 0.4, 0.8)
	await _walk_to(TABLE_SPOT, seconds, gen)
	if gen != _gen or not is_inside_tree():
		return
	state = State.AT_TABLE
	await _look_at_board(gen)


func _on_accusation_resolved(accuser: int, correct: bool, warnings: int) -> void:
	_gen += 1
	var gen := _gen
	# Si no llegó a tiempo, se planta igualmente (el servidor ya decidió).
	if position.distance_to(TABLE_SPOT) > 0.3:
		position = TABLE_SPOT
	state = State.GESTURE
	var accused := ChessPiece.opposite(accuser)
	var text := ""
	if correct:
		text = "Cheating confirmed. %s is disqualified." % _color_name(accused)
	else:
		text = "Nothing irregular here. Warning %d of %d for %s." % [
			warnings, root.config.false_accusations_to_eliminate, _color_name(accuser)]
	root.hud.show_subtitle(text, 4.0)
	await _gesture(correct, accused, gen)
	if gen != _gen or not is_inside_tree():
		return
	await get_tree().create_timer(1.2).timeout
	if gen != _gen or not is_inside_tree():
		return
	state = State.WALKING
	await _walk_to(HOME, position.distance_to(HOME) / WALK_SPEED, gen)
	if gen != _gen or not is_inside_tree():
		return
	_face_toward(Vector3.ZERO, true)
	state = State.IDLE


func _color_name(c: int) -> String:
	return "White" if c == ChessPiece.WHITE else "Black"


# --- Movimiento ------------------------------------------------------------------------

## Camina en línea recta a `dest` en `seconds` segundos, con balanceo de pasos.
func _walk_to(dest: Vector3, seconds: float, gen: int) -> void:
	var from := position
	var dir := dest - from
	dir.y = 0.0
	if dir.length() > 0.01:
		_face_toward(position + dir, false)
	var t := 0.0
	var dur := maxf(seconds, 0.05)
	while t < 1.0:
		if not is_inside_tree():
			return
		await get_tree().process_frame
		if gen != _gen or not is_inside_tree():
			return
		var dt := get_process_delta_time()
		t = minf(t + dt / dur, 1.0)
		var prev := position
		position = from.lerp(dest, t)
		position.y = 0.0
		var moved := position.distance_to(prev)
		_step += moved * 5.2
		_swing(moved / maxf(dt, 0.001))
		if dir.length() > 0.01:
			_face_toward(position + dir, false, dt)
	_swing(0.0)


## Gira hacia un punto (en el plano). `snap` lo hace de golpe; si no, suavizado.
func _face_toward(point: Vector3, snap: bool, dt: float = 0.0) -> void:
	var d := point - position
	d.y = 0.0
	if d.length() < 0.001:
		return
	var yaw := atan2(-d.x, -d.z)
	rotation.y = yaw if snap or dt <= 0.0 else lerp_angle(rotation.y, yaw, clampf(dt * 8.0, 0.0, 1.0))


## Balanceo de piernas y brazos según la velocidad real (m/s).
func _swing(speed: float) -> void:
	var amp := clampf(speed / WALK_SPEED, 0.0, 1.4) * 0.45
	var s := sin(_step) * amp
	_legs[0].rotation.x = s
	_legs[1].rotation.x = -s
	_arms[0].rotation.x = -s * 0.5
	_arms[1].rotation.x = s * 0.5
	_body.position.y = _body_base_y + absf(sin(_step)) * 0.012 * clampf(speed / WALK_SPEED, 0.0, 1.0)


func _look_at_board(gen: int) -> void:
	# Se planta frente a la mesa y baja la cabeza hacia el tablero.
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "rotation:y", atan2(-(0.0 - position.x), -(0.0 - position.z)), 0.4)
	tw.tween_property(_head, "rotation:x", deg_to_rad(-32.0), 0.5)
	await tw.finished
	if gen != _gen or not is_inside_tree():
		return


## Gesto del veredicto: si hubo trampa señala al acusado; si no, extiende la palma y niega.
func _gesture(correct: bool, accused: int, gen: int) -> void:
	var arm := _arms[1]
	var tw := create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(_head, "rotation:x", 0.0, 0.3)
	if correct:
		# Brazo estirado hacia el rival (o el jugador) y sacudida seca.
		var toward_rival := accused != root.human_color
		var yaw := atan2(-(0.0 - position.x), -((-0.55 if toward_rival else 0.55) - position.z))
		tw.tween_property(self, "rotation:y", yaw, 0.35)
		tw.tween_property(arm, "rotation:x", deg_to_rad(-95.0), 0.4)
		tw.tween_property(arm, "rotation:x", deg_to_rad(-80.0), 0.15)
		tw.tween_property(arm, "rotation:x", deg_to_rad(-95.0), 0.15)
	else:
		tw.tween_property(arm, "rotation:x", deg_to_rad(-70.0), 0.35)
		tw.tween_property(_head, "rotation:y", deg_to_rad(18.0), 0.2)
		tw.tween_property(_head, "rotation:y", deg_to_rad(-18.0), 0.3)
		tw.tween_property(_head, "rotation:y", 0.0, 0.2)
	tw.tween_interval(0.5)
	tw.tween_property(arm, "rotation:x", 0.0, 0.4)
	tw.tween_property(_head, "rotation:y", 0.0, 0.1)
	await tw.finished
	if gen != _gen or not is_inside_tree():
		return


# --- Construcción ----------------------------------------------------------------------

func _build() -> void:
	var cloth := Color(0.045, 0.045, 0.055)
	var skin := Color(0.66, 0.60, 0.55)
	var parts := OpponentAvatar.build_figure(skin, cloth, false)
	_body = parts.root
	_head = parts.head
	# La figura base está sentada: se quitan los muslos y se sube al asiento.
	var thighs: Array[Node] = []
	for i in _body.get_child_count():
		var c := _body.get_child(i)
		if c is MeshInstance3D and abs(c.rotation.x - deg_to_rad(90.0)) < 0.01:
			thighs.append(c)
	for t in thighs:
		_body.remove_child(t)
		t.queue_free()
	_body_base_y = HIP_HEIGHT - 0.45 + 0.02
	_body.position = Vector3(0, _body_base_y, 0)
	_body.get_child(0).position = Vector3(0.0, 0.70, 0.0)
	add_child(_body)

	var cloth_mat := StandardMaterial3D.new()
	cloth_mat.albedo_color = cloth
	cloth_mat.roughness = 0.9
	# Piernas con pivote en la cadera, brazos en el hombro.
	for s in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(s * 0.09, HIP_HEIGHT, 0.0)
		add_child(leg)
		var lm := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.075
		cm.height = 0.88
		lm.mesh = cm
		lm.material_override = cloth_mat
		lm.position = Vector3(0, -0.40, 0)
		leg.add_child(lm)
		_legs.append(leg)
	for s in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(s * 0.23, 1.42, 0.0)
		add_child(arm)
		var am := MeshInstance3D.new()
		var acm := CapsuleMesh.new()
		acm.radius = 0.045
		acm.height = 0.62
		am.mesh = acm
		am.material_override = cloth_mat
		am.position = Vector3(0, -0.27, 0)
		arm.add_child(am)
		var hand := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.04
		hm.height = 0.08
		hand.mesh = hm
		var skin_mat := StandardMaterial3D.new()
		skin_mat.albedo_color = skin
		hand.material_override = skin_mat
		hand.position = Vector3(0, -0.6, 0)
		arm.add_child(hand)
		_arms.append(arm)
	# Gorra de árbitro: copa y visera.
	var hat_mat := StandardMaterial3D.new()
	hat_mat.albedo_color = Color(0.02, 0.02, 0.025)
	var crown := MeshInstance3D.new()
	var crm := CylinderMesh.new()
	crm.top_radius = 0.095
	crm.bottom_radius = 0.108
	crm.height = 0.085
	crown.mesh = crm
	crown.material_override = hat_mat
	crown.position = Vector3(0, 0.1, 0.0)
	_head.add_child(crown)
	var brim := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.17, 0.012, 0.075)
	brim.mesh = bm
	brim.material_override = hat_mat
	brim.position = Vector3(0, 0.065, -0.1)
	_head.add_child(brim)
	# Un farol tenue lo hace legible al acercarse a la mesa, sin romper la penumbra.
	_lantern = OmniLight3D.new()
	_lantern.light_color = Color(0.85, 0.75, 0.6)
	_lantern.light_energy = 0.45
	_lantern.omni_range = 2.6
	_lantern.shadow_enabled = false
	_lantern.position = Vector3(0, 1.9, -0.3)
	add_child(_lantern)
