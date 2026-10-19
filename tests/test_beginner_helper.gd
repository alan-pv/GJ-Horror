extends TestCase
## Ayuda para principiantes: textos en inglés, resultados y atajo de precálculo.

const HANGS_QUEEN := "rnbqkbnr/ppp2ppp/4p3/3p4/3P4/3Q4/PPP1PPPP/RNB1KBNR w KQkq - 0 3"


func test_hanging_queen_text_is_english() -> void:
	var b := BoardState.from_fen(HANGS_QUEEN)
	var text := BeginnerHelper.check_move(b, ChessMove.from_uci("d3h7"), 150)
	check_eq(text, "...no, that leaves the queen hanging.", "dama colgada")


func test_quiet_move_is_accepted() -> void:
	var b := BoardState.start_position()
	check_eq(BeginnerHelper.check_move(b, ChessMove.from_uci("e2e4"), 150), "", "e4 es normal")


func test_illegal_or_null_move_is_ignored() -> void:
	var b := BoardState.start_position()
	check_eq(BeginnerHelper.check_move(b, ChessMove.from_uci("e2e5"), 150), "", "ilegal")
	check_eq(BeginnerHelper.check_move(b, null, 150), "", "null")


func test_allowing_mate_is_flagged() -> void:
	# Ta5?? deja la primera fila sin guardia: Td1# (la torre blanca ya no cubre d1).
	var b := BoardState.from_fen("3r2k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1")
	check_eq(BeginnerHelper.check_move(b, ChessMove.from_uci("a1a5"), 150), "...wait, that allows mate.", "mate en 1")


func test_precompute_gives_same_answer() -> void:
	var positions := [HANGS_QUEEN, BoardState.START_FEN, "r1bq1rk1/pppp1ppp/2n2n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQ1RK1 b - - 0 6"]
	for fen in positions:
		var b := BoardState.from_fen(fen)
		for m in ChessRules.legal_moves(b):
			BeginnerHelper._cache_key = ""
			var plain := BeginnerHelper.check_move(b, m, 150)
			BeginnerHelper.precompute_async(b, false)
			check_eq(BeginnerHelper._cache_key, b.position_key(), "se guardó el análisis")
			var cached := BeginnerHelper.check_move(b, m, 150)
			check_eq(cached, plain, "%s %s con y sin precálculo" % [fen, m.uci()])
			if plain != "":
				break  # basta una jugada con aviso por posición para no alargar la prueba
	BeginnerHelper._cache_key = ""
