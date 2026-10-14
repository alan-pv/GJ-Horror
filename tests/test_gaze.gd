extends TestCase


func test_cone() -> void:
	var eye := Vector3(0, 1.2, 0.6)
	var board := Vector3.ZERO
	check(Gaze.is_looking(eye, board - eye, board, 0.82), "mirando directo")
	check(not Gaze.is_looking(eye, Vector3.FORWARD, board, 0.82), "mirando al frente, el tablero queda abajo")
	check(not Gaze.is_looking(eye, Vector3.BACK, board, 0.82), "mirando atrás")


func test_forward_from_angles() -> void:
	check(Gaze.forward_from_angles(0, 0).is_equal_approx(Vector3.FORWARD), "neutro")
	check(Gaze.forward_from_angles(PI / 2, 0).is_equal_approx(Vector3.LEFT), "yaw positivo gira a la izquierda")
	check(Gaze.forward_from_angles(0, -PI / 2).is_equal_approx(Vector3.DOWN), "pitch negativo mira abajo")
