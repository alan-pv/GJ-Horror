extends TestCase
## Lógica pura del árbitro: cola de ejecuciones, rutas por pasillos y pasos.


func test_queue_nearest_first() -> void:
	var q := ExecutionQueue.new()
	q.push(0, 0, Vector3(10, 0, 10))
	q.push(1, 0, Vector3(1, 0, 1))
	q.push(2, 0, Vector3(5, 0, 5))
	check_eq(int(q.take_next(Vector3.ZERO).table), 1, "la más cercana primero")
	check_eq(int(q.take_next(Vector3(5, 0, 5)).table), 2, "después la más cercana a su posición")
	check_eq(int(q.take_next(Vector3.ZERO).table), 0)
	check(q.take_next(Vector3.ZERO).is_empty(), "vacía")


func test_queue_priority_and_duplicates() -> void:
	var q := ExecutionQueue.new()
	q.push(3, 1, Vector3(1, 0, 1))
	check(q.push(9, 1, Vector3(50, 0, 50), true), "la del humano entra")
	check(not q.push(9, 1, Vector3(50, 0, 50), true), "sin duplicados en cola")
	check_eq(int(q.take_next(Vector3.ZERO).table), 9, "la prioritaria va primero aunque esté lejos")
	check(not q.push(9, 1, Vector3.ZERO), "tampoco mientras está en curso")
	q.finish()
	check(q.was_done(9, 1), "hecha")
	check(not q.push(9, 1, Vector3.ZERO), "ni después de hecha")


func test_queue_busy() -> void:
	var q := ExecutionQueue.new()
	check(not q.busy(), "libre")
	q.push(1, 0, Vector3.ZERO)
	check(q.busy(), "pendiente")
	var e := q.take_next(Vector3.ZERO)
	check(q.busy(), "en curso")
	q.requeue(e)
	check_eq(q.size(), 1, "se devuelve a la cola")
	q.take_next(Vector3.ZERO)
	q.finish()
	check(not q.busy(), "libre al terminar")


func test_arbiter_pending_work() -> void:
	var a := Arbiter.new()
	check(not a.has_pending_work(), "sin trabajo")
	a.begin_accusation(0)
	check(a.has_pending_work(), "acusación pendiente")
	check(a.accusation_active(), "acusación activa")
	a.free()


func test_aisles_between_tables() -> void:
	check_eq(ArbiterRoutes.aisle_xs().size(), HallLayout.COLS + 1)
	check_eq(ArbiterRoutes.aisle_zs().size(), HallLayout.ROWS + 1)
	# Ninguna intersección cae dentro de una mesa.
	for n in ArbiterRoutes.nodes():
		check(not ArbiterRoutes.segment_hits_table(n, n + Vector3(0.01, 0, 0)), "nodo libre %s" % n)
	# Pasillo de la espalda del jugador entre la mesa del humano y la fila de atrás.
	check_eq(ArbiterRoutes.behind_player_z(), 1.6)


func _route_clear(from: Vector3, path: Array[Vector3]) -> bool:
	var prev := from
	for p in path:
		if ArbiterRoutes.segment_hits_table(prev, p):
			return false
		prev = p
	return true


func test_routes_never_cross_tables() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var nodes := ArbiterRoutes.nodes()
	for i in 60:
		var a: Vector3 = nodes[rng.randi() % nodes.size()]
		var b: Vector3 = nodes[rng.randi() % nodes.size()]
		var path := ArbiterRoutes.route(a, b)
		check(_route_clear(a, path), "ruta %s -> %s libre" % [a, b])
		if a.distance_to(b) > 0.1:
			check(not path.is_empty() and path[path.size() - 1].distance_to(b) < 0.05, "llega")


func test_routes_to_every_execution_spot() -> void:
	var start := Vector3(ArbiterRoutes.aisle_xs()[0], 0.0, ArbiterRoutes.aisle_zs()[0])
	for t in HallLayout.table_count():
		for seat in 2:
			for color in 2:
				var spot := ArbiterRoutes.execution_spot(t, seat, color)
				var path := ArbiterRoutes.route(start, spot)
				check(_route_clear(start, path), "mesa %d asiento %d libre" % [t, seat])
				check(path[path.size() - 1].distance_to(spot) < 0.05, "llega al punto")
				# Y de vuelta desde el punto a la red.
				check(_route_clear(spot, ArbiterRoutes.route(spot, start)), "vuelta libre")


func test_route_to_human_side_and_seat_spots() -> void:
	var start := Vector3(ArbiterRoutes.aisle_xs()[4], 0.0, ArbiterRoutes.aisle_zs()[0])
	check(_route_clear(start, ArbiterRoutes.route(start, ArbiterRoutes.HUMAN_SIDE_SPOT)), "al lado del humano")
	# Junto a cada condenado sentado, el árbitro llega sin cruzar mesas.
	for t in HallLayout.table_count():
		for seat in 2:
			var s := ArbiterRoutes.seat_position(t, seat, 0)
			var spot := s + Vector3(ArbiterRoutes.SIDE_OFFSET, 0, 0)
			check(_route_clear(start, ArbiterRoutes.route(start, spot)), "asiento mesa %d asiento %d" % [t, seat])


func test_behind_player_route() -> void:
	var from := Vector3(ArbiterRoutes.aisle_xs()[0], 0.0, ArbiterRoutes.aisle_zs()[0])
	var path := ArbiterRoutes.behind_player_route(from)
	check(_route_clear(from, path), "libre")
	var passes := false
	var prev := from
	for p in path:
		# Algún tramo recorre el pasillo de la espalda del jugador.
		if is_equal_approx(prev.z, 1.6) and is_equal_approx(p.z, 1.6) and absf(p.x - prev.x) > 1.0:
			passes = true
		prev = p
	check(passes, "cruza por detrás de la silla")


func test_seat_sign() -> void:
	check_eq(ArbiterRoutes.seat_sign(3, ChessPiece.WHITE, ChessPiece.WHITE), 1.0, "blancas en +Z")
	check_eq(ArbiterRoutes.seat_sign(3, ChessPiece.BLACK, ChessPiece.WHITE), -1.0, "negras en -Z")
	check_eq(ArbiterRoutes.seat_sign(HallLayout.human_table, ChessPiece.BLACK, ChessPiece.BLACK), 1.0, "el humano siempre en +Z")
	check_eq(ArbiterRoutes.seat_sign(HallLayout.human_table, ChessPiece.WHITE, ChessPiece.BLACK), -1.0, "su rival en -Z")


func test_footstep_attenuation() -> void:
	# Se oye cada vez menos al alejarse, claramente audible de cerca y a media sala, mudo muy lejos.
	var prev := 100.0
	for d in [1.0, 2.0, 4.0, 8.0, 16.0, 24.0]:
		var g := Arbiter.footstep_gain_db(d)
		check(g < prev or is_equal_approx(g, prev), "baja con la distancia (%.0f m = %.1f dB)" % [d, g])
		prev = g
	check(Arbiter.footstep_gain_db(2.0) - Arbiter.footstep_gain_db(16.0) > 12.0, "diferencia audible al acercarse")
	check(Arbiter.footstep_gain_db(10.0) > -15.0, "a 10 m aún se oye")
	check(Arbiter.footstep_gain_db(40.0) <= -80.0, "más allá del máximo, silencio")
