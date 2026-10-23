extends TestCase


func test_proportional_to_screen_pixels() -> void:
	var d := PlayerController.look_delta(Vector2(100, -50), 1.0)
	check(d.is_equal_approx(Vector2(100, -50) * PlayerController.MOUSE_SENSITIVITY), "píxeles por sensibilidad base")
	check(PlayerController.look_delta(Vector2(100, 0), 2.0).is_equal_approx(Vector2(200, 0) * PlayerController.MOUSE_SENSITIVITY), "el ajuste multiplica")


func test_spike_ignored() -> void:
	check_eq(PlayerController.look_delta(Vector2(3000, 0), 1.0), Vector2.ZERO, "salto falso del navegador")
	check(PlayerController.look_delta(Vector2(300, 0), 1.0) != Vector2.ZERO, "un giro rápido real sí cuenta")


func test_smoothing_converges() -> void:
	var pending := Vector2(0.3, -0.1)
	var applied := Vector2.ZERO
	var first := PlayerController.smooth_take(pending, 1.0 / 60.0)
	check(first.length() > 0.0 and first.length() < pending.length(), "un fotograma aplica solo una parte")
	for i in 30:
		var take := PlayerController.smooth_take(pending, 1.0 / 60.0)
		applied += take
		pending -= take
	check(pending.length() < 0.001, "en medio segundo ya se aplicó casi todo")


func test_web_smoothing_is_direct() -> void:
	check_eq(PlayerController.LOOK_SMOOTH_WEB, 0.0, "en web el giro no lleva retraso")
	var pending := Vector2(0.3, -0.1)
	check_eq(PlayerController.smooth_take(pending, 1.0 / 60.0, PlayerController.LOOK_SMOOTH_WEB), pending, "tau 0 aplica todo")
	check_eq(PlayerController.smooth_take(pending, 1.0 / 60.0, -1.0), pending, "tau negativa tampoco suaviza")


func test_scale_is_independent_of_canvas() -> void:
	# Los píxeles CSS de movementX no dependen del tamaño del lienzo ni del dpr: misma entrada, mismo giro.
	var a := PlayerController.scale_look(Vector2(300, 0), 1.0)
	check(is_equal_approx(a.x, 300.0 * PlayerController.MOUSE_SENSITIVITY), "300 px = 0,66 rad con sensibilidad 1")
	check(PlayerController.scale_look(Vector2(100, 40), 2.5).is_equal_approx(Vector2(100, 40) * PlayerController.MOUSE_SENSITIVITY * 2.5))


func test_filter_events_sums_normal_motion() -> void:
	var r := PlayerController.filter_events(PackedFloat32Array([3, 1, 4, -1, 2, 0]), 0.0)
	check_eq(r["sum"], Vector2(9, 0), "suma de los eventos")
	check_eq(r["dropped"], 0, "ninguno descartado")
	check(float(r["recent"]) > 0.0, "la media reciente se actualiza")


func test_filter_events_drops_isolated_spike() -> void:
	# Movimiento lento (~3 px) y de pronto un evento de 300 px: salto aislado, se descarta.
	var r := PlayerController.filter_events(PackedFloat32Array([3, 0, 3, 0, 300, 0, 3, 0]), 3.0)
	check_eq(r["sum"], Vector2(9, 0), "el pico no cuenta")
	check_eq(r["dropped"], 1, "un descartado")
	# Más allá del tope absoluto se descarta aunque el movimiento reciente sea enorme.
	var big := PlayerController.filter_events(PackedFloat32Array([500, 0]), 300.0)
	check_eq(big["sum"], Vector2.ZERO, "tope por evento")


func test_filter_events_keeps_fast_flick() -> void:
	# Un giro rápido real crece por pasos y no se come.
	var r := PlayerController.filter_events(PackedFloat32Array([5, 0, 20, 0, 60, 0, 120, 0, 200, 0, 250, 0]), 0.0)
	check_eq(r["dropped"], 0, "el giro rápido real se conserva")
	check_eq(r["sum"], Vector2(655, 0), "suma completa")
	# Con ritmo alto sostenido, 200 px por evento tampoco es pico.
	var fast := PlayerController.filter_events(PackedFloat32Array([200, 0]), 150.0)
	check_eq(fast["dropped"], 0, "lo reciente ya era rápido")
