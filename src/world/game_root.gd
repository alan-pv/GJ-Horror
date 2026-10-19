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
##   --demo-pause         abre el menú de pausa al arrancar (capturas)
## Sin argumentos el juego arranca en el menú principal (`src/ui/main_menu.tscn`);
## con cualquier argumento de usuario el menú salta directo a `main.tscn`.
##   --fen="..."          posición inicial distinta (pruebas)
##   --shot-select=e2     selecciona esa casilla antes de capturar
##   --no-shadows         desactiva las sombras de la lámpara
##   --aerial[=x,y,z,tx,ty,tz]  cámara aérea del salón entero, sin techo (capturas)
##   --no-arbiter-exec    las eliminaciones de fondo usan el respaldo sin árbitro (pruebas)
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
	"res://src/client/arbiter_module.gd",
	"res://src/client/events/event_module.gd",
]

## Tope de jugadas de las mesas de fondo por fotograma (reparte el costo).
const BG_MOVES_PER_FRAME := 1
const CHEAT_IDS := ["nudge", "slide", "steal", "move_enemy"]
const PERSONALITY_IDS := ["honesto", "paranoico", "tramposo_nervioso"]
## Suelo bajo el centro del asiento del rival (la silla del salón está a 0,80 m; se avanza para llegar al tablero).
const RIVAL_SEAT := Vector3(0.0, 0.0, -PlayerController.SEAT.z)

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
var sheet_view: ScoresheetView
var player: PlayerController
var avatar: OpponentAvatar
var hud: Hud
var pause_menu: PauseMenu
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
## El árbitro del salón (lo crea un módulo; null en pruebas sin módulos).
var arbiter: Arbiter = null
var _shot_done: bool = false
var _shot_armed_at: float = -1.0
## Vida de las mesas de fondo: índice de mesa -> BackgroundTable.
var bg_tables: Dictionary = {}
var _bt_cost_ms: float = 0.0
var _bt_max_ms: float = 0.0
var _bt_frames: int = 0
var _fps_sum: float = 0.0
var _draw_sum: float = 0.0
var _proc_sum: float = 0.0
## Pulsación del reloj rechazada por mano ocupada en una trampa (por color).
var _press_retry: Array[bool] = [false, false]


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
	_setup_aerial_camera.call_deferred()
	_setup_tournament(rng)
	rival_color = ChessPiece.opposite(human_color)

	board_view = BoardView.new()
	board_view.name = "Tablero"
	add_child(board_view)
	board_view.setup(human_color)
	clock_view = ClockView.new()
	add_child(clock_view)
	clock_view.setup(human_color)
	sheet_view = ScoresheetView.new()
	add_child(sheet_view)
	sheet_view.setup(human_color)

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
	hud.set_pace(_pace_text())
	# Pausa con Esc: suelta el ratón al abrir y lo recaptura al reanudar.
	pause_menu = PauseMenu.new()
	pause_menu.name = "Pausa"
	add_child(pause_menu)
	pause_menu.opened.connect(func() -> void: player.capture_mouse(false))
	pause_menu.resumed.connect(func() -> void: player.capture_mouse(true))
	if _args.has("demo-pause"):
		# Para la captura el bucle debe seguir corriendo aunque el árbol esté en pausa.
		process_mode = Node.PROCESS_MODE_ALWAYS
		pause_menu.open.call_deferred()
	_connect_signals()
	_install_modules()
	_populate_hall()
	_start_background()
	_refresh_tournament_hud()
	hud.set_warnings(manager.sessions[manager.human_id].warnings, config.false_accusations_to_eliminate)

	board_view.sync(server.board)
	if tgame != null:
		server.start()
		_prefetch_beginner_help()
	else:
		# Descanso: la mesa queda sin partida y el rival no está.
		avatar.visible = false
		_human_settled = true
		hud.set_status("You advance to the next round without playing")
	match_started.emit(server)
	clock_view.set_running(server.clock.running)
	if _args.has("autoplay"):
		hud.set_hint("Autoplay mode")
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
	# El turno pasa al pulsar el reloj: la mano lo hace al final de cada jugada.
	config.require_clock_press = true
	config.white_seconds = float(_args.get("clock", config.white_seconds))
	config.black_seconds = config.white_seconds
	# Suspenso de una acusación: el árbitro cruza la sala y revisa las planillas (`--arbiter-delay=S`).
	config.arbiter_delay = float(_args.get("arbiter-delay", 6.5))
	# Las sesiones viven en el torneo: las advertencias se arrastran entre partidas.
	var human := manager.sessions[manager.human_id]
	var rival := manager.sessions[rival_id] if rival_id >= 0 else PlayerSession.new(-1, "Nobody", true)
	if _args.has("autoplay"):
		human.beginner_help = false
	var sessions := [null, null]
	sessions[human_color] = human
	sessions[rival_color] = rival
	server = MatchServer.new(config, sessions[0], sessions[1], str(_args.get("fen", BoardState.START_FEN)), rng.randi())


func _build_actors(rng: RandomNumberGenerator) -> void:
	# Cada jugador del torneo conserva su aspecto en todas sus partidas.
	var look_rng := RandomNumberGenerator.new()
	look_rng.seed = hash("rival%d" % rival_id)
	var rival_look := CharacterFigure.bot_look(look_rng)
	look_rng.seed = hash("human%d" % manager.human_id)
	var human_look := CharacterFigure.random_look(look_rng)

	player = PlayerController.new()
	player.name = "Jugador"
	add_child(player)
	player.setup(server, board_view, human_color, human_look)
	player.send_gaze = not _args.has("autoplay")

	avatar = OpponentAvatar.new()
	avatar.position = RIVAL_SEAT
	add_child(avatar)
	avatar.build(rival_look)

	var human_rest := Vector3(0.34, BoardView.TABLE_TOP + 0.03, 0.40)
	var rival_rest := Vector3(0.34, BoardView.TABLE_TOP + 0.03, -0.40)
	var ha := HandAnimator.new()
	ha.name = "AnimadorJugador"
	add_child(ha)
	ha.setup(player.hand_rig, board_view, clock_view, human_color, human_rest)
	ha.sheet = sheet_view
	var ra := HandAnimator.new()
	ra.name = "AnimadorRival"
	add_child(ra)
	ra.setup(avatar.hand_rig, board_view, clock_view, rival_color, rival_rest)
	ra.sheet = sheet_view
	ra.set_write_rig(avatar.idle_rig, Vector3(-0.34, BoardView.TABLE_TOP + 0.03, -0.40))
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
	# Elo del rival de este bot (para Maia): el humano cuenta 1300 en el torneo.
	var opp_elo := 1300
	if player_id >= 0:
		var g := manager.game_of(player_id)
		if g != null:
			opp_elo = manager.elo[g.opponent_of(player_id)]
	var brain: ChessBrain
	if ResourceLoader.exists("res://src/bots/maia_brain.gd"):
		brain = load("res://src/bots/maia_brain.gd").new()
	else:
		brain = FallbackBrain.new()
	var bot := BotController.new()
	bot.name = "Bot_" + _color_name(color)
	add_child(bot)
	bot.setup(server, color, personality, brain, eye, BoardView.CENTER)
	bot.opponent_elo = opp_elo
	return bot


func _connect_signals() -> void:
	server.state_changed.connect(func() -> void: board_view.sync(server.board))
	server.move_made.connect(_on_move_made)
	server.beginner_warning.connect(_on_beginner_warning)
	# Secuencia física: la mano pulsa el reloj (pasa el turno) y anota en la planilla.
	server.sheet_entry.connect(sheet_view.add_entry)
	server.cheat_finished.connect(func(c: int, _id: StringName, _f: int, _t: int) -> void: _after_cheat(c))
	server.cheat_aborted.connect(func(c: int, _id: StringName) -> void: _after_cheat(c))
	for a in animators:
		a.clock_hit.connect(_on_clock_hit)
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


## La mano golpeó el botón del reloj: el turno pasa. Si la mano está ocupada en una trampa
## el servidor lo rechaza y se reintenta al terminar la trampa.
func _on_clock_hit(color: int) -> void:
	var res := server.press_clock(color)
	if not res.ok and server.awaiting_press(color):
		_press_retry[color] = true


## Terminó o se abortó una trampa: reintenta una pulsación pendiente y, si el turno es del
## humano, analiza su posición en segundo plano (el tablero cambió).
func _after_cheat(color: int) -> void:
	if _press_retry[color] and not server.is_hand_busy(color):
		_press_retry[color] = false
		server.press_clock(color)
	_prefetch_beginner_help()


## Lanza el análisis de ayuda del humano si le toca mover (sin esperar: corre por trozos).
func _prefetch_beginner_help() -> void:
	if server.is_over() or server.board.side_to_move != human_color:
		return
	if server.config.beginner_help and server.sessions[human_color].beginner_help:
		BeginnerHelper.precompute_async(server.board.clone())


func _on_beginner_warning(color: int, uci: String, text: String) -> void:
	if color != human_color:
		return
	_log("Aviso: %s" % text)
	hud.show_subtitle(text)
	animators[color].enqueue_hesitate(uci)


func _on_accusation_started(accuser: int) -> void:
	hud.show_arbiter("The arbiter is coming to the table...", config.arbiter_delay + 0.5)
	if arbiter != null:
		arbiter.begin_accusation(accuser)


func _on_accusation_resolved(accuser: int, correct: bool, warnings: int) -> void:
	# Con árbitro, él anuncia el veredicto al terminar de revisar las planillas.
	if arbiter != null:
		arbiter.resolve_accusation(accuser, correct, warnings)
		return
	var by_human := accuser == human_color
	if correct:
		hud.show_arbiter("Cheating confirmed" if by_human else "You were caught")
	else:
		hud.show_arbiter(("False accusation: warning %d/%d" % [warnings, config.false_accusations_to_eliminate]) if by_human else "The opponent accused you falsely")
	hud.set_warnings(server.sessions[human_color].warnings, config.false_accusations_to_eliminate)


func _on_game_over(winner: int, reason: String) -> void:
	_log("Fin: gana %s (%s)" % [_color_name(winner), reason])
	var won := winner == human_color
	var times: PackedFloat64Array = [server.clock.remaining[0], server.clock.remaining[1]]
	manager.report_result(tgame, winner, reason, times)
	_refresh_tournament_hud()
	# En la final perder (o ganar) la primera partida no elimina a nadie: solo la segunda,
	# y solo si el desempate ya está decidido.
	var series := _final_series_for_human()
	var eliminated := not won and (not manager.is_final or series < 0)
	var rival_dies := won and (not manager.is_final or series > 0)
	if eliminated:
		_ending = true
	# Un instante para que se vea el último movimiento.
	await get_tree().create_timer(1.2).timeout
	if not is_inside_tree():
		return
	# Si el árbitro aún está dando el veredicto de una acusación, se espera a que termine.
	if arbiter != null and arbiter.accusation_active():
		await arbiter.accusation_done
		if not is_inside_tree():
			return
	if eliminated:
		_human_eliminated(reason)
		return
	if won:
		hud.show_subtitle("You won: %s" % reason, 3.0)
	else:
		hud.show_subtitle("You lost this game of the final", 3.0)
	if rival_dies and arbiter != null and tgame != null:
		# El árbitro viene y ejecuta al rival frente al jugador.
		arbiter.request_execution(HallLayout.HUMAN_TABLE, rival_color)
		await arbiter.wait_executed(HallLayout.HUMAN_TABLE, rival_color)
		if not is_inside_tree():
			return
		await get_tree().create_timer(1.5).timeout
		if not is_inside_tree():
			return
	_human_settled = true
	if not manager.round_complete():
		hud.set_status("Waiting for the other tables...")


## Resultado de la serie de la final para el humano al terminar su segunda partida:
## 1 = la gana, -1 = la pierde, 0 = aún no se sabe (primera partida o desempate al azar).
func _final_series_for_human() -> int:
	if not manager.is_final or manager.final_games.size() != 1 or tgame == null:
		return 0
	var games: Array[TournamentGame] = [manager.final_games[0], tgame]
	var human := manager.human_id
	var wins := 0
	var time_human := 0.0
	var time_rival := 0.0
	for g in games:
		if g.winner_id() == human:
			wins += 1
		time_human += g.time_left_of(human)
		time_rival += g.time_left_of(g.opponent_of(human))
	if wins != 1:
		return 1 if wins == 2 else -1
	if is_equal_approx(time_human, time_rival):
		return 0
	return 1 if time_human > time_rival else -1


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


## Lámparas del salón: las 16 mesas siguen encendidas en todas las rondas (las vacías
## también, para que el salón no se vaya quedando a oscuras); solo se retiran las figuras
## y las piezas de las mesas que no se usan. La atenuación llega solo con las ejecuciones.
func _populate_hall() -> void:
	for i in hall.table_count():
		if i == HallLayout.HUMAN_TABLE:
			continue
		hall.clear_table_board(i)
		hall.set_table_active(i, true, false)


func _start_background() -> void:
	for g in manager.pending_games():
		if g == tgame:
			continue
		var bg := BackgroundMatch.new(g, manager.sessions[g.white], manager.sessions[g.black],
				manager.elo[g.white], manager.elo[g.black], randi(), config.white_seconds)
		bg.finished.connect(_on_background_finished.bind(bg))
		background.append(bg)
		if g.table >= 0 and g.table != HallLayout.HUMAN_TABLE:
			_make_bg_table(g.table, bg, [true, true])
	# Quien descansa espera sentado en su mesa (el humano, en la suya, lo maneja el cliente).
	for id in manager.byes:
		var t: int = manager.bye_tables.get(id, TournamentGame.TABLE_NONE)
		if t >= 0 and t != HallLayout.HUMAN_TABLE and not bg_tables.has(t):
			_make_bg_table(t, null, [true, false])
	# Cada mesa conoce a las demás (y a la del humano) para mirarlas de vez en cuando.
	for t in bg_tables:
		var bt: BackgroundTable = bg_tables[t]
		bt.neighbors.clear()
		bt.neighbors.append(Vector3.ZERO)
		for u in bg_tables:
			if u != t:
				bt.neighbors.append(hall.table_position(u))
	if arbiter != null and not arbiter.executed.is_connected(_on_executed):
		arbiter.executed.connect(_on_executed)


func _make_bg_table(table: int, bg: BackgroundMatch, present: Array) -> void:
	var bt := BackgroundTable.new()
	hall.table_root(table).add_child(bt)
	bt.setup(hall, table, bg, present, randi())
	bg_tables[table] = bt


func _on_background_finished(g: TournamentGame, bg: BackgroundMatch) -> void:
	var times: PackedFloat64Array = [bg.server.clock.remaining[0], bg.server.clock.remaining[1]]
	manager.report_result(g, bg.server.winner, bg.server.end_reason, times)
	var loser_color := ChessPiece.opposite(bg.server.winner)
	_log("Mesa %d: gana %s a %s (%s)" % [g.table, manager.player_name(g.winner_id()), manager.player_name(g.loser_id()), g.reason])
	if g.table >= 0:
		var bt: BackgroundTable = bg_tables.get(g.table)
		if bt != null:
			bt.on_game_over(bg.server.winner)
		table_eliminated.emit(g.table, hall.table_position(g.table), loser_color)
		if arbiter != null and not _args.has("no-arbiter-exec"):
			# El árbitro va a la mesa y ejecuta al perdedor; `_on_executed` apaga la lámpara.
			arbiter.request_execution(g.table, loser_color)
		else:
			# Sin árbitro: la figura se levanta y se va; la lámpara queda tenue.
			if bt != null:
				bt.send_away(loser_color)
			hall.set_table_level(g.table, 0.4, true, true)
	_refresh_tournament_hud()


## Terminó la ejecución en (`table`, `seat`): la lámpara de esa mesa titila y queda tenue,
## el ganador sigue sentado esperando, y el disparo se oye en todo el salón.
func _on_executed(table: int, _seat: int) -> void:
	if not is_inside_tree():
		return
	var pos := hall.table_position(table)
	if table != HallLayout.HUMAN_TABLE:
		hall.set_table_level(table, 0.4, true, true)
	for t in bg_tables:
		if t != table:
			(bg_tables[t] as BackgroundTable).notice_noise(pos)


## Figura sentada en (`table`, `seat`); `seat` = color (0 blancas, 1 negras). En la
## mesa del humano devuelve la del rival (`avatar.figure`) o el cuerpo del propio jugador
## (`player.body`) si existen. Null si no hay. Contrato de la oleada 2.
func figure_at(table: int, seat: int) -> CharacterFigure:
	if table == HallLayout.HUMAN_TABLE:
		var node: Variant = null
		if seat == human_color:
			node = player.get("body") if player != null else null
		else:
			node = avatar.get("figure") if avatar != null else null
		return node as CharacterFigure if node is CharacterFigure else null
	var bt: BackgroundTable = bg_tables.get(table)
	return bt.figure(seat) if bt != null else null


## Quita la figura de (`table`, `seat`) de su animación ambiental y la entrega a
## quien la va a ejecutar (el árbitro la controla desde ahí). La figura queda en su silla
## hasta que termine la ronda. Contrato de la oleada 2.
func condemn_seat(table: int, seat: int) -> CharacterFigure:
	if table != HallLayout.HUMAN_TABLE:
		var bt: BackgroundTable = bg_tables.get(table)
		return bt.condemn(seat) if bt != null else null
	return figure_at(table, seat)


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
	# Solo ronda y cuántas faltan: sin nombres de jugadores.
	hud.set_round_info(manager.round_no, _total_rounds(), manager.is_final, players_left())


## Rondas totales del torneo, contando la final: cada ronda deja ceil(n/2) jugadores.
func _total_rounds() -> int:
	var n := manager.player_count
	var total := 1
	while n > 2:
		n = (n + 1) / 2
		total += 1
	return total


## Título visible de la ronda en curso ("Round 2" o "Final · game 1 of 2").
func _round_title() -> String:
	if manager.is_final:
		var no := manager.games[0].game_no if not manager.games.is_empty() else manager.final_games.size() + 1
		return "Final · game %d of 2" % no
	return "Round %d" % manager.round_no


## Ritmo de juego para el HUD ("3+2"); "" si aún no hay incremento en la configuración.
func _pace_text() -> String:
	var inc: Variant = config.get("increment_seconds")
	if inc == null:
		return ""
	return "%d+%d" % [int(round(config.white_seconds / 60.0)), int(inc)]


func _human_eliminated(reason: String) -> void:
	_ending = true
	_log("Humano eliminado (%s): torneo nuevo" % reason)
	hud.set_status("")
	# El árbitro viene a por el jugador: ejecución en primera persona, que acaba en negro.
	if arbiter != null:
		await arbiter.execute_player()
		if not is_inside_tree():
			return
	hud.show_screen("Eliminated", reason.substr(0, 1).to_upper() + reason.substr(1) + "\n\nEntering a new tournament...",
			"\nPress R to start now", Color(0.75, 0.12, 0.1))
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
	# Las ejecuciones en curso del árbitro terminan antes de cerrar la ronda.
	while arbiter != null and arbiter.has_pending_work():
		await get_tree().process_frame
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
			hud.show_screen("Champion!", "You won the %d-player tournament\n%s" % [manager.player_count, detail],
					"\nPress R to play another tournament", Color(0.95, 0.8, 0.3))
			await get_tree().create_timer(12.0 if not _args.has("autoplay") else 4.0).timeout
			if not is_inside_tree():
				return
		else:
			_log("Perdió la final: campeón %s" % manager.player_name(manager.champion_id))
			hud.show_screen("Eliminated", "%s won the final\n%s\n\nEntering a new tournament..." % [manager.player_name(manager.champion_id), detail],
					"\nPress R to start now", Color(0.75, 0.12, 0.1))
			await get_tree().create_timer(5.0 if not _args.has("autoplay") else 3.0).timeout
			if not is_inside_tree():
				return
		_restart_tournament()
		return
	manager.start_round()
	_log("Siguiente: %s, quedan %d" % [manager.round_label(), manager.remaining_count()])
	hud.show_screen(_round_title(), _next_round_text(res), "", Color(0.93, 0.85, 0.6))
	await get_tree().create_timer(4.0).timeout
	if not is_inside_tree():
		return
	_reload()


func _next_round_text(_res: Dictionary) -> String:
	var t := ""
	if manager.is_final and not manager.final_games.is_empty():
		var first: TournamentGame = manager.final_games[0]
		t = "First game: %s wins\nNow with the colors reversed\n" % manager.player_name(first.winner_id())
	elif manager.is_final:
		t = "Final over two games, colors reversed\nIf it ends 1-1, the most time left wins\n"
	else:
		t = "%d players left\n" % manager.remaining_count()
	var g := manager.game_of(manager.human_id)
	if g != null:
		t += "Your opponent: %s · you play %s" % [manager.player_name(g.opponent_of(manager.human_id)), _color_label(g.color_of(manager.human_id))]
	else:
		t += "You advance to the next round without playing"
	return t


## Pantallas de prueba para capturas (`--demo-screen=...`).
func _show_demo_screen() -> void:
	match str(_args.get("demo-screen", "")):
		"between":
			hud.show_screen("Round 2", "8 players left\nYour opponent: Beatriz · you play Black", "", Color(0.93, 0.85, 0.6))
		"champion":
			hud.show_screen("Champion!", "You won the 16-player tournament\nFinal 1-1 · most time left", "\nPress R to play another tournament", Color(0.95, 0.8, 0.3))
		"eliminated":
			hud.show_screen("Eliminated", "Third false accusation\n\nEntering a new tournament...", "\nPress R to start now", Color(0.75, 0.12, 0.1))


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
	_tick_bg_tables(delta)
	server.tick(delta)
	_fps_sum += Engine.get_frames_per_second()
	_draw_sum += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_proc_sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	# La ronda termina cuando acabaron todas las partidas y el árbitro no tiene trabajo pendiente.
	if not _ending and _human_settled and manager.round_complete() \
			and (arbiter == null or not arbiter.has_pending_work()):
		_finish_round_flow()
	var c := server.clock
	clock_view.set_times(c.remaining[ChessPiece.WHITE], c.remaining[ChessPiece.BLACK])
	clock_view.set_running(c.running)
	hud.set_clocks(c.remaining[human_color], c.remaining[rival_color],
			c.running == human_color, c.running == rival_color)
	# El estrés de cada mano crece cuando le queda poco tiempo en el reloj.
	for color in 2:
		animators[color].rig.stress = clampf(1.0 - c.remaining[color] / 45.0, 0.0, 1.0)
	if _args.has("quit-after") and _elapsed >= float(_args["quit-after"]):
		TournamentSession.elapsed = _elapsed
		_print_summary()
		get_tree().quit()
	if _args.has("screenshot") and not _shot_done:
		_update_screenshot()


## Vida de las mesas de fondo (figuras, tablero) con su costo medido.
func _tick_bg_tables(delta: float) -> void:
	if bg_tables.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var cam := get_viewport().get_camera_3d()
	var arb_pos: Variant = null
	if arbiter != null and arbiter.is_inside_tree() and arbiter.visible:
		arb_pos = arbiter.global_position
	for t in bg_tables:
		(bg_tables[t] as BackgroundTable).tick(delta, cam, arb_pos)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_bt_cost_ms += ms
	_bt_max_ms = maxf(_bt_max_ms, ms)
	_bt_frames += 1


## Cámara aérea de depuración (`--aerial`): sin techo, mirando el salón entero.
func _setup_aerial_camera() -> void:
	if not _args.has("aerial"):
		return
	var v: Array = [1.5, 13.0, 9.0, 1.5, 0.0, -2.0]
	if str(_args["aerial"]).contains(","):
		var parts := str(_args["aerial"]).split(",")
		for k in mini(parts.size(), 6):
			v[k] = float(parts[k])
	hall.set_ceiling_visible(false)
	var env_node := get_node_or_null("Entorno") as WorldEnvironment
	if env_node != null and env_node.environment != null:
		env_node.environment.ambient_light_energy = 1.0
	var cam := Camera3D.new()
	cam.name = "CamaraAerea"
	cam.fov = 65.0
	add_child(cam)
	cam.global_position = Vector3(v[0], v[1], v[2])
	cam.look_at(Vector3(v[3], v[4], v[5]), Vector3.UP)
	cam.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		_restart_tournament()


func _print_summary() -> void:
	print("[resumen] t=%.1fs jugadas=%d animaciones_completas=%d terminada=%s ply=%d" % [
		_elapsed, _moves_seen, _anims_done, server.is_over(), server.ply])
	if _bg_frames > 0:
		print("[resumen] mesas de fondo: %d activas, %.3f ms/fotograma de media, %.2f ms máximo" % [background.size(), _bg_cost_ms / _bg_frames, _bg_max_ms])
	if _bt_frames > 0:
		print("[resumen] vida de mesas: %d mesas, %.3f ms/fotograma de media, %.2f ms máximo" % [bg_tables.size(), _bt_cost_ms / _bt_frames, _bt_max_ms])
		print("[resumen] FPS medios %.1f, llamadas de dibujo %.0f, _process total %.2f ms/fotograma" % [_fps_sum / _bt_frames, _draw_sum / _bt_frames, _proc_sum / _bt_frames])
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


## Nombre del color para el jugador ("White" / "Black").
func _color_label(c: int) -> String:
	return "White" if c == ChessPiece.WHITE else "Black"


func _color_name(c: int) -> String:
	return "blancas" if c == ChessPiece.WHITE else "negras"


func _log(text: String) -> void:
	if _verbose:
		print("[juego %.1f] %s" % [_elapsed, text])
