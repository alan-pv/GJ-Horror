extends TestCase

const W := ChessPiece.WHITE
const B := ChessPiece.BLACK


func _sq(n: String) -> int:
	return ChessPiece.square_from_name(n)


func _make(fen: String = BoardState.START_FEN) -> MatchServer:
	var cfg := MatchConfig.new()
	cfg.beginner_help = false
	cfg.arbiter_delay = 1.0
	for id in ["nudge", "slide", "steal", "move_enemy"]:
		cfg.cheats.append(load("res://data/cheats/%s.tres" % id))
	var m := MatchServer.new(cfg, PlayerSession.new(1, "Blancas"), PlayerSession.new(2, "Negras", true), fen, 7)
	m.start()
	return m


func _def(id: String) -> CheatDef:
	return load("res://data/cheats/%s.tres" % id)


func test_kings_are_untouchable() -> void:
	var b := BoardState.start_position()
	check(not CheatRules.validate(b, W, _def("steal"), _sq("e8"), -1).ok, "no se roba un rey")
	check(not CheatRules.validate(b, W, _def("move_enemy"), _sq("e8"), _sq("e6")).ok, "no se mueve un rey")


func test_nudge_forward_only() -> void:
	var b := BoardState.start_position()
	check(CheatRules.validate(b, W, _def("nudge"), _sq("e2"), _sq("e3")).ok, "peón avanza")
	check(not CheatRules.validate(b, W, _def("nudge"), _sq("e2"), _sq("d3")).ok, "solo recto")
	check(CheatRules.validate(b, B, _def("nudge"), _sq("e7"), _sq("e6")).ok, "negras avanzan hacia abajo")


func test_slide_needs_clear_line() -> void:
	var b := BoardState.from_fen("4k3/8/8/8/8/8/8/R3K3 w - - 0 1")
	var v := CheatRules.validate(b, W, _def("slide"), _sq("a1"), _sq("a4"))
	check(v.ok, "torre se desliza")
	check_eq(v.duration, 1.0 + 0.35 * 3, "duración = base + distancia")
	check(not CheatRules.validate(b, W, _def("slide"), _sq("a1"), _sq("b3")).ok, "no en línea")
	check(not CheatRules.validate(b, W, _def("slide"), _sq("a1"), _sq("a8")).ok, "más lejos que el máximo")


func test_cannot_leave_own_king_in_check() -> void:
	# El alfil de e2 tapa la torre de e8: moverlo deja al rey en jaque.
	var b := BoardState.from_fen("4r1k1/8/8/8/8/8/4B3/4K3 b - - 0 1")
	check(not CheatRules.validate(b, W, _def("slide"), _sq("e2"), _sq("c4")).ok, "clavado")


func test_cannot_check_side_not_to_move() -> void:
	# Le toca a blancas: si el empujón pone en jaque a negras, la posición es imposible.
	var b := BoardState.from_fen("4k3/8/8/8/8/8/8/R3K3 w - - 0 1")
	var cfg := _def("slide").duplicate()
	cfg.max_distance = 0
	check(not CheatRules.validate(b, W, cfg, _sq("a1"), _sq("a8")).ok, "no dar jaque en tu turno")
	b.side_to_move = B
	check(CheatRules.validate(b, W, cfg, _sq("a1"), _sq("a8")).ok, "en turno rival sí: se resuelve en su turno")


func test_steal_goes_to_hand_and_takes_time() -> void:
	var m := _make()
	var r := m.start_cheat(B, &"steal", _sq("b1"))
	check(r.ok, "robo empieza en el turno rival: " + str(r))
	check(m.is_hand_busy(B), "mano ocupada")
	m.tick(1.0)
	check_eq(m.board.piece_at(_sq("b1")), ChessPiece.make(W, ChessPiece.KNIGHT), "aún no termina")
	m.tick(1.0)
	check_eq(m.board.piece_at(_sq("b1")), ChessPiece.NONE, "caballo robado")
	check_eq(m.board.hand[B], [ChessPiece.make(W, ChessPiece.KNIGHT)], "en la mano")
	check(ChessRules.find_legal(m.board, ChessMove.from_uci("b1c3")) == null, "las blancas juegan como si nunca hubiera estado")


func test_cannot_move_while_cheating() -> void:
	var m := _make()
	m.start_cheat(W, &"nudge", _sq("e2"), _sq("e3"))
	check(not m.submit_move(W, "d2d4").ok, "una sola mano")


func test_cheat_revalidated_at_end() -> void:
	var m := _make()
	m.submit_move(W, "e2e4")
	# Negras mueven un caballo blanco en el turno negro; la mano queda ocupada.
	m.start_cheat(B, &"move_enemy", _sq("g1"), _sq("e2"))
	m.submit_move(B, "a7a6")  # mano ocupada: no debe aceptarse
	check_eq(m.board.side_to_move, B, "negras no movieron")
	m.tick(3.0)
	check_eq(m.board.piece_at(_sq("e2")), ChessPiece.make(W, ChessPiece.KNIGHT), "caballo movido")
	check(m.board.offsets[_sq("e2")].length() > 0.0, "queda descentrado (evidencia)")


func test_correct_accusation_eliminates_cheater() -> void:
	var m := _make()
	m.submit_move(W, "e2e4")
	m.start_cheat(B, &"nudge", _sq("d7"), _sq("d6"))
	m.tick(1.0)
	m.submit_move(B, "a7a6")
	check(m.accuse(W).ok, "acusación")
	check(m.clock.paused, "el reloj se detiene mientras llega el árbitro")
	m.tick(1.1)
	check_eq(m.winner, W, "el acusador gana")
	check_eq(m.end_reason, MatchServer.REASON_CAUGHT)


func test_window_only_since_last_move() -> void:
	var m := _make()
	m.start_cheat(B, &"nudge", _sq("d7"), _sq("d6"))
	m.tick(1.0)
	m.submit_move(W, "e2e4")  # la trampa quedó antes de la última jugada blanca
	m.submit_move(B, "a7a6")
	m.accuse(W)
	m.tick(1.1)
	check(not m.is_over(), "acusación falsa: la partida sigue")
	check_eq(m.sessions[W].warnings, 1, "una advertencia")


func test_three_false_accusations_eliminate() -> void:
	var m := _make()
	for i in 3:
		m.accuse(W)
		m.tick(1.1)
	check_eq(m.winner, B, "tercera falsa elimina al acusador")
	check_eq(m.end_reason, MatchServer.REASON_FALSE_ACCUSATIONS)


func test_aborted_cheat_does_not_count() -> void:
	var m := _make()
	m.submit_move(W, "e2e4")
	m.start_cheat(B, &"steal", _sq("b1"))
	m.tick(0.5)
	m.abort_cheat(B)
	m.tick(2.0)
	check_eq(m.board.piece_at(_sq("b1")), ChessPiece.make(W, ChessPiece.KNIGHT), "nada cambió")
	m.accuse(W)
	m.tick(1.1)
	check(not m.is_over(), "abortada no cuenta")


func test_exposure_marks_seen() -> void:
	var m := _make()
	m.set_gaze(W, Vector3(0, 1, 1), Vector3(0, 0, -1))  # mira al frente, no al tablero
	m.start_cheat(B, &"steal", _sq("b1"))
	check(not m.active_cheat(B).seen, "no visto al empezar")
	m.set_gaze(W, Vector3(0, 1, 1), Vector3(0, -1, -1))  # baja la vista al tablero
	m.tick(0.1)
	check(m.active_cheat(B).seen, "visto")


func test_cheat_resets_fifty_move_rule() -> void:
	var m := _make("4k3/8/8/8/8/8/8/R3K3 b - - 60 40")
	m.start_cheat(W, &"slide", _sq("a1"), _sq("a3"))
	m.tick(2.0)
	check_eq(m.board.halfmove_clock, 0, "50 jugadas reiniciadas")


func test_game_end_emits_cheat_aborted() -> void:
	var m := _make()
	var aborted: Array = []
	m.cheat_aborted.connect(func(color: int, id: StringName) -> void: aborted.append([color, id]))
	m.start_cheat(B, &"steal", _sq("b1"))
	m.clock.remaining[W] = 0.05
	m.tick(0.1)
	check(m.is_over(), "se acabó el tiempo")
	check_eq(aborted.size(), 1, "una trampa cancelada con aviso")
	check_eq(aborted[0], [B, &"steal"], "color e id de la trampa")
	check(not m.is_hand_busy(B), "mano libre")
	check_eq(m.cheat_log[0].status, "aborted", "queda abortada en el registro")


func test_legal_cache_follows_board() -> void:
	var m := _make()
	var before := m.legal_moves()
	check_eq(before.size(), 20, "20 jugadas iniciales")
	check(m.legal_moves() == before, "misma lista reutilizada si nada cambió")
	m.submit_move(W, "e2e4")
	m.submit_move(B, "e7e5")
	var n := m.legal_moves().size()
	# Las blancas roban el peón e5: el peón e4 gana el avance y la caché debe notarlo.
	check(m.start_cheat(W, &"steal", _sq("e5")).ok, "robo empieza")
	m.tick(2.1)
	check_eq(m.board.piece_at(_sq("e5")), ChessPiece.NONE, "peón robado")
	check_eq(m.legal_moves().size(), ChessRules.legal_moves(m.board).size(), "caché igual al cálculo directo")
	check(m.legal_moves().size() != n, "la lista cambió tras la trampa")
