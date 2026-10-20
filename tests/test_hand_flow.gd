extends TestCase
## Curva de los gestos de la mano (`HandAnimator._flow`), su perfil de velocidad, la
## consulta `is_busy_for_action` y la escritura a medias de `ScoresheetView`.

const W := ChessPiece.WHITE


func test_min_jerk_profile() -> void:
	check_eq(HandAnimator._profile(0.0, 0.0), 0.0, "empieza en 0")
	check(absf(HandAnimator._profile(1.0, 0.0) - 1.0) < 1e-6, "termina en 1")
	check(absf(HandAnimator._profile(0.5, 0.0) - 0.5) < 1e-6, "simétrico")
	var prev := 0.0
	for i in range(1, 101):
		var s := HandAnimator._profile(float(i) / 100.0, 0.0)
		check(s >= prev, "monótono")
		prev = s
	# Con tramo de crucero también es monótono y llega a 1.
	prev = 0.0
	for i in range(1, 101):
		var s2 := HandAnimator._profile(float(i) / 100.0, 0.5)
		check(s2 >= prev - 1e-9, "monótono con crucero")
		prev = s2
	check(absf(HandAnimator._profile(1.0, 0.5) - 1.0) < 1e-6, "crucero: termina en 1")
	# La velocidad en los extremos es casi nula (arranque y frenado suaves).
	check(HandAnimator._profile(0.01, 0.0) < 0.0001, "arranque suave")
	check(1.0 - HandAnimator._profile(0.99, 0.0) < 0.0001, "frenado suave")


func test_catmull_passes_through_waypoints() -> void:
	var p0 := Vector3(0, 0, 0)
	var p1 := Vector3(0.1, 0.2, 0)
	var p2 := Vector3(0.3, 0.2, 0.1)
	var p3 := Vector3(0.5, 0, 0.1)
	check(HandAnimator._catmull(p0, p1, p2, p3, 0.0).distance_to(p1) < 1e-5, "en p1")
	check(HandAnimator._catmull(p0, p1, p2, p3, 1.0).distance_to(p2) < 1e-5, "en p2")
	# Continuidad de velocidad: la tangente de salida de un tramo es la de entrada del siguiente.
	var e := 1e-3
	var out_prev := HandAnimator._catmull(p0, p1, p2, p3, 1.0) - HandAnimator._catmull(p0, p1, p2, p3, 1.0 - e)
	var p4 := Vector3(0.7, 0.1, 0.0)
	var out_next := HandAnimator._catmull(p1, p2, p3, p4, e) - HandAnimator._catmull(p1, p2, p3, p4, 0.0)
	check(out_prev.normalized().dot(out_next.normalized()) > 0.99, "tangente continua en el punto de paso")


func test_busy_for_action_ignores_writing() -> void:
	var a := HandAnimator.new()
	check(not a.is_busy_for_action(), "libre")
	a._queue.append({"kind": "write"})
	check(a.is_busy(), "is_busy cuenta la escritura")
	check(not a.is_busy_for_action(), "pero no para actuar")
	check(not a._action_waiting())
	a._queue.append({"kind": "move"})
	check(a.is_busy_for_action(), "una jugada en cola sí ocupa la mano")
	check(a._action_waiting(), "e interrumpe la pluma")
	a.free()


func test_partial_write_can_be_cancelled() -> void:
	var v := ScoresheetView.new()
	v.setup(W)
	v.add_entry(W, 1, "Nf3")
	v.show_partial(W, 0.5)
	check(v.line_text(W, 0) != "" and v.line_text(W, 0) != "1. Nf3", "a medias")
	check(v.has_pending(W), "sigue pendiente")
	check_eq(v.written_count(W), 0)
	v.clear_partial(W)
	check_eq(v.line_text(W, 0), "", "se borra lo escrito a medias")
	check(v.has_pending(W), "la entrada no se pierde")
	v.show_partial(W, 1.0)
	check_eq(v.line_text(W, 0), "1. Nf3")
	v.reveal_next(W, 0.0)
	check_eq(v.line_text(W, 0), "1. Nf3", "al retomar queda completa")
	check_eq(v.written_count(W), 1)
	check(not v.has_pending(W))
	v.free()


# --- Gestos de trampa continuos y escritura en paralelo del rival ------------------

func _tangent(pts: Array, i: int, u: float, e: float) -> Vector3:
	# Dirección de la curva de `HandAnimator._flow` entre los puntos i e i+1 en el parámetro u.
	var n := pts.size()
	var p0: Vector3 = pts[i - 1] if i > 0 else pts[0] * 2.0 - pts[1]
	var p3: Vector3 = pts[i + 2] if i + 2 < n else pts[n - 1] * 2.0 - pts[n - 2]
	return HandAnimator._catmull(p0, pts[i], pts[i + 1], p3, u + e) - HandAnimator._catmull(p0, pts[i], pts[i + 1], p3, u)


func test_carry_plan_is_one_continuous_curve() -> void:
	var grip_a := Vector3(0.1, BoardView.BOARD_TOP + 0.04, 0.1)
	var dest := Vector3(-0.1, BoardView.BOARD_TOP, -0.05)
	var plan := HandAnimator._plan_carry(grip_a, 0.04, dest)
	var wps: Array = plan.wps
	var grab: float = plan.grab_seg
	check(grab > 0.0 and grab < float(wps.size()), "el agarre ocurre a mitad de la curva, no al final")
	check(wps[int(grab) - 1].p.distance_to(grip_a) < 1e-6, "el punto de agarre es la pinza sobre la pieza")
	check(wps[-1].p.distance_to(Vector3(dest.x, dest.y + 0.044, dest.z)) < 1e-6, "acaba posando en el destino")
	for w in wps:
		check(float(w.w) > 0.0, "todo tramo avanza (peso de velocidad positivo)")
	# Sin cúspide en el agarre: la tangente de llegada y de salida apuntan casi igual (la mano no frena a cero).
	var pts: Array = [Vector3(0.3, 0.2, 0.3)]
	for w in wps:
		pts.append(w.p)
	var gi := int(grab)
	var tin := _tangent(pts, gi - 1, 1.0 - 1e-3, 1e-3)
	var tout := _tangent(pts, gi, 0.0, 1e-3)
	check(tin.length() > 1e-6 and tout.length() > 1e-6, "velocidad no nula en el agarre")
	check(tin.normalized().dot(tout.normalized()) > 0.5, "la mano no invierte el sentido al agarrar")


func test_nudge_plan_pushes_in_line() -> void:
	var start := Vector3(0.0, 0.02, 0.0)
	var delta := Vector3(0.05, 0.0, 0.05)
	var plan := HandAnimator._plan_nudge(start, 0.04, delta)
	var wps: Array = plan.wps
	check_eq(wps.size(), 3, "llegar, contacto y empujar: una sola curva")
	check(wps[2].p.distance_to(plan.contact + delta) < 1e-6, "acaba un paso más allá del contacto")
	check(wps[0].p.y > wps[1].p.y, "llega por encima y baja al contacto")
	check(plan.dir.distance_to(delta.normalized()) < 1e-6)


func test_cheat_lasts_what_server_says() -> void:
	var a := HandAnimator.new()
	a._clock = 10.0
	check(absf(a._cheat_total({"deadline": 12.5}) - 2.5) < 1e-6, "la curva dura lo que dicta el servidor")
	check(absf(a._cheat_total({"deadline": 9.0}) - HandAnimator.CHEAT_MIN_TIME) < 1e-6, "con retraso, el mínimo")
	a.free()


func test_abort_before_start_leaves_board_untouched() -> void:
	var b := BoardView.new()
	var a := HandAnimator.new()
	a.board = b
	var from_sq := ChessPiece.square_from_name("c3")
	var node := Node3D.new()
	b.pieces[from_sq] = node
	# Abortada antes de empezar: no hay gesto (la corrutina acaba sin esperar) y la pieza sigue en su casilla.
	var job := {"kind": "cheat", "cheat_kind": CheatDef.Kind.OWN_MOVE, "from": from_sq, "to": from_sq + 16, "distance": 2,
		"duration": 1.0, "deadline": 1.0, "resolved": true, "applied": false, "offset": Vector2.ZERO}
	a._run_cheat(job)
	check(b.pieces.get(from_sq) == node, "la pieza sigue en su casilla")
	a.free()
	node.free()
	b.free()


func test_rival_writes_in_parallel_with_actions() -> void:
	var a := HandAnimator.new()
	a.rig = HandRig.new()
	a.write_rig = HandRig.new()
	a._queue.append({"kind": "cheat"})  # una trampa en espera para la mano que juega
	check(a._parallel_write(), "escribe la otra mano")
	check(not a._write_should_abort(), "la trampa no interrumpe la pluma de la otra mano")
	check(a._goes_to_write_queue({"kind": "write"}), "la anotación va a su propia cola")
	check(not a._goes_to_write_queue({"kind": "move"}), "las acciones siguen en la cola de acciones")
	check(not a.is_busy_for_action() or a._action_waiting(), "la escritura no cuenta como acción")
	a._wqueue.append({"kind": "write"})
	check(a.is_busy(), "is_busy cuenta la escritura paralela")
	a._queue.clear()
	check(not a.is_busy_for_action(), "y no ocupa la mano que juega")
	# Con la misma mano (humano) se mantiene el comportamiento: la trampa interrumpe y la escritura espera.
	a._queue.append({"kind": "cheat"})
	a.write_rig = a.rig
	check(not a._parallel_write())
	check(a._write_should_abort(), "misma mano: la trampa interrumpe la pluma")
	check(not a._goes_to_write_queue({"kind": "write"}), "misma mano: la anotación va a la cola única")
	a.rig.free()
	a.free()
