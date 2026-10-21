extends TestCase
## Giro suave del paseo (`HallWalk.look_ahead`, `HallWalk.smooth_yaw`) y parpadeo (`BlinkOverlay`).

const DT := 1.0 / 60.0
const OMEGA := 5.5
const MAX := 3.0


func check_near(a: float, b: float, eps: float, msg: String = "") -> void:
	check(absf(a - b) <= eps, "%s esperado=%f obtenido=%f" % [msg, b, a])


func test_smooth_yaw_bounded_and_continuous_at_corner() -> void:
	var yaw := 0.0
	var vel := 0.0
	var want := 0.0
	var prev_vel := 0.0
	for k in 240:
		if k == 60:
			want = PI * 0.5  # el rumbo deseado salta de golpe (esquina)
		if k == 140:
			want = -PI * 0.75
		var r := HallWalk.smooth_yaw(yaw, vel, want, DT, OMEGA, MAX)
		yaw = r.x
		vel = r.y
		check(absf(vel) <= MAX + 0.0001, "velocidad angular acotada")
		# Aceleración acotada: sin saltos de velocidad entre fotogramas.
		check(absf(vel - prev_vel) <= (OMEGA * OMEGA * PI + 2.0 * OMEGA * MAX) * DT + 0.001, "velocidad continua")
		prev_vel = vel
	check_near(absf(angle_difference(yaw, want)), 0.0, 0.02, "converge al rumbo")


func test_smooth_yaw_does_not_jump_at_wrap() -> void:
	# Cruzar +-PI no debe dar vueltas largas.
	var yaw := 3.0
	var vel := 0.0
	for k in 120:
		var r := HallWalk.smooth_yaw(yaw, vel, -3.0, DT, OMEGA, MAX)
		check(absf(angle_difference(yaw, r.x)) < 0.1, "paso pequeño")
		yaw = r.x
		vel = r.y
	check_near(absf(angle_difference(yaw, -3.0)), 0.0, 0.02)


func test_smooth_yaw_large_step_stable() -> void:
	var r := HallWalk.smooth_yaw(0.0, 0.0, 1.0, 0.25, OMEGA, MAX)
	check(is_finite(r.x) and is_finite(r.y))
	check(absf(r.y) <= MAX)


func test_look_ahead_on_straight_and_corner() -> void:
	var path: Array[Vector3] = [Vector3(2, 0, 0), Vector3(2, 0, 3)]
	var p := HallWalk.look_ahead(Vector3.ZERO, path, 0, 1.0)
	check_eq(p, Vector3(1, 0, 0))
	# 0,5 m antes del vértice con 1 m de adelanto: 0,5 m ya en el tramo siguiente.
	p = HallWalk.look_ahead(Vector3(1.5, 0, 0), path, 0, 1.0)
	check_near(p.x, 2.0, 0.001)
	check_near(p.z, 0.5, 0.001)
	# Más allá del final se queda en el último punto.
	p = HallWalk.look_ahead(Vector3(2, 0, 2.9), path, 1, 5.0)
	check_eq(p, Vector3(2, 0, 3))


func test_walk_heading_smooth_on_every_route() -> void:
	# Simula el paseo sobre las rutas reales: el rumbo nunca salta ni supera la velocidad máxima.
	var human := HallLayout.human_table
	var worst := 0.0
	for a in HallLayout.table_count():
		for b in HallLayout.table_count():
			if a == b or (a * 7 + b) % 5 != 0:
				continue
			HallLayout.set_human_table(a)
			var path := HallWalk.route(a, b)
			var pos := HallWalk.seat_point(a)
			var yaw := PI
			var vel := 0.0
			for i in path.size():
				var guard := 0
				while guard < 4000:
					guard += 1
					var to := path[i] - pos
					to.y = 0.0
					if to.length() < 0.02:
						break
					var ahead := HallWalk.look_ahead(pos, path, i, 0.8) - pos
					ahead.y = 0.0
					var want := HallWalk.yaw_for(ahead) if ahead.length() > 0.05 else yaw
					var r := HallWalk.smooth_yaw(yaw, vel, want, DT, OMEGA, MAX)
					worst = maxf(worst, absf(angle_difference(yaw, r.x)))
					yaw = r.x
					vel = r.y
					pos += to.normalized() * minf(CharacterFigure.WALK_SPEED * DT, to.length())
	HallLayout.set_human_table(human)
	check(worst <= MAX * DT + 0.0001, "giro por fotograma %.4f" % worst)


func test_blink_overlay_closed_value() -> void:
	var b := BlinkOverlay.new()
	b.closed = 0.5
	check_near(b.closed, 0.5, 0.0001)
	b.closed = 3.0
	check_near(b.closed, 1.0, 0.0001, "se acota a 1")
	check(b._rect.visible)
	b.closed = 0.0
	check(not b._rect.visible)
	b.free()
