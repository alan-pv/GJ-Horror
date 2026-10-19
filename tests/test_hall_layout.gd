extends TestCase


func test_human_table_is_origin() -> void:
	check_eq(HallLayout.table_position(HallLayout.HUMAN_TABLE), Vector3.ZERO, "humano en el origen")
	check_eq(HallLayout.table_count(), 16)
	check_eq(HallLayout.table_count(), HallLayout.COLS * HallLayout.ROWS)


func test_grid_positions() -> void:
	# Fila 0 es la más lejana (-Z): dos filas delante del humano.
	check_eq(HallLayout.table_position(0), Vector3(-HallLayout.SPACING_X, 0.0, -2.0 * HallLayout.SPACING_Z))
	check_eq(HallLayout.table_position(3), Vector3(2.0 * HallLayout.SPACING_X, 0.0, -2.0 * HallLayout.SPACING_Z))
	check_eq(HallLayout.table_position(13), Vector3(0.0, 0.0, HallLayout.SPACING_Z), "una fila detrás")
	var seen := {}
	for i in 16:
		seen[HallLayout.table_position(i)] = true
	check_eq(seen.size(), 16, "posiciones distintas")


func test_tables_by_distance() -> void:
	var order := HallLayout.tables_by_distance()
	check_eq(order.size(), 16)
	check_eq(order[0], HallLayout.HUMAN_TABLE, "la primera es la del humano")
	for i in range(1, order.size()):
		check(HallLayout.table_position(order[i - 1]).length() <= HallLayout.table_position(order[i]).length() + 0.0001, "orden creciente")
	check_eq(order, HallLayout.tables_by_distance(), "estable")
