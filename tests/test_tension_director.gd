extends TestCase


func _director(seed_value: int = 5) -> TensionDirector:
	var d := TensionDirector.new(TensionDirector.load_defs(), seed_value)
	d.table_positions = Hall.table_positions()
	return d


## Simula `seconds` y devuelve [{id, origin, time}].
func _run(d: TensionDirector, seconds: float) -> Array:
	var log: Array = []
	d.event_triggered.connect(func(id: StringName, origin: Vector3, _dur: float) -> void:
		log.append({"id": id, "origin": origin, "time": d.time}))
	var t := 0.0
	while t < seconds:
		d.tick(0.1)
		t += 0.1
	return log


func test_defs_load() -> void:
	var defs := TensionDirector.load_defs()
	check_eq(defs.size(), 5, "cinco eventos como datos")
	for dd in defs:
		check(dd.duration > 0.0, "duración positiva: " + String(dd.id))


func test_first_event_not_before_delay() -> void:
	var d := _director()
	var log := _run(d, 10.0)
	check(log.is_empty(), "nada antes del retraso inicial")


func test_spacing_and_no_back_to_back() -> void:
	var d := _director()
	d.set_players_remaining(2, 16)
	var log := _run(d, 900.0)
	check(log.size() > 5, "salen varios eventos")
	for i in range(1, log.size()):
		check(log[i].time - log[i - 1].time >= d.min_spacing - 0.2, "separación mínima")
		check(log[i].id != log[i - 1].id, "sin repetir seguidos")
		var def := d.get_def(log[i].id)
		check(def.kind != EventDef.Kind.RIVAL, "el director no sortea eventos del rival")


func test_frequency_rises_with_fewer_players() -> void:
	var full := _director(3)
	full.set_players_remaining(16, 16)
	var few := _director(3)
	few.set_players_remaining(2, 16)
	var n_full := _run(full, 1200.0).size()
	var n_few := _run(few, 1200.0).size()
	check(n_few > n_full, "más eventos con menos jugadores (%d > %d)" % [n_few, n_full])
	check(few.current_interval() < full.current_interval(), "intervalo menor")
	check(few.tension() > full.tension(), "más tensión")


func test_same_seed_same_sequence() -> void:
	var a := _run(_director(9), 400.0)
	var b := _run(_director(9), 400.0)
	check_eq(a.size(), b.size(), "misma cantidad")
	for i in mini(a.size(), b.size()):
		check_eq(a[i].id, b[i].id, "mismo evento")
		check_eq(a[i].origin, b[i].origin, "mismo origen")


func test_event_cooldown_respected() -> void:
	var d := _director()
	d.interval_full = 1.0
	d.interval_final = 1.0
	d.min_spacing = 1.0
	d.first_delay = 0.0
	var log := _run(d, 120.0)
	var last := {}
	for e in log:
		var cd := d.get_def(e.id).cooldown
		if last.has(e.id):
			check(e.time - last[e.id] >= cd - 0.2, "cooldown de " + String(e.id))
		last[e.id] = e.time


func test_origins() -> void:
	var d := _director()
	d.listener_pos = Vector3(0.0, 0.0, 0.5)
	d.listener_forward = Vector3(0.0, 0.0, -1.0)
	for i in 30:
		var o := d.pick_origin(d.get_def(&"ruido_detras"))
		check(o.z > d.listener_pos.z, "ruido detrás queda a espaldas del jugador")
		check(absf(o.x) <= d.room_half.x and absf(o.z) <= d.room_half.y, "dentro del salón")
	var t := d.pick_origin(d.get_def(&"acusacion_ajena"))
	check(Hall.table_positions().has(t), "acusación ajena en una mesa")


func test_fire_forced() -> void:
	var d := _director()
	var got: Array = []
	d.event_triggered.connect(func(id: StringName, origin: Vector3, dur: float) -> void: got.append([id, origin, dur]))
	check(d.fire(&"acusacion_ajena", Vector3(1, 0, 2)), "se dispara")
	check_eq(got.size(), 1)
	check_eq(got[0][1], Vector3(1, 0, 2), "origen dado")
	check_eq(got[0][2], 3.5, "duración del dato")
	check(not d.fire(&"no_existe"), "id desconocido")
	check(not d.candidates().any(func(e: EventDef) -> bool: return e.id == &"acusacion_ajena"), "queda en espera")


func test_disabled_director() -> void:
	var d := _director()
	d.enabled = false
	check(_run(d, 300.0).is_empty(), "apagado no dispara")
