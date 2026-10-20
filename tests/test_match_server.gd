extends TestCase


func _make(fen: String = BoardState.START_FEN, help: bool = false) -> MatchServer:
	var cfg := MatchConfig.new()
	cfg.beginner_help = help
	cfg.arbiter_delay = 1.0
	for id in ["own", "enemy", "steal"]:
		cfg.cheats.append(load("res://data/cheats/%s.tres" % id))
	var m := MatchServer.new(cfg, PlayerSession.new(1, "Blancas"), PlayerSession.new(2, "Negras", true), fen, 1)
	m.start()
	return m


func test_turns_and_clock() -> void:
	var m := _make()
	check(not m.submit_move(ChessPiece.BLACK, "e7e5").ok, "negras no mueven primero")
	m.tick(2.0)
	check(m.submit_move(ChessPiece.WHITE, "e2e4").ok, "e4")
	check_eq(m.clock.remaining[0], 180.0, "reloj blancas (2 s de partida +2 de incremento)")
	check_eq(m.clock.running, ChessPiece.BLACK, "corre el reloj negro")
	check(not m.submit_move(ChessPiece.BLACK, "e7e4").ok, "ilegal rechazada")


func test_timeout_loses() -> void:
	var m := _make()
	m.tick(181.0)
	check_eq(m.winner, ChessPiece.BLACK, "blancas pierden por tiempo")
	check_eq(m.end_reason, MatchServer.REASON_TIMEOUT)


func test_checkmate() -> void:
	var m := _make()
	for u in ["f2f3", "e7e5", "g2g4"]:
		m.submit_move(m.board.side_to_move, u)
	m.submit_move(ChessPiece.BLACK, "d8h4")
	check_eq(m.winner, ChessPiece.BLACK, "mate del loco")
	check_eq(m.end_reason, MatchServer.REASON_CHECKMATE)


func test_stalemate_black_wins_even_if_black_is_stalemated() -> void:
	var m2 := _make("7k/8/6K1/8/8/8/8/5Q2 w - - 0 1")
	m2.submit_move(ChessPiece.WHITE, "f1f7")
	check_eq(m2.end_reason, MatchServer.REASON_STALEMATE)
	check_eq(m2.winner, ChessPiece.BLACK, "ahogado: ganan negras")


func test_repetition_black_wins() -> void:
	var m := _make()
	for i in 2:
		for u in ["g1f3", "g8f6", "f3g1", "f6g8"]:
			m.submit_move(m.board.side_to_move, u)
	check_eq(m.end_reason, MatchServer.REASON_REPETITION)
	check_eq(m.winner, ChessPiece.BLACK)


func test_insufficient_material_black_wins() -> void:
	var m := _make("8/8/4k3/8/8/2K5/3r4/8 w - - 0 1")
	m.submit_move(ChessPiece.WHITE, "c3d2")
	check_eq(m.end_reason, MatchServer.REASON_MATERIAL)
	check_eq(m.winner, ChessPiece.BLACK)


func test_beginner_warning_then_allowed() -> void:
	# Blancas dejan la dama colgada con Dxd5?? cuando el peón de e6 la captura.
	var m := _make("rnbqkbnr/ppp2ppp/4p3/3p4/3P4/8/PPPQPPPP/RNB1KBNR w KQkq - 0 3", true)
	var r := m.submit_move(ChessPiece.WHITE, "d2a5")
	check(r.ok, "jugada normal aceptada")
	m = _make("rnbqkbnr/ppp2ppp/4p3/3p4/3P4/8/PPPQPPPP/RNB1KBNR w KQkq - 0 3", true)
	m.board.squares[ChessPiece.square_from_name("d2")] = ChessPiece.NONE
	m.board.squares[ChessPiece.square_from_name("d3")] = ChessPiece.make(ChessPiece.WHITE, ChessPiece.QUEEN)
	r = m.submit_move(ChessPiece.WHITE, "d3h7")
	check(not r.ok and r.warning.contains("queen"), "primer intento bloqueado: " + str(r))
	r = m.submit_move(ChessPiece.WHITE, "d3h7")
	check(r.ok, "segundo intento permitido")


func test_beginner_help_off_for_bots() -> void:
	var m := _make("4k3/8/8/8/8/8/2q5/3QK3 b - - 0 1", true)
	# Negras (bot) cambian damas mal a propósito: no debe haber aviso.
	var r := m.submit_move(ChessPiece.BLACK, "c2c1")
	check(r.ok, "los bots no reciben ayuda")
