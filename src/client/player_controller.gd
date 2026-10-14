class_name PlayerController
extends Node3D
## Jugador humano en primera persona, sentado. Mira con el ratón (capturado;
## en web hay que hacer clic para capturarlo, Esc lo suelta), manda su mirada
## al servidor unas 10 veces por segundo y elige casillas con un rayo desde
## el centro de la pantalla contra el plano del tablero.
##
## Clic en pieza propia → resalta los destinos legales → clic en destino →
## `submit_move` (la coronación es siempre a dama). Solo se puede jugar si es
## tu turno, miras el tablero y tu mano está libre.

signal mouse_capture_changed(captured: bool)

const EYE_POSITION := Vector3(0.0, 1.13, 0.52)
const SHOULDER_POSITION := Vector3(0.24, 0.96, 0.50)
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
## Si es false no se manda la mirada (modo autoplay, donde la manda un bot).
var send_gaze: bool = true
var yaw: float = 0.0
var pitch: float = 0.0
var selected: int = -1

var _head: Node3D
var _legal: Array[ChessMove] = []
var _gaze_timer: float = 0.0
var _headless: bool = false


func setup(p_server: MatchServer, p_board: BoardView, p_color: int) -> void:
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

	hand_rig = HandRig.new()
	hand_rig.name = "ManoJugador"
	# Brazo derecho, ligeramente atrás y debajo de los ojos.
	hand_rig.position = SHOULDER_POSITION - EYE_POSITION
	add_child(hand_rig)
	hand_rig.setup(1.0, Color(0.14, 0.20, 0.34), Color(0.80, 0.62, 0.50))


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
		set_look(yaw - event.relative.x * MOUSE_SENSITIVITY, pitch - event.relative.y * MOUSE_SENSITIVITY)
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
	_legal = ChessRules.legal_moves(server.board)
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
