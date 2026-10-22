extends TestCase
## Programación del tic-tac de las mesas de fondo: un segundo entero por tic, desfasado por mesa.


func test_tick_index_changes_once_per_second() -> void:
	var changes := 0
	var last := BackgroundTable.tick_index(0.0, 0.3)
	var t := 0.0
	while t < 10.0:
		t += 1.0 / 60.0
		var i := BackgroundTable.tick_index(t, 0.3)
		if i != last:
			changes += 1
			last = i
	check_eq(changes, 10, "diez tics en diez segundos")


func test_phase_offsets_the_tick() -> void:
	check_eq(BackgroundTable.tick_index(0.5, 0.0), 0, "sin fase, aún no toca")
	check_eq(BackgroundTable.tick_index(0.5, 0.6), 1, "con fase, ya tocó")


func test_sound_assets_exist() -> void:
	for p in [BackgroundTable.TICK_PATH, BackgroundTable.TOCK_PATH, BackgroundTable.PRESS_PATH] + BackgroundTable.PLACE_PATHS:
		check(ResourceLoader.exists(p), "existe " + p)
