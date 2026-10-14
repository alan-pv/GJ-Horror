class_name MatchServer
extends RefCounted
## Una partida con autoridad del servidor. Humanos y bots usan exactamente las
## mismas intenciones (mover, mirar, hacer trampa, acusar); el servidor valida,
## decide y avisa por señales. Nada que decida el resultado vive en el cliente.
##
## En el prototipo corre en el mismo proceso que el cliente, pero solo se
## comunica por esta frontera para que el paso a red no obligue a reescribir.

signal state_changed
signal move_made(color: int, uci: String, info: Dictionary)
signal beginner_warning(color: int, uci: String, text: String)
signal cheat_started(color: int, cheat_id: StringName, from: int, to: int, duration: float)
signal cheat_aborted(color: int, cheat_id: StringName)
signal cheat_finished(color: int, cheat_id: StringName, from: int, to: int)
signal accusation_started(accuser: int)
signal accusation_resolved(accuser: int, correct: bool, warnings: int)
signal game_over(winner: int, reason: String)

const REASON_CHECKMATE := "jaque mate"
const REASON_TIMEOUT := "tiempo agotado"
const REASON_STALEMATE := "ahogado: las tablas ganan negras"
const REASON_REPETITION := "triple repetición: las tablas ganan negras"
const REASON_FIFTY := "regla de 50 jugadas: las tablas ganan negras"
const REASON_MATERIAL := "material insuficiente: las tablas ganan negras"
const REASON_CAUGHT := "trampa descubierta"
const REASON_FALSE_ACCUSATIONS := "tercera acusación falsa"

var config: MatchConfig
var board: BoardState
var clock: ChessClock
## sessions[color]
var sessions: Array[PlayerSession] = []
## Segundos de servidor desde el inicio de la partida.
var time: float = 0.0
var started: bool = false
var winner: int = -1
var end_reason: String = ""

## Historial de trampas: {color, cheat_id, from, to, start, end, ply, seen, status}.
## status: "active", "done" o "aborted". Sirve para resolver acusaciones.
var cheat_log: Array[Dictionary] = []
var move_log: Array[Dictionary] = []
var ply: int = 0

var _looking: Array[bool] = [true, true]
var _last_move_time: PackedFloat64Array = [0.0, 0.0]
var _active_cheat: Array = [null, null]
var _pending_accusation: Dictionary = {}
var _position_counts: Dictionary = {}
var _warned: Dictionary = {}
var _cheats_by_id: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _init(p_config: MatchConfig, white: PlayerSession, black: PlayerSession, start_fen: String = BoardState.START_FEN, seed_value: int = -1) -> void:
	config = p_config
	sessions = [white, black]
	board = BoardState.from_fen(start_fen)
	clock = ChessClock.new(config.white_seconds, config.black_seconds)
	clock.flagged.connect(_on_flag)
	for c in config.cheats:
		_cheats_by_id[c.id] = c
	if seed_value >= 0:
		_rng.seed = seed_value
	_record_position()


func start() -> void:
	started = true
	clock.start(board.side_to_move)
	state_changed.emit()


func is_over() -> bool:
	return winner >= 0


func is_looking(color: int) -> bool:
	return _looking[color]


func is_hand_busy(color: int) -> bool:
	return _active_cheat[color] != null


func active_cheat(color: int) -> Variant:
	return _active_cheat[color]


func accusation_pending() -> bool:
	return not _pending_accusation.is_empty()


func get_cheat(id: StringName) -> CheatDef:
	return _cheats_by_id.get(id)


func _can_act(color: int) -> String:
	if not started:
		return "la partida no ha empezado"
	if is_over():
		return "la partida terminó"
	if accusation_pending():
		return "el árbitro está en la mesa"
	if color != ChessPiece.WHITE and color != ChessPiece.BLACK:
		return "color inválido"
	return ""


# --- Intenciones -----------------------------------------------------------

## La jugada se registra al soltar la pieza (clic). La animación es solo visual.
## Devuelve {ok, reason, warning}.
func submit_move(color: int, uci: String) -> Dictionary:
	var err := _can_act(color)
	if err == "" and color != board.side_to_move:
		err = "no es tu turno"
	if err == "" and is_hand_busy(color):
		err = "tu mano está ocupada"
	if err != "":
		return {"ok": false, "reason": err, "warning": ""}
	var move := ChessRules.find_legal(board, ChessMove.from_uci(uci))
	if move == null:
		return {"ok": false, "reason": "jugada ilegal", "warning": ""}

	if config.beginner_help and sessions[color].beginner_help:
		var key := board.position_key() + "|" + move.uci()
		if not _warned.has(key):
			var text := BeginnerHelper.check_move(board, move, config.blunder_threshold_cp)
			if text != "":
				# Primer intento: se bloquea. Si insiste con la misma jugada, se permite.
				_warned[key] = true
				beginner_warning.emit(color, move.uci(), text)
				return {"ok": false, "reason": "advertencia", "warning": text}

	var info := ChessRules.apply_move(board, move)
	ply += 1
	_last_move_time[color] = time
	move_log.append({"color": color, "uci": move.uci(), "time": time})
	clock.press(color)
	_record_position()
	move_made.emit(color, move.uci(), info)
	_check_board_end()
	state_changed.emit()
	return {"ok": true, "reason": "", "warning": ""}


## El cliente manda la orientación de su cámara; el servidor decide si mira el tablero.
func set_gaze(color: int, eye: Vector3, forward: Vector3) -> void:
	_looking[color] = Gaze.is_looking(eye, forward, config.board_center, config.gaze_cos_threshold)


## Empieza una trampa. Se puede hacer en cualquier turno; en el propio, el
## reloj sigue corriendo mientras la mano trabaja. Devuelve {ok, reason, duration}.
func start_cheat(color: int, cheat_id: StringName, from: int, to: int = -1) -> Dictionary:
	var err := _can_act(color)
	if err == "" and is_hand_busy(color):
		err = "tu mano está ocupada"
	var def := get_cheat(cheat_id)
	if err == "" and def == null:
		err = "trampa no disponible"
	if err != "":
		return {"ok": false, "reason": err, "duration": 0.0}
	var v := CheatRules.validate(board, color, def, from, to)
	if not v.ok:
		return {"ok": false, "reason": v.reason, "duration": 0.0}
	var entry := {
		"color": color, "cheat_id": cheat_id, "from": from, "to": to,
		"start": time, "end": time + v.duration, "ply": ply,
		"seen": _looking[ChessPiece.opposite(color)], "status": "active",
	}
	cheat_log.append(entry)
	_active_cheat[color] = entry
	cheat_started.emit(color, cheat_id, from, to, v.duration)
	return {"ok": true, "reason": "", "duration": v.duration}


## Abortar a mitad de la trampa: el tablero no cambia y no cuenta como trampa
## para una acusación posterior. La animación de regreso también es visible.
func abort_cheat(color: int) -> bool:
	var entry: Variant = _active_cheat[color]
	if entry == null:
		return false
	entry.status = "aborted"
	_active_cheat[color] = null
	cheat_aborted.emit(color, entry.cheat_id)
	return true


## Llama al árbitro. Cubre solo lo ocurrido desde la última jugada del acusador.
func accuse(color: int) -> Dictionary:
	var err := _can_act(color)
	if err == "" and is_hand_busy(color):
		err = "tu mano está ocupada"
	if err != "":
		return {"ok": false, "reason": err}
	var accused := ChessPiece.opposite(color)
	var correct := false
	for e in cheat_log:
		if e.color == accused and e.status != "aborted" and e.start >= _last_move_time[color]:
			correct = true
			break
	_pending_accusation = {"accuser": color, "correct": correct, "resolve_at": time + config.arbiter_delay}
	if config.pause_clock_on_accusation:
		clock.paused = true
	accusation_started.emit(color)
	return {"ok": true, "reason": ""}


# --- Simulación ------------------------------------------------------------

func tick(delta: float) -> void:
	if not started or is_over():
		return
	time += delta
	if accusation_pending():
		if time >= _pending_accusation.resolve_at:
			_resolve_accusation()
		if config.pause_clock_on_accusation:
			return
	clock.tick(delta)
	if is_over():
		return
	for color in 2:
		var entry: Variant = _active_cheat[color]
		if entry == null:
			continue
		if _looking[ChessPiece.opposite(color)]:
			entry.seen = true
		if time >= entry.end and not accusation_pending():
			_finish_cheat(color, entry)


func _finish_cheat(color: int, entry: Dictionary) -> void:
	_active_cheat[color] = null
	var def := get_cheat(entry.cheat_id)
	# El tablero pudo cambiar mientras la mano trabajaba: se valida de nuevo.
	var v := CheatRules.validate(board, color, def, entry.from, entry.to)
	if not v.ok:
		entry.status = "aborted"
		cheat_aborted.emit(color, entry.cheat_id)
		return
	CheatRules.apply(board, color, def, entry.from, entry.to, _rng)
	entry.status = "done"
	_record_position()
	cheat_finished.emit(color, entry.cheat_id, entry.from, entry.to)
	_check_board_end()
	state_changed.emit()


func _resolve_accusation() -> void:
	var p := _pending_accusation
	_pending_accusation = {}
	clock.paused = false
	var accuser: int = p.accuser
	var session := sessions[accuser]
	if p.correct:
		if config.correct_accusation_clears_warning and session.warnings > 0:
			session.warnings -= 1
		accusation_resolved.emit(accuser, true, session.warnings)
		_end(accuser, REASON_CAUGHT)
	else:
		session.warnings += 1
		# La ventana de la siguiente acusación arranca aquí: así una
		# acusación falsa no se puede repetir sobre lo mismo.
		_last_move_time[accuser] = time
		accusation_resolved.emit(accuser, false, session.warnings)
		if session.warnings >= config.false_accusations_to_eliminate:
			_end(ChessPiece.opposite(accuser), REASON_FALSE_ACCUSATIONS)
	state_changed.emit()


func _record_position() -> void:
	var key := board.position_key()
	_position_counts[key] = _position_counts.get(key, 0) + 1


func _check_board_end() -> void:
	if is_over():
		return
	var side := board.side_to_move
	if ChessRules.legal_moves(board).is_empty():
		if ChessRules.in_check(board, side):
			_end(ChessPiece.opposite(side), REASON_CHECKMATE)
		else:
			_end(ChessPiece.BLACK, REASON_STALEMATE)
	elif ChessRules.insufficient_material(board):
		_end(ChessPiece.BLACK, REASON_MATERIAL)
	elif board.halfmove_clock >= 100:
		_end(ChessPiece.BLACK, REASON_FIFTY)
	elif _position_counts.get(board.position_key(), 0) >= 3:
		_end(ChessPiece.BLACK, REASON_REPETITION)


func _on_flag(color: int) -> void:
	_end(ChessPiece.opposite(color), REASON_TIMEOUT)


func _end(p_winner: int, reason: String) -> void:
	if is_over():
		return
	winner = p_winner
	end_reason = reason
	clock.stop()
	for c in 2:
		if _active_cheat[c] != null:
			_active_cheat[c].status = "aborted"
			_active_cheat[c] = null
	game_over.emit(winner, reason)
