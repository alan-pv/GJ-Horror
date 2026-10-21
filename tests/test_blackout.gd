extends TestCase
## Apagón: las trampas hechas a oscuras no se ven ni prosperan en una acusación
## (`MatchConfig.blackout_hides_cheats`), los bots no acusan con fundamento y el cliente
## decide qué nivel de luz cuenta como oscuridad.

const W := ChessPiece.WHITE
const B := ChessPiece.BLACK


func _sq(n: String) -> int:
	return ChessPiece.square_from_name(n)


func _make(hides: bool = true) -> MatchServer:
	var cfg := MatchConfig.new()
	cfg.beginner_help = false
	cfg.arbiter_delay = 1.0
	cfg.blackout_hides_cheats = hides
	for id in ["own", "enemy", "steal"]:
		cfg.cheats.append(load("res://data/cheats/%s.tres" % id))
	var m := MatchServer.new(cfg, PlayerSession.new(1, "Blancas"), PlayerSession.new(2, "Negras", true), BoardState.START_FEN, 7)
	m.start()
	return m


## Acusa de `color` y deja pasar el tiempo del árbitro; devuelve si prosperó.
func _accuse_correct(m: MatchServer, color: int) -> bool:
	var got: Array = []
	m.accusation_resolved.connect(func(_a: int, ok: bool, _w: int) -> void: got.append(ok))
	check(m.accuse(color).ok)
	for i in 30:
		m.tick(0.1)
	return got.size() == 1 and got[0]


func test_option_default_and_api() -> void:
	check(MatchConfig.new().blackout_hides_cheats, "por defecto sí")
	var m := _make()
	check(not m.is_blackout())
	m.set_blackout(true)
	check(m.is_blackout())
	m.set_blackout(false)
	check(not m.is_blackout())


func test_cheat_started_in_blackout_is_not_seen() -> void:
	var m := _make()
	m._looking[B] = true
	m.set_blackout(true)
	check(m.start_cheat(W, _sq("a7"), _sq("a6")).ok)
	m.tick(0.1)
	check(not m.cheat_log[0].seen, "mirando a oscuras no la ve")
	check(m.cheat_log[0].dark, "marcada como oscura")
	m.set_arbiter_near(true)
	m.tick(0.1)
	check(not m.cheat_log[0].seen, "ni el árbitro cerca")


func test_accusation_does_not_prosper_over_dark_cheat() -> void:
	var m := _make()
	m.set_blackout(true)
	check(m.start_cheat(W, _sq("a7"), _sq("a6")).ok)
	for i in 80:
		m.tick(0.1)
	check_eq(m.cheat_log[0].status, "done")
	m.set_blackout(false)
	check(m.cheat_log[0].dark, "sigue oscura al volver la luz")
	check(not _accuse_correct(m, B), "la acusación no prospera")


func test_cheat_seen_before_blackout_still_counts() -> void:
	var m := _make()
	m._looking[B] = true
	check(m.start_cheat(W, _sq("a7"), _sq("a6")).ok)
	m.tick(0.1)
	check(m.cheat_log[0].seen)
	m.set_blackout(true)
	m.tick(0.1)
	check(m.cheat_log[0].seen, "sigue vista")
	check(not m.cheat_log[0].dark, "no es oscura")
	for i in 80:
		m.tick(0.1)
	check(_accuse_correct(m, B), "la acusación prospera")


func test_cheat_in_progress_when_dark_starts() -> void:
	var m := _make()
	m._looking[B] = false
	check(m.start_cheat(W, _sq("a7"), _sq("a6")).ok)
	m.tick(0.1)
	m.set_blackout(true)
	check(m.cheat_log[0].dark, "en curso al apagarse sin haber sido vista")
	m._looking[B] = true
	m.tick(0.1)
	check(not m.cheat_log[0].seen, "no se ve a oscuras")


func test_cheat_continues_after_light_returns_and_is_seen() -> void:
	var m := _make()
	m._looking[B] = false
	m.set_blackout(true)
	check(m.start_cheat(W, _sq("a7"), _sq("a6")).ok)
	m.tick(0.1)
	m.set_blackout(false)
	m.tick(0.1)
	check(m.cheat_log[0].dark and not m.cheat_log[0].seen, "nadie mira todavía")
	m._looking[B] = true
	m.tick(0.1)
	check(m.cheat_log[0].seen, "se la ve terminar")
	check(not m.cheat_log[0].dark)
	for i in 80:
		m.tick(0.1)
	check(_accuse_correct(m, B), "esa sí prospera")


func test_option_off_keeps_old_behaviour() -> void:
	var m := _make(false)
	m._looking[B] = true
	m.set_blackout(true)
	check(m.start_cheat(W, _sq("a7"), _sq("a6")).ok)
	m.tick(0.1)
	check(m.cheat_log[0].seen, "se ve aunque esté oscuro")
	check(not m.cheat_log[0].dark)
	for i in 80:
		m.tick(0.1)
	check(_accuse_correct(m, B), "prospera")


func test_bot_does_not_judge_dark_cheat() -> void:
	var m := _make()
	m.set_blackout(true)
	var bot := BotController.new()
	var pers := BotPersonality.new()
	pers.detect_chance = 1.0
	var eye := Vector3(0.0, 1.146, -0.53)
	bot.setup(m, B, pers, FallbackBrain.new(), eye, BoardView.CENTER)
	m.set_gaze(B, eye, Gaze.forward_from_angles(bot.look_yaw, bot.look_pitch))
	check(m.is_looking(B), "el bot mira el tablero")
	check(m.start_cheat(W, _sq("a7"), _sq("a6")).ok)
	bot._watch_for_cheats()
	check(bot._judged.is_empty(), "no la juzga a oscuras")
	check(not m.accusation_pending(), "no acusa")
	var entry: Dictionary = m.cheat_log[0]
	check(not entry.seen, "el bot no la vio")
	bot.free()


func test_client_darkness_threshold() -> void:
	check(EventStage.is_dark_level(0.0))
	check(EventStage.is_dark_level(0.06), "parpadeo bajo")
	check(EventStage.is_dark_level(0.25), "destello del apagón")
	check(not EventStage.is_dark_level(0.3), "umbral")
	check(not EventStage.is_dark_level(1.0))
	# La curva real: hay oscuridad en el centro y luz al principio/final.
	var dark_steps := 0
	for i in 200:
		if EventStage.is_dark_level(EventStage.blackout_level(i / 200.0)):
			dark_steps += 1
	check(dark_steps > 80, "la mayor parte es oscura: %d" % dark_steps)
	check(not EventStage.is_dark_level(EventStage.blackout_level(1.0)), "al final hay luz")
