extends TestCase


func _white_wins(m: TournamentManager, g: TournamentGame, w_left: float = 50.0, b_left: float = 0.0) -> void:
	var t: PackedFloat64Array = [w_left, b_left]
	m.report_result(g, ChessPiece.WHITE, "prueba", t)


## Gana siempre el jugador de id más bajo (resultado determinista).
func _lowest_wins(m: TournamentManager) -> void:
	for g in m.pending_games():
		var t: PackedFloat64Array = [10.0, 10.0]
		m.report_result(g, ChessPiece.WHITE if g.white < g.black else ChessPiece.BLACK, "prueba", t)


func test_pairing_16() -> void:
	var m := TournamentManager.new(16, 7)
	var games := m.start_round()
	check_eq(games.size(), 8, "8 partidas")
	check(m.byes.is_empty(), "sin descansos")
	var seen := {}
	for g in games:
		check(not seen.has(g.white) and not seen.has(g.black), "nadie repetido")
		check(g.white != g.black)
		seen[g.white] = true
		seen[g.black] = true
	check_eq(seen.size(), 16, "los 16 juegan")
	# El humano está en la mesa principal; las demás, en mesas distintas.
	check_eq(m.game_of(0).table, TournamentGame.TABLE_MAIN, "humano en la mesa principal")
	var tables := {}
	for g in games:
		check(not tables.has(g.table), "mesas distintas")
		tables[g.table] = true
	check_eq(m.round_label(), "Ronda 1")


func test_colors_are_random() -> void:
	var white_count := 0
	for s in 30:
		var m := TournamentManager.new(2, s)
		m.start_round()
		if m.game_of(0).white == 0:
			white_count += 1
	check(white_count > 5 and white_count < 25, "colores mezclados: %d" % white_count)


func test_odd_players_bye() -> void:
	var m := TournamentManager.new(5, 3)
	var games := m.start_round()
	check_eq(games.size(), 2, "2 partidas")
	check_eq(m.byes.size(), 1, "un descanso")
	var bye: int = m.byes[0]
	check(m.game_of(bye) == null, "el que descansa no juega")
	_lowest_wins(m)
	check(m.round_complete())
	var res := m.finish_round()
	check_eq(res.eliminated.size(), 2, "dos eliminados")
	check_eq(m.alive.size(), 3, "pasan 3 (2 ganadores + descanso)")
	check(m.is_alive(bye), "el descanso sigue vivo")
	# Ronda 2 con 3 jugadores: otro descanso, a alguien distinto.
	m.start_round()
	check_eq(m.byes.size(), 1)
	check(m.byes[0] != bye, "descansa otro jugador")
	_lowest_wins(m)
	m.finish_round()
	check_eq(m.alive.size(), 2, "quedan 2")
	m.start_round()
	check(m.is_final, "ahora es la final")


func test_bye_for_human_uses_main_table() -> void:
	# Con semillas distintas el humano descansa alguna vez; entonces ocupa la mesa principal.
	var found := false
	for s in 40:
		var m := TournamentManager.new(5, s)
		m.start_round()
		if m.byes.has(0):
			found = true
			check_eq(m.bye_tables[0], TournamentGame.TABLE_MAIN, "descanso del humano en la mesa principal")
			check(m.game_of(0) == null)
			for g in m.games:
				check(g.table != TournamentGame.TABLE_MAIN, "ninguna partida en la principal")
			break
	check(found, "el humano descansó en alguna semilla")


func test_round_progression_16() -> void:
	var m := TournamentManager.new(16, 11)
	var sizes: Array[int] = []
	while not m.is_finished():
		var games := m.start_round()
		sizes.append(m.alive.size())
		check(not m.round_complete())
		_lowest_wins(m)
		check(m.round_complete())
		var res := m.finish_round()
		if res.final_continues:
			check_eq(m.alive.size(), 2)
	check_eq(sizes, [16, 8, 4, 2, 2] as Array[int], "16, 8, 4, final de 2 partidas")
	check_eq(m.champion_id, 0, "gana el id más bajo")
	check_eq(m.alive.size(), 1)
	check_eq(m.round_no, 4, "4 rondas con la final")
	check_eq(TournamentManager.rounds_for(16), 4)
	check_eq(TournamentManager.rounds_for(5), 3)


func test_next_round_waits_for_all_games() -> void:
	var m := TournamentManager.new(8, 2)
	var games := m.start_round()
	for i in games.size() - 1:
		_white_wins(m, games[i])
		check(not m.round_complete(), "faltan partidas")
	_white_wins(m, games[games.size() - 1])
	check(m.round_complete())


func test_final_two_games_inverted_colors() -> void:
	var m := TournamentManager.new(2, 5)
	var g1: TournamentGame = m.start_round()[0]
	check(m.is_final)
	check_eq(g1.game_no, 1)
	_white_wins(m, g1)
	var r1 := m.finish_round()
	check(r1.final_continues, "la final sigue")
	check_eq(m.champion_id, -1)
	var g2: TournamentGame = m.start_round()[0]
	check_eq(g2.game_no, 2)
	check_eq(g2.white, g1.black, "colores invertidos")
	check_eq(g2.black, g1.white, "colores invertidos")
	check_eq(m.round_no, 1, "misma ronda")


func test_final_2_0_no_tiebreak() -> void:
	var m := TournamentManager.new(2, 5)
	var g1: TournamentGame = m.start_round()[0]
	var a := g1.white
	_white_wins(m, g1, 1.0, 0.0)
	m.finish_round()
	var g2: TournamentGame = m.start_round()[0]
	# En la segunda partida el que era negro juega con blancas; gana el negro (= a).
	var t: PackedFloat64Array = [100.0, 1.0]
	m.report_result(g2, ChessPiece.BLACK, "prueba", t)
	var res := m.finish_round()
	check_eq(res.champion, a, "2-0 para a aunque tuviera menos tiempo")
	check(m.is_finished())


func test_final_tiebreak_by_remaining_time() -> void:
	for flip in 2:
		var m := TournamentManager.new(2, 9 + flip)
		var g1: TournamentGame = m.start_round()[0]
		var p1 := g1.white
		var p2 := g1.black
		# Partida 1: gana p1 (blancas) con 10 s sobrantes; p2 queda con 0.
		var t1: PackedFloat64Array = [10.0, 0.0]
		m.report_result(g1, ChessPiece.WHITE, "prueba", t1)
		m.finish_round()
		var g2: TournamentGame = m.start_round()[0]
		# Partida 2 (p2 con blancas): gana p2 con 'flip ? 30 : 5' s; p1 con 0.
		var left := 30.0 if flip == 1 else 5.0
		var t2: PackedFloat64Array = [left, 0.0]
		m.report_result(g2, ChessPiece.WHITE, "prueba", t2)
		var res := m.finish_round()
		# p1: 10 + 0; p2: 0 + left.
		var expected := p2 if left > 10.0 else p1
		check_eq(res.champion, expected, "desempate por tiempo (flip=%d)" % flip)
		check_eq(m.champion_id, expected)
		check(m.is_finished())
		var s := m.final_summary()
		check_eq(s.wins[p1], 1)
		check_eq(s.wins[p2], 1)


func test_warnings_persist_and_reset() -> void:
	var m := TournamentManager.new(4, 1)
	m.sessions[0].warnings = 2
	m.start_round()
	check_eq(m.sessions[0].warnings, 2, "las advertencias sobreviven a la ronda")
	_lowest_wins(m)
	m.finish_round()
	m.start_round()
	check_eq(m.sessions[0].warnings, 2, "y a la siguiente")
	# Un servidor de partida usa la misma sesión: la advertencia cuenta ahí.
	var g := m.game_of(0)
	var cfg := MatchConfig.new()
	var s := MatchServer.new(cfg, m.sessions[g.white], m.sessions[g.black], BoardState.START_FEN, 1)
	check_eq(s.sessions[g.color_of(0)].warnings, 2)
	m.new_tournament()
	check_eq(m.sessions[0].warnings, 0, "torneo nuevo: advertencias a cero")
	check_eq(m.alive.size(), 4)
	check_eq(m.round_no, 0)
	check_eq(m.champion_id, -1)


func test_human_eliminated_then_new_tournament() -> void:
	var m := TournamentManager.new(8, 4)
	m.sessions[0].warnings = 1
	var games := m.start_round()
	for g in games:
		var t: PackedFloat64Array = [10.0, 10.0]
		# El humano pierde su partida.
		var wc := ChessPiece.opposite(g.color_of(0)) if g.involves(0) else ChessPiece.WHITE
		m.report_result(g, wc, "prueba", t)
	m.finish_round()
	check(not m.is_alive(0), "el humano fue eliminado")
	check_eq(m.eliminated_log.size(), 4)
	m.new_tournament()
	check(m.is_alive(0), "vuelve a la cola: torneo nuevo")
	check_eq(m.alive.size(), 8)
	check_eq(m.sessions[0].warnings, 0)
	check_eq(m.eliminated_log.size(), 0)
	check_eq(m.start_round().size(), 4, "empieza otra vez desde la ronda 1")
	check_eq(m.round_no, 1)


func test_full_simulated_tournaments_have_one_champion() -> void:
	for n in [2, 3, 5, 7, 9, 16, 17, 33]:
		var m := TournamentManager.new(n, n * 13)
		var guard := 0
		while not m.is_finished() and guard < 20:
			guard += 1
			m.start_round()
			var played := 0
			for g in m.games:
				played += 2
			check_eq(played + m.byes.size(), m.alive.size(), "todos juegan o descansan (n=%d)" % n)
			m.simulate_round()
			m.finish_round()
		check(m.is_finished(), "termina (n=%d)" % n)
		check_eq(m.alive.size(), 1, "un solo campeón (n=%d)" % n)
		check_eq(m.alive[0], m.champion_id)
		check_eq(m.eliminated_log.size(), n - 1, "n-1 eliminados (n=%d)" % n)
		check_eq(m.round_no, TournamentManager.rounds_for(n), "rondas (n=%d)" % n)


func test_background_match_runs_to_a_result() -> void:
	var m := TournamentManager.new(4, 21)
	var games := m.start_round()
	var g := games[0]
	var bg := BackgroundMatch.new(g, m.sessions[g.white], m.sessions[g.black], m.elo[g.white], m.elo[g.black], 5, 20.0)
	var got := []
	bg.finished.connect(func(done: TournamentGame) -> void: got.append(done))
	var guard := 0
	while not bg.is_over() and guard < 4000:
		bg.tick(0.5)
		guard += 1
	check(bg.is_over(), "la partida de fondo termina")
	check_eq(got.size(), 1, "avisa una vez")
	check(bg.server.winner >= 0)
	check(bg.moves_made > 0, "hubo jugadas")


func test_background_policy_is_legal_and_prefers_free_captures() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# Blancas pueden capturar una dama negra con un peón sin riesgo.
	var b := BoardState.from_fen("4k3/8/8/3q4/4P3/8/8/4K3 w - - 0 1")
	var hits := 0
	for i in 40:
		if BackgroundMatch.choose_move(b, 1600, rng) == "e4d5":
			hits += 1
	check(hits >= 35, "casi siempre captura la dama: %d/40" % hits)
	var start := BoardState.start_position()
	for i in 20:
		var uci := BackgroundMatch.choose_move(start, 1000, rng)
		check(ChessRules.find_legal(start, ChessMove.from_uci(uci)) != null, "jugada legal " + uci)
