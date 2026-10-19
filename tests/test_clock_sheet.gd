extends TestCase

const W := ChessPiece.WHITE
const B := ChessPiece.BLACK


func _make(press: bool, fen: String = BoardState.START_FEN) -> MatchServer:
	var cfg := MatchConfig.new()
	cfg.beginner_help = false
	cfg.arbiter_delay = 1.0
	cfg.require_clock_press = press
	for id in ["nudge", "slide", "steal", "move_enemy"]:
		cfg.cheats.append(load("res://data/cheats/%s.tres" % id))
	var m := MatchServer.new(cfg, PlayerSession.new(1, "White"), PlayerSession.new(2, "Black", true), fen, 1)
	m.start()
	return m


func _san(fen: String, uci: String) -> String:
	return San.of(BoardState.from_fen(fen), ChessMove.from_uci(uci))


func _sq(n: String) -> int:
	return ChessPiece.square_from_name(n)


func test_increment() -> void:
	var c := ChessClock.new(180.0, 180.0, 2.0)
	c.start(W)
	c.tick(5.0)
	c.press(W)
	check_eq(c.remaining[W], 177.0, "5 s gastados +2")
	check_eq(c.running, B)
	var m := _make(false)
	m.tick(3.0)
	m.submit_move(W, "e2e4")
	check_eq(m.clock.remaining[W], 179.0, "partida 3+2")


func test_turn_passes_on_press() -> void:
	var m := _make(true)
	m.tick(3.0)
	var moves := []
	m.move_made.connect(func(_c: int, u: String, _i: Dictionary) -> void: moves.append(u))
	var pressed := []
	m.clock_pressed.connect(func(c: int) -> void: pressed.append(c))
	check(m.submit_move(W, "e2e4").ok)
	check_eq(moves, ["e2e4"], "move_made se emite igual")
	check(m.awaiting_press(W))
	check_eq(m.clock.running, W, "el reloj de quien movió sigue corriendo")
	m.tick(2.0)
	check_eq(m.clock.remaining[W], 175.0)
	var r := m.submit_move(B, "e7e5")
	check(not r.ok, "el rival no mueve antes de la pulsación")
	check_eq(r.reason, "opponent has not pressed the clock")
	check(not m.press_clock(B).ok, "el rival no tiene pulsación pendiente")
	check(m.press_clock(W).ok)
	check_eq(pressed, [W])
	check_eq(m.clock.running, B)
	check_eq(m.clock.remaining[W], 177.0, "incremento al pulsar")
	check(not m.press_clock(W).ok, "ya no hay pulsación pendiente")
	check(m.submit_move(B, "e7e5").ok)


func test_press_clock_invalid_without_pending() -> void:
	var m := _make(true)
	var r := m.press_clock(W)
	check(not r.ok and r.reason != "")


func test_flag_before_press_loses() -> void:
	var m := _make(true)
	m.submit_move(W, "e2e4")
	m.tick(181.0)
	check_eq(m.winner, B, "blancas pierden por tiempo sin pulsar")
	check_eq(m.end_reason, MatchServer.REASON_TIMEOUT)


func test_mate_without_press() -> void:
	var m := _make(true)
	for u in ["f2f3", "e7e5", "g2g4", "d8h4"]:
		var c := m.board.side_to_move
		check(m.submit_move(c, u).ok, u)
		if not m.is_over():
			m.press_clock(c)
	check_eq(m.winner, B)
	check_eq(m.end_reason, MatchServer.REASON_CHECKMATE)
	check_eq(m.scoresheet(B)[1], "Qh4#", "el mate queda anotado")


func test_cheats_allowed_while_press_pending() -> void:
	var m := _make(true)
	m.submit_move(W, "e2e4")
	check(m.start_cheat(B, &"nudge", _sq("a7"), _sq("a6")).ok, "trampa del rival permitida")


func test_accusation_window_starts_at_submit() -> void:
	var m := _make(true)
	m.tick(1.0)
	m.submit_move(W, "e2e4")
	m.tick(1.0)
	m.press_clock(W)
	m.start_cheat(B, &"nudge", _sq("a7"), _sq("a6"))
	m.tick(1.0)
	check(m.accuse(W).ok)
	m.tick(2.0)
	check_eq(m.end_reason, MatchServer.REASON_CAUGHT)


func test_scoresheet_records_on_press_and_skips_cheats() -> void:
	var m := _make(true)
	var entries := []
	m.sheet_entry.connect(func(c: int, n: int, s: String) -> void: entries.append([c, n, s]))
	m.submit_move(W, "e2e4")
	check(m.scoresheet(W).is_empty(), "aún no se pulsó")
	m.press_clock(W)
	m.start_cheat(B, &"nudge", _sq("a7"), _sq("a6"))
	m.tick(10.0)
	m.submit_move(B, "e7e5")
	m.press_clock(B)
	check_eq(m.scoresheet(W), PackedStringArray(["e4"]))
	check_eq(m.scoresheet(B), PackedStringArray(["e5"]), "la trampa no se anota")
	check_eq(entries, [[W, 1, "e4"], [B, 1, "e5"]])
	# Sin pulsación obligatoria se anota al mover.
	var m2 := _make(false)
	m2.submit_move(W, "g1f3")
	check_eq(m2.scoresheet(W), PackedStringArray(["Nf3"]))


func test_san() -> void:
	check_eq(_san(BoardState.START_FEN, "e2e4"), "e4")
	check_eq(_san(BoardState.START_FEN, "g1f3"), "Nf3")
	# Dos caballos pueden ir a d6: desambiguación por columna.
	check_eq(_san("7k/8/8/1N3N2/8/8/8/4K3 w - - 0 1", "b5d6"), "Nbd6")
	# Dos torres en la misma columna: por fila.
	check_eq(_san("4k3/R7/8/8/8/8/R7/4K3 w - - 0 1", "a2a4"), "R2a4")
	# Captura de peón y de pieza.
	check_eq(_san("4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1", "e4d5"), "exd5")
	check_eq(_san("4k3/8/8/3p4/8/2N5/8/4K3 w - - 0 1", "c3d5"), "Nxd5")
	# Enroques.
	check_eq(_san("4k3/8/8/8/8/8/8/4K2R w K - 0 1", "e1g1"), "O-O")
	check_eq(_san("4k3/8/8/8/8/8/8/R3K3 w Q - 0 1", "e1c1"), "O-O-O")
	# Coronación, con y sin jaque.
	check_eq(_san("8/4P3/8/8/8/8/8/k3K3 w - - 0 1", "e7e8q"), "e8=Q")
	check_eq(_san("8/P7/8/8/8/8/8/k3K3 w - - 0 1", "a7a8n"), "a8=N")
	check_eq(_san("k7/4P3/8/8/8/8/8/4K3 w - - 0 1", "e7e8q"), "e8=Q+")
	# Jaque y mate.
	check_eq(_san("6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1", "a1a8"), "Ra8#")
	check_eq(_san("4k3/8/8/8/8/8/8/4KR2 w - - 0 1", "f1f8"), "Rf8+")


func test_san_en_passant() -> void:
	check_eq(_san("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", "e5d6"), "exd6")


func test_press_clock_rejected_while_hand_busy() -> void:
	var m := _make(true)
	check(m.submit_move(W, "e2e4").ok)
	var r := m.start_cheat(W, &"nudge", _sq("h2"), _sq("h3"))
	check(r.ok, "trampa con pulsación pendiente: " + str(r))
	var p := m.press_clock(W)
	check(not p.ok, "no se pulsa con la mano en una trampa")
	check_eq(p.reason, "your hand is busy")
	check(m.awaiting_press(W), "la pulsación sigue pendiente")
	m.tick(r.duration + 0.5)
	check(not m.is_hand_busy(W), "trampa terminada")
	check(m.press_clock(W).ok, "ahora sí")
	check_eq(m.clock.running, B)


func test_scoresheet_view_writes_entries() -> void:
	var v := ScoresheetView.new()
	v.setup(W)
	check(not v.has_pending(W))
	v.add_entry(W, 1, "e4")
	v.add_entry(W, 2, "Nf3")
	check(v.has_pending(W))
	v.reveal_next(W, 0.0)
	check_eq(v.line_text(W, 0), "1. e4")
	check_eq(v.written_count(W), 1)
	v.reveal_next(W, 0.0)
	check_eq(v.line_text(W, 1), "2. Nf3")
	check(not v.has_pending(W))
	check_eq(v.line_text(B, 0), "", "la hoja rival sigue en blanco")
	v.free()
