class_name GameRoot
extends Node3D
## Raíz de la partida 1 contra 1 (Hito 1). Crea las sesiones, los colores
## aleatorios, el `MatchServer` y el bot rival, arma el salón y conecta las
## señales del servidor con la vista (tablero, manos, reloj, HUD). Avanza el
## servidor con `tick()` cada fotograma y reinicia con la acción "restart".
##
## Argumentos de depuración (después de `--` en la línea de comandos):
##   --autoplay           un segundo bot juega por el humano
##   --human=white|black  fuerza el color del humano
##   --seed=N             semilla del azar de la partida
##   --speed=X            escala de tiempo del motor
##   --quit-after=S       termina tras S segundos (muestra un resumen)
##   --screenshot=ruta    guarda una captura y sale
##   --shot-delay=S       segundos antes de la captura (por defecto 2)
##   --shot-look=yaw,pitch  gira la cámara del jugador (grados) antes de capturar
##   --shot-when=rival_carry|player_carry  espera a que esa mano lleve una pieza
##   --shot-after=S       con shot-when, segundos extra tras empezar a llevar la pieza
##   --players=N          jugadores del torneo (32 por defecto)
##   --clock=S            segundos por jugador en cada partida (180 por defecto)
##   --start-round=N      salta a la ronda N (el humano gana las anteriores, simuladas)
##   --demo-screen=between|champion|eliminated  muestra esa pantalla al arrancar (capturas)
##   --fen="..."          posición inicial distinta (pruebas)
##   --shot-select=e2     selecciona esa casilla antes de capturar
##   --no-shadows         desactiva las sombras de la lámpara
##   --verbose            imprime el desarrollo de la partida

## Se emite cuando la partida ya está armada y arrancó. Los módulos se enganchan aquí.
signal match_started(server: MatchServer)
## Se emite cuando se elimina a alguien en otra mesa del salón (lo usa el director de tensión).
## `seat` = asiento del eliminado (0 = blancas, 1 = negras).
signal table_eliminated(table_index: int, position: Vector3, seat: int)
## Cambió cuántos jugadores siguen en el torneo (lo usa el director de tensión).
signal players_remaining_changed(remaining: int, total: int)

## Módulos de gameplay. Cada uno es un script cuyo `new()` da un Node con
## `func install(root: GameRoot) -> void`. Se instancian como hijos de la raíz
## después de armar la partida y antes de que arranque. Para agregar un módulo
## basta con añadir su ruta aquí; no hace falta tocar el resto de este archivo.
const MODULES: Array[String] = [
	"res://src/client/cheats/cheat_module.gd",
	"res://src/client/events/event_module.gd",
]

## Tope de jugadas de las mesas de fondo por fotograma (reparte el costo).
const BG_MOVES_PER_FRAME := 1
const CHEAT_IDS := ["nudge", "slide", "steal", "move_enemy"]
const PERSONALITY_IDS := ["honesto", "paranoico", "tramposo_nervioso"]
const RIVAL_SEAT := Vector3(0.0, 0.0, -0.55)

## Torneo en curso (sobrevive a la recarga de la escena: ver `TournamentSession`).
var manager: TournamentManager
## Partida del humano en esta ronda; null si descansa (pasa sin jugar).
var tgame: TournamentGame
var rival_id: int = -1
## Partidas de fondo de las otras mesas.
var background: Array[BackgroundMatch] = []
var human_color: int = ChessPiece.WHITE
var rival_color: int = ChessPiece.BLACK
var config: MatchConfig
var server: MatchServer
var hall: Hall
var board_view: BoardView
var clock_view: ClockView
var player: PlayerController
var avatar: OpponentAvatar
var hud: Hud
var rival_bot: BotController
var auto_bot: BotController
## animators[color]: quien mueve las piezas de ese color.
var animators: Array[HandAnimator] = [null, null]

var _args: Dictionary = {}
var _scene_elapsed: float = 0.0
var _ending: bool = false
var _human_settled: bool = false
var _bg_cost_ms: float = 0.0
var _bg_max_ms: float = 0.0
var _bg_frames: int = 0
var _bg_rotation: int = 0
var _verbose: bool = false
var _elapsed: float = 0.0
var _moves_seen: int = 0
var _anims_done: int = 0
var _shot_done: bool = false
var _shot_armed_at: float = -1.0


func _ready() -> void:
	_parse_args()
	var rng := RandomNumberGenerator.new()
	if _args.has("seed"):
		rng.seed = int(_args.seed)
		seed(int(_args.seed))
	else:
		rng.randomize()
	if _args.has("speed"):
		Engine.time_scale = float(_args.speed)
	_elapsed = TournamentSession.elapsed

	hall = Hall.new()
	add_child(hall)
	hall.build()
	_setup_tournament(rng)
	rival_color = ChessPiece.opposite(human_color)

	board_view = BoardView.new()
	board_view.name = "Tablero"
	add_child(board_view)
	board_view.setup(human_color)
	clock_view = ClockView.new()
	add_child(clock_view)
	clock_view.setup(human_color)

	_build_match(rng)
	_build_actors(rng)

	if _args.has("no-shadows"):
		hall.spot.shadow_enabled = false
	if _args.has("shot-look"):
		var parts := str(_args["shot-look"]).split(",")
		if parts.size() == 2:
			player.set_look(deg_to_rad(float(parts[0])), deg_to_rad(float(parts[1])))
	if _args.has("shot-select"):
		player.select_square(ChessPiece.square_from_name(str(_args["shot-select"])))
	hud = Hud.new()
	hud.name = "Interfaz"
	add_child(hud)
	hud.show_capture_prompt = not _args.has("screenshot")
	hud.set_mouse_captured(false)
	player.mouse_capture_changed.connect(hud.set_mouse_captured)
	_connect_signals()
	_install_modules()
	_populate_hall()
	_start_background()
	_refresh_tournament_hud()
	hud.set_warnings(manager.sessions[manager.human_id].warnings, config.false_accusations_to_eliminate)

	board_view.sync(server.board)
	if tgame != null:
		server.start()
	else:
		# Descanso: la mesa queda sin partida y el rival no está.
		avatar.visible = false
		_human_settled = true
		hud.set_status("Pasas a la siguiente ronda sin jugar")
	match_started.emit(server)
	clock_view.set_running(server.clock.running)
	if _args.has("autoplay"):
		hud.set_hint("Modo autoplay")
	_log("%s: humano = %s, rival = %s (%s)" % [manager.round_label(), _color_name(human_color), _color_name(rival_color), rival_bot.brain.brain_name()])
	if tgame != null:
		_log("Rival: %s (elo %d)" % [manager.player_name(rival_id), manager.elo[rival_id]])
	else:
		_log("El humano descansa esta ronda")
	_show_demo_screen()


func _install_modules() -> void:
	for path in MODULES:
		if not ResourceLoader.exists(path):
			push_warning("Módulo no encontrado: " + path)
			continue
		var module: Node = load(path).new()
		add_child(module)
		module.install(self)


## Argumentos de línea de comandos ya interpretados (los módulos pueden leer los suyos).
func get_args() -> Dictionary:
	return _args


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else true
	_verbose = _args.has("verbose") or _args.has("autoplay")


func _build_match(rng: RandomNumberGenerator) -> void:
	config = MatchConfig.new()
	config.board_center = BoardView.CENTER
	var cheats: Array[CheatDef] = []
	for id in CHEAT_IDS:
		var def := load("res://data/cheats/%s.tres" % id) as CheatDef
		if def != null:
			cheats.append(def)
	config.cheats = cheats
	config.white_seconds = float(_args.get("clock", config.white_seconds))
	config.black_seconds = config.white_seconds
	# Las sesiones viven en el torneo: las advertencias se arrastran entre partidas.
	var human := manager.sessions[manager.human_id]
	var rival := manager.sessions[rival_id] if rival_id >= 0 else PlayerSession.new(-1, "Nadie", true)
	if _args.has("autoplay"):
		human.beginner_help = false
	var sessions := [null, null]
	sessions[human_color] = human
	sessions[rival_color] = rival
	server = MatchServer.new(config, sessions[0], sessions[1], str(_args.get("fen", BoardState.START_FEN)), rng.randi())


func _build_actors(rng: RandomNumberGenerator) -> void:
	player = PlayerController.new()
	player.name = "Jugador"
	add_child(player)
	player.setup(server, board_view, human_color)
	player.send_gaze = not _args.has("autoplay")

	avatar = OpponentAvatar.new()
	avatar.position = RIVAL_SEAT
	avatar.rotation.y = PI
	add_child(avatar)
	avatar.build(Color(0.30, 0.07, 0.08), Color(0.70, 0.55, 0.46), -1.0)

	var human_rest := Vector3(0.26, BoardView.BOARD_TOP + 0.10, 0.33)
	var rival_rest := Vector3(0.26, BoardView.BOARD_TOP + 0.10, -0.33)
	var ha := HandAnimator.new()
	ha.name = "AnimadorJugador"
	add_child(ha)
	ha.setup(player.hand_rig, board_view, clock_view, human_color, human_rest)
	var ra := HandAnimator.new()
	ra.name = "AnimadorRival"
	add_child(ra)
	ra.setup(avatar.hand_rig, board_view, clock_view, rival_color, rival_rest)
	animators[human_color] = ha
	animators[rival_color] = ra
	player.animator = ha

	rival_bot = _make_bot(rival_color, avatar.eye_position(), rng, rival_id)
	avatar.bind_bot(rival_bot)
	if _args.has("autoplay"):
		auto_bot = _make_bot(human_color, player.global_position, rng)


func _make_bot(color: int, eye: Vector3, rng: RandomNumberGenerator, player_id: int = -1) -> BotController:
	var personality := load("res://data/personalities/%s.tres" % PERSONALITY_IDS[rng.randi() % PERSONALITY_IDS.size()]) as BotPersonality
	if player_id >= 0:
		# Cada jugador del torneo tiene su nivel.
		personality = personality.duplicate() as BotPersonality
		personality.elo = manager.elo[player_id]
	var brain: ChessBrain
	if ResourceLoader.exists("res://src/bots/maia_brain.gd"):
		brain = load("res://src/bots/maia_brain.gd").new()
	else:
		brain = FallbackBrain.new()
	var bot := BotController.new()
	bot.name = "Bot_" + _color_name(color)
	add_child(bot)
	bot.setup(server, color, personality, brain, eye, BoardView.CENTER)
	return bot


func _connect_signals() -> void:
	server.state_changed.connect(func() -> void: board_view.sync(server.board))
	server.move_made.connect(_on_move_made)
	server.beginner_warning.connect(_on_beginner_warning)
	server.accusation_started.connect(_on_accusation_started)
	server.accusation_resolved.connect(_on_accusation_resolved)
	server.game_over.connect(_on_game_over)
	for a in animators:
		a.job_done.connect(func(kind: String) -> void:
			_anims_done += 1
			_log("Animación terminada: %s" % kind))


# --- Señales del servidor -----------------------------------------------------

func _on_move_made(color: int, uci: String, info: Dictionary) -> void:
	_moves_seen += 1
	_log("Jugada %d: %s mueve %s%s" % [_moves_seen, _color_name(color), uci, " (captura)" if int(info.get("capture_square", -1)) >= 0 else ""])
	animators[color].enqueue_move(uci, info)


func _on_beginner_warning(color: int, uci: String, text: String) -> void:
	if color != human_color:
		return
	_log("Aviso: %s" % text)
	hud.show_subtitle(text)
	animators[color].enqueue_hesitate(uci)


func _on_accusation_started(accuser: int) -> void:
	hud.show_arbiter("El árbitro se acerca a la mesa...", config.arbiter_delay + 0.5)


func _on_accusation_resolved(accuser: int, correct: bool, warnings: int) -> void:
	var by_human := accuser == human_color
	if correct:
		hud.show_arbiter("Trampa confirmada" if by_human else "Te descubrieron")
	else:
		hud.show_arbiter(("Acusación falsa: advertencia %d/%d" % [warnings, config.false_accusations_to_eliminate]) if by_human else "Acusación falsa del rival")
	hud.set_warnings(server.sessions[human_color].warnings, config.false_accusations_to_eliminate)


func _on_game_over(winner: int, reason: String) -> void:
	_log("Fin: gana %s (%s)" % [_color_name(winner), reason])
	var won := winner == human_color
	var times: PackedFloat64Array = [server.clock.remaining[0], server.clock.remaining[1]]
	manager.report_result(tgame, winner, reason, times)
	_refresh_tournament_hud()
	# En la final perder la primera partida no elimina: se decide al cerrar la serie.
	var eliminated := not won and not manager.is_final
	if eliminated:
		_ending = true
	# Un instante para que se vea el último movimiento.
	await get_tree().create_timer(1.2).timeout
	if not is_inside_tree():
		return
	if eliminated:
		_human_eliminated(reason)
		return
	_human_settled = true
	if won:
		hud.show_subtitle("Ganaste: %s" % reason, 3.0)
	else:
		hud.show_subtitle("Perdiste esta partida de la final", 3.0)
	if not manager.round_complete():
		hud.set_status("Esperando a las demás mesas...")


# --- Torneo ------------------------------------------------------------------------

func _setup_tournament(rng: RandomNumberGenerator) -> void:
	manager = TournamentSession.ensure(int(_args.get("players", 32)), int(_args.get("seed", -1)))
	if manager.phase == TournamentManager.Phase.FINISHED:
		manager.new_tournament()
	elif manager.phase == TournamentManager.Phase.ROUND_DONE:
		manager.finish_round()
	if manager.phase == TournamentManager.Phase.IDLE:
		# Salto de depuración a una ronda posterior: el humano gana las anteriores.
		var target := int(_args.get("start-round", 1))
		while manager.round_no + 1 < target and manager.alive.size() > 2:
			manager.start_round()
			manager.simulate_round(true)
			manager.finish_round()
		manager.start_round()
	if _args.get("human", "") == "white":
		manager.force_human_color(ChessPiece.WHITE)
	elif _args.get("human", "") == "black":
		manager.force_human_color(ChessPiece.BLACK)
	tgame = manager.game_of(manager.human_id)
	if tgame != null:
		human_color = tgame.color_of(manager.human_id)
		rival_id = tgame.opponent_of(manager.human_id)
	else:
		human_color = rng.randi() % 2
		rival_id = -1


## Ocupantes y lámparas de las mesas del salón según la ronda en curso.
func _populate_hall() -> void:
	for i in hall.table_count():
		hall.set_occupants(i, 0)
		hall.set_table_active(i, false, false)
	for g in manager.games:
		if g.table >= 0:
			hall.set_table_active(g.table, true, false)
			hall.set_occupants(g.table, 2)
	for id in manager.byes:
		var t: int = manager.bye_tables.get(id, TournamentGame.TABLE_NONE)
		if t >= 0:
			hall.set_table_active(t, true, false)
			hall.set_occupants(t, 1)


func _start_background() -> void:
	for g in manager.pending_games():
		if g == tgame:
			continue
		var bg := BackgroundMatch.new(g, manager.sessions[g.white], manager.sessions[g.black],
				manager.elo[g.white], manager.elo[g.black], randi(), config.white_seconds)
		bg.finished.connect(_on_background_finished.bind(bg))
		background.append(bg)


func _on_background_finished(g: TournamentGame, bg: BackgroundMatch) -> void:
	var times: PackedFloat64Array = [bg.server.clock.remaining[0], bg.server.clock.remaining[1]]
	manager.report_result(g, bg.server.winner, bg.server.end_reason, times)
	var loser_color := ChessPiece.opposite(bg.server.winner)
	_log("Mesa %d: gana %s a %s (%s)" % [g.table, manager.player_name(g.winner_id()), manager.player_name(g.loser_id()), g.reason])
	if g.table >= 0:
		# Si hay quien escuche (módulo de eventos), los guardias se llevan al perdedor;
		# si no, la figura se levanta y se va sola.
		if table_eliminated.get_connections().is_empty():
			hall.remove_occupant(g.table, loser_color)
		else:
			table_eliminated.emit(g.table, hall.table_position(g.table), loser_color)
	_refresh_tournament_hud()


## Jugadores que siguen vivos ahora: los de la ronda menos los perdedores ya conocidos.
func players_left() -> int:
	var n := manager.remaining_count()
	if not manager.is_final:
		for g in manager.games:
			if g.done:
				n -= 1
	return maxi(n, 1)


func _refresh_tournament_hud() -> void:
	players_remaining_changed.emit(players_left(), manager.player_count)
	if hud == null:
		return
	hud.set_tournament_info(manager.round_label(), manager.remaining_count())
	var lines: Array[String] = []
	for g in manager.games:
		var w := manager.player_name(g.white)
		var b := manager.player_name(g.black)
		var mark := "» " if g.involves(manager.human_id) else ""
		if g.done:
			lines.append("%s%s - %s: gana %s" % [mark, w, b, manager.player_name(g.winner_id())])
		else:
			lines.append("%s%s - %s" % [mark, w, b])
	for id in manager.byes:
		lines.append("%s%s pasa sin jugar" % ["» " if id == manager.human_id else "", manager.player_name(id)])
	hud.set_bracket(lines)


func _human_eliminated(reason: String) -> void:
	_ending = true
	_log("Humano eliminado (%s): torneo nuevo" % reason)
	hud.set_status("")
	hud.show_screen("Eliminado", reason.substr(0, 1).to_upper() + reason.substr(1) + "\n\nEntrando a un torneo nuevo...",
			"\nR para empezar ya", Color(0.75, 0.12, 0.1))
	await get_tree().create_timer(5.0 if not _args.has("autoplay") else 3.0).timeout
	if not is_inside_tree():
		return
	_restart_tournament()


func _restart_tournament() -> void:
	manager.new_tournament()
	_reload()


func _reload() -> void:
	TournamentSession.elapsed = _elapsed
	get_tree().reload_current_scene()


## Termina la ronda cuando acabaron todas las partidas (y se vio el final de la del humano).
func _finish_round_flow() -> void:
	_ending = true
	hud.set_status("")
	await get_tree().create_timer(1.5).timeout
	if not is_inside_tree():
		return
	var res := manager.finish_round()
	_refresh_tournament_hud()
	var human_id := manager.human_id
	if manager.is_finished():
		var s := manager.final_summary()
		var other: int = rival_id if manager.champion_id == human_id else manager.champion_id
		var detail := "Final %d-%d" % [s.wins.get(human_id, 0), s.wins.get(other, 0)]
		if manager.champion_id == human_id:
			_log("Campeón: el humano")
			hud.show_screen("¡Campeón!", "Ganaste el torneo de %d jugadores\n%s" % [manager.player_count, detail],
					"\nR para jugar otro torneo", Color(0.95, 0.8, 0.3))
			await get_tree().create_timer(12.0 if not _args.has("autoplay") else 4.0).timeout
			if not is_inside_tree():
				return
		else:
			_log("Perdió la final: campeón %s" % manager.player_name(manager.champion_id))
			hud.show_screen("Eliminado", "%s ganó la final\n%s\n\nEntrando a un torneo nuevo..." % [manager.player_name(manager.champion_id), detail],
					"\nR para empezar ya", Color(0.75, 0.12, 0.1))
			await get_tree().create_timer(5.0 if not _args.has("autoplay") else 3.0).timeout
			if not is_inside_tree():
				return
		_restart_tournament()
		return
	manager.start_round()
	_log("Siguiente: %s, quedan %d" % [manager.round_label(), manager.remaining_count()])
	_darken_for_next_round()
	hud.show_screen(manager.round_label(), _next_round_text(res), "", Color(0.93, 0.85, 0.6))
	await get_tree().create_timer(4.0).timeout
	if not is_inside_tree():
		return
	_reload()


func _next_round_text(_res: Dictionary) -> String:
	var t := ""
	if manager.is_final and not manager.final_games.is_empty():
		var first: TournamentGame = manager.final_games[0]
		t = "Primera partida: gana %s\nAhora con los colores invertidos\n" % manager.player_name(first.winner_id())
	elif manager.is_final:
		t = "Final a dos partidas, colores invertidos\nSi quedan 1-1, gana quien tenga más tiempo sobrante\n"
	else:
		t = "Quedan %d jugadores\n" % manager.remaining_count()
	var g := manager.game_of(manager.human_id)
	if g != null:
		t += "Tu rival: %s · juegas con %s" % [manager.player_name(g.opponent_of(manager.human_id)), _color_name(g.color_of(manager.human_id))]
	else:
		t += "Pasas a la siguiente ronda sin jugar"
	return t


## Las mesas que ya no se usan en la siguiente ronda se apagan y se vacían.
func _darken_for_next_round() -> void:
	var used := {}
	for g in manager.games:
		used[g.table] = true
	for id in manager.byes:
		used[manager.bye_tables.get(id, TournamentGame.TABLE_NONE)] = true
	for i in hall.table_count():
		if used.has(i):
			continue
		if hall.is_table_active(i):
			hall.set_table_active(i, false, true)
		for seat in 2:
			hall.remove_occupant(i, seat)


## Pantallas de prueba para capturas (`--demo-screen=...`).
func _show_demo_screen() -> void:
	match str(_args.get("demo-screen", "")):
		"between":
			hud.show_screen("Ronda 2", "Quedan 8 jugadores\nTu rival: Beatriz · juegas con negras", "", Color(0.93, 0.85, 0.6))
		"champion":
			hud.show_screen("¡Campeón!", "Ganaste el torneo de 16 jugadores\nFinal 1-1 · más tiempo sobrante", "\nR para jugar otro torneo", Color(0.95, 0.8, 0.3))
		"eliminated":
			hud.show_screen("Eliminado", "Tercera acusación falsa\n\nEntrando a un torneo nuevo...", "\nR para empezar ya", Color(0.75, 0.12, 0.1))


# --- Bucle -----------------------------------------------------------------------

func _process(delta: float) -> void:
	_elapsed += delta
	_scene_elapsed += delta
	var t0 := Time.get_ticks_usec()
	# A lo sumo BG_MOVES_PER_FRAME jugadas de fondo por fotograma; se rota el orden por equidad.
	var moves_left := BG_MOVES_PER_FRAME
	for k in background.size():
		var bg := background[(k + _bg_rotation) % background.size()]
		if bg.tick(delta, moves_left > 0):
			moves_left -= 1
	_bg_rotation += 1
	if not background.is_empty():
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		_bg_cost_ms += ms
		_bg_max_ms = maxf(_bg_max_ms, ms)
		_bg_frames += 1
	server.tick(delta)
	if not _ending and _human_settled and manager.round_complete():
		_finish_round_flow()
	var c := server.clock
	clock_view.set_times(c.remaining[ChessPiece.WHITE], c.remaining[ChessPiece.BLACK])
	clock_view.set_running(c.running)
	# El estrés de cada mano crece cuando le queda poco tiempo en el reloj.
	for color in 2:
		animators[color].rig.stress = clampf(1.0 - c.remaining[color] / 45.0, 0.0, 1.0)
	if _args.has("quit-after") and _elapsed >= float(_args["quit-after"]):
		TournamentSession.elapsed = _elapsed
		_print_summary()
		get_tree().quit()
	if _args.has("screenshot") and not _shot_done:
		_update_screenshot()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		_restart_tournament()


func _print_summary() -> void:
	print("[resumen] t=%.1fs jugadas=%d animaciones_completas=%d terminada=%s ply=%d" % [
		_elapsed, _moves_seen, _anims_done, server.is_over(), server.ply])
	if _bg_frames > 0:
		print("[resumen] mesas de fondo: %d activas, %.3f ms/fotograma de media, %.2f ms máximo" % [background.size(), _bg_cost_ms / _bg_frames, _bg_max_ms])
	print("[resumen] torneo: %s, quedan %d de %d, eliminados %d" % [manager.round_label(), manager.remaining_count(), manager.player_count, manager.eliminated_log.size()])
	print("[resumen] correcciones de sincronía visual: %d" % board_view.sync_fixes)
	print("[resumen] FEN final: ", server.board.to_fen())
	print("[resumen] relojes: blancas %.1f negras %.1f" % [server.clock.remaining[0], server.clock.remaining[1]])


func _update_screenshot() -> void:
	var delay := float(_args.get("shot-delay", 2.0))
	if _scene_elapsed < delay:
		return
	var when := str(_args.get("shot-when", ""))
	if when != "":
		var who := animators[rival_color] if when == "rival_carry" else animators[human_color]
		if who.phase != &"carry":
			if _scene_elapsed > delay + 60.0:
				push_warning("No hubo fase 'carry' para la captura.")
				_shot_done = true
				get_tree().quit(1)
			return
		if _shot_armed_at < 0.0:
			_shot_armed_at = _scene_elapsed
		if _scene_elapsed < _shot_armed_at + float(_args.get("shot-after", 0.25)):
			return
	_shot_done = true
	_take_screenshot()


func _take_screenshot() -> void:
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var path := str(_args["screenshot"])
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_warning("Sin imagen del viewport (¿modo headless?).")
	else:
		img.save_png(path)
		print("[captura] guardada en ", path)
	get_tree().quit()


func _color_name(c: int) -> String:
	return "blancas" if c == ChessPiece.WHITE else "negras"


func _log(text: String) -> void:
	if _verbose:
		print("[juego %.1f] %s" % [_elapsed, text])
