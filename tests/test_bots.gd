extends TestCase


func test_sample_respects_policy() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var policy := {"e2e4": 0.9, "a2a3": 0.1}
	var counts := {"e2e4": 0, "a2a3": 0}
	for i in 2000:
		counts[ChessBrain.sample(policy, 1.0, rng)] += 1
	check(counts["e2e4"] > 1650 and counts["e2e4"] < 1950, "≈90%: " + str(counts))
	check_eq(ChessBrain.sample(policy, 0.0, rng), "e2e4", "temperatura 0 = la más probable")


func test_fallback_strong_bot_takes_hanging_queen() -> void:
	var b := BoardState.from_fen("rnb1kbnr/pppp1ppp/8/4p2q/3P4/5N2/PPP1PPPP/RNBQKB1R w KQkq - 0 3")
	var policy := FallbackBrain.new().get_policy(b, 2000, 1500)
	check(policy.get("f3h4", 0.0) < 0.5, "Nh4 no captura nada")
	var b2 := BoardState.from_fen("rnb1kbnr/pppp1ppp/8/4q3/3P4/5N2/PPP1PPPP/RNBQKB1R w KQkq - 0 3")
	var p2 := FallbackBrain.new().get_policy(b2, 2000, 1500)
	var takes: float = p2.get("d4e5", 0.0) + p2.get("f3e5", 0.0)
	check(takes > 0.8, "un 2000 captura la dama colgada (dxe5 o Nxe5): %f" % takes)


func test_fallback_weak_bot_is_more_random() -> void:
	var b2 := BoardState.from_fen("rnb1kbnr/pppp1ppp/8/4q3/3P4/5N2/PPP1PPPP/RNBQKB1R w KQkq - 0 3")
	var strong := FallbackBrain.new().get_policy(b2, 2000, 1500)
	var weak := FallbackBrain.new().get_policy(b2, 700, 1500)
	check(weak["d4e5"] + weak["f3e5"] < strong["d4e5"] + strong["f3e5"], "el débil reparte más la probabilidad")


func test_think_time_bounds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var b := BoardState.from_fen("r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 10")
	var total := 0.0
	for i in 200:
		var t := BotController.think_time(b, 150.0, rng)
		check(t >= 0.3 and t <= 12.0, "fuera de rango: %f" % t)
		total += t
	var avg := total / 200.0
	check(avg > 1.5 and avg < 6.0, "promedio razonable para blitz de 3 min: %f" % avg)
	var hurry := 0.0
	for i in 200:
		hurry += BotController.think_time(b, 8.0, rng)
	check(hurry / 200.0 < 0.6, "en apuros juega rápido")
