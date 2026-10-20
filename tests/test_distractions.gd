extends TestCase
## Distracciones: probabilidades por evento, descartados, retardo y duración, y que el bot que
## voltea deja de mirar el tablero para el servidor.

const EXPECTED := {
	&"gunshot": 0.95, &"accusation": 0.8, &"blackout": 0.8, &"arbiter_pass": 0.45,
	&"plea": 0.45, &"piece_drop": 0.15, &"flag": 0.15,
}


func _rng(seed_value: int = 3) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func test_table_probabilities() -> void:
	for k in EXPECTED:
		check_eq(Distraction.chance_of(k), EXPECTED[k], "probabilidad base de " + String(k))


func test_ignored_never_turn() -> void:
	var r := _rng()
	for k in Distraction.IGNORED:
		check_eq(Distraction.chance_of(k), 0.0, "descartado: " + String(k))
		for i in 200:
			check(not Distraction.plan(k, -1.0, 1.45, r).turn, "no voltea: " + String(k))


func test_frequency_matches_chance() -> void:
	var r := _rng(11)
	for k in [&"gunshot", &"arbiter_pass", &"piece_drop"]:
		var n := 0
		for i in 4000:
			if Distraction.plan(k, -1.0, 1.0, r).turn:
				n += 1
		check(absf(float(n) / 4000.0 - EXPECTED[k]) < 0.03, "frecuencia de " + String(k))


func test_personality_factor_scales_and_averages_one() -> void:
	var sum := 0.0
	for id in ["honesto", "paranoico", "tramposo_nervioso"]:
		var p := load("res://data/personalities/%s.tres" % id) as BotPersonality
		sum += p.turn_factor()
	check(absf(sum / 3.0 - 1.0) < 0.1, "media del factor ~1")
	check_eq(Distraction.turn_probability(0.95, 1.45), 1.0, "acotada a 1")
	check(Distraction.turn_probability(0.45, 0.55) < Distraction.turn_probability(0.45, 1.45), "más factor, más probable")


func test_delay_and_duration_in_range() -> void:
	var r := _rng(5)
	for k in EXPECTED:
		var spec := Distraction.spec(k)
		for i in 100:
			var plan := Distraction.plan(k, 1.0, 1.0, r)
			check(plan.delay >= 0.15 and plan.delay <= 0.45, "retardo 0,15-0,45: " + String(k))
			check(plan.seconds >= spec.look.x and plan.seconds <= spec.look.y, "duración en rango: " + String(k))
	var shot := Distraction.look_seconds(&"gunshot", r)
	check(shot >= 1.5 and shot <= 3.0, "disparo 1,5-3 s")
	var glance := Distraction.look_seconds(&"arbiter_pass", r)
	check(glance >= 0.4 and glance <= 0.9, "de reojo 0,4-0,9 s")
	check(Distraction.reaction_delay(&"gunshot", r) < Distraction.reaction_delay(&"piece_drop", _rng(1)) + 0.07, "más fuerte, más rápido")


func test_startle_only_strong() -> void:
	check(Distraction.startle_chance(&"gunshot") > 0.5)
	check(Distraction.startle_chance(&"accusation") > 0.5)
	check(Distraction.startle_chance(&"blackout") > 0.5)
	check_eq(Distraction.startle_chance(&"piece_drop"), 0.0)
	check_eq(Distraction.startle_chance(&"arbiter_pass"), 0.0)
	check(Distraction.is_glance(&"arbiter_pass"))


func test_range() -> void:
	check(Distraction.in_range(&"gunshot", Vector3.ZERO, Vector3(50, 0, 50)), "disparo: todo el salón")
	check(not Distraction.in_range(&"piece_drop", Vector3.ZERO, Vector3(8, 0, 0)), "pieza: solo vecinas")
	check(Distraction.in_range(&"piece_drop", Vector3.ZERO, Vector3(3, 0, 0)))


func test_event_defs_data() -> void:
	var by := {}
	for d in TensionDirector.load_defs():
		by[d.id] = d
	check_eq(by[&"apagon"].turn_chance, 0.8)
	check_eq(by[&"acusacion_ajena"].turn_chance, 0.8)
	check_eq(by[&"arbitro_pasa"].turn_chance, 0.45)
	for id in [&"ruido_detras", &"eliminacion", &"cough", &"drop_piece"]:
		check_eq(by[id].turn_chance, 0.0, "no voltea: " + String(id))


## El bot que voltea hacia un disparo lejano deja de mirar el tablero (la ventana para la trampa).
func test_turned_bot_stops_looking_at_board() -> void:
	var cfg := MatchConfig.new()
	var server := MatchServer.new(cfg, PlayerSession.new(1, "a"), PlayerSession.new(2, "b", true), BoardState.START_FEN, 7)
	server.start()
	var bot := BotController.new()
	var pers := load("res://data/personalities/honesto.tres") as BotPersonality
	var eye := Vector3(0.0, 1.146, -0.53)
	bot.setup(server, ChessPiece.BLACK, pers, FallbackBrain.new(), eye, BoardView.CENTER)
	var board_fwd := Gaze.forward_from_angles(bot.look_yaw, bot.look_pitch)
	check(Gaze.is_looking(eye, board_fwd, BoardView.CENTER, server.config.gaze_cos_threshold if "gaze_cos_threshold" in server.config else 0.9), "al inicio mira el tablero")
	bot._look_at_point(Vector3(6.0, 1.5, -6.0), 2.0, 1.6, 1.0)
	for i in 120:
		bot._turn_head(0.05)
	var fwd := Gaze.forward_from_angles(bot.look_yaw, bot.look_pitch)
	check(not Gaze.is_looking(eye, fwd, BoardView.CENTER, 0.9), "mirando a otra mesa ya no mira el tablero")
	# Un aviso leve no pisa una distracción fuerte en curso.
	bot._look_at_point(Vector3(-5.0, 1.5, 5.0), 0.5, 2.0, 0.25)
	check(bot._target_dir.x > 0.0, "el aviso leve no interrumpe al fuerte")
	bot.free()
