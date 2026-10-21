extends TestCase
## Gesto de tomar la pluma: orientación de la mano para la toma (`HandRig.orient_for_axis`), que el
## eje de la pluma no atraviese las falanges de pulgar e índice en la toma ni al escribir, y que el
## giro de la pluma en la mano (`set_tool_blend`) sea continuo.

## Separación mínima (m) entre el eje de la pluma y la línea central de las falanges largas.
const MIN_CLEARANCE := 0.0075


func _figure() -> SeatedFigure:
	var f := SeatedFigure.new()
	f.setup(CharacterFigure.bot_look(RandomNumberGenerator.new(), {}))
	f.play(&"sit_idle", 0.0)
	f.animation_player().advance(0.0)
	f.skeleton().force_update_all_bone_transforms()
	return f


## Distancia mínima de la recta (`a`, `u`) al segmento p-q.
func _seg_line(p: Vector3, q: Vector3, a: Vector3, u: Vector3) -> float:
	var best := 9.0
	for i in 21:
		var r := p.lerp(q, float(i) / 20.0) - a
		r -= u * r.dot(u)
		best = minf(best, r.length())
	return best


func _axis(writing: bool, pal: float) -> Vector3:
	var u := HandRig.PEN_AXIS_WRITE if writing else HandRig.PEN_AXIS_GRASP
	return Vector3(u.x * pal, u.y, u.z).normalized()


func test_orientation_solver_hits_the_lying_pen() -> void:
	# Mano derecha: la pluma yace hacia la derecha-delante del hombro (el humano la alcanza así, el
	# rival con todo girado 180 grados). La izquierda es el reflejo.
	for pal in [1.0, -1.0]:
		for turn in [0.0, PI]:
			for off in [0.3, 0.45, 0.6]:
				var dir_h := Vector3(off * pal, 0, -1).normalized().rotated(Vector3.UP, turn)
				var lying := Vector3(pal, 0, 0).rotated(Vector3.UP, turn)
				var r := HandRig.orient_for_axis(_axis(false, pal), lying, dir_h, pal, 55.0)
				var tag := "pal %.0f giro %.0f desvío %.2f" % [pal, turn, off]
				check(r.z < 1.0, "el eje queda a menos de 1 grado (%.2f) %s" % [r.z, tag])
				check(r.x > 20.0 and r.x < 85.0, "pitch plausible (%.0f) %s" % [r.x, tag])
				check(absf(r.y) < 100.0, "giro plausible (%.0f) %s" % [r.y, tag])


func test_pen_axis_clears_the_fingers() -> void:
	var f := _figure()
	for side in [&"R", &"L"]:
		var mod := f.arm_pose_modifier(side)
		var sgn := 1.0 if side == &"R" else -1.0
		for writing in [false, true]:
			var u := _axis(writing, sgn)
			var plan := mod.pinch_plan(HandRig.PEN_R, 0.0, 0.0, 0.0, u, HandRig.PEN_WRITE_OPP if writing else 180.0)
			var a: Vector3 = plan.a
			var ix := mod.chain(ArmPoseModifier.INDEX)
			var th := mod.chain(ArmPoseModifier.THUMB)
			var ji := ix.joints(float(plan.ci), sgn)
			var jt := th.joints(float(plan.ct), sgn)
			var tag := "%s %s" % [side, "escribir" if writing else "toma"]
			# Falanges proximal y media del índice, y proximal del pulgar (las yemas tocan la pluma).
			for k in 2:
				var d := _seg_line(ji[k], ji[k + 1], a, u)
				check(d > MIN_CLEARANCE, "%s: índice falange %d a %.1f mm" % [tag, k, d * 1000.0])
			var dt := _seg_line(jt[0], jt[1], a, u)
			check(dt > MIN_CLEARANCE, "%s: pulgar a %.1f mm" % [tag, dt * 1000.0])
	f.free()


func test_pen_pivot_is_continuous() -> void:
	# La pluma pivota en la pinza con un giro mínimo: sin saltos entre pasos y sin pasarse.
	var a := Basis.looking_at(Vector3(0.3, -0.4, -0.8).normalized(), Vector3.UP)
	var u_w := HandRig.PEN_AXIS_WRITE.normalized()
	var w := (Basis(Quaternion(a.x.normalized(), u_w)) * a).orthonormalized()
	check(w.x.angle_to(u_w) < 1e-3, "el destino lleva el eje al de escribir")
	var total := rad_to_deg(a.x.angle_to(w.x))
	check(total < 90.0, "el giro en la mano es moderado (%.0f grados)" % total)
	var prev := a
	var steps := 100
	for i in range(1, steps + 1):
		var k := smoothstep(0.0, 1.0, float(i) / float(steps))
		var b := a.slerp(w, k)
		check(rad_to_deg(prev.x.angle_to(b.x)) < total * 0.04, "paso %d continuo" % i)
		prev = b
	check(prev.x.angle_to(w.x) < 1e-3, "termina en la postura de escribir")


func test_tripod_geometry() -> void:
	# Agarre trípode: yemas de pulgar e índice a 2-3 cm de la punta, la pluma a 45-55 grados del papel
	# y apuntando hacia atrás (hacia el hombro), en las dos manos y con cualquier dirección de la mano.
	check(ScoresheetView.PEN_GRIP >= 0.02 and ScoresheetView.PEN_GRIP <= 0.03, "yemas a 2-3 cm de la punta")
	for pal in [1.0, -1.0]:
		for yaw in [0.0, 0.4, -0.4, PI, PI + 0.4]:
			var dir_h := Vector3(0, 0, -1).rotated(Vector3.UP, yaw)
			var b := HandRig.basis_for(dir_h, deg_to_rad(HandAnimator.WRITE_PITCH), deg_to_rad(HandAnimator.WRITE_ROLL * pal), pal)
			var uw := b * _axis(true, pal)
			var elev := rad_to_deg(asin(uw.y))
			var tag := "pal %.0f yaw %.1f" % [pal, yaw]
			check(elev >= 45.0 and elev <= 55.5, "pluma a %.0f grados del papel %s" % [elev, tag])
			var back := Vector3(uw.x, 0, uw.z).normalized().dot(-dir_h)
			check(back > 0.3, "la pluma apunta hacia atrás (%.2f) %s" % [back, tag])


func test_tripod_pads_face_each_other_across_the_pen() -> void:
	# Las yemas de pulgar e índice quedan a ambos lados de la pluma (oposición cercana a la pedida) y
	# la pluma pasa a menos de 2,5 cm de la base del índice (la membrana entre pulgar e índice).
	var f := _figure()
	for side in [&"R", &"L"]:
		var mod := f.arm_pose_modifier(side)
		var sgn := 1.0 if side == &"R" else -1.0
		var u := _axis(true, sgn)
		var plan := mod.pinch_plan(HandRig.PEN_R, 0.0, 0.0, 0.0, u, HandRig.PEN_WRITE_OPP)
		check(float(plan.cost) < 25.0, "%s: plan de pinza de la pluma viable (coste %.1f)" % [side, float(plan.cost)])
		check(absf(float(plan.opp) - HandRig.PEN_WRITE_OPP) < 20.0, "%s: oposición %.0f cerca de %.0f" % [side, float(plan.opp), HandRig.PEN_WRITE_OPP])
		var ix := mod.chain(ArmPoseModifier.INDEX)
		var base: Vector3 = ix.rest[0].origin
		var d := _seg_line(base, base, plan.a, u)
		check(d < 0.025, "%s: pluma a %.1f mm de la base del índice" % [side, d * 1000.0])
	f.free()
