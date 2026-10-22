class_name BackgroundMatch
extends RefCounted
## Partida de fondo bot contra bot en una mesa lejana. Es un `MatchServer`
## de verdad (mismas reglas, reloj y finales que la partida del humano), pero
## sin nodos ni cerebros: la política es de 1 jugada de profundidad, barata,
## y se avanza con `tick()` desde el gestor. Las jugadas se escalonan en el
## tiempo (piensa entre 1 y 6 s simuladas) para repartir el costo por fotograma.
## Reloj 3+2 como la partida del humano.
##
## Cada partida tiene un fin previsto (`planned_end`, entre END_MIN y END_MAX
## segundos de ronda): si no terminó antes por sus propias reglas, al llegar se
## resuelve con un resultado simulado (abandono o mate) según el Elo. Así las
## eliminaciones se reparten a lo largo de la ronda en vez de juntarse al final.
##
## Las tablas (ahogado, material, 50 jugadas, repetición) darían la victoria a las
## negras en el servidor; aquí se re-sortean por Elo para no sesgar por color.
##
## El nivel (Elo) sesga la política: los fuertes capturan mejor, no regalan
## piezas y piensan algo más rápido, así que ganan más a menudo.

signal finished(game: TournamentGame)

const THINK_MIN := 1.0
const THINK_MAX := 6.0
## Ventana (segundos de ronda) en que puede caer el fin previsto de una partida.
const END_MIN := 25.0
const END_MAX := 200.0
## Probabilidad de que el fin simulado sea un abandono (si no, un mate).
const RESIGN_CHANCE := 0.7

var game: TournamentGame
var server: MatchServer
var elo: PackedInt32Array = [1200, 1200]
var table: int = TournamentGame.TABLE_NONE
## Total de jugadas hechas (estadística para medir el costo).
var moves_made: int = 0
## Milisegundos acumulados en la política y en el servidor (medición).
var cost_ms: float = 0.0
## Segundo de la ronda en que la partida se resuelve a la fuerza si sigue en juego.
var planned_end: float = 0.0

var _think_left: float = 0.0
var _thinking_color: int = -1
var _rng := RandomNumberGenerator.new()


func _init(p_game: TournamentGame, white: PlayerSession, black: PlayerSession, white_elo: int, black_elo: int, seed_value: int = -1, seconds: float = 180.0, increment: float = 2.0) -> void:
	game = p_game
	table = p_game.table
	elo = [white_elo, black_elo]
	var cfg := MatchConfig.new()
	cfg.white_seconds = seconds
	cfg.black_seconds = seconds
	cfg.increment_seconds = increment
	cfg.keep_scoresheet = false
	cfg.beginner_help = false
	var cheats: Array[CheatDef] = []
	cfg.cheats = cheats
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	# Más temprano que tarde: la mayoría cae a mitad de ronda, pocas al límite.
	planned_end = lerpf(END_MIN, END_MAX, pow(_rng.randf(), 1.15))
	server = MatchServer.new(cfg, white, black, BoardState.START_FEN, _rng.randi())
	server.game_over.connect(_on_game_over)
	server.start()


func is_over() -> bool:
	return server.is_over()


## Avanza la partida. `can_move` = false retrasa la jugada que tocaba hasta el
## siguiente fotograma (el gestor reparte el costo). Devuelve true si movió.
func tick(delta: float, can_move: bool = true) -> bool:
	if server.is_over():
		return false
	var moved := false
	var t0 := Time.get_ticks_usec()
	server.tick(delta)
	if not server.is_over() and server.time >= planned_end:
		_resolve_simulated()
	if not server.is_over():
		var side := server.board.side_to_move
		if _thinking_color != side:
			_thinking_color = side
			_think_left = _think_time(side)
		_think_left -= delta
		if _think_left <= 0.0 and can_move:
			_play(side)
			moved = true
	cost_ms += (Time.get_ticks_usec() - t0) / 1000.0
	return moved


## Cierra ya la partida con un resultado simulado (la usa el corte de ronda).
func force_end() -> void:
	if not server.is_over():
		_resolve_simulated()


## Cierra la partida con un resultado simulado: gana el favorito del Elo con
## más frecuencia; el perdedor abandona o recibe mate.
func _resolve_simulated() -> void:
	var win := _pick_winner()
	server.force_end(win, _pick_reason())


## Ganador al azar ponderado por Elo (logística), sin sesgo de color.
func _pick_winner() -> int:
	var p_white := 1.0 / (1.0 + pow(10.0, (elo[1] - elo[0]) / 400.0))
	return ChessPiece.WHITE if _rng.randf() < p_white else ChessPiece.BLACK


func _pick_reason() -> String:
	return MatchServer.REASON_RESIGNED if _rng.randf() < RESIGN_CHANCE else MatchServer.REASON_CHECKMATE


## Motivos con que el servidor da la partida a las negras por ser tablas.
static func is_draw_reason(reason: String) -> bool:
	return reason in [MatchServer.REASON_STALEMATE, MatchServer.REASON_REPETITION,
			MatchServer.REASON_FIFTY, MatchServer.REASON_MATERIAL]


func _think_time(color: int) -> float:
	# Más Elo, algo más rápido: así los fuertes llegan mejor al final del reloj.
	var speed := lerpf(1.3, 0.8, clampf((elo[color] - 800.0) / 1000.0, 0.0, 1.0))
	var base := _rng.randf_range(THINK_MIN, THINK_MAX)
	# Con poco tiempo juega más rápido.
	var rem := server.clock.remaining[color]
	if rem < 30.0:
		base *= 0.4
	return base * speed


func _play(color: int) -> void:
	var uci := choose_move(server.board, elo[color], _rng, server.legal_moves())
	_thinking_color = -1
	if uci == "":
		return
	var res := server.submit_move(color, uci)
	if res.ok:
		moves_made += 1


## Política de 1 jugada: valor de la captura y de la coronación, castigo por dejar
## la pieza en una casilla atacada y un poco de centro y desarrollo; se muestrea
## con una temperatura que baja con el Elo. Devuelve la jugada en UCI.
static func choose_move(board: BoardState, elo_value: int, rng: RandomNumberGenerator, legal: Array[ChessMove] = []) -> String:
	var moves: Array[ChessMove] = legal if not legal.is_empty() else ChessRules.legal_moves(board)
	if moves.is_empty():
		return ""
	var us := board.side_to_move
	var them := ChessPiece.opposite(us)
	var skill := clampf((elo_value - 800.0) / 1000.0, 0.0, 1.0)
	var temperature := lerpf(220.0, 45.0, skill)
	var scores := PackedFloat64Array()
	scores.resize(moves.size())
	var best := -1.0e9
	for i in moves.size():
		var m: ChessMove = moves[i]
		var piece := board.squares[m.from]
		var type := ChessPiece.type_of(piece)
		var s := 0.0
		if ChessRules.is_capture(board, m):
			var victim := board.squares[m.to]
			s += ChessPiece.value_of(victim) if victim != ChessPiece.NONE else 100.0
		if m.promotion != 0:
			s += ChessPiece.VALUES[m.promotion] - 100.0
		if type != ChessPiece.KING and ChessRules.is_square_attacked(board, m.to, them):
			s -= ChessPiece.VALUES[type] * lerpf(0.5, 1.0, skill)
		# Centro y desarrollo: pequeñas preferencias para que no parezca ruido puro.
		var f := ChessPiece.file_of(m.to)
		var r := ChessPiece.rank_of(m.to)
		s += (3.5 - absf(f - 3.5) + 3.5 - absf(r - 3.5)) * 4.0 * (1.0 if type != ChessPiece.KING else -1.0)
		if (type == ChessPiece.KNIGHT or type == ChessPiece.BISHOP) and ChessPiece.rank_of(m.from) == (0 if us == ChessPiece.WHITE else 7):
			s += 25.0
		scores[i] = s
		best = maxf(best, s)
	var weights := PackedFloat64Array()
	weights.resize(moves.size())
	var total := 0.0
	for i in moves.size():
		weights[i] = exp((scores[i] - best) / temperature)
		total += weights[i]
	var pick := rng.randf() * total
	for i in moves.size():
		pick -= weights[i]
		if pick <= 0.0:
			return moves[i].uci()
	return moves[moves.size() - 1].uci()


func _on_game_over(winner: int, reason: String) -> void:
	# En el torneo las tablas se las lleva siempre el negro; en una mesa de fondo eso
	# sesgaría los resultados, así que se re-sortean por Elo como un final simulado.
	if is_draw_reason(reason):
		winner = _pick_winner()
		reason = _pick_reason()
		server.winner = winner
		server.end_reason = reason
	game.reason = reason
	finished.emit(game)
