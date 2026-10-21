extends TestCase
## La mesa del humano es una variable estática: cada prueba la restaura al terminar.

const DEFAULT_TABLE := 15


func _restore() -> void:
	HallLayout.set_human_table(DEFAULT_TABLE)


func test_human_table_is_origin_for_every_table() -> void:
	check_eq(HallLayout.table_count(), 16)
	check_eq(HallLayout.table_count(), HallLayout.COLS * HallLayout.ROWS)
	for h in 16:
		HallLayout.set_human_table(h)
		check_eq(HallLayout.table_position(h), Vector3.ZERO, "humano en el origen (mesa %d)" % (h + 1))
		check_eq(HallLayout.human_table, h)
	_restore()


func test_numbering_rows_and_podium() -> void:
	# Mesas 1-4 en la fila del fondo (la más lejana, z menor) y 13-16 en la más cercana.
	for i in 16:
		check_eq(HallLayout.cell_of(i).y, i / 4, "fila de la mesa %d" % (i + 1))
		check_eq(HallLayout.number_of(i), i + 1)
		check_eq(HallLayout.index_at(HallLayout.cell_of(i).x, HallLayout.cell_of(i).y), i, "ida y vuelta")
	check(HallLayout.grid_position(0).z < HallLayout.grid_position(15).z, "la 1 está más al fondo que la 16")
	# Las mesas 1 y 2 en el centro de la fila 0; la 3 a la izquierda y la 4 a la derecha.
	check_eq(HallLayout.cell_of(0).x, 1)
	check_eq(HallLayout.cell_of(1).x, 2)
	check_eq(HallLayout.cell_of(2).x, 0)
	check_eq(HallLayout.cell_of(3).x, 3)
	var seen := {}
	for i in 16:
		seen[HallLayout.grid_position(i)] = true
	check_eq(seen.size(), 16, "posiciones distintas")
	check(HallLayout.is_podium(0) and HallLayout.is_podium(1), "1 y 2 en el podio")
	check(not HallLayout.is_podium(2) and not HallLayout.is_podium(15))


func test_relative_positions() -> void:
	HallLayout.set_human_table(15)
	# La 16 es la celda (3, 3): la 1 está 3 filas delante (-Z) y 2 columnas a la izquierda.
	check_eq(HallLayout.table_position(0), Vector3(-2.0 * HallLayout.SPACING_X, 0.0, -3.0 * HallLayout.SPACING_Z))
	check_eq(HallLayout.table_position(3), Vector3(0.0, 0.0, -3.0 * HallLayout.SPACING_Z), "la 4, justo delante")
	HallLayout.set_human_table(0)
	check_eq(HallLayout.table_position(15), Vector3(2.0 * HallLayout.SPACING_X, 0.0, 3.0 * HallLayout.SPACING_Z), "la 16 desde la 1")
	# Las posiciones relativas cambian solo por un desplazamiento común.
	HallLayout.set_human_table(7)
	var d := HallLayout.table_position(3) - HallLayout.table_position(7)
	HallLayout.set_human_table(12)
	check((HallLayout.table_position(3) - HallLayout.table_position(7)).is_equal_approx(d), "la disposición no se deforma")
	_restore()


func test_room_offset_puts_human_table_at_origin() -> void:
	for h in 16:
		HallLayout.set_human_table(h)
		# Posición de la mesa en el mundo = desplazamiento de la sala + su posición en el marco de la sala.
		var world := HallLayout.room_offset() + HallLayout.room_position(h)
		check(Vector2(world.x, world.z).length() < 0.0001, "la mesa %d queda en el origen" % (h + 1))
		for i in 16:
			var w := HallLayout.room_offset() + HallLayout.room_position(i)
			check_eq(Vector2(w.x, w.z), Vector2(HallLayout.table_position(i).x, HallLayout.table_position(i).z), "coherencia mesa %d" % (i + 1))
	HallLayout.set_human_table(0)
	check(is_equal_approx(HallLayout.room_offset().y, -HallLayout.PODIUM_HEIGHT), "con el humano en el podio la sala baja")
	HallLayout.set_human_table(15)
	check_eq(HallLayout.room_offset().y, 0.0)
	_restore()


func test_floor_height_follows_podium() -> void:
	HallLayout.set_human_table(15)
	check_eq(HallLayout.floor_y(Vector3.ZERO), 0.0, "suelo bajo el humano")
	check(is_equal_approx(HallLayout.floor_y(HallLayout.table_position(0)), HallLayout.PODIUM_HEIGHT), "la mesa 1 sobre la tarima")
	check(is_equal_approx(HallLayout.floor_y(HallLayout.table_position(1)), HallLayout.PODIUM_HEIGHT), "la mesa 2 sobre la tarima")
	check_eq(HallLayout.floor_y(HallLayout.table_position(3)), 0.0, "la 4 al nivel del suelo")
	# Fuera del podio y en una rampa (a medio camino del borde).
	var edge := HallLayout.table_position(0) + Vector3(-(HallLayout.SPACING_X * 0.5 - HallLayout.PODIUM_RAMP * 0.5), 0.0, 0.0)
	var y := HallLayout.floor_y(edge)
	check(y > 0.0 and y < HallLayout.PODIUM_HEIGHT, "la rampa sube poco a poco: %f" % y)
	# Con el humano sobre el podio su suelo es el cero y el resto baja.
	HallLayout.set_human_table(1)
	check_eq(HallLayout.floor_y(Vector3.ZERO), 0.0)
	check(is_equal_approx(HallLayout.floor_y(HallLayout.table_position(15)), -HallLayout.PODIUM_HEIGHT), "abajo del podio")
	_restore()


func test_richness_grows_toward_table_1() -> void:
	check_eq(HallLayout.richness(0), 3)
	check_eq(HallLayout.richness(1), 3)
	check_eq(HallLayout.richness(2), 2)
	check_eq(HallLayout.richness(3), 2)
	check_eq(HallLayout.richness(15), 0)
	for i in range(1, 16):
		check(HallLayout.richness(i) <= HallLayout.richness(i - 1), "nunca más rica que la anterior (mesa %d)" % (i + 1))


func test_human_table_for_round_size() -> void:
	check_eq(HallLayout.human_table_for(16), 15)
	check_eq(HallLayout.human_table_for(8), 7)
	check_eq(HallLayout.human_table_for(1), 0)
	check_eq(HallLayout.human_table_for(40), 15, "tope")
	check_eq(HallLayout.human_table_for(0), 0)


func test_human_path_is_readable() -> void:
	# Con 32 jugadores el humano sube 16 -> 8 -> 4 -> 2 -> 1: nunca baja de fila ni se aleja del podio.
	var path := [15, 7, 3, 1, 0]
	for k in range(1, path.size()):
		var a := HallLayout.cell_of(path[k - 1])
		var b := HallLayout.cell_of(path[k])
		check(b.y <= a.y, "no retrocede de fila (%d -> %d)" % [path[k - 1] + 1, path[k] + 1])
	check_eq(HallLayout.cell_of(15).x, 3, "arranca en el lado derecho")


func test_tables_by_distance() -> void:
	HallLayout.set_human_table(5)
	var order := HallLayout.tables_by_distance()
	check_eq(order.size(), 16)
	check_eq(order[0], 5, "la primera es la del humano")
	for i in range(1, order.size()):
		check(HallLayout.table_position(order[i - 1]).length() <= HallLayout.table_position(order[i]).length() + 0.0001, "orden creciente")
	_restore()


func test_walk_route_ends_at_destination_seat_and_avoids_tables() -> void:
	# Todas las parejas de mesas con la mesa del humano en `from`: la ruta no cruza mesas ajenas y
	# acaba en la silla (lado +Z) de la mesa destino.
	for from in 16:
		HallLayout.set_human_table(from)
		for to in 16:
			if to == from:
				check(HallWalk.route(from, to).is_empty(), "misma mesa sin paseo")
				continue
			var path := HallWalk.route(from, to)
			check(not path.is_empty(), "hay ruta %d -> %d" % [from + 1, to + 1])
			var goal := HallWalk.seat_point(to)
			check(Vector2(path[path.size() - 1].x - goal.x, path[path.size() - 1].z - goal.z).length() < 0.001, "acaba en la silla %d" % (to + 1))
			check(not HallWalk.is_blocked(from, to, path), "no cruza mesas %d -> %d" % [from + 1, to + 1])
	HallLayout.set_human_table(DEFAULT_TABLE)


func test_walk_route_of_the_32_player_tournament() -> void:
	var steps := [[15, 7], [7, 3], [3, 1], [1, 0]]
	for st in steps:
		HallLayout.set_human_table(st[0])
		var path := HallWalk.route(st[0], st[1])
		check(not HallWalk.is_blocked(st[0], st[1], path), "ruta %d -> %d libre" % [st[0] + 1, st[1] + 1])
		var meters := HallWalk.length(st[0], path)
		check(meters > 2.0 and meters < 25.0, "longitud razonable (%.1f m)" % meters)
	# Subir al podio sube el suelo al final del trayecto.
	HallLayout.set_human_table(3)
	var up := HallWalk.route(3, 1)
	check(is_equal_approx(up[up.size() - 1].y, HallLayout.PODIUM_HEIGHT), "la silla de la 2 está sobre la tarima")
	HallLayout.set_human_table(DEFAULT_TABLE)
