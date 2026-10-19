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
	var policy := FallbackBrain.new().get_policy_sync(b, 2000, 1500)
	check(policy.get("f3h4", 0.0) < 0.5, "Nh4 no captura nada")
	var b2 := BoardState.from_fen("rnb1kbnr/pppp1ppp/8/4q3/3P4/5N2/PPP1PPPP/RNBQKB1R w KQkq - 0 3")
	var p2 := FallbackBrain.new().get_policy_sync(b2, 2000, 1500)
	var takes: float = p2.get("d4e5", 0.0) + p2.get("f3e5", 0.0)
	check(takes > 0.8, "un 2000 captura la dama colgada (dxe5 o Nxe5): %f" % takes)


func test_fallback_weak_bot_is_more_random() -> void:
	var b2 := BoardState.from_fen("rnb1kbnr/pppp1ppp/8/4q3/3P4/5N2/PPP1PPPP/RNBQKB1R w KQkq - 0 3")
	var strong := FallbackBrain.new().get_policy_sync(b2, 2000, 1500)
	var weak := FallbackBrain.new().get_policy_sync(b2, 700, 1500)
	check(weak["d4e5"] + weak["f3e5"] < strong["d4e5"] + strong["f3e5"], "el débil reparte más la probabilidad")


const MID_FEN := "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 10"


func _avg_think(board: BoardState, remaining: float, policy: Dictionary, seed_value: int = 1) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var total := 0.0
	for i in 300:
		total += BotController.think_time(board, remaining, policy, rng)
	return total / 300.0


func _flat_policy(n: int) -> Dictionary:
	var p := {}
	for i in n:
		p["m%d" % i] = 1.0 / n
	return p


func test_think_time_bounds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var b := BoardState.from_fen(MID_FEN)
	var flat := _flat_policy(20)
	for rem in [150.0, 8.0, 1.0, 400.0]:
		for i in 200:
			var t := BotController.think_time(b, rem, flat, rng)
			check(t > 0.0 and t <= minf(rem * 0.15, 15.0) + 0.001, "fuera de rango: %f con %f s" % [t, rem])
			check(t >= minf(0.3, rem * 0.15) - 0.001, "por debajo del mínimo: %f" % t)
	var avg := _avg_think(b, 150.0, flat)
	check(avg > 1.5 and avg < 10.0, "promedio razonable para blitz de 3 min: %f" % avg)
	check(_avg_think(b, 8.0, flat) < 0.6, "en apuros juega rápido")


func test_think_time_obvious_move_is_faster() -> void:
	var b := BoardState.from_fen(MID_FEN)
	var obvious := {"a": 0.95, "b": 0.03, "c": 0.02}
	for i in 17:
		obvious["x%d" % i] = 0.0
	check(BotController.policy_difficulty(obvious) < BotController.policy_difficulty(_flat_policy(20)), "dificultad")
	check(_avg_think(b, 150.0, obvious) < _avg_think(b, 150.0, _flat_policy(20)) * 0.5, "jugada obvia piensa mucho menos")


func test_think_time_depends_on_clock() -> void:
	var b := BoardState.from_fen(MID_FEN)
	var flat := _flat_policy(20)
	check(_avg_think(b, 10.0, flat) < _avg_think(b, 180.0, flat), "con 10 s piensa menos que con 180 s")


func test_think_time_opening_is_fast() -> void:
	var flat := _flat_policy(20)
	var opening := BoardState.start_position()
	check(_avg_think(opening, 180.0, flat) < _avg_think(BoardState.from_fen(MID_FEN), 180.0, flat), "la apertura es rápida")
