extends TestCase
## Corte de ronda: elección de la última mesa y reparto del resto (`RoundCut`), cola del árbitro
## (`ExecutionQueue.peek_next/skip_pending`) y punto del discurso (`ArbiterRoutes.address_spot`).


func _unf(pairs: Array) -> Array:
	var out: Array = []
	for p in pairs:
		out.append({"table": p[0], "dist": p[1]})
	return out


func test_current_execution_wins() -> void:
	var r := RoundCut.plan(5, 7, _unf([[2, 1.0], [3, 4.0]]))
	check_eq(r.last_table, 5, "la que ejecuta ahora")
	check(not r.close_last)
	check_eq(r.silent, [2, 3] as Array[int], "las demás en juego, en silencio")


func test_queued_next_when_nothing_current() -> void:
	var r := RoundCut.plan(-1, 7, _unf([[2, 1.0]]))
	check_eq(r.last_table, 7)
	check(not r.close_last)
	check_eq(r.silent, [2] as Array[int])


func test_nearest_unfinished_is_closed() -> void:
	var r := RoundCut.plan(-1, -1, _unf([[4, 9.0], [2, 3.5], [6, 3.5], [8, 12.0]]))
	check_eq(r.last_table, 2, "la más cercana (empate: menor mesa)")
	check(r.close_last, "hay que cerrarla")
	check_eq(r.silent, [4, 6, 8] as Array[int])


func test_nothing_left() -> void:
	var r := RoundCut.plan(-1, -1, [])
	check_eq(r.last_table, -1)
	check(not r.close_last)
	check(r.silent.is_empty())


func test_queue_skip_pending_marks_done() -> void:
	var q := ExecutionQueue.new()
	q.push(1, 0, Vector3(1, 0, 1))
	q.push(2, 1, Vector3(5, 0, 5))
	q.push(3, 0, Vector3(9, 0, 9))
	check_eq(int(q.peek_next(Vector3.ZERO).table), 1, "peek no saca")
	check_eq(q.size(), 3)
	var skipped := q.skip_pending(2)
	check_eq(skipped.size(), 2)
	check_eq(q.size(), 1, "solo queda la mesa elegida")
	check(q.was_done(1, 0) and q.was_done(3, 0), "las descartadas cuentan como hechas")
	check(not q.was_done(2, 1))
	check(not q.push(1, 0, Vector3.ZERO), "no se vuelven a encolar")


func test_queue_drop_and_mark_done() -> void:
	var q := ExecutionQueue.new()
	q.push(4, 1, Vector3.ZERO)
	q.drop(4, 1)
	check(q.is_empty())
	q.mark_done(4, 1)
	check(q.was_done(4, 1))


func test_arbiter_resolve_silently_without_root() -> void:
	var a := Arbiter.new()
	a.queue.push(6, 0, Vector3.ZERO)
	a.resolve_silently(6, 0)
	check(not a.has_pending_work(), "ya no está pendiente")
	check(a.queue.was_done(6, 0))
	a.queue.push(7, 1, Vector3.ZERO)
	a.queue.push(8, 0, Vector3.ZERO)
	var skipped := a.skip_pending(8)
	check_eq(skipped.size(), 1)
	check_eq(a.queue.size(), 1)
	a.free()


func test_address_spot_in_aisle() -> void:
	for human in [HallLayout.human_table_for(16), HallLayout.human_table_for(8), HallLayout.human_table_for(4), 0]:
		HallLayout.set_human_table(human)
		var p := ArbiterRoutes.address_spot()
		check(p.z < -2.4 and p.z > -3.6, "unos 3 m delante del jugador")
		check(absf(p.x) > 0.9, "desplazado a un lado")
		for r in ArbiterRoutes.table_rects():
			check(not r.grow(0.3).has_point(Vector2(p.x, p.z)), "no cae sobre una mesa")
	HallLayout.set_human_table(HallLayout.human_table_for(16))
