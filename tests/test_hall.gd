extends TestCase


func test_hall_builds_sixteen_tables() -> void:
	HallLayout.set_human_table(15)
	var hall := Hall.new()
	hall.build()
	check_eq(hall.table_count(), 16)
	for i in 16:
		check_eq(hall.table_position(i), HallLayout.table_position(i), "posición de la mesa %d" % i)
		check(hall.table_lamp(i) != null, "lámpara %d" % i)
		check(hall.chair(i, 0) != null and hall.chair(i, 1) != null, "sillas %d" % i)
	# Solo la lámpara de la mesa del humano proyecta sombras.
	for i in 16:
		check_eq(hall.table_lamp(i).shadow_enabled, i == HallLayout.human_table, "sombras de la mesa %d" % i)
	check_eq(hall.spot, hall.table_lamp(HallLayout.human_table))
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


func test_hall_shifts_room_around_human_table() -> void:
	for h in [0, 1, 3, 7, 15]:
		HallLayout.set_human_table(h)
		var hall := Hall.new()
		hall.build()
		check_eq(hall.table_position(h), Vector3.ZERO, "la mesa %d en el origen" % (h + 1))
		var root := hall.table_root(h)
		check(absf(root.position.y) < 0.0001, "su suelo es el cero")
		check_eq(hall.spot, hall.table_lamp(h), "sombras en la mesa del humano")
		var room := hall.get_node("Sala") as Node3D
		check(room.position.is_equal_approx(HallLayout.room_offset()), "sala desplazada")
		# Cada mesa en su sitio y con la altura del podio relativa a la del humano.
		for i in 16:
			var r := hall.table_root(i)
			check(Vector2(r.position.x, r.position.z).is_equal_approx(Vector2(HallLayout.table_position(i).x, HallLayout.table_position(i).z)))
			var want := HallLayout.floor_height(i) - HallLayout.floor_height(h)
			check(is_equal_approx(r.position.y, want), "altura de la mesa %d" % (i + 1))
			check(r.get_node_or_null("Tarjeta/Numero") != null, "número en la mesa %d" % (i + 1))
			check_eq((r.get_node("Tarjeta/Numero") as Label3D).text, str(i + 1))
		hall.free()
	HallLayout.set_human_table(15)


func test_podium_and_rich_tables() -> void:
	HallLayout.set_human_table(15)
	var hall := Hall.new()
	hall.build()
	var room := hall.get_node("Sala") as Node3D
	check(room.get_node_or_null("Podio0") != null and room.get_node_or_null("Podio1") != null, "podio en dos mallas")
	# Las mesas ricas llevan más geometría fusionada que las sencillas.
	var plain := (hall.table_root(15).get_node("MesaBase") as MeshInstance3D).mesh.get_faces().size()
	var rich := (hall.table_root(1).get_node("MesaBase") as MeshInstance3D).mesh.get_faces().size()
	check(rich > plain, "la mesa 2 tiene más detalle que la 16")
	var mid := (hall.table_root(5).get_node("MesaBase") as MeshInstance3D).mesh.get_faces().size()
	check(mid > plain and mid < rich, "el lujo crece por tramos")
	hall.free()
