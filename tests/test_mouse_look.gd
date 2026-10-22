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
