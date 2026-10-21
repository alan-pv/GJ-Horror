extends TestCase
## Memoria del salón entre rondas (`HallMemory`) y pose final instantánea de las figuras.


func _board() -> PackedInt32Array:
	return BoardState.start_position().squares


func test_remember_and_read() -> void:
	HallMemory.clear()
	HallMemory.remember(9, _board(), ChessPiece.BLACK, {"jacket": Color.RED})
	check(HallMemory.has(9))
	check(HallMemory.has_corpse(9))
	check_eq(HallMemory.entry(9).seat, ChessPiece.BLACK)
	check_eq(HallMemory.entry(9).squares.size(), 64)
	check_eq(HallMemory.entry(9).look.jacket, Color.RED)
	HallMemory.remember(10, _board())
	check(HallMemory.has(10) and not HallMemory.has_corpse(10), "mesa sin ejecución: solo piezas")
	check(not HallMemory.has(3))
	check_eq(HallMemory.entry(3).size(), 0)


func test_remember_copies_data() -> void:
	HallMemory.clear()
	var sq := _board()
	HallMemory.remember(12, sq, 0, {})
	sq[0] = ChessPiece.NONE
	check(HallMemory.entry(12).squares[0] != ChessPiece.NONE, "guarda una copia")


func test_release_used_keeps_old_tables() -> void:
	HallMemory.clear()
	# Ronda 1: mesas 0..15 recordadas. La ronda 2 usa 0..7: se conservan las 8..15.
	for t in 16:
		HallMemory.remember(t, _board(), 1, {})
	HallMemory.release_used(8)
	check_eq(HallMemory.remembered(), [8, 9, 10, 11, 12, 13, 14, 15] as Array[int])


func test_accumulates_between_rounds() -> void:
	HallMemory.clear()
	for t in 16:
		HallMemory.remember(t, _board(), 1, {})
	HallMemory.release_used(8)         # empieza la ronda 2 (8 mesas)
	for t in 8:
		HallMemory.remember(t, _board(), 0, {})  # termina la ronda 2
	HallMemory.release_used(4)         # empieza la ronda 3 (4 mesas)
	check_eq(HallMemory.remembered().size(), 12, "4..7 de la ronda 2 y 8..15 de la 1")
	check_eq(HallMemory.entry(5).seat, 0, "la 5 es de la ronda 2")
	check_eq(HallMemory.entry(12).seat, 1, "la 12 sigue siendo de la ronda 1")
	check(not HallMemory.has(2), "la 2 se reutiliza")


func test_clear_for_new_tournament() -> void:
	HallMemory.remember(9, _board(), 1, {})
	HallMemory.clear()
	check(HallMemory.remembered().is_empty())


func test_tables_to_empty() -> void:
	HallMemory.clear()
	# Ronda 2 con 8 mesas (destino = índice 7). Recuerdos en 8..13; la 14 y la 15 nunca se usaron.
	for t in range(8, 14):
		HallMemory.remember(t, _board(), 1, {})
	var e := HallMemory.tables_to_empty(16, 8, 7)
	check(not e.has(7), "la destino la prepara el paseo")
	for t in 7:
		check(e.has(t), "la mesa %d se vacía" % t)
	for t in range(8, 14):
		check(not e.has(t), "la mesa %d conserva su recuerdo" % t)
	check(e.has(14) and e.has(15), "sin recuerdo = vacía")
	# Idempotente: llamar otra vez da lo mismo.
	check_eq(HallMemory.tables_to_empty(16, 8, 7), e)


func test_hold_final_pose_is_instant_and_held() -> void:
	var f := CharacterFigure.new()
	f.setup(CharacterFigure.random_look(RandomNumberGenerator.new()))
	check_eq(f.applied_look.size(), 7, "guarda el aspecto aplicado")
	f.hold_final_pose(&"death_slump_table")
	check_eq(f.current(), &"death_slump_table")
	check(f.is_finished(), "pose sostenida")
	var ap := f.animation_player()
	check(not ap.is_playing(), "en pausa")
	check_eq(ap.current_animation_position, ap.get_animation(&"death_slump_table").length, "último fotograma")
	f.free()


func test_hold_final_pose_matches_played_clip() -> void:
	var look := CharacterFigure.random_look(RandomNumberGenerator.new())
	var a := CharacterFigure.new()
	a.setup(look)
	a.hold_final_pose(&"death_slump_table")
	var b := CharacterFigure.new()
	b.setup(look)
	b.play(&"death_slump_table", 0.0)
	b.animation_player().advance(b.animation_player().get_animation(&"death_slump_table").length + 0.5)
	var sa: Skeleton3D = a._skeleton
	var sb: Skeleton3D = b._skeleton
	for bone in ["Head", "Hips", "Spine"]:
		var i := sa.find_bone(bone)
		if i < 0:
			continue
		check(sa.get_bone_pose(i).origin.distance_to(sb.get_bone_pose(sb.find_bone(bone)).origin) < 0.01, "%s: misma pose que el clip terminado" % bone)
		check(sa.get_bone_pose(i).basis.get_rotation_quaternion().angle_to(sb.get_bone_pose(i).basis.get_rotation_quaternion()) < 0.05, "%s: misma rotación" % bone)
	a.free()
	b.free()
