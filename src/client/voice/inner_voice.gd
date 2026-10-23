class_name InnerVoice
extends Node
## Monólogo interior del jugador. Solo lee estado y escucha señales (nunca llama intenciones del
## servidor); convierte cada suceso en un pedido a la `VoiceQueue` (las frases están en
## `VoiceLines`, los disparadores puros en `VoiceRules`) y muestra lo que sale con
## `Hud.show_subtitle`. Tras un aviso de la ayuda para principiantes calla 3,5 s.

const BEGINNER_MUTE := 3.5
const START_CONTEXT_DELAY := 20.0
const ROUND_DELAY := 2.0
const NUDGE_HANDS_AT := 75.0
const NUDGE_FAIR_AT := 150.0
const CLOCK_MINE_1 := 30.0
const CLOCK_MINE_2 := 10.0
const CLOCK_RIVAL := 20.0
## Tras anunciar un apagón, el flanco de oscuridad no repite la frase durante este tiempo.
const BLACKOUT_ANNOUNCE_WINDOW := 8.0
## Mini tutorial de trampas: demora (s) de cada paso respecto al suceso que lo dispara.
const TUT_PICK_DELAY := 0.5
const TUT_EYES_DELAY := 4.0
const TUT_COVER_DELAY := 5.0

var root: GameRoot
var queue := VoiceQueue.new()

var _now: float = 0.0
var _started: bool = false
var _match_started_at: float = 0.0
var _watch := VoiceRules.GazeWatch.new()
var _blackout: bool = false
## Instante (`_now`) en que se anunció un apagón desde el evento; evita repetir la frase al oscurecerse.
var _blackout_announced_at: float = -1000.0
var _arbiter_near: bool = false
var _human_cheated: bool = false
var _prev_clock: Array[float] = [-1.0, -1.0]
var _queens: Array[int] = [0, 0]


func install(p_root: GameRoot) -> void:
	name = "MonologoInterior"
	root = p_root
	queue.rng.randomize()
	# Torneo nuevo: se borra lo "una vez por torneo".
	if root.manager.round_no <= 1:
		VoiceQueue.reset_tournament()
	add_to_group(Distraction.GROUP)
	root.match_started.connect(_on_match_started)
	root.last_execution_done.connect(func(_t: int) -> void: queue.say(&"last_execution", _now, 1.0))
	root.human_condemned.connect(func() -> void: queue.say(&"condemned", _now))
	root.champion_crowned.connect(func() -> void: queue.say(&"champion", _now))
	var s := root.server
	s.beginner_warning.connect(func(_c: int, _u: String, _t: String) -> void: queue.mute(_now, BEGINNER_MUTE))
	s.cheat_started.connect(_on_cheat_started)
	s.cheat_finished.connect(_on_cheat_finished)
	s.cheat_aborted.connect(_on_cheat_aborted)
	s.accusation_started.connect(_on_accusation_started)
	s.accusation_resolved.connect(_on_accusation_resolved)
	s.state_changed.connect(_on_state_changed)
	s.move_made.connect(_on_move_made)
	if root.arbiter != null:
		root.arbiter.executed.connect(_on_executed)
	if root.player != null and root.player.interaction != null:
		root.player.interaction.piece_picked.connect(_on_piece_picked)
	var intro := root.get_node_or_null("Discurso")
	if intro != null and intro.has_signal("finished"):
		intro.finished.connect(_on_intro_finished)


func _on_intro_finished(full: bool) -> void:
	# Tras el discurso corto no hay monólogo.
	if full:
		queue.say(&"cheat_hint", _now, 1.5)


func _on_match_started(_server: MatchServer) -> void:
	_started = true
	_match_started_at = _now
	var s := root.server
	_queens = [VoiceRules.count_queens(s.board, 0), VoiceRules.count_queens(s.board, 1)]
	var m := root.manager
	if m.round_no <= 1:
		queue.say(&"context_players", _now, START_CONTEXT_DELAY, [VoiceRules.count_word(m.player_count)])
	else:
		var r := VoiceRules.round_start(root.players_left(), m.is_final, m.final_games.is_empty())
		if not r.is_empty():
			queue.say(r.id, _now, ROUND_DELAY, r.fmt)


func _process(delta: float) -> void:
	_now += delta
	if _started and root.tgame != null:
		_poll(delta)
		if root.server.is_over():
			queue.drop_play_only()
	var line := queue.next(_now)
	if not line.is_empty() and root.hud != null:
		if root.get_args().has("verbose"):
			print("[voz %.1f] %s" % [_now, DialogueText.plain(line.text)])
		root.hud.show_subtitle(line.text, line.seconds, true, line.prio == VoiceLines.HIGH)


## ¿La partida del humano sigue en juego?
func _playing() -> bool:
	return _started and root.tgame != null and root.server.started and not root.server.is_over()


func _poll(delta: float) -> void:
	var s := root.server
	if not _playing():
		return
	var me := root.human_color
	var rival := root.rival_color
	var match_time := _now - _match_started_at
	# Apagón (flanco de subida): respaldo para oscuridades que no pasaron por `announce_blackout`.
	var dark := s.is_blackout()
	if dark and not _blackout and _now - _blackout_announced_at > BLACKOUT_ANNOUNCE_WINDOW:
		queue.say_first(&"blackout_first", &"blackout", _now)
		_tutorial(&"tut_cover", TUT_COVER_DELAY)
	_blackout = dark
	# Árbitro cerca (flanco de subida).
	var near := s.is_arbiter_near()
	if near and not _arbiter_near:
		if s.is_hand_busy(me):
			queue.say(&"arbiter_cheating", _now)
		else:
			queue.say(&"arbiter_near", _now)
	_arbiter_near = near
	# Rival distraído.
	var active := not s.is_hand_busy(me)
	if _watch.update(delta, active, s.is_looking(rival)):
		queue.say_first(&"distracted_first", &"distracted", _now)
		_tutorial(&"tut_eyes", TUT_EYES_DELAY)
	# Empujón a hacer trampa.
	if not _human_cheated:
		if match_time >= NUDGE_HANDS_AT and _watch.is_distracted():
			queue.say(&"nudge_hands", _now)
		if match_time >= NUDGE_FAIR_AT and VoiceRules.is_behind(s.board, s.clock, me):
			queue.say(&"nudge_fair", _now)
	# Reloj.
	var mine: float = s.clock.remaining[me]
	var theirs: float = s.clock.remaining[rival]
	if _prev_clock[me] >= 0.0:
		if VoiceRules.crossed(_prev_clock[me], mine, CLOCK_MINE_2):
			queue.say(&"clock_10", _now)
		elif VoiceRules.crossed(_prev_clock[me], mine, CLOCK_MINE_1):
			queue.say(&"clock_30", _now)
		if VoiceRules.crossed(_prev_clock[rival], theirs, CLOCK_RIVAL):
			queue.say(&"clock_rival_20", _now)
	_prev_clock[me] = mine
	_prev_clock[rival] = theirs


## El evento de apagón avisa ANTES de apagar las luces: la frase sale de inmediato. Solo si la
## partida del humano está en juego. Devuelve si se pidió la frase.
func announce_blackout() -> bool:
	if not _playing():
		return false
	if not queue.say_first(&"blackout_first", &"blackout", _now):
		return false
	_blackout_announced_at = _now
	_tutorial(&"tut_cover", TUT_COVER_DELAY)
	return true


## ¿Sigue vigente el mini tutorial? Solo hasta que el jugador hace su primera trampa del torneo.
func _tutorial_on() -> bool:
	return not _human_cheated and not VoiceQueue.tournament_done.has(&"cheat_first")


## Pide un paso del tutorial si sigue vigente (cada uno se dice una vez por torneo).
func _tutorial(id: StringName, delay: float) -> void:
	if _tutorial_on() and _playing():
		queue.say(id, _now, delay)


## El jugador agarró una pieza: la primera vez se explica el mapa de calor; la primera de las rivales,
## que también se pueden mover o llevar a su pila.
func _on_piece_picked(rival_piece: bool) -> void:
	if not _tutorial_on() or not _playing():
		return
	if rival_piece:
		queue.say_first(&"tut_select", &"tut_rival_piece", _now, TUT_PICK_DELAY)
	else:
		queue.say(&"tut_select", _now, TUT_PICK_DELAY)


# --- Señales del servidor ------------------------------------------------------------------------

func _on_cheat_started(color: int, _id: StringName, _from: int, _to: int, _d: float) -> void:
	if color == root.rival_color:
		# Primera trampa del rival del torneo: le recuerda que puede acusar (tecla A), la vea o no
		# (variante 1: no miraba el tablero o había apagón). Si no llega a decirse porque la partida
		# termina, `drop_play_only` la descarta sin marcarla y se reintenta en la siguiente trampa.
		if _playing():
			var s := root.server
			var saw := VoiceRules.can_see_rival_cheat(s.is_looking(root.human_color), s.is_blackout())
			queue.say(&"rival_cheating", _now, 0.8, [], 0 if saw else 1)
		return
	if color != root.human_color:
		return
	_human_cheated = true
	queue.say(&"cheat_first", _now)


func _on_cheat_finished(color: int, _id: StringName, from: int, to: int) -> void:
	if color != root.human_color:
		return
	var seen := false
	var entries := root.server.cheat_log
	for i in range(entries.size() - 1, -1, -1):
		var e := entries[i]
		if e.color == color and e.from == from and e.to == to:
			seen = e.seen
			break
	queue.say(&"cheat_seen" if seen else &"cheat_unseen", _now, 0.8)


func _on_cheat_aborted(color: int, _id: StringName) -> void:
	if color == root.human_color:
		queue.say(&"cheat_abort", _now)


func _on_accusation_started(accuser: int) -> void:
	if accuser == root.rival_color:
		queue.say(&"accused", _now)


func _on_accusation_resolved(accuser: int, correct: bool, warnings: int) -> void:
	if accuser == root.rival_color:
		if not correct:
			queue.say(&"accused_false", _now, 1.5)
		return
	if correct:
		queue.say(&"my_correct", _now, 1.5)
	elif warnings == 1:
		queue.say(&"my_false_1", _now, 1.5)
	elif warnings == 2:
		queue.say(&"my_false_2", _now, 1.5)


func _on_state_changed() -> void:
	if not _started:
		return
	var b := root.server.board
	var now_q: Array[int] = [VoiceRules.count_queens(b, 0), VoiceRules.count_queens(b, 1)]
	if now_q[root.human_color] < _queens[root.human_color]:
		queue.say(&"queen_lost", _now, 0.8)
	if now_q[root.rival_color] < _queens[root.rival_color]:
		queue.say(&"queen_taken", _now, 0.8)
	_queens = now_q


func _on_move_made(color: int, _uci: String, _info: Dictionary) -> void:
	if color == root.rival_color and ChessRules.in_check(root.server.board, root.human_color):
		queue.say(&"check_given", _now, 1.0)


func _on_executed(table: int, seat: int) -> void:
	if table == HallLayout.human_table and seat == root.rival_color:
		queue.say(&"rival_executed", _now, 1.5)


## Aviso de `Distraction.broadcast`: aquí solo interesan los disparos.
func on_distraction(kind: StringName, _pos: Vector3, _table: int = -1, _chance: float = -1.0) -> void:
	if kind == &"gunshot":
		queue.say_first(&"first_shot", &"shot_next", _now, 0.5)
