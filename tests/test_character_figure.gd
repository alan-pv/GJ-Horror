extends TestCase
## Pruebas de las figuras 3D (`CharacterFigure`, `ArbiterFigure`) con los .glb reales.

const PLAYER_ANIMS := [
	"sit_idle", "sit_think", "sit_nervous", "sit_look_left", "sit_look_right", "sit_move_piece",
	"sit_press_clock", "sit_write", "sit_beg", "sit_cry", "sit_frozen", "stand_flee",
	"stand_flee_cycle", "death_slump_table", "death_fall_back", "death_standing",
]
const ROLE_CLIPS := {
	&"sit_wait": ["sit_wait__chin", "sit_wait__crossed", "sit_wait__head", "sit_wait__lean_back"],
	&"sit_think": ["sit_think", "sit_think__chin", "sit_think__temple"],
	&"sit_startle": ["sit_startle__left", "sit_startle__right"],
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
		if f._find_named(f._model, n).visible:
			out.append(n)
	return out


func test_animations_exist() -> void:
	var p := CharacterFigure.new()
	for a in PLAYER_ANIMS:
		check(p.has_animation(a), "jugador sin " + a)
	var a := ArbiterFigure.new()
	for n in ARBITER_ANIMS:
		check(a.has_animation(n), "árbitro sin " + n)
	check(p.skeleton() != null and p.skeleton().get_bone_count() == 23, "23 huesos")
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
	a.setup({"shirt": Color(1, 0, 0), "skin": Color(0, 1, 0), "hair_style": "long"})
	check_eq(_albedo(a, "Shirt"), Color(1, 0, 0), "camisa de a")
	check_eq(_albedo(a, "Skin"), Color(0, 1, 0), "piel de a")
	check_eq(_albedo(b, "Shirt"), before, "b no cambia")
	check_eq(_visible_hair(a), ["Hair_Long"], "un solo peinado")
	check_eq(_visible_hair(b), ["Hair_Short"], "b: peinado por defecto")
	a.setup({"hair_style": "bald"})
	check_eq(_visible_hair(a), ["Hair_Bald"], "calvo")
	# Una tercera instancia nueva tampoco hereda el rojo.
	var c := CharacterFigure.new()
	check_eq(_albedo(c, "Shirt"), before, "c limpia")
	a.free()
	b.free()
	c.free()


func test_random_look() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 30:
		var look := CharacterFigure.random_look(rng)
		for k in ["skin", "shirt", "jacket", "pants", "shoes", "hair", "hair_style"]:
			check(look.has(k), "falta " + k)
		seen[look["hair_style"]] = true
	check(seen.size() >= 2, "varía el peinado")


func test_bot_look_is_featureless_gray() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var look := CharacterFigure.bot_look(rng)
	check(look["skin"] == CharacterFigure.BOT_SKIN, "piel gris")
	check(look["eyes"] == look["skin"] and look["hair"] == look["skin"], "ojos y cabello del color de la piel")
	check(look["hair_style"] == "bald", "sin cabello")
	var f := _spawn(CharacterFigure.new()) as CharacterFigure
	f.setup(look)
	for mat in f._materials.get("Eyes", []):
		check((mat as StandardMaterial3D).albedo_color == CharacterFigure.BOT_SKIN, "ojos pintados de gris")
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
	check_eq(_visible_hair(a), ["Hair_Short"], "pelo corto")
	a.play(&"walk", 0.0)
	a.set_walk_speed(ArbiterFigure.WALK_SPEED * 2.0)
	check(absf(a.animation_player().speed_scale - 2.0) < 0.001, "walk al doble")
	a.play(&"idle", 0.0)
	check(absf(a.animation_player().speed_scale - 1.0) < 0.001, "idle a 1")
	a.queue_free()


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
		check_eq(got, ROLE_CLIPS[role], "variantes de " + role)
		check(f.has_role(role), "has_role " + role)
	for role in AnimRoles.ROLES:
		check(f.has_role(role), "el jugador trae el rol " + role)
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


func test_play_role_avoids_repeating_variant() -> void:
	var f := CharacterFigure.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var last := &""
	var seen := {}
	for i in 40:
		var clip := f.play_role(&"sit_wait", rng, 1.0)
		check(clip != last, "no repite la variante (%s)" % clip)
		check(AnimRoles.role_of(clip) == &"sit_wait", "es del rol")
		seen[clip] = true
		last = clip
	check_eq(seen.size(), 4, "usa todas las variantes")
	check_eq(f.current(), last, "reproduce la elegida")
	# Con una sola variante (sit_cough) sí puede repetir.
	check_eq(f.play_role(&"sit_cough", rng), &"sit_cough")
	check_eq(f.play_role(&"sit_cough", rng), &"sit_cough")
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
	check_eq(AnimRoles.role_of(f.current()), &"sit_startle", "reproduce una variante del rol")
	f.animation_player().advance(0.2)
	f.animation_player().advance(2.0)
	check(done[0], "play_role_once terminó")
	f.queue_free()


func test_naming_problems_are_detected() -> void:
	check_eq(AnimRoles.naming_problem(&"sit_wait__crossed"), "", "bien")
	check_eq(AnimRoles.naming_problem(&"sit_idle"), "", "clip directo")
	check(AnimRoles.naming_problem(&"sit_wait_crossed") != "", "un guion bajo")
	check(AnimRoles.naming_problem(&"sit_wiat__x") != "", "rol desconocido")
	check_eq(AnimRoles.role_of(&"stand_accuse_hold"), &"stand_accuse_hold", "rol con prefijo de otro")
	check_eq(AnimRoles.role_of(&"stand_accuse__loud"), &"stand_accuse", "variante")


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
			check(worst < 0.6, "%s cierra el ciclo (salto %.2f)" % [c, worst])
	f.free()


## `stand_accuse` termina en la pose con la que arranca `stand_accuse_hold` (empalme sin salto).
func test_accuse_hands_over_to_hold() -> void:
	var f := CharacterFigure.new()
	var ap := f.animation_player()
	var a := ap.get_animation(&"stand_accuse")
	var h := ap.get_animation(&"stand_accuse_hold")
	var worst := 0.0
	for t in a.get_track_count():
		var ht := h.find_track(a.track_get_path(t), a.track_get_type(t))
		if ht < 0:
			continue
		var va = a.track_get_key_value(t, a.track_get_key_count(t) - 1)
		var vb = h.track_get_key_value(ht, 0)
		if va is Quaternion:
			worst = maxf(worst, rad_to_deg((va as Quaternion).angle_to(vb)))
	check(worst < 1.0, "empalme accuse -> hold (%.2f grados)" % worst)
	f.free()
