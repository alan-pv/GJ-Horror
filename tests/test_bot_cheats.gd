extends TestCase

const W := ChessPiece.WHITE
const B := ChessPiece.BLACK


func _defs() -> Array:
	var defs: Array = []
	for id in ["nudge", "slide", "steal", "move_enemy"]:
		defs.append(load("res://data/cheats/%s.tres" % id))
	return defs


func _rng(seed_value: int = 5) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _personality(chance: float = 0.3) -> BotPersonality:
	var p := BotPersonality.new()
	p.cheat_chance = chance
	return p


func test_candidates_are_all_valid() -> void:
	var fens := [
		BoardState.START_FEN,
		"r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3",
		"4k3/8/8/8/8/8/4P3/R3K3 w - - 0 1",
		"r3k2r/ppp2ppp/2n5/3q4/3P4/2N2N2/PPP2PPP/R2QK2R b KQkq - 0 8",
	]
	var rng := _rng(11)
	var total := 0
	for fen in fens:
		for color in [W, B]:
			var b := BoardState.from_fen(fen)
			for c in CheatPlanner.candidates(b, color, _defs(), rng):
				total += 1
				var v := CheatRules.validate(b, color, c.def, c.from, c.to)
				check(v.ok, "candidata inválida: %s %d->%d" % [c.def.id, c.from, c.to])
				check(ChessPiece.type_of(b.squares[c.from]) != ChessPiece.KING, "tocó un rey")
	check(total > 50, "debería haber candidatas: %d" % total)


func test_plan_never_proposes_invalid_fuzz() -> void:
	var rng := _rng(21)
	for i in 40:
		# Posición aleatoria: partida de jugadas legales al azar.
		var b := BoardState.start_position()
		for k in rng.randi_range(0, 30):
			var moves := ChessRules.legal_moves(b)
			if moves.is_empty():
				break
			ChessRules.apply_move(b, moves[rng.randi() % moves.size()])
		for color in [W, B]:
			var plan := CheatPlanner.plan(b, color, _defs(), rng)
			if plan.is_empty():
				continue
			check(CheatRules.validate(b, color, plan.def, plan.from, plan.to).ok, "plan inválido en iteración %d" % i)


func test_kind_mix_and_rare_big_steals() -> void:
	# Posiciones de partidas al azar: mezcla de tipos, robos minoritarios y casi nunca dama/torre.
	var rng := _rng(9)
	var counts := {}
	var big := 0
	var total := 0
	for i in 40:
		var b := BoardState.start_position()
		for k in rng.randi_range(0, 30):
			var moves := ChessRules.legal_moves(b)
			if moves.is_empty():
				break
			ChessRules.apply_move(b, moves[rng.randi() % moves.size()])
		for color in [W, B]:
			var plan := CheatPlanner.plan(b, color, _defs(), rng, 0.4)
			if plan.is_empty():
				continue
			total += 1
			counts[plan.def.kind] = counts.get(plan.def.kind, 0) + 1
			if plan.def.kind == CheatDef.Kind.STEAL:
				var t := ChessPiece.type_of(b.squares[plan.from])
				if t == ChessPiece.QUEEN or t == ChessPiece.ROOK:
					big += 1
	check(total > 40, "hay planes: %d" % total)
	check(counts.size() >= 4, "salen los 4 tipos: %s" % str(counts))
	check(counts.get(CheatDef.Kind.STEAL, 0) < total * 0.35, "robos <35%%: %s de %d" % [str(counts), total])
	check(big < total * 0.08, "dama/torre muy raras: %d de %d" % [big, total])


func test_score_diminishing_gain_and_risk() -> void:
	var d_low := CheatPlanner.score(200.0, 1.0, 0.5) - CheatPlanner.score(100.0, 1.0, 0.5)
	var d_high := CheatPlanner.score(1000.0, 1.0, 0.5) - CheatPlanner.score(900.0, 1.0, 0.5)
	check(d_low > d_high * 3.0, "la ganancia rinde cada vez menos")
	check(CheatPlanner.score(900.0, 1.0, 0.5) - CheatPlanner.score(100.0, 1.0, 0.5) < 3.0, "ganancia acotada")
	check(CheatPlanner.score(300.0, 1.0, 0.9) < CheatPlanner.score(300.0, 1.0, 0.2), "más evidencia, menos puntaje")
	check(CheatPlanner.score(300.0, 3.0, 0.5) < CheatPlanner.score(300.0, 1.0, 0.5), "más duración, menos puntaje")
	check(CheatPlanner.score(300.0, 1.0, 0.9, 0.9) > CheatPlanner.score(300.0, 1.0, 0.9, 0.1), "el audaz castiga menos el riesgo")
	check(CheatPlanner.score(300.0, 1.0, 0.9, 0.5, 9.0) < CheatPlanner.score(300.0, 1.0, 0.9, 0.5, 1.0), "robar piezas grandes se nota")


func test_bold_steals_more_than_cautious() -> void:
	var b := BoardState.from_fen("r1bqkb1r/pppp1ppp/2n2n2/4p3/4P3/2N2N2/PPPP1PPP/R1BQKB1R w KQkq - 4 4")
	var rng := _rng(13)
	var bold := 0
	var careful := 0
	for i in 200:
		if CheatPlanner.plan(b, W, _defs(), rng, 1.0).def.kind == CheatDef.Kind.STEAL:
			bold += 1
		if CheatPlanner.plan(b, W, _defs(), rng, 0.0).def.kind == CheatDef.Kind.STEAL:
			careful += 1
	check(bold > careful, "audaz roba más: %d vs %d" % [bold, careful])


func test_blind_accusation_drops_with_warnings() -> void:
	var p0 := CheatPlanner.blind_accuse_probability(0.02, 0)
	var p1 := CheatPlanner.blind_accuse_probability(0.02, 1)
	var p2 := CheatPlanner.blind_accuse_probability(0.02, 2)
	check_eq(p0, 0.02, "sin advertencias, la base")
	check(p1 < p0 * 0.5, "con 1 advertencia baja mucho")
	check_eq(p2, 0.0, "con 2 no acusa a ciegas")


func test_event_cooldown_by_personality() -> void:
	var rng := _rng(3)
	for i in 50:
		var bold := CheatPlanner.event_cooldown(1.0, rng)
		var careful := CheatPlanner.event_cooldown(0.0, rng)
		check(bold >= 45.0 and careful >= 90.0, "esperas mínimas: %f %f" % [bold, careful])


func test_choice_is_stochastic() -> void:
	var b := BoardState.from_fen("r1bqkb1r/pppp1ppp/2n2n2/4p3/4P3/2N2N2/PPPP1PPP/R1BQKB1R w KQkq - 4 4")
	var rng := _rng(4)
	var seen := {}
	for i in 100:
		var plan := CheatPlanner.plan(b, W, _defs(), rng)
		seen["%d_%d" % [plan.from, plan.to]] = true
	check(seen.size() > 1, "no siempre elige la misma")


func test_attempt_probability() -> void:
	var even := BoardState.start_position()
	var p := _personality(0.3)
	check_eq(CheatPlanner.attempt_probability(even, W, p, 120.0, true), 0.0, "si lo miran, cero")
	var base := CheatPlanner.attempt_probability(even, W, p, 120.0, false)
	check(base > 0.0, "sin mirar hay probabilidad")
	# Blancas sin dama ni torres: pierden.
	var losing := BoardState.from_fen("4k3/pppppppp/8/8/8/8/PPP5/4K3 w - - 0 1")
	check(CheatPlanner.attempt_probability(losing, W, p, 120.0, false) > base, "perdiendo sube")
	check(CheatPlanner.attempt_probability(even, W, p, 10.0, false) > base, "poco reloj sube")
	check(CheatPlanner.attempt_probability(even, W, _personality(0.02), 120.0, false) < base, "el honesto intenta menos")
	check(CheatPlanner.attempt_probability(losing, W, _personality(1.0), 5.0, false) <= 0.5, "tope")


func test_abort_probability_by_nerves() -> void:
	var calm := BotPersonality.new()
	calm.abort_chance = 0.2
	var nervous := BotPersonality.new()
	nervous.abort_chance = 0.9
	check(CheatPlanner.abort_probability(nervous, 0.5) > CheatPlanner.abort_probability(calm, 0.5), "el nervioso aborta más")


func test_simulated_server_flow() -> void:
	var cfg := MatchConfig.new()
	cfg.beginner_help = false
	for d in _defs():
		cfg.cheats.append(d)
	var m := MatchServer.new(cfg, PlayerSession.new(1, "Blancas"), PlayerSession.new(2, "Negras"), BoardState.START_FEN, 3)
	m.start()
	var rng := _rng(2)
	var plan := CheatPlanner.plan(m.board, B, cfg.cheats, rng)
	check(not plan.is_empty(), "hay plan")
	var before := m.board.position_key()
	var res := m.start_cheat(B, plan.def.id, plan.from, plan.to)
	check(res.ok, "el servidor acepta el plan: " + str(res.reason))
	check(m.is_hand_busy(B), "mano ocupada")
	for i in int(res.duration / 0.1) + 5:
		m.tick(0.1)
	check(not m.is_hand_busy(B), "mano libre")
	check(m.board.position_key() != before or plan.def.kind == CheatDef.Kind.MOVE_ENEMY, "el tablero cambió")
	check_eq(m.cheat_log.size(), 1, "una trampa registrada")

	# Abortar a mitad: el tablero no cambia.
	var m2 := MatchServer.new(cfg, PlayerSession.new(1, "Blancas"), PlayerSession.new(2, "Negras"), BoardState.START_FEN, 3)
	m2.start()
	var plan2 := CheatPlanner.plan(m2.board, W, cfg.cheats, rng)
	var key2 := m2.board.position_key()
	check(m2.start_cheat(W, plan2.def.id, plan2.from, plan2.to).ok, "empieza")
	m2.tick(0.2)
	check(m2.abort_cheat(W), "aborta")
	for i in 40:
		m2.tick(0.1)
	check_eq(m2.board.position_key(), key2, "tablero intacto tras abortar")
