extends TestCase
## Pruebas del modelo de estrés (`StressModel`) y del latido.


func _model(clock: float = 180.0) -> StressModel:
	var m := StressModel.new()
	m.set_floor_inputs(clock, 32, 32, 0.0)
	m.step(0.0)
	return m


func test_calm_is_zero() -> void:
	var m := _model()
	m.step(1.0)
	check_eq(m.value, 0.0, "en calma el estrés es 0")


func test_clock_floor() -> void:
	check_eq(StressModel.clock_floor(60.0), 0.0, "60 s o más: 0")
	check_eq(StressModel.clock_floor(200.0), 0.0, "mucho tiempo: 0")
	check(absf(StressModel.clock_floor(30.0) - 0.3) < 0.001, "30 s: mitad del piso")
	check(absf(StressModel.clock_floor(0.0) - StressModel.CLOCK_FLOOR_MAX) < 0.001, "0 s: piso máximo")
	var m := _model(0.0)
	check(absf(m.value - 0.6) < 0.001, "el valor sigue al piso")


func test_tournament_floor() -> void:
	check_eq(StressModel.tournament_floor(32, 32), 0.0, "primera ronda: 0")
	check(absf(StressModel.tournament_floor(2, 32) - StressModel.TOURNAMENT_FLOOR_MAX) < 0.001, "final: tope")
	var mid := StressModel.tournament_floor(8, 32)
	check(mid > 0.0 and mid < StressModel.TOURNAMENT_FLOOR_MAX, "ronda intermedia entre ambos")
	check(StressModel.tournament_floor(4, 32) > mid, "crece con las rondas")
	check(absf(StressModel.tournament_floor(2, 2) - StressModel.TOURNAMENT_FLOOR_MAX) < 0.001, "dos jugadores es la final")


func test_material_floor() -> void:
	check_eq(StressModel.material_floor(0.0), 0.0, "sin desventaja")
	check_eq(StressModel.material_floor(-3.0), 0.0, "ventaja propia no estresa")
	check(absf(StressModel.material_floor(5.0) - 0.15) < 0.001, "5 peones: tope")
	check(absf(StressModel.material_floor(20.0) - 0.15) < 0.001, "más de 5 no pasa del tope")


func test_material_deficit() -> void:
	var b := BoardState.from_fen("4k3/8/8/8/8/8/PPPPP3/4K3 w - - 0 1")
	check_eq(StressModel.material_deficit(b, ChessPiece.BLACK), 5.0, "negras pierden 5 peones")
	check_eq(StressModel.material_deficit(b, ChessPiece.WHITE), -5.0, "blancas van 5 arriba")


func test_floor_is_max_not_sum() -> void:
	var m := StressModel.new()
	m.set_floor_inputs(0.0, 2, 32, 5.0)
	check(absf(m.floor_value - 0.6) < 0.001, "el piso es el máximo de los tres")


func test_spike_hold_then_decay_to_floor() -> void:
	var m := _model()
	m.add_spike(StressModel.SPIKE_SHOT_TABLE)
	check(absf(m.value - 0.6) < 0.001, "el pico sube de golpe")
	m.step(1.4)
	check(absf(m.value - 0.6) < 0.001, "se sostiene 1,5 s")
	m.step(0.2)
	m.step(1.0)
	check(m.value < 0.6 and m.value > 0.4, "después decae despacio")
	for i in 100:
		m.step(1.0)
	check_eq(m.value, 0.0, "acaba en el piso (0)")


func test_decay_stops_at_floor() -> void:
	var m := _model(20.0)
	var floor_v := m.floor_value
	m.add_spike(0.3)
	for i in 100:
		m.step(1.0)
	check(absf(m.value - floor_v) < 0.001, "el pico cae hasta el piso, no por debajo")


func test_spikes_add_and_cap() -> void:
	var m := _model()
	m.add_spike(0.6)
	m.add_spike(0.35)
	check(absf(m.value - 0.95) < 0.001, "los picos se suman")
	m.add_spike(0.6)
	check_eq(m.value, 1.0, "tope 1")


func test_sustained() -> void:
	var m := _model()
	m.set_sustained(&"accused", StressModel.SUSTAIN_ACCUSED)
	m.step(30.0)
	check(absf(m.value - 0.45) < 0.001, "lo sostenido no decae mientras dure")
	m.set_sustained(&"arbiter", StressModel.SUSTAIN_ARBITER)
	check(absf(m.value - 0.6) < 0.001, "se suma con otros")
	m.set_sustained(&"accused", 0.0)
	check(absf(m.value - 0.15) < 0.001, "al terminar la causa se quita")


func test_condemn_goes_to_one_and_stays() -> void:
	var m := _model()
	m.condemn()
	check_eq(m.value, 1.0, "condenado: 1")
	m.step(100.0)
	check_eq(m.value, 1.0, "y no baja")


func test_shake_trauma() -> void:
	var m := _model()
	m.add_shake(0.8)
	m.add_shake(0.8)
	check_eq(m.shake_trauma, 1.0, "tope 1")
	m.step(0.4)
	check(absf(m.shake_trauma - 0.4) < 0.001, "decae 1,5 por segundo")
	m.step(5.0)
	check_eq(m.shake_trauma, 0.0, "no baja de 0")


func test_heart() -> void:
	check_eq(StressModel.bpm(0.0), StressModel.BPM_MIN, "bpm en calma")
	check_eq(StressModel.bpm(1.0), StressModel.BPM_MAX, "bpm al máximo")
	check(StressModel.bpm(0.5) > StressModel.BPM_MIN and StressModel.bpm(0.5) < StressModel.BPM_MAX, "intermedio")
	check(StressModel.heart_pulse(0.04) > 0.95, "pico del primer golpe")
	check(StressModel.heart_pulse(0.32) > 0.5, "segundo golpe")
	check(StressModel.heart_pulse(0.7) < 0.01, "silencio entre latidos")
	check(absf(StressModel.heart_pulse(1.04) - StressModel.heart_pulse(0.04)) < 0.0001, "periódico")


func test_blackout_alone_gives_no_spike_but_cheating_in_it_does() -> void:
	check(StressModel.SPIKE_CHEAT_IN_BLACKOUT > 0.0 and StressModel.SPIKE_CHEAT_IN_BLACKOUT < StressModel.SPIKE_SHOT_TABLE, "pico moderado")
	var m := _model()
	m.step(1.0)
	check_eq(m.value, 0.0, "sin trampa, el apagón no sube el estrés")
	m.add_spike(StressModel.SPIKE_CHEAT_IN_BLACKOUT)
	check(absf(m.value - StressModel.SPIKE_CHEAT_IN_BLACKOUT) < 0.001, "la trampa a oscuras sí")
