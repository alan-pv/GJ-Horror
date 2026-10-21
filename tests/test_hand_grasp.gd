extends TestCase
## Agarres por pieza (`PieceFactory.grasp_for`), dedos individuales (`ArmPoseModifier`) y cierre
## hasta tocar la superficie, con el esqueleto real de `player.glb` y con uno sintético de huesos
## viejos (`Fingers` / `Thumb`). Corre fuera del árbol: el modificador se invoca a mano.

const TYPES := [ChessPiece.PAWN, ChessPiece.ROOK, ChessPiece.KNIGHT, ChessPiece.BISHOP, ChessPiece.QUEEN, ChessPiece.KING]
## Tolerancia de contacto (m): yema a menos de esto de la superficie, sin penetrar.
const TOUCH_TOL := 0.003
const PENETRATION := 0.0008


func _figure() -> SeatedFigure:
	var f := SeatedFigure.new()
	f.setup(CharacterFigure.bot_look(RandomNumberGenerator.new(), {}))
	f.play(&"sit_idle", 0.0)
	f.animation_player().advance(0.0)
	f.skeleton().force_update_all_bone_transforms()  # fuera del árbol las globales no se recalculan solas
	return f


## Distancia (con signo) de un punto del mundo a la superficie de revolución del agarre.
func _surface_dist(g: Dictionary, base: Vector3, p: Vector3) -> float:
	var rel := p - base
	var s: float = rel.y
	var rho := Vector2(rel.x, rel.z).length()
	var prof: PackedFloat32Array = g.profile
	var fi := maxf(s, 0.0) / float(g.step)
	var i := int(fi)
	if i >= prof.size() - 1:
		return rho
	return rho - lerpf(prof[i], prof[i + 1], fi - float(i))


## Transformación global (espacio del esqueleto) de `bone` calculada a partir de las poses locales
## que dejó el modificador (fuera del árbol el esqueleto no recalcula las globales).
func _global_of(sk: Skeleton3D, bone: int) -> Transform3D:
	var chain: Array[int] = []
	var i := bone
	while i >= 0:
		chain.push_front(i)
		i = sk.get_bone_parent(i)
	var t := Transform3D.IDENTITY
	for b in chain:
		t = t * Transform3D(Basis(sk.get_bone_pose_rotation(b)), sk.get_bone_pose_position(b))
	return t


## Pone `mod` (mano de `side`) en un agarre de `piece` con la mano orientada y los datos de dedos
## como en el juego (plan de pinza incluido) y lo deja converger. Devuelve {base, basis, origin}.
func _grasp_pose(f: SeatedFigure, mod: ArmPoseModifier, piece: int, side: StringName = &"R") -> Dictionary:
	var g := PieceFactory.grasp_for(piece)
	var pal := 1.0 if side == &"R" else -1.0
	var basis := HandRig.basis_for(Vector3(0, 0, -1), deg_to_rad(float(g.pitch)), deg_to_rad(float(g.roll)) * pal, pal)
	mod.hand_basis = basis
	mod.controlled = true
	var sk := f.skeleton()
	var hand_idx := sk.find_bone("Hand." + side)
	mod._process_modification()  # fija la rotación de la mano
	var origin := _global_of(sk, hand_idx).origin
	var plan := mod.pinch_plan(float(g.radius), deg_to_rad(float(g.pitch)), deg_to_rad(float(g.roll)), 0.0, Vector3.ZERO, float(g.opposition))
	var pinch: Vector3 = origin + basis * (plan.a as Vector3)
	var base := pinch - Vector3(0, float(g.height), 0)
	var gd := {
		"axis_point": base, "axis_dir": Vector3.UP, "profile": g.profile, "step": g.step,
		"contact": g.contact, "weight": 1.0, "relax": 0.7,
		"thumb_swing": float(plan.sw), "plan_ci": float(plan.ci), "plan_ct": float(plan.ct),
	}
	mod.grasp = gd
	for i in 12:
		mod._process_modification()
	return {"base": base, "basis": basis, "origin": origin}


func test_grasp_data_for_every_piece() -> void:
	for t in TYPES:
		var g := PieceFactory.grasp_for(t)
		var name := ChessPiece.to_char(t)
		check(float(g.height) > 0.0 and float(g.height) < float(g.top), "altura dentro de la pieza " + name)
		check(float(g.radius) > 0.006 and float(g.radius) < 0.03, "radio medido plausible " + name)
		check(ArmPoseModifier.THUMB in g.contact and ArmPoseModifier.INDEX in g.contact, "pulgar e índice tocan " + name)
		check((g.profile as PackedFloat32Array).size() > 3, "perfil de radios " + name)
		check_eq(PieceFactory.grip_height(t), float(g.height), "grip_height = altura del agarre " + name)
	# La corona del rey y la dama se agarra más alto que el cuerpo del peón y la torre.
	check(PieceFactory.grasp_for(ChessPiece.KING).height > PieceFactory.grasp_for(ChessPiece.ROOK).height)
	# Los reyes también tienen agarre (las trampas pueden moverlos).
	check_eq(PieceFactory.grasp_for(ChessPiece.make(ChessPiece.WHITE, ChessPiece.KING)).type, ChessPiece.KING)


func test_profile_comes_from_mesh() -> void:
	# El peón tiene la cabeza redonda (~11 mm de radio) y el cuello más fino; la base ~20 mm.
	var head := PieceFactory.radius_at(ChessPiece.PAWN, 0.030)
	var base := PieceFactory.radius_at(ChessPiece.PAWN, 0.001)
	check(head > 0.009 and head < 0.014, "cabeza del peón %.1f mm" % (head * 1000.0))
	check(base > 0.017 and base < 0.022, "base del peón %.1f mm" % (base * 1000.0))
	check(PieceFactory.radius_at(ChessPiece.KING, 0.062) > 0.014, "corona del rey")


func test_five_finger_chains_read_from_skeleton() -> void:
	var f := _figure()
	var mod := f.arm_pose_modifier(&"R")
	check(mod.ready_for_queries())
	check(not mod.is_legacy(), "esqueleto de cinco dedos")
	for i in 5:
		var ch := mod.chain(i)
		check(ch != null and ch.bones.size() == 3, "tres falanges " + ArmPoseModifier.FINGER_NAMES[i])
		check(ch.tip_len > 0.01 and ch.tip_len < 0.035, "yema medida " + ArmPoseModifier.FINGER_NAMES[i])
	# Longitudes de falange leídas del reposo: la del medio es la más larga.
	check(mod.chain(ArmPoseModifier.MIDDLE).rest[1].origin.length() > mod.chain(ArmPoseModifier.INDEX).rest[1].origin.length())
	f.free()


func test_each_finger_flexes_independently() -> void:
	var f := _figure()
	var mod := f.arm_pose_modifier(&"R")
	mod.controlled = true
	mod.curls = PackedFloat32Array([0.0, 1.2, 0.0, 0.6, 0.0])
	mod._process_modification()
	var sk := f.skeleton()
	var ang := func(bone: String) -> float:
		return sk.get_bone_pose_rotation(sk.find_bone(bone)).get_angle()
	check(ang.call("Index2.R") > 0.9, "índice muy cerrado")
	check(ang.call("Middle2.R") < 0.05, "medio abierto")
	var r2: float = ang.call("Ring2.R")
	check(r2 > 0.4 and r2 < 0.9, "anular a medias")
	# Las tres falanges del índice se doblan (reparto de la flexión).
	check(ang.call("Index1.R") > 0.5 and ang.call("Index3.R") > 0.5)
	f.free()


func test_fingertips_touch_surface_without_penetrating() -> void:
	for t in TYPES:
		var f := _figure()
		var mod := f.arm_pose_modifier(&"R")
		var pose := _grasp_pose(f, mod, t)
		var g := PieceFactory.grasp_for(t)
		var sk := f.skeleton()
		var touched := 0
		for finger in [ArmPoseModifier.THUMB, ArmPoseModifier.INDEX]:
			var ch := mod.chain(finger)
			var last := _global_of(sk, ch.bones[2])
			var pad := last * ch.contact_local
			var d := _surface_dist(g, pose.base, pad)
			var name := "%s %s" % [ChessPiece.to_char(t), ArmPoseModifier.FINGER_NAMES[finger]]
			check(d > -PENETRATION, "%s no penetra (%.2f mm)" % [name, d * 1000.0])
			if d < TOUCH_TOL:
				touched += 1
			else:
				check(false, "%s a %.1f mm de la superficie" % [name, d * 1000.0])
		check_eq(touched, 2, "pulgar e índice tocan " + ChessPiece.to_char(t))
		f.free()


func test_palm_faces_piece() -> void:
	for t in TYPES:
		var f := _figure()
		var mod := f.arm_pose_modifier(&"R")
		var pose := _grasp_pose(f, mod, t)
		var g := PieceFactory.grasp_for(t)
		var b: Basis = pose.basis
		var palm_n := -b.x  # normal de la palma en la mano derecha
		var palm_c: Vector3 = pose.origin + b.y * 0.045
		var to_piece := ((pose.base as Vector3) + Vector3(0, float(g.height), 0) - palm_c).normalized()
		var cosang := palm_n.dot(to_piece)
		check(cosang > 0.5, "la palma mira a la pieza %s (cos %.2f)" % [ChessPiece.to_char(t), cosang])
		f.free()


## Posición del contacto de la yema de `finger` en el mundo, tras `_grasp_pose`.
func _pad_world(f: SeatedFigure, mod: ArmPoseModifier, finger: int) -> Vector3:
	var ch := mod.chain(finger)
	return _global_of(f.skeleton(), ch.bones[2]) * ch.contact_local


func test_thumb_opposes_index_by_piece() -> void:
	# Oposición pulgar-índice: ángulo, visto desde el eje de la pieza, entre los contactos de ambas
	# yemas. Debe quedar entre 80 y 160 grados, cerca de lo pedido por pieza (no como garra).
	for side in [&"R", &"L"]:
		for t in TYPES:
			var f := _figure()
			var mod := f.arm_pose_modifier(side)
			var pose := _grasp_pose(f, mod, t, side)
			var g := PieceFactory.grasp_for(t)
			var base: Vector3 = pose.base
			var vi := _pad_world(f, mod, ArmPoseModifier.INDEX) - base
			var vt := _pad_world(f, mod, ArmPoseModifier.THUMB) - base
			var opp := rad_to_deg(Vector2(vi.x, vi.z).angle_to(Vector2(vt.x, vt.z)))
			opp = absf(opp)
			var tag := "%s %s (pedida %.0f)" % [side, ChessPiece.to_char(t), float(g.opposition)]
			check(opp >= 80.0 and opp <= 160.0, "oposición %.0f° en 80-160 %s" % [opp, tag])
			check(absf(opp - float(g.opposition)) < 20.0, "oposición %.0f° cerca de la pedida %s" % [opp, tag])
			f.free()


## Altura mínima (mundo) de las articulaciones y las puntas de todos los dedos de la mano de `mod`.
func _lowest_finger_point(f: SeatedFigure, mod: ArmPoseModifier) -> float:
	var low := 1e9
	for finger in 5:
		var ch := mod.chain(finger)
		for k in range(1, 3):
			low = minf(low, _global_of(f.skeleton(), ch.bones[k]).origin.y)
		low = minf(low, (_global_of(f.skeleton(), ch.bones[2]) * Vector3(0, ch.tip_len, 0)).y)
	return low


func test_no_finger_goes_below_the_table() -> void:
	# Con agarres bajos (la torre, a 16 mm) los dedos que no tocan podían quedar bajo la mesa: con el
	# límite de suelo ninguna articulación ni punta baja de la superficie y los que tocan siguen tocando.
	for side in [&"R", &"L"]:
		for t in TYPES:
			var f := _figure()
			var mod := f.arm_pose_modifier(side)
			var pose := _grasp_pose(f, mod, t, side)
			var surface: float = (pose.base as Vector3).y
			mod.floor_y = surface
			for i in 12:
				mod._process_modification()
			var tag := "%s %s" % [side, ChessPiece.to_char(t)]
			var low := _lowest_finger_point(f, mod)
			check(low >= surface - 0.0003, "%s: ningún dedo bajo la mesa (%.1f mm)" % [tag, (low - surface) * 1000.0])
			var g := PieceFactory.grasp_for(t)
			for finger in [ArmPoseModifier.THUMB, ArmPoseModifier.INDEX]:
				var d := _surface_dist(g, pose.base, _pad_world(f, mod, finger))
				check(d < TOUCH_TOL and d > -PENETRATION, "%s %s sigue tocando con el suelo (%.2f mm)" % [tag, ArmPoseModifier.FINGER_NAMES[finger], d * 1000.0])
			f.free()


func test_floor_limit_acts_on_the_free_fingers() -> void:
	# Sensibilidad: con la superficie 3 mm más alta de lo que dejan los dedos libres de la torre, sin el
	# límite alguno baja de ella; con el límite, ninguno.
	var f := _figure()
	var mod := f.arm_pose_modifier(&"R")
	var pose := _grasp_pose(f, mod, ChessPiece.ROOK)
	var surface: float = (pose.base as Vector3).y + 0.003
	var free_low := _lowest_finger_point(f, mod)
	check(free_low < surface, "sin límite un dedo queda a %.1f mm de la superficie elevada" % ((free_low - surface) * 1000.0))
	mod.floor_y = surface
	for i in 12:
		mod._process_modification()
	var low := _lowest_finger_point(f, mod)
	check(low >= surface - 0.0003, "con límite ninguno baja de ella (%.1f mm)" % ((low - surface) * 1000.0))
	f.free()


func test_thumb_stays_at_grip_height() -> void:
	# Dama y rey: el pulgar no queda alto sobre la corona, sino a la altura de la pinza (el pulgar
	# del plan toca a la altura del índice, no más arriba que la corona).
	for t in TYPES:
		var f := _figure()
		var mod := f.arm_pose_modifier(&"R")
		var pose := _grasp_pose(f, mod, t)
		var g := PieceFactory.grasp_for(t)
		var y: float = (_pad_world(f, mod, ArmPoseModifier.THUMB) - (pose.base as Vector3)).y
		check(absf(y - float(g.height)) < 0.006, "%s: yema del pulgar a %.1f mm (pinza a %.1f)" % [ChessPiece.to_char(t), y * 1000.0, float(g.height) * 1000.0])
		f.free()


func test_tremor_only_opens_fingers() -> void:
	var f := _figure()
	var mod := f.arm_pose_modifier(&"R")
	mod.controlled = true
	mod.curls = PackedFloat32Array([0.5, 0.6, 0.6, 0.6, 0.6])
	mod._process_modification()
	var base := mod.flex_now(ArmPoseModifier.INDEX)
	mod.tremor = 0.08
	for k in 20:
		mod.time = float(k) * 0.05
		mod._process_modification()
		check(mod.flex_now(ArmPoseModifier.INDEX) <= base + 1e-6, "el temblor nunca cierra de más")
	f.free()


func test_pinch_plan_is_derived_from_geometry() -> void:
	var f := _figure()
	var mod := f.arm_pose_modifier(&"R")
	var small := mod.pinch_plan(0.008, deg_to_rad(15.0), deg_to_rad(15.0))
	var big := mod.pinch_plan(0.018, deg_to_rad(15.0), deg_to_rad(15.0))
	check((small.a as Vector3).distance_to(big.a as Vector3) > 0.002, "el punto de pinza depende del radio de la pieza")
	check((small.a as Vector3).y > 0.05 and (small.a as Vector3).y < 0.15, "queda delante de la palma, a la altura de los dedos")
	f.free()


# --- Esqueleto viejo (un solo hueso para los dedos y otro para el pulgar) ---------------

func _legacy_skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.add_bone("Hand.R")
	sk.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3(0, 0.28, 0)))
	sk.add_bone("Fingers.R")
	sk.set_bone_parent(1, 0)
	sk.set_bone_rest(1, Transform3D(Basis(Vector3.RIGHT, 0.155), Vector3(0, 0.09, 0)))
	sk.add_bone("Thumb.R")
	sk.set_bone_parent(2, 0)
	sk.set_bone_rest(2, Transform3D(Basis(Vector3(0, 0, 1), 0.3), Vector3(-0.01, 0.02, 0.013)))
	for i in 3:
		sk.set_bone_pose(i, sk.get_bone_rest(i))
	return sk


func test_legacy_skeleton_fallback() -> void:
	var sk := _legacy_skeleton()
	var mod := ArmPoseModifier.new()
	sk.add_child(mod)
	mod.controlled = true
	mod.hand_basis = Basis.IDENTITY
	mod.curls = PackedFloat32Array([0.5, 0.8, 0.8, 0.8, 0.8])
	mod._process_modification()
	check(mod.is_legacy(), "detecta los huesos viejos")
	var fingers := sk.get_bone_pose_rotation(1)
	check(absf(fingers.get_angle()) > 0.6, "el hueso `Fingers` se dobla")
	check(mod.chain(ArmPoseModifier.INDEX) != null and mod.chain(ArmPoseModifier.MIDDLE) == null, "una sola cadena de dedos")
	# Con un agarre cierra hasta tocar (o queda relajado), sin atravesar la pieza.
	var ch := mod.chain(ArmPoseModifier.INDEX)
	var hand := _global_of(sk, 0)
	var axis_pt := hand.origin + Vector3(-0.045, 0.14, 0.0)
	var prof := PackedFloat32Array()
	prof.resize(60)
	prof.fill(0.012)
	mod.grasp = {"axis_point": axis_pt - Vector3(0, 0.03, 0), "axis_dir": Vector3.UP, "profile": prof, "step": 0.001,
		"contact": PackedInt32Array([ArmPoseModifier.INDEX]), "weight": 1.0, "relax": 0.7}
	for i in 5:
		mod._process_modification()
	var pad := _global_of(sk, 1) * ch.contact_local
	var rel := pad - (axis_pt - Vector3(0, 0.03, 0))
	var rho := Vector2(rel.x, rel.z).length()
	check(rho > 0.012 - PENETRATION or rel.y < 0.0 or rel.y > 0.06, "la yema vieja no atraviesa la pieza (rho %.1f mm)" % (rho * 1000.0))
	sk.free()
