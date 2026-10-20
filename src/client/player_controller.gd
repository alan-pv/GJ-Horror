class_name PlayerController
extends Node3D
## Jugador humano en primera persona, sentado en su silla (+Z, mirando a -Z). Su cuerpo es una
## `SeatedFigure` (`body`) con la cabeza oculta y la cámara en los ojos; su brazo derecho es el
## que mueve las piezas (`hand_rig`, por IK). Mira con el ratón (capturado;
## en web hay que hacer clic para capturarlo, Esc lo suelta), manda su mirada
## al servidor unas 10 veces por segundo y elige casillas con un rayo desde
## el centro de la pantalla contra el plano del tablero.
##
## Clic en cualquier pieza (menos reyes; propia o rival, en tu turno o fuera de él) → mapa de
## calor de adónde puede ir → clic en destino. Nivel 0 = jugada normal (`submit_move`, coronación
## siempre a dama); otro nivel = trampa (`start_cheat`); la pila propia = robo. Toda esa lógica
## vive en `PieceInteraction`; aquí solo se convierte el rayo en destino. Solo se actúa con la
## mano libre (anotar en la planilla no cuenta: la mano suelta la pluma y atiende el gesto).
## `X` aborta la trampa en curso, clic derecho o `Esc` sueltan la pieza, `A` acusa.

signal mouse_capture_changed(captured: bool)

## Suelo bajo el centro del asiento (la silla del salón está a 0,80 m; se avanza un poco para llegar al tablero).
const SEAT := Vector3(0.0, 0.0, 0.72)
## Ojos del jugador: los de la figura sentada (que está girada 180 grados).
const EYE_POSITION := Vector3(0.0, OpponentAvatar.EYE_LOCAL.y, SEAT.z - OpponentAvatar.EYE_LOCAL.z)
const MOUSE_SENSITIVITY := 0.0022
const YAW_LIMIT := deg_to_rad(120.0)
const PITCH_MIN := deg_to_rad(-80.0)
const PITCH_MAX := deg_to_rad(55.0)
const GAZE_INTERVAL := 0.1

var server: MatchServer
var board: BoardView
var animator: HandAnimator
var color: int = ChessPiece.WHITE
var camera: Camera3D
var hand_rig: HandRig
## Mano izquierda (libre): descansa sobre la mesa.
var idle_rig: HandRig
## Cuerpo del jugador (la cabeza se oculta: se ve el torso y los brazos).
var body: SeatedFigure
## Si es false no se manda la mirada (modo autoplay, donde la manda un bot).
var send_gaze: bool = true
## true si la cámara está fija en un punto de depuración (`--shot-cam`).
var debug_camera: bool = false
## true durante la ejecución en primera persona: no se puede mover, hacer trampa, acusar ni mirar
## (la cámara la gira el árbitro hacia el cañón).
var input_locked: bool = false
var yaw: float = 0.0
var pitch: float = 0.0
## Para los subtítulos (lo asigna `GameRoot` al crear el HUD).
var hud: Hud
## Selección de piezas, mapa de calor y envío de jugadas y trampas.
var interaction: PieceInteraction
## Casilla de la pieza elegida (-1 si ninguna).
var selected: int:
	get:
		return interaction.selected if interaction != null else -1

var _head: Node3D
var _gaze_timer: float = 0.0
var _headless: bool = false


func setup(p_server: MatchServer, p_board: BoardView, p_color: int, look: Dictionary = {}) -> void:
	server = p_server
	board = p_board
	color = p_color
	name = "Jugador"
	position = EYE_POSITION
	_headless = DisplayServer.get_name() == "headless"
	_head = Node3D.new()
	_head.name = "Cabeza"
	add_child(_head)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.near = 0.02
	camera.far = 60.0
	camera.current = true
	_head.add_child(camera)
	# Empieza mirando el centro del tablero.
	var to_board := BoardView.CENTER - EYE_POSITION
	pitch = asin(to_board.normalized().y)
	_apply_look()

	# Cuerpo: sentado, mirando a -Z, con la cabeza oculta.
	body = SeatedFigure.new()
	body.name = "Cuerpo"
	body.position = SEAT - EYE_POSITION
	body.rotation.y = PI
	add_child(body)
	body.setup(CharacterFigure.random_look(RandomNumberGenerator.new()) if look.is_empty() else look)
	body.set_hidden_for_first_person(true)
	body.play(&"sit_idle", 0.0)
	# Brazo derecho (el del personaje: queda hacia +X del mundo, del lado del reloj).
	hand_rig = HandRig.new()
	hand_rig.name = "ManoJugador"
	add_child(hand_rig)
	hand_rig.setup(body, &"R")
	idle_rig = HandRig.new()
	idle_rig.name = "ManoLibre"
	add_child(idle_rig)
	idle_rig.setup(body, &"L")
	idle_rig.rest_at(Vector3(-0.34, BoardView.TABLE_TOP + 0.03, 0.40), 20.0)
	_apply_debug_camera()

	interaction = PieceInteraction.new()
	interaction.setup(server, board, color)
	interaction.subtitle = func(text: String, seconds: float) -> void:
		if hud != null:
			hud.show_subtitle(text, seconds)
	interaction.player_ok = func() -> bool:
		return not input_locked and (animator == null or not animator.is_busy_for_action())


## Cámara de depuración para capturas: `--shot-cam=side|px,py,pz,tx,ty,tz[,fov]`.
func _apply_debug_camera() -> void:
	var spec := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-cam="):
			spec = a.substr(11)
	if spec == "":
		return
	var pos := Vector3(1.5, 0.95, 0.0)
	var at := Vector3(0.0, 0.8, 0.0)
	var fov := 40.0
	match spec:
		"side":
			pass
		"sidenear":
			pos = Vector3(1.2, 0.95, 0.35)
			at = Vector3(0.2, 0.8, 0.35)
		"sidefar":
			pos = Vector3(1.2, 0.95, -0.35)
			at = Vector3(0.2, 0.8, -0.35)
		_:
			var v := spec.split(",")
			if v.size() >= 6:
				pos = Vector3(float(v[0]), float(v[1]), float(v[2]))
				at = Vector3(float(v[3]), float(v[4]), float(v[5]))
				if v.size() >= 7:
					fov = float(v[6])
	camera.top_level = true
	camera.fov = fov
	camera.look_at_from_position(pos, at)
	debug_camera = true


func is_mouse_captured() -> bool:
	return not _headless and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func set_look(p_yaw: float, p_pitch: float) -> void:
	yaw = clampf(p_yaw, -YAW_LIMIT, YAW_LIMIT)
	pitch = clampf(p_pitch, PITCH_MIN, PITCH_MAX)
	_apply_look()


func _apply_look() -> void:
	_head.rotation = Vector3(pitch, yaw, 0.0)


## Bloquea o devuelve toda la entrada del jugador (movimiento, trampas, acusación y mirada).
func set_input_locked(on: bool) -> void:
	input_locked = on
	if on:
		interaction.deselect()
		board.set_hover(-1)
		board.set_pile_hover(false)


func _unhandled_input(event: InputEvent) -> void:
	if _headless or input_locked:
		return
	if event is InputEventMouseMotion and is_mouse_captured():
		var k := MOUSE_SENSITIVITY * _sensitivity_scale()
		set_look(yaw - event.relative.x * k, pitch - event.relative.y * k)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not is_mouse_captured():
			capture_mouse(true)
		else:
			interaction.click(pick_target())
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		interaction.deselect()
	elif event.is_action_pressed("ui_cancel"):
		interaction.deselect()
		capture_mouse(false)
	elif event.is_action_pressed("cheat_abort"):
		if server.started and server.abort_cheat(color) and hud != null:
			hud.show_subtitle("...better not")
	elif event.is_action_pressed("accuse"):
		if server.started and not server.is_over():
			server.accuse(color)


## Multiplicador de sensibilidad de los ajustes (1.0 si no existe el autoload).
func _sensitivity_scale() -> float:
	var settings := get_node_or_null("/root/GameSettings")
	return float(settings.mouse_sensitivity) if settings != null else 1.0


func capture_mouse(on: bool) -> void:
	if _headless:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
	mouse_capture_changed.emit(on)


func _process(delta: float) -> void:
	if server == null:
		return
	_gaze_timer -= delta
	if _gaze_timer <= 0.0:
		_gaze_timer = GAZE_INTERVAL
		if send_gaze:
			server.set_gaze(color, camera.global_position, -camera.global_basis.z)
	if not _headless:
		_update_hover()
	# Si ya no se puede actuar (mano ocupada, acusación, fin), se suelta la pieza.
	if interaction.selected >= 0 and not interaction.can_act():
		interaction.deselect()


## Casilla bajo el centro de la pantalla (o -1).
func pick_square() -> int:
	var ray_origin := camera.global_position
	var dir := -camera.global_basis.z
	var p := board.ray_to_board_point(ray_origin, dir)
	if p == Vector3.INF:
		return -1
	return board.world_to_square(p)


## Destino bajo el centro de la pantalla: una casilla, `TO_PILE` si apunta a la zona de la pila
## propia con una pieza rival elegida, o -1.
func pick_target() -> int:
	var sq := pick_square()
	if sq >= 0:
		return sq
	if interaction.levels.has(CheatRules.TO_PILE) \
			and board.ray_to_pile(camera.global_position, -camera.global_basis.z, color):
		return CheatRules.TO_PILE
	return -1


func _update_hover() -> void:
	var sq := -1
	var pile := false
	if is_mouse_captured() and not input_locked and interaction.can_act():
		var t := pick_target()
		if t == CheatRules.TO_PILE:
			pile = true
		else:
			sq = t
	board.set_hover(sq)
	board.set_pile_hover(pile)


## Selecciona una pieza por código (pruebas y capturas de depuración).
func select_square(sq: int) -> void:
	interaction.select(sq)
