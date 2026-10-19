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
