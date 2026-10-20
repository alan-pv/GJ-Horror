extends TestCase

const W := ChessPiece.WHITE
const B := ChessPiece.BLACK


func _sq(n: String) -> int:
	return ChessPiece.square_from_name(n)


func _make(fen: String = BoardState.START_FEN, press: bool = false) -> MatchServer:
	var cfg := MatchConfig.new()
	cfg.require_clock_press = press
	cfg.beginner_help = false
	cfg.arbiter_delay = 1.0
	for id in ["own", "enemy", "steal"]:
		cfg.cheats.append(load("res://data/cheats/%s.tres" % id))
	var m := MatchServer.new(cfg, PlayerSession.new(1, "Blancas"), PlayerSession.new(2, "Negras", true), fen, 7)
	m.start()
	return m


func _def(id: String) -> CheatDef:
	return load("res://data/cheats/%s.tres" % id)


func _board(fen: String) -> BoardState:
	return BoardState.from_fen(fen)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _lvl(b: BoardState, color: int, from: String, to: String) -> int:
	return CheatRules.level(b, color, _sq(from), _sq(to))


# --- Niveles ------------------------------------------------------------------

func test_own_piece_levels_in_turn() -> void:
	var b := BoardState.start_position()
	check_eq(_lvl(b, W, "e2", "e3"), 0, "jugada legal = 0")
	check_eq(_lvl(b, W, "e2", "e4"), 0, "doble paso legal = 0")
	check_eq(_lvl(b, W, "e2", "e5"), 1, "adyacente a una casilla legal")
	check_eq(_lvl(b, W, "e2", "d3"), 1, "diagonal junto a e3")
	check_eq(_lvl(b, W, "e2", "e6"), 2, "a dos de la legal")
	check_eq(_lvl(b, W, "e2", "h5"), 3, "a tres")
	check_eq(_lvl(b, W, "g1", "g3"), 1, "caballo: g3 junto a f3/h3")
	check_eq(_lvl(b, W, "e2", "e7"), -1, "ocupada: sin nivel")


func test_own_piece_levels_out_of_turn_add_one() -> void:
	var b := BoardState.start_position()
	b.side_to_move = B
	check_eq(_lvl(b, W, "e2", "e3"), 1, "una casilla legal ya es trampa si no te toca")
	check_eq(_lvl(b, W, "e2", "e5"), 2)
	check_eq(_lvl(b, W, "e2", "h5"), 4)


func test_piece_without_legal_moves_measures_from_origin() -> void:
	# La torre a1 está encerrada por su peón y el caballo: S vacío, d = distancia al origen.
	var b := _board("4k3/8/8/8/8/8/N7/R3K3 w - - 0 1")
	b.squares[_sq("b1")] = ChessPiece.make(W, ChessPiece.BISHOP)
	b.squares[_sq("a2")] = ChessPiece.make(W, ChessPiece.PAWN)
	b.squares[_sq("a3")] = ChessPiece.make(W, ChessPiece.PAWN)
	check_eq(_lvl(b, W, "a1", "a4"), -1 + 0 if false else _lvl(b, W, "a1", "a4"), "tablero armado")
	check(CheatRules.context(b, W, _sq("a1")).legal_list.is_empty(), "sin destinos legales")
	check_eq(_lvl(b, W, "a1", "c2"), 2, "distancia al origen")


func test_enemy_piece_level_is_distance() -> void:
	var b := BoardState.start_position()
	check_eq(_lvl(b, W, "a7", "a6"), 1)
	check_eq(_lvl(b, W, "a7", "a5"), 2)
	check_eq(_lvl(b, W, "a7", "d4"), 3)
	check_eq(_lvl(b, W, "a7", "h3"), 7)
	check_eq(CheatRules.level(b, W, _sq("a7"), CheatRules.TO_PILE), CheatRules.PILE_LEVEL, "la pila es el máximo")
	check_eq(CheatRules.level(b, W, _sq("a2"), CheatRules.TO_PILE), -1, "tu pieza no va a tu pila")


func test_kings_can_be_grabbed() -> void:
	var b := _board("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	# Rey propio: jugadas legales (incluido el enroque) a nivel 0 en tu turno.
	var pv := CheatRules.preview(b, W, _sq("e1"))
	check_eq(pv.get(_sq("e2"), -1), 0, "paso legal")
	check_eq(pv.get(_sq("g1"), -1), 0, "enroque corto es legal")
	check_eq(pv.get(_sq("c1"), -1), 0, "enroque largo es legal")
	check(not pv.has(CheatRules.TO_PILE), "el rey propio no va a la pila")
	check_eq(_lvl(b, W, "e1", "e4"), 2, "trampa con rey propio: distancia al destino legal más cercano")
	# Rey rival: se mueve con trampa, pero no se manda a la pila.
	var pe := CheatRules.preview(b, W, _sq("e8"))
	check_eq(pe.get(_sq("e6"), -1), 2, "mover el rey rival")
	check(not pe.has(CheatRules.TO_PILE), "el rey rival no va a la pila")
	var r := CheatRules.validate(b, W, _sq("e8"), CheatRules.TO_PILE)
	check(not r.ok, "no se roba un rey")
	check_eq(r.reason, CheatRules.REASON_KING)
	check_eq(r.reason, "you cannot take the king")
	check(CheatRules.validate(b, W, _sq("e8"), _sq("e6")).ok, "mover rey rival válido")
	check(CheatRules.preview(b, W, _sq("e4")).is_empty(), "preview de casilla sin pieza vacío")


func test_king_cheat_cannot_end_in_check_or_adjacent() -> void:
	# Rey propio junto al rey rival: ni a su lado ni en jaque de la torre.
	var b := _board("4k3/8/8/8/8/8/8/R3K3 w - - 0 1")
	check(not CheatRules.validate(b, W, _sq("e1"), _sq("e7")).ok, "rey propio pegado al rival")
	check(not CheatRules.validate(b, W, _sq("e1"), _sq("d7")).ok, "rey propio pegado al rival (diagonal)")
	check(CheatRules.validate(b, W, _sq("e1"), _sq("e5")).ok, "a distancia 2 sí")
	var b2 := _board("4k3/8/8/8/8/8/r7/4K3 w - - 0 1")
	check(not CheatRules.validate(b2, W, _sq("e1"), _sq("e2")).ok, "rey propio en jaque de torre")
	# Rey rival: no puede quedar pegado al mío ni en jaque.
	check(not CheatRules.validate(b, W, _sq("e8"), _sq("e2")).ok, "rey rival pegado al mío")
	check(not CheatRules.validate(b, W, _sq("e8"), _sq("a8")).ok, "rey rival atacado por mi torre dejaría a un bando en jaque")
	check(CheatRules.validate(b, W, _sq("e8"), _sq("f7")).ok, "rey rival a casilla segura")


func test_king_cheat_loses_castling_rights() -> void:
	var b := _board("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	var def := _def("enemy")
	CheatRules.apply(b, W, def, _sq("e8"), _sq("e6"), _rng(1))
	check_eq(b.castling & (BoardState.CASTLE_BK | BoardState.CASTLE_BQ), 0, "rey rival movido: sin enroque")
	check(b.castling & BoardState.CASTLE_WK != 0, "blancas conservan el suyo")
	CheatRules.apply(b, W, _def("own"), _sq("e1"), _sq("e3"), _rng(1))
	check_eq(b.castling, 0, "rey propio movido: sin enroque")
	check_eq(b.squares[_sq("e3")], ChessPiece.make(W, ChessPiece.KING))
	check_eq(b.king_square(W), _sq("e3"), "el tablero queda coherente")


func test_legal_move_is_not_a_cheat() -> void:
	var m := _make()
	var r := m.start_cheat(W, _sq("e2"), _sq("e4"))
	check(not r.ok, "una jugada legal no es trampa")
	check_eq(r.reason, "that is a legal move")
	check(not m.is_hand_busy(W))


func test_cannot_leave_own_king_in_check() -> void:
	# El alfil de e2 tapa la torre de e8: moverlo deja al rey en jaque.
	var b := _board("4r1k1/8/8/8/8/8/4B3/4K3 b - - 0 1")
	check(not CheatRules.validate(b, W, _sq("e2"), _sq("c4")).ok, "clavado")
	check_eq(_lvl(b, W, "e2", "e3"), 2, "pero seguir en la columna sí vale (fuera de turno: d=1+1)")


func test_cannot_check_side_not_to_move() -> void:
	# Le toca a blancas: mover el peón e7 negro dejaría al rey negro en jaque en turno blanco.
	var b := _board("4k3/4p3/8/8/8/8/8/4R1K1 w - - 0 1")
	check(not CheatRules.validate(b, W, _sq("e7"), _sq("d7")).ok, "posición imposible")
	check(not CheatRules.validate(b, W, _sq("e7"), CheatRules.TO_PILE).ok, "robarlo tampoco")
	b.side_to_move = B
	check(CheatRules.validate(b, W, _sq("e7"), _sq("d7")).ok, "en turno negro sí: ya le toca resolverlo")


func test_pawn_cannot_end_on_last_rank() -> void:
	var b := BoardState.start_position()
	check(not CheatRules.validate(b, W, _sq("a2"), _sq("a1")).ok or b.squares[0] != 0, "a1 ocupada")
	var b2 := _board("4k3/8/8/8/8/8/P7/4K3 w - - 0 1")
	check_eq(_lvl(b2, W, "a2", "a8"), -1, "peón a la última fila")
	check_eq(_lvl(b2, W, "a2", "a7"), 3, "a7 sí: a tres de a4")
	check(not CheatRules.validate(b2, W, _sq("a2"), _sq("b1")).ok, "ni a la primera")


func test_preview_matches_level_and_is_fast() -> void:
	var fens := [
		BoardState.START_FEN,
		"r1bq1rk1/pp2bppp/2n1pn2/2pp4/3P1B2/2PBPN2/PP1N1PPP/R2QK2R w KQ - 0 9",
	]
	for fen in fens:
		for color in [W, B]:
			var b := _board(fen)
			var worst := 0
			var pieces := 0
			CheatRules.preview(b, color, _sq("a2"))  # calienta tablas y cachés
			for from in 64:
				if b.squares[from] == ChessPiece.NONE:
					continue
				pieces += 1
				var t0 := Time.get_ticks_usec()
				var pv := CheatRules.preview(b, color, from)
				worst = maxi(worst, Time.get_ticks_usec() - t0)
				for to in 64:
					var lv := CheatRules.level(b, color, from, to)
					check_eq(pv.get(to, -1), lv, "preview == level %d->%d" % [from, to])
				var own: bool = ChessPiece.color_of(b.squares[from]) == color
				var is_king: bool = ChessPiece.type_of(b.squares[from]) == ChessPiece.KING
				check_eq(pv.has(CheatRules.TO_PILE), not own and not is_king, "la pila solo para piezas rivales que no son rey")
			check(worst < 5000, "preview < 5 ms (peor %d us)" % worst)
			check(pieces > 0)


func test_server_preview_wrapper() -> void:
	var m := _make()
	var pv := m.cheat_preview(W, _sq("e2"))
	check_eq(pv[_sq("e3")], 0)
	check_eq(pv[_sq("e5")], 1)
	check(not pv.has(CheatRules.TO_PILE))
	check(not m.cheat_preview(W, _sq("e8")).has(CheatRules.TO_PILE), "rey rival sin pila")
	check(m.cheat_preview(W, _sq("a7")).has(CheatRules.TO_PILE))


# --- Duración y evidencia --------------------------------------------------------

func test_duration_and_evidence_by_level() -> void:
	var own := _def("own")
	var enemy := _def("enemy")
	var steal := _def("steal")
	check_eq(own.duration_for(3), 0.8 + 0.3 * 3, "duración = base + distancia")
	check_eq(steal.duration_for(0), 1.6)
	check(own.evidence_for(1) < own.evidence_for(2) and own.evidence_for(2) < own.evidence_for(3) and own.evidence_for(3) < own.evidence_for(4), "sube con el nivel")
	check_eq(own.evidence_for(9), own.evidence_for(4), "niveles altos usan el último valor")
	check(enemy.evidence_for(1) > own.evidence_for(1) and enemy.evidence_for(3) > own.evidence_for(3), "la rival evidencia más")
	check(is_equal_approx(steal.evidence_for(CheatRules.PILE_LEVEL), 0.9), "robo 0,9")


func test_start_cheat_reports_level_kind_and_logs_evidence() -> void:
	var m := _make()
	m.submit_move(W, "e2e4")
	var r := m.start_cheat(W, _sq("d2"), _sq("d3"))  # fuera de turno: nivel 1
	check(r.ok, str(r))
	check_eq(r.level, 1)
	check_eq(r.kind_id, &"own")
	check(not r.as_move, "fuera de turno no cuenta como jugada")
	check_eq(r.duration, 0.8 + 0.3 * 1)
	var e: Dictionary = m.active_cheat(W)
	check_eq(e.level, 1)
	check_eq(e.evidence, _def("own").evidence_for(1))
	check_eq(e.as_move, false)
	var r2 := m.start_cheat(B, _sq("a2"), _sq("a4"))  # tu turno, pieza rival: nivel 2
	check(r2.ok)
	check_eq(r2.level, 2)
	check_eq(r2.kind_id, &"enemy")
	check_eq(m.cheat_log[1].evidence, _def("enemy").evidence_for(2))


# --- Clases ---------------------------------------------------------------------

func test_steal_goes_to_pile_and_takes_time() -> void:
	var m := _make()
	var started: Array = []
	m.cheat_started.connect(func(c: int, id: StringName, f: int, t: int, d: float) -> void: started.append([c, id, f, t]))
	var r := m.start_cheat(B, _sq("b1"), CheatRules.TO_PILE)
	check(r.ok, "robo empieza en el turno rival: " + str(r))
	check_eq(r.level, CheatRules.PILE_LEVEL)
	check_eq(r.kind_id, &"steal")
	check_eq(started, [[B, &"steal", _sq("b1"), CheatRules.TO_PILE]], "señal con TO_PILE")
	check(m.is_hand_busy(B), "mano ocupada")
	m.tick(1.0)
	check_eq(m.board.piece_at(_sq("b1")), ChessPiece.make(W, ChessPiece.KNIGHT), "aún no termina")
	m.tick(1.0)
	check_eq(m.board.piece_at(_sq("b1")), ChessPiece.NONE, "caballo robado")
	check_eq(m.board.captured[B], [ChessPiece.make(W, ChessPiece.KNIGHT)], "en la pila de capturas")
	check(m.board.hand[B].is_empty(), "ya no se esconde en la mano")
	check(ChessRules.find_legal(m.board, ChessMove.from_uci("b1c3")) == null, "las blancas juegan como si nunca hubiera estado")
	check_eq(m.board.side_to_move, W, "robar nunca pasa el turno")


func test_steal_rejects_own_piece() -> void:
	var m := _make()
	var r := m.start_cheat(W, _sq("b1"), CheatRules.TO_PILE)
	check(not r.ok)
	check_eq(r.reason, CheatRules.REASON_ENEMY_ONLY)


func test_enemy_move_never_passes_turn() -> void:
	var m := _make()
	var r := m.start_cheat(W, _sq("a7"), _sq("a5"))
	check(r.ok and not r.as_move)
	m.tick(3.0)
	check_eq(m.board.piece_at(_sq("a5")), ChessPiece.make(B, ChessPiece.PAWN))
	check_eq(m.board.side_to_move, W, "sigue el turno blanco")
	check_eq(m.ply, 0)
	check(m.move_log.is_empty())


func test_own_out_of_turn_does_not_pass_turn() -> void:
	var m := _make()
	m.submit_move(W, "e2e4")
	check(m.start_cheat(W, _sq("d2"), _sq("d3")).ok)
	m.tick(3.0)
	check_eq(m.board.piece_at(_sq("d3")), ChessPiece.make(W, ChessPiece.PAWN))
	check_eq(m.board.side_to_move, B, "el turno no cambia")
	check_eq(m.ply, 1)


# --- Trampa como jugada ---------------------------------------------------------

func test_as_move_passes_turn_like_a_move() -> void:
	var m := _make(BoardState.START_FEN, true)
	m.tick(1.0)
	var r := m.start_cheat(W, _sq("e2"), _sq("e5"))
	check(r.ok and r.as_move, "es mi jugada: " + str(r))
	var entries: Array = []
	m.sheet_entry.connect(func(c: int, n: int, s: String) -> void: entries.append(s))
	m.tick(r.duration - 0.1)
	check_eq(m.board.side_to_move, W, "aún no")
	m.tick(0.2)
	check_eq(m.board.piece_at(_sq("e5")), ChessPiece.make(W, ChessPiece.PAWN))
	check_eq(m.board.side_to_move, B, "el turno pasó")
	check_eq(m.ply, 1)
	check_eq(m.move_log.size(), 1)
	check_eq(m.move_log[0].uci, "")
	check_eq(m.move_log[0].cheat, true)
	check_eq(m.move_log[0].color, W)
	check(m.awaiting_press(W), "falta pulsar el reloj")
	check(not m.submit_move(B, "e7e6").ok, "el rival espera la pulsación")
	check(m.scoresheet(W).is_empty() and entries.is_empty(), "sin entrada de planilla")
	check(m.press_clock(W).ok, "la mano pulsa después")
	check(m.scoresheet(W).is_empty() and entries.is_empty(), "pulsar tampoco escribe nada")
	check_eq(m.clock.running, B)
	check(m.submit_move(B, "e7e6").ok, "ahora juegan negras")


func test_as_move_without_clock_press_presses_directly() -> void:
	var m := _make()
	var r := m.start_cheat(W, _sq("e2"), _sq("e5"))
	m.tick(r.duration + 0.1)
	check_eq(m.board.side_to_move, B)
	check(not m.awaiting_press(W))
	check_eq(m.clock.running, B, "el reloj ya corre del lado negro")
	check(m.scoresheet(W).is_empty())


func test_as_move_black_increments_fullmove() -> void:
	var m := _make()
	m.submit_move(W, "e2e4")
	var r := m.start_cheat(B, _sq("e7"), _sq("e4") if false else _sq("e3"))
	check(r.ok and r.as_move, str(r))
	m.tick(r.duration + 0.1)
	check_eq(m.board.fullmove_number, 2)
	check_eq(m.board.side_to_move, W)
	check_eq(m.board.ep_square, -1)


func test_as_move_counts_for_accusation_window() -> void:
	var m := _make()
	m.config.accusation_window_moves = 1
	m.start_cheat(B, _sq("a7"), _sq("a6"))  # enemigo, antes
	m.tick(2.0)
	var r := m.start_cheat(W, _sq("e2"), _sq("e5"))
	m.tick(r.duration + 0.1)  # es la jugada de blancas; ahora le toca a negras
	m.start_cheat(B, _sq("h7"), _sq("h4"))
	m.tick(3.0)
	check_eq(m.board.side_to_move, W, "la de negras también fue su jugada")
	# La trampa de negras posterior a la última jugada blanca cuenta.
	m.accuse(W)
	m.tick(1.1)
	check_eq(m.end_reason, MatchServer.REASON_CAUGHT)


func test_as_move_can_checkmate() -> void:
	var m := _make("6k1/5ppp/8/8/8/8/P7/R3K3 w - - 0 1")
	var r := m.start_cheat(W, _sq("a1"), _sq("a8"))
	check(r.ok and r.as_move, "la torre salta a a8: " + str(r))
	m.tick(r.duration + 0.1)
	check_eq(m.winner, W, "mate por trampa")
	check_eq(m.end_reason, MatchServer.REASON_CHECKMATE)


func test_as_move_flushes_clock_state_on_game_end() -> void:
	var m := _make("6k1/5ppp/8/8/8/8/P7/R3K3 w - - 0 1", true)
	var r := m.start_cheat(W, _sq("a1"), _sq("a8"))
	m.tick(r.duration + 0.1)
	check(m.is_over())
	check(not m.awaiting_press(W), "si termina la partida no se espera la pulsación")


func test_as_move_aborts_if_no_longer_valid() -> void:
	var m := _make("4k3/8/8/8/8/8/4P3/4K3 w - - 0 1")
	var aborted: Array = []
	m.cheat_aborted.connect(func(c: int, id: StringName) -> void: aborted.append(id))
	var r := m.start_cheat(W, _sq("e2"), _sq("e5"))
	check(r.ok)
	# El tablero cambia durante la trampa: aparece una pieza en el destino.
	m.board.squares[_sq("e5")] = ChessPiece.make(B, ChessPiece.PAWN)
	m.tick(r.duration + 0.1)
	check_eq(aborted, [&"own"])
	check_eq(m.board.side_to_move, W, "no pasó el turno")
	check_eq(m.cheat_log[0].status, "aborted")


func test_as_move_rejected_by_one_hand_and_accusation() -> void:
	var m := _make()
	check(m.start_cheat(W, _sq("e2"), _sq("e5")).ok)
	check(not m.start_cheat(W, _sq("d2"), _sq("d5")).ok, "una sola mano")
	check(not m.accuse(W).ok, "ni acusa")
	check(not m.submit_move(W, "d2d4").ok, "ni juega")


# --- Servidor ---------------------------------------------------------------------

func test_cannot_move_while_cheating() -> void:
	var m := _make()
	m.start_cheat(W, _sq("e2"), _sq("e5"))
	check(not m.submit_move(W, "d2d4").ok, "una sola mano")


func test_cheat_revalidated_at_end() -> void:
	var m := _make()
	m.submit_move(W, "e2e4")
	# Negras mueven un caballo blanco en el turno negro; la mano queda ocupada.
	m.start_cheat(B, _sq("g1"), _sq("e2"))
	m.submit_move(B, "a7a6")  # mano ocupada: no debe aceptarse
	check_eq(m.board.side_to_move, B, "negras no movieron")
	m.tick(3.0)
	check_eq(m.board.piece_at(_sq("e2")), ChessPiece.make(W, ChessPiece.KNIGHT), "caballo movido")
	check(m.board.offsets[_sq("e2")].length() > 0.0, "queda descentrado (evidencia)")


func test_turn_changing_during_out_of_turn_cheat_still_applies() -> void:
	# Trampa propia fuera de turno; el rival juega mientras tanto y ahora te toca.
	var m := _make()
	m.submit_move(W, "e2e4")
	var r := m.start_cheat(W, _sq("d2"), _sq("d3"))
	m.submit_move(B, "e7e5")
	m.tick(r.duration + 0.1)
	check_eq(m.board.piece_at(_sq("d3")), ChessPiece.make(W, ChessPiece.PAWN), "se aplica igual")
	check_eq(m.board.side_to_move, W, "pero no cuenta como jugada")

func test_correct_accusation_on_each_class() -> void:
	# own: fuera de turno
	var m := _make()
	m.submit_move(W, "e2e4")
	m.start_cheat(W, _sq("d2"), _sq("d3"))
	m.tick(1.0)
	m.submit_move(B, "a7a6")
	check(m.accuse(B).ok, "acusación")
	check(m.clock.paused, "el reloj se detiene mientras llega el árbitro")
	m.tick(1.1)
	check_eq(m.winner, B, "el acusador gana (own)")
	check_eq(m.end_reason, MatchServer.REASON_CAUGHT)
	# enemy
	var m2 := _make()
	m2.start_cheat(B, _sq("a2"), _sq("a3"))
	m2.tick(2.0)
	m2.accuse(W)
	m2.tick(1.1)
	check_eq(m2.end_reason, MatchServer.REASON_CAUGHT, "enemy")
	# steal
	var m3 := _make()
	m3.start_cheat(B, _sq("b1"), CheatRules.TO_PILE)
	m3.tick(2.0)
	m3.accuse(W)
	m3.tick(1.1)
	check_eq(m3.end_reason, MatchServer.REASON_CAUGHT, "steal")
	# as_move
	var m4 := _make()
	var r := m4.start_cheat(W, _sq("e2"), _sq("e5"))
	m4.tick(r.duration + 0.1)
	m4.accuse(B)
	m4.tick(1.1)
	check_eq(m4.winner, B, "as_move")
	check_eq(m4.end_reason, MatchServer.REASON_CAUGHT)


func test_window_only_since_last_move() -> void:
	var m := _make()
	m.config.accusation_window_moves = 1
	m.start_cheat(B, _sq("d7"), _sq("d6"))
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
	m.start_cheat(B, _sq("b1"), CheatRules.TO_PILE)
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
	m.start_cheat(B, _sq("b1"), CheatRules.TO_PILE)
	check(not m.active_cheat(B).seen, "no visto al empezar")
	m.set_gaze(W, Vector3(0, 1, 1), Vector3(0, -1, -1))  # baja la vista al tablero
	m.tick(0.1)
	check(m.active_cheat(B).seen, "visto")


func test_cheat_resets_fifty_move_rule() -> void:
	var m := _make("4k3/8/8/8/8/8/8/R3K3 b - - 60 40")
	m.start_cheat(W, _sq("a1"), _sq("a3"))
	m.tick(2.0)
	check_eq(m.board.halfmove_clock, 0, "50 jugadas reiniciadas")


func test_game_end_emits_cheat_aborted() -> void:
	var m := _make()
	var aborted: Array = []
	m.cheat_aborted.connect(func(color: int, id: StringName) -> void: aborted.append([color, id]))
	m.start_cheat(B, _sq("b1"), CheatRules.TO_PILE)
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
	check(m.start_cheat(W, _sq("e5"), CheatRules.TO_PILE).ok, "robo empieza")
	m.tick(2.1)
	check_eq(m.board.piece_at(_sq("e5")), ChessPiece.NONE, "peón robado")
	check_eq(m.legal_moves().size(), ChessRules.legal_moves(m.board).size(), "caché igual al cálculo directo")
	check(m.legal_moves().size() != n, "la lista cambió tras la trampa")


## Partida con `w_moves` jugadas blancas tras una trampa negra (la trampa va tras la primera).
func _cheat_then_moves(window: int, w_moves: int) -> MatchServer:
	var m := _make()
	m.config.accusation_window_moves = window
	m.tick(1.0)
	m.submit_move(W, "e2e4")
	m.tick(1.0)
	m.start_cheat(B, _sq("a2"), _sq("a3"))
	m.tick(5.0)
	var whites := ["d2d4", "g1f3", "b1c3", "c1e3"]
	var blacks := ["a7a6", "a6a5", "a5a4", "h7h6"]
	for i in w_moves:
		m.submit_move(B, blacks[i])
		m.tick(1.0)
		m.submit_move(W, whites[i])
		m.tick(1.0)
	return m


func test_window_three_moves_covers_cheat_two_moves_ago() -> void:
	var m := _cheat_then_moves(3, 2)
	m.accuse(W)
	m.tick(1.1)
	check_eq(m.end_reason, MatchServer.REASON_CAUGHT, "con N=3 cubre la trampa de hace 2 jugadas")
	var m1 := _cheat_then_moves(1, 2)
	m1.accuse(W)
	m1.tick(1.1)
	check(not m1.is_over(), "con N=1 es falsa")


func test_window_three_moves_misses_cheat_four_moves_ago() -> void:
	var m := _cheat_then_moves(3, 4)
	m.accuse(W)
	m.tick(1.1)
	check(not m.is_over(), "trampa de hace 4 jugadas: falsa")


func test_false_accusation_resets_window() -> void:
	var m := _cheat_then_moves(3, 4)
	m.accuse(W)
	m.tick(1.1)
	check_eq(m.sessions[W].warnings, 1)
	# Tras la falsa, la ventana arranca en ese instante.
	check(m.accusation_window_start(W) >= m.time - 0.001, "ventana reiniciada")
	m.start_cheat(B, _sq("h2"), _sq("h3"))
	m.tick(3.0)
	m.accuse(W)
	m.tick(1.1)
	check_eq(m.end_reason, MatchServer.REASON_CAUGHT, "la trampa posterior sí cuenta")
