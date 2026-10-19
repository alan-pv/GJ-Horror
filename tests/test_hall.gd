extends TestCase


func test_hall_builds_sixteen_tables() -> void:
	var hall := Hall.new()
	hall.build()
	check_eq(hall.table_count(), 16)
	for i in 16:
		check_eq(hall.table_position(i), HallLayout.table_position(i), "posición de la mesa %d" % i)
		check(hall.table_lamp(i) != null, "lámpara %d" % i)
		check(hall.chair(i, 0) != null and hall.chair(i, 1) != null, "sillas %d" % i)
	# Solo la lámpara de la mesa del humano proyecta sombras.
	for i in 16:
		check_eq(hall.table_lamp(i).shadow_enabled, i == HallLayout.HUMAN_TABLE, "sombras de la mesa %d" % i)
	check_eq(hall.spot, hall.table_lamp(HallLayout.HUMAN_TABLE))
	hall.free()


func test_seat_transform_faces_table() -> void:
	var hall := Hall.new()
	hall.build()
	var w := hall.seat_transform(3, ChessPiece.WHITE)
	var b := hall.seat_transform(3, ChessPiece.BLACK)
	check(w.origin.z > hall.table_position(3).z, "blancas en +Z")
	check(b.origin.z < hall.table_position(3).z, "negras en -Z")
	check((w.basis * Vector3.BACK).z < -0.9, "la figura blanca mira a -Z")
	check((b.basis * Vector3.BACK).z > 0.9, "la figura negra mira a +Z")
	hall.free()


func test_table_level() -> void:
	var hall := Hall.new()
	hall.build()
	hall.set_table_active(2, false, false)
	check(not hall.table_lamp(2).visible, "apagada")
	check_eq(hall.table_level(2), 0.0)
	hall.set_table_level(2, 0.5, false)
	check(hall.table_lamp(2).visible, "tenue")
	hall.free()


func test_mid_game_fens_are_valid() -> void:
	for fen in StaticBoard.MID_GAME_FENS:
		var b := BoardState.from_fen(fen)
		var kings := [0, 0]
		for p in b.squares:
			if ChessPiece.type_of(p) == ChessPiece.KING:
				kings[ChessPiece.color_of(p)] += 1
		check_eq(kings, [1, 1], fen)


func test_mesh_baker_groups_by_material() -> void:
	var baker := MeshBaker.new()
	var m1 := StandardMaterial3D.new()
	var m2 := StandardMaterial3D.new()
	baker.add_box(Vector3.ONE, Transform3D.IDENTITY, m1)
	baker.add_box(Vector3.ONE, Transform3D(Basis.IDENTITY, Vector3(2, 0, 0)), m1)
	baker.add_box(Vector3.ONE, Transform3D.IDENTITY, m2)
	var mesh := baker.build()
	check_eq(mesh.get_surface_count(), 2)
	check_eq(baker.triangle_count(), 36)


func test_background_table_without_match() -> void:
	var hall := Hall.new()
	hall.build()
	var bt := BackgroundTable.new()
	hall.table_root(4).add_child(bt)
	bt.setup(hall, 4, null, [true, false], 1)
	check(bt.figure(0) != null, "figura blanca")
	check(bt.figure(1) == null, "asiento negro vacío")
	var f := bt.condemn(0)
	check(f != null, "condenada")
	check_eq(bt.stage_of(0), &"condemned")
	hall.free()
