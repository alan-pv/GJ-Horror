extends TestCase
## La silla sigue a la pose real al levantarse y sentarse (`ChairFollow`), con el .glb real.
## Necesita fotogramas (el esqueleto solo aplica la animación dentro del árbol), por eso las
## pruebas son corrutinas que run_tests.gd espera.

const STEPS := 14


func _tree() -> SceneTree:
	return tree


## Figura en el árbol, con `clip` en pausa; la silla está en el origen mirando a +Z.
func _setup(clip: StringName) -> CharacterFigure:
	var f := CharacterFigure.new()
	_tree().root.add_child(f)
	f.play(clip, 0.0)
	f.animation_player().pause()
	return f


## Recorre el clip y simula la silla paso a paso. Devuelve {max_overlap, min_naive_need, r_end}:
## el mayor solape de piernas con la silla ya retirada, lo que pediría una silla sin moverse y la
## retirada final.
func _drive(role: StringName, standing_up: bool) -> Dictionary:
	var probe := CharacterFigure.new()
	var clip := probe.pick_role_clip(role)
	probe.free()
	var f := _setup(clip)
	var ap := f.animation_player()
	var length := ap.get_animation(clip).length
	var home := Transform3D.IDENTITY
	var back := Vector3(0.0, 0.0, -1.0)
	var r := 0.0 if standing_up else 0.5
	var out := {"max_overlap": -1.0, "max_naive": 0.0, "r_end": 0.0}
	for i in STEPS + 1:
		ap.seek(length * i / float(STEPS), true)
		await _tree().process_frame
		var dt := length / STEPS
		var fade := 0.0 if standing_up else float(i) / STEPS
		r = ChairFollow.step(r, ChairFollow.need(f, home), ChairFollow.desired(ChairFollow.rise_progress(f, home), 0.5), 0.0, dt, fade)
		var moved := Transform3D(Basis.IDENTITY, back * r)
		out.max_overlap = maxf(out.max_overlap, ChairFollow.need(f, moved))
		out.max_naive = maxf(out.max_naive, ChairFollow.need(f, home))
	out.r_end = r
	f.queue_free()
	return out


func test_chair_clears_legs_when_standing_up() -> void:
	var res := await _drive(&"stand_up", true)
	check(res.max_overlap <= 0.001, "stand_up: la silla no toca las piernas (solape %.3f)" % res.max_overlap)
	check(res.max_naive > 0.05, "stand_up: sin mover la silla sí se solaparía (%.3f)" % res.max_naive)
	check(res.r_end >= 0.40, "stand_up: la silla acaba retirada >= 0,40 m (%.2f)" % res.r_end)


func test_chair_returns_when_sitting_down() -> void:
	var res := await _drive(&"sit_down", false)
	check(res.max_overlap <= 0.001, "sit_down: la silla no toca las piernas (solape %.3f)" % res.max_overlap)
	check(res.r_end < 0.1, "sit_down: la silla vuelve a la par (%.2f)" % res.r_end)


func test_seated_legs_do_not_push_chair() -> void:
	var f := _setup(&"sit_idle")
	f.animation_player().seek(0.0, true)
	await _tree().process_frame
	await _tree().process_frame
	check_eq(ChairFollow.need(f, Transform3D.IDENTITY), 0.0, "sentado no pide retirada")
	f.queue_free()


## Postura sentada natural: espalda casi recta (la inclinación sale del cuello) y la cabeza a una
## altura razonable sobre la mesa (0,72 m), incluso mirando al tablero (pitch -35 grados).
## Con la figura en el árbol y fotogramas de por medio, para que el esqueleto aplique de verdad la
## animación (fuera del árbol queda en T-pose y la prueba no mediría nada). Antes de medir se
## comprueba que la pose no es la T-pose (muñeca bajo el hombro), para que no pase en falso.
func test_seated_posture_is_upright() -> void:
	var table := 0.72
	for clip in ["sit_idle", "sit_nervous", "sit_think"]:
		var f := _setup(StringName(clip))
		var ap := f.animation_player()
		var length := ap.get_animation(clip).length
		for frac in [0.0, 0.5]:
			ap.seek(frac * length, true)
			f.set_look(0.0, deg_to_rad(-35.0), true)
			for i in 3:
				await _tree().process_frame
			var hips := f.bone_global(&"Hips").origin
			var tr := f.bone_global(&"Neck").origin - hips
			var lean := rad_to_deg(atan2(tr.z, tr.y))
			var h := f.head_global_position().y - table
			# T-pose: brazos en horizontal; sentado la muñeca queda muy por debajo del hombro.
			var drop := f.bone_global(&"UpperArm.L").origin.y - f.bone_global(&"Hand.L").origin.y
			check(drop > 0.10, "%s: la animación se aplicó (muñeca %.2f m bajo el hombro)" % [clip, drop])
			check(hips.y < 0.7, "%s: pelvis sentada (y %.2f)" % [clip, hips.y])
			check(lean < 13.0, "%s: tronco a %.1f grados de la vertical (máx 13)" % [clip, lean])
			check(h >= 0.30, "%s: cabeza a %.2f m sobre la mesa (mín 0,30)" % [clip, h])
		f.queue_free()

