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


func test_chair_clears_legs_when_accusing() -> void:
	var res := await _drive(&"stand_accuse", true)
	check(res.max_overlap <= 0.001, "stand_accuse: sin solape (%.3f)" % res.max_overlap)
	check(res.r_end >= 0.40, "stand_accuse: silla retirada >= 0,40 m (%.2f)" % res.r_end)


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
