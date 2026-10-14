extends TestCase

const KIWIPETE := "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
const POS3 := "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"
const POS4 := "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1"
const POS5 := "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8"


func _play(b: BoardState, ucis: Array) -> void:
	for u in ucis:
		var m := ChessRules.find_legal(b, ChessMove.from_uci(u))
		check(m != null, "jugada ilegal en la secuencia: " + u)
		if m == null:
			return
		ChessRules.apply_move(b, m)


func test_fen_roundtrip() -> void:
	for fen in [BoardState.START_FEN, KIWIPETE, POS4, POS5]:
		check_eq(BoardState.from_fen(fen).to_fen(), fen, "fen")


func test_perft_start() -> void:
	var b := BoardState.start_position()
	check_eq(ChessRules.perft(b, 1), 20, "d1")
	check_eq(ChessRules.perft(b, 2), 400, "d2")
	check_eq(ChessRules.perft(b, 3), 8902, "d3")


func test_perft_kiwipete() -> void:
	var b := BoardState.from_fen(KIWIPETE)
	check_eq(ChessRules.perft(b, 1), 48, "d1")
	check_eq(ChessRules.perft(b, 2), 2039, "d2")
	check_eq(ChessRules.perft(b, 3), 97862, "d3")


func test_perft_pos3() -> void:
	var b := BoardState.from_fen(POS3)
	check_eq(ChessRules.perft(b, 3), 2812, "d3")
	check_eq(ChessRules.perft(b, 4), 43238, "d4")


func test_perft_pos4() -> void:
	check_eq(ChessRules.perft(BoardState.from_fen(POS4), 3), 9467, "d3")


func test_perft_pos5() -> void:
	check_eq(ChessRules.perft(BoardState.from_fen(POS5), 3), 62379, "d3")


func test_en_passant_and_capture_pile() -> void:
	var b := BoardState.start_position()
	_play(b, ["e2e4", "a7a6", "e4e5", "d7d5"])
	check_eq(ChessPiece.square_name(b.ep_square), "d6", "casilla al paso")
	_play(b, ["e5d6"])
	check_eq(b.piece_at(ChessPiece.square_from_name("d5")), ChessPiece.NONE, "peón capturado al paso")
	check_eq(b.captured[ChessPiece.WHITE], [ChessPiece.make(ChessPiece.BLACK, ChessPiece.PAWN)], "pila de blancas")


func test_ep_square_only_when_capturable() -> void:
	var b := BoardState.start_position()
	_play(b, ["e2e4"])
	check_eq(b.ep_square, -1, "sin peón rival al lado no hay al paso")


func test_castling_blocked_through_check() -> void:
	var b := BoardState.from_fen("4k3/8/8/8/8/8/5r2/4K2R w K - 0 1")
	check(ChessRules.find_legal(b, ChessMove.from_uci("e1g1")) == null, "no se enroca pasando por casilla atacada")


func test_castling_needs_physical_rook() -> void:
	# El derecho sigue anotado pero la torre ya no está (p. ej. robada).
	var b := BoardState.from_fen("4k3/8/8/8/8/8/8/4K3 w K - 0 1")
	check(ChessRules.find_legal(b, ChessMove.from_uci("e1g1")) == null, "sin torre no hay enroque")


func test_promotion_defaults_to_queen() -> void:
	var b := BoardState.from_fen("8/P6k/8/8/8/8/8/K7 w - - 0 1")
	var m := ChessRules.find_legal(b, ChessMove.from_uci("a7a8"))
	check(m != null and m.promotion == ChessPiece.QUEEN, "coronación a dama por defecto")
	m = ChessRules.find_legal(b, ChessMove.from_uci("a7a8n"))
	check(m != null and m.promotion == ChessPiece.KNIGHT, "subpromoción")


func test_insufficient_material() -> void:
	check(ChessRules.insufficient_material(BoardState.from_fen("8/8/4k3/8/8/2K5/8/8 w - - 0 1")), "K vs K")
	check(ChessRules.insufficient_material(BoardState.from_fen("8/8/4k3/8/8/2KN4/8/8 w - - 0 1")), "KN vs K")
	check(ChessRules.insufficient_material(BoardState.from_fen("8/8/2k1b3/8/8/2KB4/8/8 w - - 0 1")), "alfiles del mismo color")
	check(not ChessRules.insufficient_material(BoardState.from_fen("8/8/4kb2/8/8/2KB4/8/8 w - - 0 1")), "alfiles de distinto color")
	check(not ChessRules.insufficient_material(BoardState.from_fen("8/8/4k3/8/8/2KP4/8/8 w - - 0 1")), "con peón")


func test_never_capture_king() -> void:
	# Posición imposible: el rey negro está en jaque y le toca a blancas.
	var b := BoardState.from_fen("4k3/8/8/8/8/8/8/R3K3 w - - 0 1")
	b.squares[ChessPiece.square_from_name("a1")] = ChessPiece.NONE
	b.squares[ChessPiece.square_from_name("e2")] = ChessPiece.make(ChessPiece.WHITE, ChessPiece.ROOK)
	for m in ChessRules.legal_moves(b):
		check(m.to != ChessPiece.square_from_name("e8"), "capturó al rey")
