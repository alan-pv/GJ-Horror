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
## Un jugador hizo toser o tiró una pieza a su personaje (lo anima el cliente).
signal rival_event(color: int, event_id: StringName)
## `color` pulsó el reloj: su turno terminó (con `require_clock_press` pasa después de mover).
signal clock_pressed(color: int)
## Se anotó una jugada legal en la planilla de `color`. Las trampas nunca se anotan.
signal sheet_entry(color: int, move_number: int, san: String)

## Eventos que un jugador puede provocar sobre sí mismo.
const RIVAL_EVENT_IDS: Array[StringName] = [&"cough", &"drop_piece"]

const REASON_CHECKMATE := "checkmate"
const REASON_TIMEOUT := "time ran out"
const REASON_STALEMATE := "stalemate: draws go to Black"
const REASON_REPETITION := "threefold repetition: draws go to Black"
const REASON_FIFTY := "fifty-move rule: draws go to Black"
const REASON_MATERIAL := "insufficient material: draws go to Black"
const REASON_CAUGHT := "cheating caught"
const REASON_FALSE_ACCUSATIONS := "third false accusation"
## Solo las partidas de fondo simuladas (`force_end`).
const REASON_RESIGNED := "resignation"

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

## Color que movió y aún no pulsó el reloj (-1 = nadie). Solo con `require_clock_press`.
var pending_press: int = -1
var _pending_san: String = ""
var _pending_number: int = 0
var _sheets: Array[PackedStringArray] = [PackedStringArray(), PackedStringArray()]

var _looking: Array[bool] = [true, true]
var _last_move_time: PackedFloat64Array = [0.0, 0.0]
var _active_cheat: Array = [null, null]
var _pending_accusation: Dictionary = {}
var _position_counts: Dictionary = {}
var _warned: Dictionary = {}
var _cheats_by_id: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## Cuándo (tiempo de servidor) puede repetir cada color cada evento: "color:id" -> segundos.
var _rival_event_ready: Dictionary = {}
var _arbiter_near: bool = false
## Jugadas legales de la posición actual (caché; se invalida al cambiar el tablero).
var _legal_cache: Array[ChessMove] = []
var _legal_key: String = ""
var _legal_valid: bool = false


func _init(p_config: MatchConfig, white: PlayerSession, black: PlayerSession, start_fen: String = BoardState.START_FEN, seed_value: int = -1) -> void:
	config = p_config
	sessions = [white, black]
	board = BoardState.from_fen(start_fen)
	clock = ChessClock.new(config.white_seconds, config.black_seconds, config.increment_seconds)
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


## Jugadas legales de la posición actual. Se calculan una vez por posición y se
## reutilizan en `submit_move`, el fin de partida y quienes las consulten.
func legal_moves() -> Array[ChessMove]:
	var key := board.position_key()
	if not _legal_valid or key != _legal_key:
		_legal_cache = ChessRules.legal_moves(board)
		_legal_key = key
		_legal_valid = true
	return _legal_cache


## Descarta la caché de jugadas legales (el tablero cambió).
func _invalidate_legal() -> void:
	_legal_valid = false


## ¿`color` movió y debe pulsar el reloj para terminar su turno?
func awaiting_press(color: int) -> bool:
	return pending_press == color


## Jugadas anotadas por `color` en notación algebraica (solo las legales).
func scoresheet(color: int) -> PackedStringArray:
	return _sheets[color]


func accusation_pending() -> bool:
	return not _pending_accusation.is_empty()


func get_cheat(id: StringName) -> CheatDef:
	return _cheats_by_id.get(id)


func _can_act(color: int) -> String:
	if not started:
		return "the game has not started"
	if is_over():
		return "the game is over"
	if accusation_pending():
		return "the arbiter is at the table"
	if color != ChessPiece.WHITE and color != ChessPiece.BLACK:
		return "invalid color"
	return ""


# --- Intenciones -----------------------------------------------------------

## La jugada se registra al soltar la pieza (clic). La animación es solo visual.
## Devuelve {ok, reason, warning}.
func submit_move(color: int, uci: String) -> Dictionary:
	var err := _can_act(color)
	if err == "" and pending_press >= 0 and color == board.side_to_move:
		err = "opponent has not pressed the clock"
	if err == "" and color != board.side_to_move:
		err = "it is not your turn"
	if err == "" and is_hand_busy(color):
		err = "your hand is busy"
	if err != "":
		return {"ok": false, "reason": err, "warning": ""}
	var move := _find_legal(ChessMove.from_uci(uci))
	if move == null:
		return {"ok": false, "reason": "illegal move", "warning": ""}

	if config.beginner_help and sessions[color].beginner_help:
		var key := board.position_key() + "|" + move.uci()
		if not _warned.has(key):
			var text := BeginnerHelper.check_move(board, move, config.blunder_threshold_cp)
			if text != "":
				# Primer intento: se bloquea. Si insiste con la misma jugada, se permite.
				_warned[key] = true
				beginner_warning.emit(color, move.uci(), text)
				return {"ok": false, "reason": "warning", "warning": text}

	var san := San.of(board, move) if config.keep_scoresheet else ""
	var number := board.fullmove_number
	var info := ChessRules.apply_move(board, move)
	_invalidate_legal()
	ply += 1
	_last_move_time[color] = time
	move_log.append({"color": color, "uci": move.uci(), "time": time})
	_record_position()
	move_made.emit(color, move.uci(), info)
	if config.require_clock_press:
		pending_press = color
		_pending_san = san
		_pending_number = number
	else:
		_press(color, san, number)
	_check_board_end()
	# Si la jugada terminó la partida no se espera la pulsación: se anota igual.
	if is_over() and pending_press == color:
		_flush_pending_sheet()
	state_changed.emit()
	return {"ok": true, "reason": "", "warning": ""}


## `color` pulsa el reloj: termina su turno, gana el incremento y se anota su
## jugada. Solo vale con una pulsación pendiente (`require_clock_press`).
## Devuelve {ok, reason}.
func press_clock(color: int) -> Dictionary:
	var err := _can_act(color)
	if err == "" and pending_press != color:
		err = "no clock press pending"
	if err != "":
		return {"ok": false, "reason": err}
	var san := _pending_san
	var number := _pending_number
	pending_press = -1
	_press(color, san, number)
	state_changed.emit()
	return {"ok": true, "reason": ""}


func _press(color: int, san: String, number: int) -> void:
	clock.press(color)
	if san != "":
		_sheets[color].append(san)
		sheet_entry.emit(color, number, san)
	clock_pressed.emit(color)


func _flush_pending_sheet() -> void:
	if pending_press >= 0 and _pending_san != "":
		_sheets[pending_press].append(_pending_san)
		sheet_entry.emit(pending_press, _pending_number, _pending_san)
	pending_press = -1


## El cliente manda la orientación de su cámara; el servidor decide si mira el tablero.
func set_gaze(color: int, eye: Vector3, forward: Vector3) -> void:
	_looking[color] = Gaze.is_looking(eye, forward, config.board_center, config.gaze_cos_threshold)


## Empieza una trampa. Se puede hacer en cualquier turno; en el propio, el
## reloj sigue corriendo mientras la mano trabaja. Devuelve {ok, reason, duration}.
func start_cheat(color: int, cheat_id: StringName, from: int, to: int = -1) -> Dictionary:
	var err := _can_act(color)
	if err == "" and is_hand_busy(color):
		err = "your hand is busy"
	var def := get_cheat(cheat_id)
	if err == "" and def == null:
		err = "cheat not available"
	if err != "":
		return {"ok": false, "reason": err, "duration": 0.0}
	var v := CheatRules.validate(board, color, def, from, to)
	if not v.ok:
		return {"ok": false, "reason": v.reason, "duration": 0.0}
	var entry := {
		"color": color, "cheat_id": cheat_id, "from": from, "to": to,
		"start": time, "end": time + v.duration, "ply": ply,
		"seen": _looking[ChessPiece.opposite(color)] or _arbiter_near, "status": "active",
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


## Un evento de distracción sobre el personaje de `color` (toser, tirar una pieza).
## Tiene tiempo de espera por color y evento. Devuelve {ok, reason}.
func trigger_rival_event(color: int, event_id: StringName) -> Dictionary:
	var err := _can_act(color)
	if err == "" and not RIVAL_EVENT_IDS.has(event_id):
		err = "unknown event"
	if err == "" and event_id == &"drop_piece" and is_hand_busy(color):
		err = "your hand is busy"
	var key := "%d:%s" % [color, event_id]
	if err == "" and time < _rival_event_ready.get(key, 0.0):
		err = "you cannot repeat it yet"
	if err != "":
		return {"ok": false, "reason": err}
	_rival_event_ready[key] = time + config.rival_event_cooldown
	rival_event.emit(color, event_id)
	return {"ok": true, "reason": ""}


## Segundos que faltan para que `color` pueda repetir `event_id`.
func rival_event_wait(color: int, event_id: StringName) -> float:
	return maxf(_rival_event_ready.get("%d:%s" % [color, event_id], 0.0) - time, 0.0)


## El árbitro está cerca de la mesa: mientras dure, toda trampa en curso se ve.
func set_arbiter_near(near: bool) -> void:
	_arbiter_near = near


func is_arbiter_near() -> bool:
	return _arbiter_near


## Llama al árbitro. Cubre solo lo ocurrido desde la última jugada del acusador.
func accuse(color: int) -> Dictionary:
	var err := _can_act(color)
	if err == "" and is_hand_busy(color):
		err = "your hand is busy"
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
		if _looking[ChessPiece.opposite(color)] or _arbiter_near:
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
	_invalidate_legal()
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


## Busca la jugada legal equivalente a `m` (misma lógica que `ChessRules.find_legal`).
func _find_legal(m: ChessMove) -> ChessMove:
	if m == null:
		return null
	for lm in legal_moves():
		if lm.from == m.from and lm.to == m.to:
			if lm.promotion == m.promotion:
				return lm
			if m.promotion == 0 and lm.promotion == ChessPiece.QUEEN:
				return lm
	return null


func _check_board_end() -> void:
	if is_over():
		return
	var side := board.side_to_move
	if legal_moves().is_empty():
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


## Termina la partida por decisión externa (las mesas de fondo simuladas:
## abandono o mate "narrado" sin llegar a jugarlo).
func force_end(p_winner: int, reason: String) -> void:
	_end(p_winner, reason)


func _end(p_winner: int, reason: String) -> void:
	if is_over():
		return
	winner = p_winner
	end_reason = reason
	clock.stop()
	# Las trampas en curso se cancelan avisando, para que la vista suelte la mano.
	for c in 2:
		var entry: Variant = _active_cheat[c]
		if entry != null:
			entry.status = "aborted"
			_active_cheat[c] = null
			cheat_aborted.emit(c, entry.cheat_id)
	game_over.emit(winner, reason)
