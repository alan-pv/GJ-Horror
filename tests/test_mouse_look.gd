extends TestCase


func test_proportional_to_screen_pixels() -> void:
	var d := PlayerController.look_delta(Vector2(100, -50), 1.0)
	check(d.is_equal_approx(Vector2(100, -50) * PlayerController.MOUSE_SENSITIVITY), "píxeles por sensibilidad base")
	check(PlayerController.look_delta(Vector2(100, 0), 2.0).is_equal_approx(Vector2(200, 0) * PlayerController.MOUSE_SENSITIVITY), "el ajuste multiplica")


func test_spike_ignored() -> void:
	check_eq(PlayerController.look_delta(Vector2(3000, 0), 1.0), Vector2.ZERO, "salto falso del navegador")
	check(PlayerController.look_delta(Vector2(300, 0), 1.0) != Vector2.ZERO, "un giro rápido real sí cuenta")
