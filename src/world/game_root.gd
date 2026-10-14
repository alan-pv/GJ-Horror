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
##   --fen="..."          posición inicial distinta (pruebas)
##   --shot-select=e2     selecciona esa casilla antes de capturar
##   --no-shadows         desactiva las sombras de la lámpara
##   --verbose            imprime el desarrollo de la partida

## Se emite cuando la partida ya está armada y arrancó. Los módulos se enganchan aquí.
signal match_started(server: MatchServer)
## Se emite cuando se elimina a alguien en otra mesa del salón (lo usa el director de tensión).
signal table_eliminated(table_index: int, position: Vector3)

## Módulos de gameplay. Cada uno es un script cuyo `new()` da un Node con
## `func install(root: GameRoot) -> void`. Se instancian como hijos de la raíz
## después de armar la partida y antes de que arranque. Para agregar un módulo
## basta con añadir su ruta aquí; no hace falta tocar el resto de este archivo.
const MODULES: Array[String] = [
	"res://src/client/events/event_module.gd",
]

const CHEAT_IDS := ["nudge", "slide", "steal", "move_enemy"]
const PERSONALITY_IDS := ["honesto", "paranoico", "tramposo_nervioso"]
const RIVAL_SEAT := Vector3(0.0, 0.0, -0.55)

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
	human_color = rng.randi() % 2
	if _args.get("human", "") == "white":
		human_color = ChessPiece.WHITE
	elif _args.get("human", "") == "black":
		human_color = ChessPiece.BLACK
	rival_color = ChessPiece.opposite(human_color)

	hall = Hall.new()
	add_child(hall)
	hall.build()

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
	hud.set_mouse_captured(false)
	player.mouse_capture_changed.connect(hud.set_mouse_captured)
	_connect_signals()
	_install_modules()

	board_view.sync(server.board)
	server.start()
	match_started.emit(server)
	clock_view.set_running(server.clock.running)
	if _args.has("autoplay"):
		hud.set_hint("Modo autoplay")
	_log("Partida: humano = %s, rival = %s (%s)" % [_color_name(human_color), _color_name(rival_color), rival_bot.brain.brain_name()])


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
	var human := PlayerSession.new(1, "Tú", false)
	var rival := PlayerSession.new(2, "Rival", true)
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

	rival_bot = _make_bot(rival_color, avatar.eye_position(), rng)
	avatar.bind_bot(rival_bot)
	if _args.has("autoplay"):
		auto_bot = _make_bot(human_color, player.global_position, rng)


func _make_bot(color: int, eye: Vector3, rng: RandomNumberGenerator) -> BotController:
	var personality := load("res://data/personalities/%s.tres" % PERSONALITY_IDS[rng.randi() % PERSONALITY_IDS.size()]) as BotPersonality
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
	# Un instante para que se vea el último movimiento.
	await get_tree().create_timer(1.2).timeout
	hud.show_result(winner == human_color, reason)


# --- Bucle -----------------------------------------------------------------------

func _process(delta: float) -> void:
	_elapsed += delta
	server.tick(delta)
	var c := server.clock
	clock_view.set_times(c.remaining[ChessPiece.WHITE], c.remaining[ChessPiece.BLACK])
	clock_view.set_running(c.running)
	# El estrés de cada mano crece cuando le queda poco tiempo en el reloj.
	for color in 2:
		animators[color].rig.stress = clampf(1.0 - c.remaining[color] / 45.0, 0.0, 1.0)
	if _args.has("quit-after") and _elapsed >= float(_args["quit-after"]):
		_print_summary()
		get_tree().quit()
	if _args.has("screenshot") and not _shot_done:
		_update_screenshot()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


func _print_summary() -> void:
	print("[resumen] t=%.1fs jugadas=%d animaciones_completas=%d terminada=%s ply=%d" % [
		_elapsed, _moves_seen, _anims_done, server.is_over(), server.ply])
	print("[resumen] correcciones de sincronía visual: %d" % board_view.sync_fixes)
	print("[resumen] FEN final: ", server.board.to_fen())
	print("[resumen] relojes: blancas %.1f negras %.1f" % [server.clock.remaining[0], server.clock.remaining[1]])


func _update_screenshot() -> void:
	var delay := float(_args.get("shot-delay", 2.0))
	if _elapsed < delay:
		return
	var when := str(_args.get("shot-when", ""))
	if when != "":
		var who := animators[rival_color] if when == "rival_carry" else animators[human_color]
		if who.phase != &"carry":
			if _elapsed > delay + 60.0:
				push_warning("No hubo fase 'carry' para la captura.")
				_shot_done = true
				get_tree().quit(1)
			return
		if _shot_armed_at < 0.0:
			_shot_armed_at = _elapsed
		if _elapsed < _shot_armed_at + float(_args.get("shot-after", 0.25)):
			return
	_shot_done = true
	_take_screenshot()


func _take_screenshot() -> void:
	await RenderingServer.frame_post_draw
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
