extends TestCase

const W := ChessPiece.WHITE
const B := ChessPiece.BLACK


func _sq(n: String) -> int:
	return ChessPiece.square_from_name(n)


func _make() -> MatchServer:
	var cfg := MatchConfig.new()
	cfg.beginner_help = false
	cfg.arbiter_delay = 1.0
	cfg.rival_event_cooldown = 5.0
	for id in ["own", "enemy", "steal"]:
		cfg.cheats.append(load("res://data/cheats/%s.tres" % id))
	var m := MatchServer.new(cfg, PlayerSession.new(1, "Blancas"), PlayerSession.new(2, "Negras", true), BoardState.START_FEN, 7)
	m.start()
	return m


func test_event_emits_signal() -> void:
	var m := _make()
	var got: Array = []
	m.rival_event.connect(func(c: int, id: StringName) -> void: got.append([c, id]))
	var r := m.trigger_rival_event(B, &"cough")
	check(r.ok, "toser se acepta")
	check_eq(got, [[B, &"cough"]], "señal emitida")
	check(not m.trigger_rival_event(B, &"nada").ok, "evento desconocido")


func test_not_started_or_over() -> void:
	var m := _make()
	m.winner = W
	check(not m.trigger_rival_event(B, &"cough").ok, "partida terminada")
	var n := MatchServer.new(MatchConfig.new(), PlayerSession.new(1, "a"), PlayerSession.new(2, "b"))
	check(not n.trigger_rival_event(B, &"cough").ok, "sin empezar")


func test_cooldown_per_color_and_event() -> void:
	var m := _make()
	check(m.trigger_rival_event(B, &"cough").ok)
	check(not m.trigger_rival_event(B, &"cough").ok, "en espera")
	check(not m.trigger_rival_event(B, &"drop_piece").ok, "evento retirado: desconocido")
	check(m.trigger_rival_event(W, &"cough").ok, "otro color sí")
	check(m.rival_event_wait(B, &"cough") > 4.0, "espera restante")
	for i in 60:
		m.tick(0.1)
	check(m.trigger_rival_event(B, &"cough").ok, "pasado el cooldown")


func test_rejected_during_accusation() -> void:
	var m := _make()
	check(m.accuse(W).ok)
	check(not m.trigger_rival_event(B, &"cough").ok, "no durante una acusación")


func test_cough_with_busy_hand() -> void:
	var m := _make()
	var r := m.start_cheat(B, _sq("e7"), _sq("e6"))
	check(r.ok, "empieza la trampa")
	check(m.trigger_rival_event(B, &"cough").ok, "toser no usa la mano")


func test_arbiter_near_marks_cheats_seen() -> void:
	var m := _make()
	m._looking[B] = false
	var r := m.start_cheat(W, _sq("a7"), _sq("a6"))
	check(r.ok)
	m.tick(0.1)
	check(not m.cheat_log[0].seen, "sin árbitro ni mirada no se ve")
	m.set_arbiter_near(true)
	m.tick(0.1)
	check(m.cheat_log[0].seen, "el árbitro cerca la ve")
	check(m.is_arbiter_near())


func test_arbiter_near_before_cheat_starts() -> void:
	var m := _make()
	m._looking[B] = false
	m.set_arbiter_near(true)
	m.start_cheat(W, _sq("a7"), _sq("a6"))
	check(m.cheat_log[0].seen, "nace vista")
	m.set_arbiter_near(false)
	m._looking[W] = false
	m.start_cheat(B, _sq("e7"), _sq("e6"))
	check(not m.cheat_log[1].seen, "sin árbitro no se ve")
