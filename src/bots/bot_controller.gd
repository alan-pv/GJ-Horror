class_name BotController
extends Node
## Bot que usa exactamente las mismas intenciones que un jugador: mover,
## mirar, hacer trampa y acusar. El servidor no distingue entre humano y bot.
##
## Máquina de estados de la mirada: VIGILAR (tablero) o DISTRAÍDO (mira un
## punto del salón un rato). Al pensar, la vista vuelve al tablero.

signal looked(yaw: float, pitch: float)

enum Attention { WATCH, DISTRACTED }

const GAZE_SEND_INTERVAL := 0.1
## Cada cuánto evalúa si hace trampa (también al dejar de ser mirado).
const CHEAT_EVAL_INTERVAL := 0.5
## No hace trampa en los primeros segundos de la partida.
const CHEAT_GRACE_START := 6.0
## Pausa tras ser descubierto y entre una trampa y la siguiente.
const CHEAT_COOLDOWN_ACCUSED := 12.0
const CHEAT_COOLDOWN_BETWEEN := Vector2(8.0, 16.0)
## Margen de tiempo antes de entregar la jugada para empezar una trampa propia.
const CHEAT_MOVE_MARGIN := 0.4
## Segundos que el rival debe llevar mirando para que el bot use un evento.
const EVENT_WATCH_SECONDS := 7.0
const EVENT_COOLDOWN := 25.0

var server: MatchServer
var color: int
var personality: BotPersonality
var brain: ChessBrain
## Posición de los ojos del bot en el mundo y centro del tablero.
var eye_position: Vector3
var board_center: Vector3
## Elo del rival (para Maia).
var opponent_elo: int = 1200

## Orientación actual de la cabeza (cámara virtual).
var look_yaw: float = 0.0
var look_pitch: float = 0.0
var attention: Attention = Attention.WATCH

var _target_dir: Vector3
var _distracted_until: float = 0.0
var _thinking: bool = false
var _gaze_timer: float = 0.0
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()
var _verbose: bool = false
# Trampa propia
var _cheat_timer: float = 0.0
var _next_cheat_ok: float = 0.0
var _think_deadline: float = INF
var _abort_at: float = -1.0
var _opp_was_looking: bool = true
var _opp_look_streak: float = 0.0
var _next_event_ok: float = 0.0
var _cheats_made: int = 0
# Vigilancia: trampas del rival ya juzgadas (clave start|id).
var _judged: Dictionary = {}


func setup(p_server: MatchServer, p_color: int, p_personality: BotPersonality, p_brain: ChessBrain, p_eye: Vector3, p_board_center: Vector3) -> void:
	server = p_server
	color = p_color
	personality = p_personality
	brain = p_brain
	eye_position = p_eye
	board_center = p_board_center
	_target_dir = (board_center - eye_position).normalized()
	_set_angles_from_dir(_target_dir)
	_verbose = "--verbose" in OS.get_cmdline_user_args() or "--autoplay" in OS.get_cmdline_user_args()
	_rng.randomize()
	server.cheat_finished.connect(_on_cheat_finished)
	server.move_made.connect(_on_move_made)
	server.accusation_resolved.connect(_on_accusation_resolved)


func _process(delta: float) -> void:
	if server == null:
		return
	_time += delta
	_update_attention()
	_turn_head(delta)
	_gaze_timer -= delta
	if _gaze_timer <= 0.0:
		_gaze_timer = GAZE_SEND_INTERVAL
		server.set_gaze(color, eye_position, Gaze.forward_from_angles(look_yaw, look_pitch))
	_update_cheating(delta)
	_watch_for_cheats()
	if not _thinking and _my_turn():
		_play_turn()


func _my_turn() -> bool:
	return server.started and not server.is_over() and server.board.side_to_move == color \
			and not server.accusation_pending() and not server.is_hand_busy(color)


# --- Atención ----------------------------------------------------------------

## Un evento ruidoso en `world_pos`. `intensity` 0..1 escala la probabilidad.
func notice_event(world_pos: Vector3, intensity: float = 1.0) -> void:
	if _rng.randf() > personality.turn_to_event_chance * intensity:
		return
	# Tarda un instante en reaccionar, como una persona.
	await get_tree().create_timer(_rng.randf_range(0.15, 0.45)).timeout
	_look_at_point(world_pos, _rng.randf_range(personality.look_away_seconds.x, personality.look_away_seconds.y))


func _look_at_point(world_pos: Vector3, seconds: float) -> void:
	attention = Attention.DISTRACTED
	_distracted_until = _time + seconds
	_target_dir = (world_pos - eye_position).normalized()


func _update_attention() -> void:
	if attention == Attention.DISTRACTED:
		if _time >= _distracted_until:
			attention = Attention.WATCH
			_target_dir = (board_center - eye_position).normalized()
		return
	# Vistazos espontáneos al salón, menos frecuentes mientras piensa.
	var rate := personality.idle_glances_per_minute / 60.0
	if _thinking:
		rate *= 0.3
	if _rng.randf() < rate * get_process_delta_time():
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var point := eye_position + Vector3(side * _rng.randf_range(2.0, 6.0), _rng.randf_range(-0.3, 0.8), _rng.randf_range(-4.0, 3.0))
		_look_at_point(point, _rng.randf_range(personality.look_away_seconds.x, personality.look_away_seconds.y))


func _set_angles_from_dir(dir: Vector3) -> void:
	look_yaw = atan2(-dir.x, -dir.z)
	look_pitch = asin(clampf(dir.y, -1.0, 1.0))


func _turn_head(delta: float) -> void:
	var target_yaw := atan2(-_target_dir.x, -_target_dir.z)
	var target_pitch := asin(clampf(_target_dir.y, -1.0, 1.0))
	var step := personality.head_turn_speed * delta
	look_yaw += clampf(wrapf(target_yaw - look_yaw, -PI, PI), -step, step)
	look_pitch += clampf(target_pitch - look_pitch, -step, step)
	looked.emit(look_yaw, look_pitch)


# --- Ajedrez -----------------------------------------------------------------

func _play_turn() -> void:
	_thinking = true
	# Al pensar, la vista vuelve al tablero.
	attention = Attention.WATCH
	_target_dir = (board_center - eye_position).normalized()
	var board := server.board.clone()
	var ply_at_start := server.ply
	var think := think_time(board, server.clock.remaining[color], _rng) * personality.think_time_scale
	_think_deadline = _time + think
	var t0 := Time.get_ticks_msec()
	var policy: Dictionary = await brain.get_policy(board, personality.elo, opponent_elo)
	var spent := (Time.get_ticks_msec() - t0) / 1000.0
	if think > spent:
		await get_tree().create_timer(think - spent).timeout
	# Una sola mano: si está en plena trampa, espera a que termine en vez de perder la jugada.
	while server.ply == ply_at_start and not server.is_over() and (server.is_hand_busy(color) or server.accusation_pending()):
		await get_tree().process_frame
	_think_deadline = INF
	# El tablero pudo cambiar (trampa, acusación, fin) mientras pensaba.
	if server.ply == ply_at_start and _my_turn() and server.board.position_key() == board.position_key():
		var uci := ChessBrain.sample(policy, personality.temperature, _rng)
		if uci != "":
			server.submit_move(color, uci)
	_thinking = false


## Tiempo de pensar: pausas variables según el reloj y la complejidad, no
## respuestas instantáneas. En apuros juega mucho más rápido.
static func think_time(board: BoardState, remaining: float, rng: RandomNumberGenerator) -> float:
	var n := ChessRules.legal_moves(board).size()
	if n <= 1:
		return rng.randf_range(0.4, 0.9)
	var base := 1.2 + 0.06 * n
	if board.fullmove_number <= 6:
		base *= 0.5  # aperturas de memoria
	if ChessRules.in_check(board, board.side_to_move):
		base *= 1.2
	# Distribución log-normal: a veces piensa mucho más.
	var t := base * exp(rng.randfn(0.0, 0.45))
	var budget := remaining / 25.0
	if remaining < 20.0:
		budget = remaining / 40.0
	return clampf(minf(t, budget * 2.0), 0.3, 12.0)


# --- Trampa propia --------------------------------------------------------------

func _update_cheating(delta: float) -> void:
	if server.is_over() or not server.started:
		return
	var opp := ChessPiece.opposite(color)
	var opp_looking := server.is_looking(opp)
	_opp_look_streak = _opp_look_streak + delta if opp_looking else 0.0
	var just_left := _opp_was_looking and not opp_looking
	var just_looked := opp_looking and not _opp_was_looking
	_opp_was_looking = opp_looking

	# A mitad de trampa: si el rival empieza a mirar, quizá se asusta y aborta.
	var active: Variant = server.active_cheat(color)
	if active != null:
		if just_looked and _abort_at < 0.0:
			var def := server.get_cheat(active.cheat_id)
			if _rng.randf() < CheatPlanner.abort_probability(personality, def.evidence):
				_abort_at = _time + _rng.randf_range(0.2, 0.6)
		if _abort_at >= 0.0 and _time >= _abort_at:
			_abort_at = -1.0
			if server.active_cheat(color) != null and server.abort_cheat(color):
				_log("aborta %s (el rival miró)" % active.cheat_id)
		return
	_abort_at = -1.0

	_cheat_timer -= delta
	if just_left:
		_cheat_timer = minf(_cheat_timer, _rng.randf_range(0.15, 0.4))
	if _cheat_timer > 0.0:
		return
	_cheat_timer = CHEAT_EVAL_INTERVAL
	_consider_cheating(opp_looking)


func _consider_cheating(opp_looking: bool) -> void:
	if server.accusation_pending() or server.is_hand_busy(color):
		return
	if server.time < CHEAT_GRACE_START or server.time < _next_cheat_ok:
		return
	var p := CheatPlanner.attempt_probability(server.board, color, personality, server.clock.remaining[color], opp_looking)
	if opp_looking:
		_maybe_distract_rival()
		return
	if _rng.randf() >= p:
		return
	var plan := CheatPlanner.plan(server.board, color, server.config.cheats, _rng)
	if plan.is_empty():
		return
	# En mi turno, no empezar algo que ocupe la mano cuando ya debo entregar la jugada.
	if server.board.side_to_move == color:
		if not _thinking or _think_deadline - _time < plan.duration + CHEAT_MOVE_MARGIN:
			return
	var def: CheatDef = plan.def
	var res := server.start_cheat(color, def.id, plan.from, plan.to)
	if res.ok:
		_cheats_made += 1
		_next_cheat_ok = server.time + res.duration + _rng.randf_range(CHEAT_COOLDOWN_BETWEEN.x, CHEAT_COOLDOWN_BETWEEN.y)
		_log("hace trampa %s %s->%s (ganancia %.0f, dura %.1fs)" % [def.id, ChessPiece.square_name(plan.from), ChessPiece.square_name(plan.to) if plan.to >= 0 else "mano", plan.gain, res.duration])


## Si el rival no deja de mirar y quiere hacer trampa, intenta distraerlo con un evento.
## Los eventos también son sospechosos, así que se usan con cuentagotas.
func _maybe_distract_rival() -> void:
	if not server.has_method("trigger_rival_event") or _opp_look_streak < EVENT_WATCH_SECONDS or server.time < _next_event_ok:
		return
	# Solo quien tiene ganas de hacer trampa (la probabilidad base sin la condición de mirada).
	var want := CheatPlanner.attempt_probability(server.board, color, personality, server.clock.remaining[color], false)
	if _rng.randf() >= minf(want * 6.0, 0.6):
		return
	_next_event_ok = server.time + EVENT_COOLDOWN
	var event_id: StringName = &"cough" if _rng.randf() < 0.6 else &"drop_piece"
	var r: Variant = server.call("trigger_rival_event", color, event_id)
	_log("evento %s: %s" % [event_id, str(r)])


func _on_accusation_resolved(accuser: int, correct: bool, _warnings: int) -> void:
	if accuser != color and correct:
		_next_cheat_ok = maxf(_next_cheat_ok, server.time + CHEAT_COOLDOWN_ACCUSED)


# --- Vigilancia ----------------------------------------------------------------

## Mirando el tablero durante una trampa rival: puede acusar con las manos en la masa.
func _watch_for_cheats() -> void:
	if server.is_over() or server.accusation_pending() or not server.is_looking(color):
		return
	var cheater := ChessPiece.opposite(color)
	var entry: Variant = server.active_cheat(cheater)
	if entry == null:
		return
	var key := _entry_key(entry)
	if _judged.has(key):
		return
	_judged[key] = true
	var def := server.get_cheat(entry.cheat_id)
	if _rng.randf() < personality.detect_chance * def.evidence:
		await get_tree().create_timer(_rng.randf_range(0.3, 1.0)).timeout
		# Si el rival abortó, ya no hay trampa que probar.
		if not server.is_over() and not server.is_hand_busy(color) and entry.status != "aborted":
			_log("acusa (trampa en curso %s)" % entry.cheat_id)
			server.accuse(color)


func _entry_key(entry: Dictionary) -> String:
	return "%s|%s" % [entry.start, entry.cheat_id]


func _on_cheat_finished(cheater: int, _cheat_id: StringName, _from: int, _to: int) -> void:
	if cheater == color or server.is_over():
		return
	var entry: Variant = _last_entry_of(cheater)
	if entry == null or not entry.seen or _judged.has(_entry_key(entry)):
		return
	_judged[_entry_key(entry)] = true
	var def := server.get_cheat(entry.cheat_id)
	var p := personality.detect_chance * lerpf(0.5, 1.0, def.evidence)
	if _rng.randf() < p:
		await get_tree().create_timer(_rng.randf_range(0.5, 1.5)).timeout
		if not server.is_over() and not server.is_hand_busy(color):
			_log("acusa (vio la trampa %s)" % entry.cheat_id)
			server.accuse(color)


func _on_move_made(mover: int, _uci: String, _info: Dictionary) -> void:
	if mover == color or server.is_over():
		return
	if _rng.randf() < personality.false_accuse_chance:
		await get_tree().create_timer(_rng.randf_range(0.8, 2.0)).timeout
		if not server.is_over() and not server.is_hand_busy(color):
			_log("acusa sin motivo")
			server.accuse(color)


func _last_entry_of(cheater: int) -> Variant:
	for i in range(server.cheat_log.size() - 1, -1, -1):
		if server.cheat_log[i].color == cheater:
			return server.cheat_log[i]
	return null


func _log(text: String) -> void:
	if _verbose:
		print("[bot %s %.1f] %s" % ["blancas" if color == ChessPiece.WHITE else "negras", server.time, text])
