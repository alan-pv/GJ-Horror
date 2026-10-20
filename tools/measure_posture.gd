extends SceneTree
## Mide la postura sentada: inclinacion del tronco (cadera->cuello) respecto a la vertical, altura
## de la cabeza sobre la mesa (0,72 m) y distancia horizontal al centro del tablero (z = 0,72).
##   godot --headless --path . --script res://tools/measure_posture.gd
## Columnas: clip | tronco(deg) | cabeza sobre mesa (m) | dist. al tablero (m), para
## clip solo, + mirada al tablero (-35 deg), + inclinacion del IK (lean en rad).

const TABLE := 0.72
const SEAT := 0.72


func _initialize() -> void:
	_run.call_deferred()


func _meas(fig: SeatedFigure) -> String:
	var hips := fig.bone_global(&"Hips").origin
	var neck := fig.bone_global(&"Neck").origin
	var chest := fig.bone_global(&"Chest").origin
	var head := fig.head_global_position()
	var tr := neck - hips
	var ang := rad_to_deg(atan2(tr.z, tr.y))
	var tr2 := neck - chest
	return "tronco %5.1f (pecho-cuello %5.1f)  cabeza+%.2f  dist %.2f" % [ang, rad_to_deg(atan2(tr2.z, tr2.y)), head.y - TABLE, Vector2(head.x, head.z - SEAT).length()]


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var fig := SeatedFigure.new()
	world.add_child(fig)
	fig.setup(CharacterFigure.bot_look(RandomNumberGenerator.new(), {}))
	var cases := [["sit_idle"], ["sit_wait__crossed"], ["sit_wait__chin"], ["sit_wait__head"], ["sit_wait__lean_back"],
		["sit_think"], ["sit_think__chin"], ["sit_think__temple"], ["sit_nervous"]]
	var ap := fig.animation_player()
	for c in cases:
		var clip := StringName(c[0])
		if not fig.has_animation(clip):
			print(clip, " no existe")
			continue
		fig.set_look(0.0, 0.0, true)
		fig.set_lean(0.0, true)
		fig.play(clip, 0.0)
		ap.pause()
		ap.seek(0.5 * ap.get_animation(clip).length, true)
		var line := clip
		for case in [[0.0, 0.0, "solo clip"], [-0.61, 0.0, "mirada tablero"], [-0.61, 0.5, "mirada+lean 0.5"], [-0.61, 0.95, "mirada+lean 0.95"]]:
			fig.set_look(0.0, case[0], true)
			fig.set_lean(case[1], true)
			fig._lean_now = case[1]
			for i in 3:
				await process_frame
			line += "\n    %-18s %s  ojos %s" % [case[2], _meas(fig), fig.eye_global_position().snapped(Vector3.ONE * 0.001)]
		print("  ojos(\u00fcltimo caso) ", fig.eye_global_position())
		print(line)
	quit(0)
