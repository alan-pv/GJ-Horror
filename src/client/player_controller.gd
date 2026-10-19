class_name PlayerController
extends Node3D
## Jugador humano en primera persona, sentado en su silla (+Z, mirando a -Z). Su cuerpo es una
## `SeatedFigure` (`body`) con la cabeza oculta y la cámara en los ojos; su brazo derecho es el
## que mueve las piezas (`hand_rig`, por IK). Mira con el ratón (capturado;
## en web hay que hacer clic para capturarlo, Esc lo suelta), manda su mirada
## al servidor unas 10 veces por segundo y elige casillas con un rayo desde
## el centro de la pantalla contra el plano del tablero.
##
## Clic en pieza propia → resalta los destinos legales → clic en destino →
## `submit_move` (la coronación es siempre a dama). Solo se puede jugar si es
## tu turno, miras el tablero y tu mano está libre.

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
var yaw: float = 0.0
var pitch: float = 0.0
var selected: int = -1

var _head: Node3D
var _legal: Array[ChessMove] = []
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
	idle_rig.rest_at(Vector3(-0.34, BoardView.TABLE_TOP + 0.03, 0.40))
	_apply_debug_camera()


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


func _unhandled_input(event: InputEvent) -> void:
	if _headless:
		return
	if event is InputEventMouseMotion and is_mouse_captured():
		var k := MOUSE_SENSITIVITY * _sensitivity_scale()
		set_look(yaw - event.relative.x * k, pitch - event.relative.y * k)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not is_mouse_captured():
			capture_mouse(true)
		else:
			_click()
	elif event.is_action_pressed("ui_cancel"):
		capture_mouse(false)
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
	# Si ya no es posible jugar (turno rival, fin), se limpia la selección.
	if selected >= 0 and not _my_turn():
		_deselect()


func _my_turn() -> bool:
	return server.started and not server.is_over() and server.board.side_to_move == color \
			and server.pending_press < 0 \
			and not server.accusation_pending() and not server.is_hand_busy(color)


func _can_play() -> bool:
	return _my_turn() and (animator == null or not animator.is_busy())


## Casilla bajo el centro de la pantalla (o -1).
func pick_square() -> int:
	var ray_origin := camera.global_position
	var dir := -camera.global_basis.z
	var p := board.ray_to_board_point(ray_origin, dir)
	if p == Vector3.INF:
		return -1
	return board.world_to_square(p)


func _update_hover() -> void:
	var sq := -1
	if is_mouse_captured() and _can_play():
		sq = pick_square()
	board.set_hover(sq)


func _click() -> void:
	if not _can_play():
		return
	var sq := pick_square()
	if sq < 0:
		_deselect()
		return
	if selected >= 0:
		var move := _find_move(selected, sq)
		if move != null:
			_try_move(move)
			return
	var piece := server.board.squares[sq]
	if piece != ChessPiece.NONE and ChessPiece.color_of(piece) == color and sq != selected:
		_select(sq)
	else:
		_deselect()


## Selecciona una casilla propia por código (pruebas y capturas de depuración).
func select_square(sq: int) -> void:
	_select(sq)


func _select(sq: int) -> void:
	_legal = server.legal_moves()
	var targets: Array = []
	var seen := {}
	for m in _legal:
		if m.from != sq or seen.has(m.to):
			continue
		seen[m.to] = true
		targets.append({"sq": m.to, "capture": _is_capture(m)})
	if targets.is_empty():
		_deselect()
		return
	selected = sq
	board.set_highlights(sq, targets)


func _deselect() -> void:
	selected = -1
	board.clear_highlights()


func _is_capture(m: ChessMove) -> bool:
	if server.board.squares[m.to] != ChessPiece.NONE:
		return true
	# Al paso: un peón que cambia de columna a una casilla vacía.
	return ChessPiece.type_of(server.board.squares[m.from]) == ChessPiece.PAWN \
			and ChessPiece.file_of(m.from) != ChessPiece.file_of(m.to)


## La jugada legal de `from` a `to`; si es coronación, a dama.
func _find_move(from: int, to: int) -> ChessMove:
	for m in _legal:
		if m.from == from and m.to == to and (m.promotion == 0 or m.promotion == ChessPiece.QUEEN):
			return m
	return null


func _try_move(move: ChessMove) -> void:
	# El resultado (incluida la advertencia de principiante) llega por señales.
	server.submit_move(color, move.uci())
	_deselect()
