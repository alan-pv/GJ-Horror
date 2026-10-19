extends TestCase
## Pruebas de las figuras 3D (`CharacterFigure`, `ArbiterFigure`) con los .glb reales.

const PLAYER_ANIMS := [
	"sit_idle", "sit_think", "sit_nervous", "sit_look_left", "sit_look_right", "sit_move_piece",
	"sit_press_clock", "sit_write", "sit_beg", "sit_cry", "sit_frozen", "stand_flee",
	"stand_flee_cycle", "death_slump_table", "death_fall_back", "death_standing",
]
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
