extends TestCase
## Inclinación del torso al alcanzar casillas lejanas: la espalda se mantiene casi recta (la
## inclinación sale sobre todo de la pelvis), la cabeza no baja hasta la mesa y todo sigue al
## alcance (casillas, reloj, pila de capturas y planilla).

const TABLE_TOP := 0.72
## Cabeza mínima sobre la mesa (m) y curvatura máxima por hueso de la columna (grados).
const HEAD_MIN := 0.25
const SPINE_MAX_DEG := 14.0
## Error máximo de la pinza respecto del objetivo (m).
const REACH_TOL := 0.06


func test_shares_sum_to_one_and_back_stays_straight() -> void:
	var s: Dictionary = TorsoLeanModifier.SHARES
	var total: float = float(s["Hips"]) + float(s["Spine"]) + float(s["Chest"])
	check(absf(total - 1.0) < 0.001, "Hips+Spine+Chest debe sumar 1 (suma %.3f)" % total)
	check(float(s["Hips"]) >= 0.4, "la pelvis lleva la mayor parte de la inclinación")
	for bone in ["Spine", "Chest"]:
		var deg := rad_to_deg(HandRig.LEAN_MAX * float(s[bone]))
		check(deg <= SPINE_MAX_DEG, "%s se curva %.1f° con el tope (máx %.0f°)" % [bone, deg, SPINE_MAX_DEG])
	check(HandRig.LEAN_MAX <= 0.75, "tope de inclinación bajo")


## Ángulo (grados) de la rotación local de un hueso respecto de su reposo en la animación.
func _bone_deg(f: SeatedFigure, bone: StringName) -> float:
	var sk := f.skeleton()
	var i := sk.find_bone(bone)
	return rad_to_deg((sk.get_bone_pose_rotation(i) * sk.get_bone_rest(i).basis.get_rotation_quaternion().inverse()).get_angle())


func test_far_reaches_keep_head_up_and_reachable() -> void:
	await tree.process_frame
	var board := BoardView.new()
	tree.root.add_child(board)
	board.setup(ChessPiece.WHITE)
	var worst_head := 99.0
	var worst_err := 0.0
	var worst_bone := 0.0
	for who in 2:
		var fig := SeatedFigure.new()
		fig.lean_speed = 1000.0
		tree.root.add_child(fig)
		var rig := HandRig.new()
		tree.root.add_child(rig)
		var sgn := 1.0
		if who == 0:
			fig.position = Vector3(0, 0, 0.8)
			fig.rotation.y = PI
			fig.play(&"sit_idle", 0.0)
			rig.setup(fig, &"R")
		else:
			fig.position = Vector3(0, 0, -0.8)
			sgn = -1.0
			fig.play(&"sit_idle", 0.0)
			rig.setup(fig, &"L")
		rig.set_active(true, 0.0)
		var targets: Array[Vector3] = []
		for sq in [0, 7, 56, 63, 3, 59, 28, 35]:  # esquinas, centro y bordes
			targets.append(board.square_to_world(sq) + Vector3(0, 0.07, 0))
		targets.append(Vector3(0.42, 0.83, sgn * 0.06))    # botón del reloj
		targets.append(Vector3(0.58, 0.745, sgn * 0.30))   # pila de capturas
		targets.append(Vector3(0.16, 0.78, sgn * 0.44))    # planilla
		for t in targets:
			for pitch in [40.0, 58.0]:
				rig.set_grip(t, pitch)
				for i in 4:
					await tree.process_frame
				worst_head = minf(worst_head, fig.head_global_position().y - TABLE_TOP)
				worst_err = maxf(worst_err, rig.carry_anchor.global_position.distance_to(t))
				for bone in [&"Spine", &"Chest"]:
					worst_bone = maxf(worst_bone, _bone_deg(fig, bone))
				check(fig.shift_now() <= HandRig.SHIFT_MAX + 0.001, "adelanto de cadera dentro del tope")
		fig.queue_free()
		rig.queue_free()
	board.queue_free()
	check(worst_head >= HEAD_MIN, "cabeza a %.3f m de la mesa (mín %.2f)" % [worst_head, HEAD_MIN])
	check(worst_err <= REACH_TOL, "alguna casilla/objeto no llega: error %.3f m" % worst_err)
	check(worst_bone <= SPINE_MAX_DEG, "Spine/Chest se curvan %.1f° respecto del reposo" % worst_bone)
