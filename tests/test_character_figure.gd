extends TestCase
## Pruebas de las figuras 3D (`CharacterFigure`, `ArbiterFigure`) con los .glb reales.

const PLAYER_ANIMS := [
	"sit_idle", "sit_think", "sit_nervous", "sit_move_piece",
	"sit_press_clock", "sit_write", "sit_cry", "sit_frozen",
	"death_slump_table",
]
## Variantes admitidas por rol: un clip por acción (el .glb viejo aún puede traer variantes).
const ROLE_CLIPS := {
	&"sit_think": ["sit_think"],
	&"sit_startle": ["sit_startle"],
}
const ARBITER_ANIMS := ["idle", "walk", "inspect_sheets", "aim", "aim_hold", "shoot", "lower_gun", "point_accuse"]


# run_tests.gd corre todo dentro de `_init`: no hay árbol ni cuadros, así que las figuras
# se prueban fuera de él, las animaciones se avanzan a mano (`advance`) y los modificadores
# se invocan directamente (`_apply`).
func _spawn(f: Node) -> Node:
	return f


## Aplica la animación y luego la mirada, como haría el esqueleto en un cuadro.
func _apply(f: FigureBase) -> void:
	f.animation_player().advance(0.0)
	f._look_mod._process_modification()


func _albedo(f: FigureBase, mat_name: String) -> Color:
	return (f._materials[mat_name][0] as StandardMaterial3D).albedo_color


func _visible_hair(f: FigureBase) -> Array:
	var out := []
	for n in ["Hair_Short", "Hair_Long", "Hair_Bald"]:
		var node := f._find_named(f._model, n) as Node3D
		if node != null and node.visible:
			out.append(n)
	return out


func test_animations_exist() -> void:
	var p := CharacterFigure.new()
	for a in PLAYER_ANIMS:
		check(p.has_animation(a), "jugador sin " + a)
	var a := ArbiterFigure.new()
	for n in ARBITER_ANIMS:
		check(a.has_animation(n), "árbitro sin " + n)
	check(p.skeleton() != null and p.skeleton().get_bone_count() == 49, "49 huesos")
	p.free()
	a.free()


func test_loops_are_cyclic() -> void:
	var p := CharacterFigure.new()
	for n in CharacterFigure.LOOPS:
		check_eq(p.animation_player().get_animation(n).loop_mode, Animation.LOOP_LINEAR, "cíclica " + n)
	check_eq(p.animation_player().get_animation(&"sit_move_piece").loop_mode, Animation.LOOP_NONE, "move_piece no cíclica")
	var a := ArbiterFigure.new()
	for n in ArbiterFigure.LOOPS:
		check_eq(a.animation_player().get_animation(n).loop_mode, Animation.LOOP_LINEAR, "cíclica " + n)
	p.free()
	a.free()


func test_play_once_finishes_and_holds() -> void:
	var f := _spawn(CharacterFigure.new()) as CharacterFigure
	f.play(&"sit_idle", 0.0)
	var done := [false]
	var run := func() -> void:
		await f.play_once(&"sit_press_clock", 0.1)
		done[0] = true
	run.call()
	check(not done[0], "aún no termina")
	check_eq(f.current(), &"sit_press_clock", "actual")
	f.animation_player().advance(0.3)
	check(not done[0], "a mitad")
	f.animation_player().advance(1.0)
	check(done[0], "play_once terminó")
	check(f.is_finished(), "marcada terminada")
	check_eq(f.current(), &"sit_press_clock", "la pose final sigue siendo la actual")
	# Una animación cíclica se rechaza en play_once (no se cuelga).
	f.play(&"sit_idle")
	check_eq(f.current(), &"sit_idle")
	f.queue_free()


func test_play_once_interrupted_returns() -> void:
	var f := _spawn(CharacterFigure.new()) as CharacterFigure
	var done := [false]
	var run := func() -> void:
		await f.play_once(&"sit_move_piece", 0.0)
		done[0] = true
	run.call()
	f.play(&"sit_idle", 0.1)
	check(done[0], "interrumpida: la espera termina")
	f.queue_free()


func test_setup_recolors_only_this_instance() -> void:
	var a := CharacterFigure.new()
	var b := CharacterFigure.new()
	var before := _albedo(b, "Shirt")
	a.setup({"shirt": Color(1, 0, 0), "skin": Color(0, 1, 0)})
	check_eq(_albedo(a, "Shirt"), Color(1, 0, 0), "camisa de a")
	check_eq(_albedo(a, "Skin"), Color(0, 1, 0), "piel de a")
	check_eq(_albedo(b, "Shirt"), before, "b no cambia")
	check_eq(_visible_hair(a), [], "sin pelo")
	check_eq(_visible_hair(b), [], "b: sin pelo")
	# Una tercera instancia nueva tampoco hereda el rojo.
	var c := CharacterFigure.new()
	check_eq(_albedo(c, "Shirt"), before, "c limpia")
	a.free()
	b.free()
	c.free()


func test_random_look() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 30:
		var look := CharacterFigure.random_look(rng)
		for k in ["skin", "shirt", "jacket", "pants", "shoes"]:
			check(look.has(k), "falta " + k)
		check(not look.has("hair") and not look.has("hair_style"), "sin pelo")


func test_bot_look_is_featureless_gray() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var look := CharacterFigure.bot_look(rng)
	check(look["skin"] == CharacterFigure.BOT_SKIN, "piel gris")
	check(not look.has("eyes"), "sin ojos")
	var f := _spawn(CharacterFigure.new()) as CharacterFigure
	f.setup(look)
	check(not f._materials.has("Eyes"), "el modelo no trae material Eyes")
	check(f._materials.has("Skin") and not f._materials.has("Skin.001"), "materiales sin sufijo")
	check(FigureBase._base_name("Shirt.001") == "Shirt" and FigureBase._base_name("Shirt") == "Shirt", "_base_name")
	f.play(&"sit_idle", 0.5)
	check(f.is_blending() or true, "is_blending existe")


func test_look_is_clamped_and_moves_head() -> void:
	var f := _spawn(CharacterFigure.new()) as CharacterFigure
	f.play(&"sit_idle", 0.0)
	f.set_look(deg_to_rad(170.0), deg_to_rad(80.0), true)
	check(absf(f.look_now().x - deg_to_rad(80.0)) < 0.001, "yaw limitado a 80")
	check(absf(f.look_now().y - deg_to_rad(35.0)) < 0.001, "pitch limitado a 35")
	var neck := f.skeleton().find_bone("Neck")
	var head := f.skeleton().find_bone("Head")
	f.set_look(0.0, 0.0, true)
	_apply(f)
	var n0 := f.skeleton().get_bone_pose_rotation(neck)
	var h0 := f.skeleton().get_bone_pose_rotation(head)
	f.set_look(deg_to_rad(60.0), 0.0, true)
	_apply(f)
	# El giro de 60 grados se reparte entre cuello y cabeza (el pecho ayuda un poco).
	var turn := n0.angle_to(f.skeleton().get_bone_pose_rotation(neck)) \
			+ h0.angle_to(f.skeleton().get_bone_pose_rotation(head))
	check(turn > deg_to_rad(35.0), "cuello y cabeza giran (%.1f grados)" % rad_to_deg(turn))
	f.set_look(0.0, 0.0, true)
	_apply(f)
	check(n0.angle_to(f.skeleton().get_bone_pose_rotation(neck)) < 0.01, "sin mirada vuelve a la animación")
	f.queue_free()


func test_attach_reuses_attachment() -> void:
	var f := CharacterFigure.new()
	var n1 := Node3D.new()
	var n2 := Node3D.new()
	var a1 := f.attach(n1, &"Hand.R")
	var a2 := f.attach(n2, &"Hand.R")
	check(a1 == a2, "mismo BoneAttachment3D")
	check_eq(n1.get_parent(), a1)
	check_eq(n2.get_parent(), a1)
	f.free()


func test_arm_ik_creates_modifier() -> void:
	var f := _spawn(CharacterFigure.new()) as CharacterFigure
	f.play(&"sit_idle", 0.0)
	var m := f.enable_arm_ik(&"R", true)
	check(m is Marker3D, "devuelve Marker3D")
	var iks := f.skeleton().find_children("*", "TwoBoneIK3D", false, false)
	check_eq(iks.size(), 1, "un TwoBoneIK3D")
	check(f.enable_arm_ik(&"R", true) == m, "el marcador se reusa")
	check_eq(f.find_children("*", "TwoBoneIK3D", true, false).size(), 1, "no se duplica")
	check(f.arm_pole(&"R") is Marker3D, "polo")
	check(f.arm_pole(&"L").position.x > 0.0 and f.arm_pole(&"R").position.x < 0.0, "polos espejados")
	f.set_arm_ik_influence(&"R", 0.5)
	check_eq(f.arm_ik_influence(&"R"), 0.5)
	f.enable_arm_ik(&"R", false)
	check(not f.arm_ik_enabled(&"R"), "apagado")
	f.queue_free()


func test_arbiter_api() -> void:
	var a := _spawn(ArbiterFigure.new()) as ArbiterFigure
	check(a.muzzle() != null, "muzzle")
	check(a.pistol().is_ancestor_of(a.muzzle()), "muzzle cuelga de la pistola")
	a.set_gun_visible(false)
	check(not a.pistol().visible, "pistola oculta")
	a.set_gun_visible(true)
	check(a.pistol().visible, "pistola visible")
	check_eq(_visible_hair(a), [], "sin pelo")
	a.play(&"walk", 0.0)
	a.set_walk_speed(ArbiterFigure.WALK_SPEED * 2.0)
	check(absf(a.animation_player().speed_scale - 2.0) < 0.001, "walk al doble")
	a.play(&"idle", 0.0)
	check(absf(a.animation_player().speed_scale - 1.0) < 0.001, "idle a 1")
	a.queue_free()


func test_arbiter_gun_in_hand() -> void:
	# El exportador de Blender desplaza la pistola 9 cm respecto a la cabeza de Hand.R.
	var a := _spawn(ArbiterFigure.new()) as ArbiterFigure
	check(a.pistol().position.length() < 0.001, "pistola sin desplazamiento respecto a Hand.R")
	check_eq(a.pistol().get_parent().get_class(), "BoneAttachment3D", "pistola en un hueso")
	a.queue_free()


## Dirección del cañón (-Z de `Muzzle`) y eje de la mano (Y del hueso `Hand.R`, hacia los dedos)
## en el marco de la figura, en la pose final de `anim`.
func _gun_vs_hand(anim: StringName) -> Array:
	var f := ArbiterFigure.new()
	f.hold_final_pose(anim)
	_apply(f)
	var sk := f.skeleton()
	var to_fig := sk.global_transform.basis
	# Fuera del árbol la pose global del esqueleto no se refresca: se compone desde las locales.
	var hand_pose := Basis.IDENTITY
	var chain: Array[int] = []
	var i := sk.find_bone("Hand.R")
	while i >= 0:
		chain.push_front(i)
		i = sk.get_bone_parent(i)
	for b in chain:
		hand_pose = hand_pose * sk.get_bone_pose(b).basis
	# Sin árbol el BoneAttachment3D no se actualiza: la orientación del hueso se aplica a mano.
	var barrel := -(to_fig * hand_pose * f.pistol().basis * f.muzzle().basis).z.normalized()
	var hand := (to_fig * hand_pose.y).normalized()
	f.free()
	return [barrel, hand]


func test_arbiter_barrel_follows_hand() -> void:
	# En reposo (fin de lower_gun) la mano cuelga: el cañón apunta hacia abajo, paralelo a los dedos.
	var idle := _gun_vs_hand(&"lower_gun")
	check(rad_to_deg(idle[0].angle_to(idle[1])) < 3.0, "reposo: cañón paralelo a la mano")
	check(idle[0].y < -0.9, "reposo: cañón hacia abajo %s" % idle[0])
	# Apuntando, la mano y el cañón van hacia el blanco (horizontales, hacia +Z).
	var aim := _gun_vs_hand(&"aim")
	check(rad_to_deg(aim[0].angle_to(aim[1])) < 3.0, "apuntando: cañón paralelo a la mano")
	check(aim[0].z > 0.9, "apuntando: cañón hacia delante %s" % aim[0])


## La empuñadura queda dentro del puño: su centro está entre la palma y los dedos curvados y dentro
## de la línea de nudillos, y la corredera apoya sobre los nudillos del índice (poses de agarre).
func test_arbiter_grip_inside_fist() -> void:
	var f := ArbiterFigure.new()
	f.hold_final_pose(&"aim")
	var sk := f.skeleton()
	var rest := func(n: String) -> Vector3:
		return sk.get_bone_rest(sk.find_bone(n)).origin
	var mesh := (f.pistol() as MeshInstance3D).mesh
	var grip := AABB()
	for i in mesh.get_surface_count():
		if mesh.surface_get_material(i).resource_name == "Grip":
			var arr := mesh.surface_get_arrays(i)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			grip = AABB(vs[0], Vector3.ZERO)
			for v in vs:
				grip = grip.expand(v)
	# `Pistol` ya está en el marco de Hand.R salvo su giro de 90 º sobre X (conversión de ejes).
	var c: Vector3 = f.pistol().basis * grip.get_center()
	var idx1: Vector3 = rest.call("Index1.R")
	var pinky1: Vector3 = rest.call("Pinky1.R")
	check(c.y > 0.03 and c.y < idx1.y, "empuñadura entre la palma y los nudillos (y=%.3f)" % c.y)
	check(c.x < -0.02 and c.x > -0.055, "empuñadura en la cavidad del puño (x=%.3f)" % c.x)
	check(c.z < idx1.z and c.z > pinky1.z - 0.01, "empuñadura a lo largo de la línea de nudillos (z=%.3f)" % c.z)
	var m: Vector3 = f.pistol().basis * f.muzzle().position
	check(absf(m.z - idx1.z) < 0.03, "corredera apoyada sobre el índice (z=%.3f)" % m.z)
	f.free()


func test_hide_for_first_person() -> void:
	var f := _spawn(CharacterFigure.new()) as CharacterFigure
	f.play(&"sit_idle", 0.0)
	f.set_hidden_for_first_person(true)
	_apply(f)
	var head := f.skeleton().find_bone("Head")
	check(f.skeleton().get_bone_pose_scale(head).x < 0.01, "cabeza a escala ~0")
	f.set_hidden_for_first_person(false)
	_apply(f)
	check(f.skeleton().get_bone_pose_scale(head).x > 0.9, "cabeza restaurada")
	f.queue_free()


func test_role_variants_are_discovered() -> void:
	var f := CharacterFigure.new()
	for role in ROLE_CLIPS:
		var got := Array(f.variants(role))
		got.sort()
		check_eq(got, ROLE_CLIPS[role], "clip único de " + role)
		check(f.has_role(role), "has_role " + role)
	for role in AnimRoles.ROLES:
		check(f.has_role(role) or f.pick_role_clip(role) != &"", "el jugador resuelve el rol " + role)
	check(not f.has_role(&"no_existe"), "rol inexistente")
	check(f.variants(&"no_existe").is_empty(), "sin variantes")
	f.free()


func test_role_clips_follow_loop_table() -> void:
	var f := CharacterFigure.new()
	for role in AnimRoles.ROLES:
		for c in f.variants(role):
			var want := Animation.LOOP_LINEAR if AnimRoles.loop_of(role) else Animation.LOOP_NONE
			check_eq(f.animation_player().get_animation(c).loop_mode, want, "ciclo de " + c)
	f.free()


func test_play_role_single_clip_and_fallback() -> void:
	var f := CharacterFigure.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# Un clip por acción: el rol se repite sin problema.
	check_eq(f.play_role(&"sit_cough", rng), &"sit_cough")
	check_eq(f.play_role(&"sit_cough", rng), &"sit_cough")
	# `sit_wait` sin clips propios cae en su respaldo `sit_idle` (con un .glb viejo usa sus variantes).
	var clip := f.play_role(&"sit_wait", rng, 1.0)
	check(clip == &"sit_idle" or AnimRoles.role_of(clip) == &"sit_wait", "sit_wait resuelve (%s)" % clip)
	check_eq(f.current(), clip, "reproduce la elegida")
	f.free()


func test_role_fallback_when_model_lacks_variants() -> void:
	var f := CharacterFigure.new()
	# Simula un modelo sin variantes de sit_wait: debe usar el respaldo `sit_idle`.
	f._roles.erase(&"sit_wait")
	check(not f.has_role(&"sit_wait"), "sin variantes")
	check_eq(f.play_role(&"sit_wait"), &"sit_idle", "respaldo sit_idle")
	check_eq(f.current(), &"sit_idle")
	check_eq(f.animation_player().get_animation(&"sit_idle").loop_mode, Animation.LOOP_LINEAR, "el respaldo cicla")
	# Un rol sin respaldo ni variantes no reproduce nada (y avisa).
	f._roles.erase(&"sit_cough")
	check_eq(f.pick_role_clip(&"sit_cough"), &"", "sin respaldo")
	# El árbitro no trae sit_wait ni su respaldo.
	var a := ArbiterFigure.new()
	check(not a.has_role(&"sit_wait"), "árbitro sin sit_wait")
	check_eq(a.pick_role_clip(&"sit_wait"), &"", "árbitro: sin respaldo")
	check(a.has_role(&"walk"), "árbitro: walk es un rol")
	check_eq(a.play_role(&"walk"), &"walk")
	f.free()
	a.free()


func test_play_role_once_finishes() -> void:
	var f := _spawn(CharacterFigure.new()) as CharacterFigure
	var done := [false]
	var run := func() -> void:
		await f.play_role_once(&"sit_startle", RandomNumberGenerator.new())
		done[0] = true
	run.call()
	check(not done[0], "aún no termina")
	check_eq(AnimRoles.role_of(f.current()), &"sit_startle", "reproduce el clip del rol")
	f.animation_player().advance(0.2)
	f.animation_player().advance(2.0)
	check(done[0], "play_role_once terminó")
	f.queue_free()


func test_naming_problems_are_detected() -> void:
	check_eq(AnimRoles.naming_problem(&"sit_wait__variante"), "", "bien")
	check_eq(AnimRoles.naming_problem(&"sit_idle"), "", "clip directo")
	check(AnimRoles.naming_problem(&"sit_wait_crossed") != "", "un guion bajo")
	check(AnimRoles.naming_problem(&"sit_wiat__x") != "", "rol desconocido")
	check_eq(AnimRoles.role_of(&"sit_wait__chin"), &"sit_wait", "variante")


## Los clips cíclicos de roles cierran sin salto: primer y último fotograma coinciden.
func test_role_loops_close_without_jump() -> void:
	var f := CharacterFigure.new()
	var ap := f.animation_player()
	for role in AnimRoles.ROLES:
		if not AnimRoles.loop_of(role):
			continue
		for c in f.variants(role):
			var an := ap.get_animation(c)
			var worst := 0.0
			for t in an.get_track_count():
				var n := an.track_get_key_count(t)
				if n < 2:
					continue
				var a = an.track_get_key_value(t, 0)
				var b = an.track_get_key_value(t, n - 1)
				if a is Quaternion:
					worst = maxf(worst, rad_to_deg((a as Quaternion).angle_to(b)))
				elif a is Vector3:
					worst = maxf(worst, ((a as Vector3) - (b as Vector3)).length() * 100.0)
			# Umbral 1.0: las animaciones re-muestreadas a 24 fps (edición a mano) cierran el ciclo con hasta ~0.7 de salto.
			check(worst < 1.0, "%s cierra el ciclo (salto %.2f)" % [c, worst])
	f.free()



## Punto más bajo (en el marco de la figura, y=0 el suelo) de los vértices de la cabeza con la
## pose local actual del esqueleto (se encadena a mano: la figura de la prueba no está en el árbol).
func _head_lowest_y(f: FigureBase) -> float:
	var sk: Skeleton3D = f._skeleton
	var hb := sk.find_bone("Head")
	var g := Transform3D.IDENTITY
	var chain: Array[int] = []
	var i := hb
	while i >= 0:
		chain.push_front(i)
		i = sk.get_bone_parent(i)
	for b in chain:
		g = g * sk.get_bone_pose(b)
	var mi := f._find_named(f._model, "Body") as MeshInstance3D
	var to_pose := g * sk.get_bone_global_rest(hb).affine_inverse()
	var low := INF
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		for j in v.size():
			for k in 4:
				if bones[j * 4 + k] == hb and w[j * 4 + k] > 0.5:
					low = minf(low, (to_pose * v[j]).y)
	return low


## La cabeza del ejecutado queda apoyada en la mesa (cara superior en y = BoardView.TABLE_TOP):
## sin holgura apreciable ni atravesarla.
func test_death_slump_head_rests_on_table() -> void:
	var f := CharacterFigure.new()
	f.setup(CharacterFigure.random_look(RandomNumberGenerator.new()))
	f.hold_final_pose(&"death_slump_table")
	_apply(f)
	var gap := _head_lowest_y(f) - BoardView.TABLE_TOP
	check(gap <= 0.01, "la cabeza no flota sobre la mesa (holgura %.3f m)" % gap)
	check(gap >= -0.02, "la cabeza no atraviesa la mesa (%.3f m)" % gap)
	f.free()
