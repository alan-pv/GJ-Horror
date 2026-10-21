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
	# 8 partidas: mesas 1..8 y el humano en la de número más alto (índice 7); todas distintas.
	check_eq(m.game_of(0).table, 7, "humano en la mesa 8")
	check_eq(m.human_table(), 7)
	var tables := {}
	for g in games:
		check(not tables.has(g.table), "mesas distintas")
		tables[g.table] = true
	check_eq(m.round_label(), "Round 1")


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


func test_bye_for_human_uses_highest_table() -> void:
	# Con semillas distintas el humano descansa alguna vez; entonces ocupa la mesa de número más alto.
	var found := false
	for s in 40:
		var m := TournamentManager.new(5, s)
		m.start_round()
		if m.byes.has(0):
			found = true
			# 2 partidas + 1 descanso = 3 mesas: la 3 (índice 2) es del humano.
			check_eq(m.bye_tables[0], 2, "descanso del humano en la mesa 3")
			check_eq(m.human_table(), 2)
			check(m.game_of(0) == null)
			var used := {}
			for g in m.games:
				check(g.table != 2, "ninguna partida en la del humano")
				used[g.table] = true
			check_eq(used.keys().size(), 2, "partidas en mesas distintas")
			check(used.has(0) and used.has(1), "las demás ocupan las mesas 1 y 2")
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


func test_tournament_32_human_climbs_to_table_1() -> void:
	var m := TournamentManager.new(32, 5)
	check_eq(m.player_count, 32)
	check_eq(TournamentManager.rounds_for(32), 5)
	var sizes: Array[int] = []
	var human_tables: Array[int] = []
	while not m.is_finished():
		var games := m.start_round()
		sizes.append(m.alive.size())
		human_tables.append(m.human_table())
		# Las partidas ocupan exactamente las mesas 1..N (N = partidas + descansos), sin repetir.
		var used := {}
		for g in games:
			check(not used.has(g.table), "mesa repetida en la ronda %d" % m.round_no)
			used[g.table] = true
		for id in m.byes:
			used[m.bye_tables[id]] = true
		check_eq(used.size(), games.size() + m.byes.size(), "mesas distintas")
		for t in used:
			check(t >= 0 and t < games.size() + m.byes.size(), "mesa %d dentro de 1..N (ronda %d)" % [t, m.round_no])
		check_eq(m.human_table(), games.size() + m.byes.size() - 1, "el humano en la N")
		_lowest_wins(m)
		m.finish_round()
	check_eq(sizes, [32, 16, 8, 4, 2, 2] as Array[int], "32, 16, 8, 4, final de 2 partidas")
	# Mesas 16, 8, 4, 2 y 1 (índices 15, 7, 3, 1, 0); la segunda partida de la final, en la misma.
	check_eq(human_tables, [15, 7, 3, 1, 0, 0] as Array[int], "el humano sube a la mesa 1")
	check_eq(m.round_no, 5, "5 rondas con la final")


func test_human_table_small_and_odd_tournaments() -> void:
	# 6 jugadores: 3 partidas -> 2 -> 1 (con descanso, 3 jugadores: 1 partida + 1 descanso).
	var m := TournamentManager.new(6, 9)
	var tables: Array[int] = []
	while not m.is_finished():
		m.start_round()
		var total := m.games.size() + m.byes.size()
		tables.append(m.human_table())
		check_eq(m.human_table(), total - 1, "humano en la N")
		_lowest_wins(m)
		m.finish_round()
	check_eq(tables[0], 2, "3 partidas: mesa 3")
	check(tables[tables.size() - 1] == 0, "la final en la mesa 1")
	# Más jugadores que mesas: el humano nunca pasa de la mesa 16 y las que no caben quedan sin mesa.
	var big := TournamentManager.new(40, 2)
	big.start_round()
	check_eq(big.human_table(), 15, "tope en la mesa 16")
	var none := 0
	for g in big.games:
		if g.table == TournamentGame.TABLE_NONE:
			none += 1
		else:
			check(g.table >= 0 and g.table <= 15)
	check_eq(none, 20 - 16, "20 partidas, 16 mesas")
	# Humano eliminado: sin mesa de humano; las demás siguen en 1..N.
	var m2 := TournamentManager.new(4, 4)
	m2.start_round()
	for g in m2.pending_games():
		var t: PackedFloat64Array = [10.0, 10.0]
		m2.report_result(g, g.color_of(0) ^ 1 if g.involves(0) else ChessPiece.WHITE, "prueba", t)
	m2.finish_round()
	check(not m2.is_alive(0), "el humano perdió")
	m2.start_round()
	check_eq(m2.human_table(), TournamentGame.TABLE_NONE, "sin mesa")
	check_eq(m2.games[0].table, 0, "la final en la mesa 1")


func test_background_ends_are_spread_over_the_round() -> void:
	var m := TournamentManager.new(32, 17)
	var games := m.start_round()
	var ends: Array[float] = []
	var sum := 0.0
	for g in games:
		if g.involves(0):
			continue
		var bg := BackgroundMatch.new(g, m.sessions[g.white], m.sessions[g.black], m.elo[g.white], m.elo[g.black], g.white * 31 + 7)
		ends.append(bg.planned_end)
		sum += bg.planned_end
	check_eq(ends.size(), 15)
	var mean := sum / ends.size()
	var sq := 0.0
	var late := 0
	for e in ends:
		sq += (e - mean) * (e - mean)
		check(e >= BackgroundMatch.END_MIN and e <= BackgroundMatch.END_MAX, "dentro de la ventana")
		if e > BackgroundMatch.END_MAX - 10.0:
			late += 1
	var sd := sqrt(sq / ends.size())
	check(sd > 30.0, "dispersión de los fines: %.1f" % sd)
	check(late < ends.size(), "no todas en los últimos 10 s")


func test_background_resolves_at_planned_end() -> void:
	var m := TournamentManager.new(4, 21)
	var g := m.start_round()[0]
	var bg := BackgroundMatch.new(g, m.sessions[g.white], m.sessions[g.black], m.elo[g.white], m.elo[g.black], 9)
	var guard := 0
	while not bg.is_over() and guard < 3000:
		bg.tick(0.5)
		guard += 1
	check(bg.is_over(), "termina")
	check(bg.server.time <= bg.planned_end + 1.0, "no más tarde de lo previsto")
	g.winner_color = bg.server.winner
	check_eq(g.loser_seat(), ChessPiece.opposite(bg.server.winner), "asiento del perdedor")
	check_eq(bg.server.config.increment_seconds, 2.0, "reloj 3+2")
	check(bg.server.scoresheet(0).is_empty(), "las mesas de fondo no llevan planilla")


func test_rival_elo_for_round() -> void:
	var m := TournamentManager.new(32, 3)
	var got: Array[int] = []
	for r in range(1, 6):
		got.append(m.rival_elo_for_round(r))
	check_eq(got, [1000, 1125, 1250, 1375, 1500] as Array[int], "32 jugadores: 5 rondas")
	var m2 := TournamentManager.new(2, 3)
	check_eq(m2.rival_elo_for_round(1), 1500, "solo la final")
	check_eq(m.rival_elo_for_round(99), 1500, "techo")


func test_human_rival_gets_round_elo() -> void:
	var m := TournamentManager.new(16, 11)
	for r in range(1, 5):
		m.start_round()
		var g := m.game_of(m.human_id)
		check(g != null)
		check_eq(m.elo[g.opponent_of(m.human_id)], m.rival_elo_for_round(m.round_no), "ronda %d" % r)
		for pg in m.pending_games():
			var t: PackedFloat64Array = [10.0, 10.0]
			m.report_result(pg, ChessPiece.WHITE if pg.white == m.human_id or (pg.black != m.human_id and pg.white < pg.black) else ChessPiece.BLACK, "prueba", t)
		m.finish_round()
		if m.is_finished():
			break


## Victorias de cada color en `n` partidas de fondo con Elo iguales y semillas fijas.
## `natural` = sin fin previsto (llegan a mate, ahogado, material, 50 jugadas...).
func _bg_color_wins(n: int, natural: bool) -> Array[int]:
	var wins: Array[int] = [0, 0]
	for i in n:
		var m := TournamentManager.new(4, 100 + i)
		var g := m.start_round()[0]
		var bg := BackgroundMatch.new(g, m.sessions[g.white], m.sessions[g.black], 1200, 1200, 1000 + i * 7)
		if natural:
			bg.planned_end = 1.0e9
		var guard := 0
		while not bg.is_over() and guard < 3000:
			bg.tick(1.0)
			guard += 1
		check(bg.is_over(), "la partida de fondo termina")
		wins[bg.server.winner] += 1
		check(not BackgroundMatch.is_draw_reason(bg.server.end_reason), "sin tablas a favor de las negras")
	return wins


func test_background_no_color_bias_planned_end() -> void:
	var w := _bg_color_wins(60, false)
	check(w[0] >= 21 and w[0] <= 39, "blancas ganan %d/60 con Elo iguales" % w[0])


func test_background_no_color_bias_natural_endings() -> void:
	# Antes las tablas (ahogado, 50 jugadas...) iban todas a las negras: ~5/40 blancas.
	var w := _bg_color_wins(30, true)
	check(w[0] >= 11 and w[0] <= 19, "blancas ganan %d/30 con Elo iguales" % w[0])
