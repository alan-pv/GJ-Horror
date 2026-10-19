extends SceneTree
## Verifica los modelos de personajes (assets/models/characters/*.glb) contra la convención.
## Uso: godot --headless --path . --script res://tools/check_characters.gd
## Imprime huesos, animaciones y duraciones; termina con código 1 si falta algo.

const BASE_BONES := ["Hips", "Spine", "Chest", "Neck", "Head"]
const SIDE_BONES := ["Shoulder", "UpperArm", "Forearm", "Hand", "Fingers", "Thumb", "Thigh", "Shin", "Foot"]
const MATERIALS := ["Skin", "Shirt", "Jacket", "Pants", "Shoes", "Hair"]

const CHARACTERS := {
	"res://assets/models/characters/player.glb": {
		"anims": ["sit_idle", "sit_think", "sit_nervous", "sit_look_left", "sit_look_right", "sit_move_piece",
			"sit_press_clock", "sit_write", "sit_beg", "sit_cry", "sit_frozen", "stand_flee", "stand_flee_loop",
			"death_slump_table", "death_fall_back", "death_standing"],
		"nodes": ["Hair_Short", "Hair_Long", "Hair_Bald"],
	},
	"res://assets/models/characters/arbiter.glb": {
		"anims": ["idle", "walk", "inspect_sheets", "aim", "aim_hold", "shoot", "lower_gun", "point_accuse"],
		"nodes": ["Pistol", "Muzzle", "Hair_Short"],
	},
}

var _errors := 0


func _init() -> void:
	for path in CHARACTERS:
		_check(path, CHARACTERS[path])
	print("")
	if _errors > 0:
		print("FALLO: %d problemas" % _errors)
		quit(1)
	else:
		print("OK: personajes conformes")
		quit(0)


func _fail(msg: String) -> void:
	_errors += 1
	printerr("  ERROR: " + msg)


func _check(path: String, spec: Dictionary) -> void:
	print("== %s" % path)
	var ps := load(path) as PackedScene
	if ps == null:
		_fail("no se pudo cargar (¿importado?)")
		return
	var root := ps.instantiate()
	var skel := _find(root, "Skeleton3D") as Skeleton3D
	if skel == null:
		_fail("sin Skeleton3D")
		root.free()
		return
	var names: Array[String] = []
	for i in skel.get_bone_count():
		names.append(skel.get_bone_name(i))
	print("  huesos (%d): %s" % [names.size(), ", ".join(names)])
	var want: Array[String] = []
	want.append_array(BASE_BONES)
	for b in SIDE_BONES:
		want.append(b + ".L")
		want.append(b + ".R")
	for b in want:
		if not names.has(b):
			_fail("falta el hueso " + b)
	# materiales
	var mats := {}
	var tris := 0
	for mi in _all(root, "MeshInstance3D"):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			if mat:
				mats[mat.resource_name] = true
		tris += m.get_faces().size() / 3
	print("  materiales: %s | triángulos: %d" % [", ".join(mats.keys()), tris])
	for mn in MATERIALS:
		if not mats.has(mn):
			_fail("falta el material " + mn)
	for n in spec["nodes"]:
		if _find_name(root, n) == null:
			_fail("falta el nodo " + n)
	# animaciones
	var ap := _find(root, "AnimationPlayer") as AnimationPlayer
	if ap == null:
		_fail("sin AnimationPlayer")
	else:
		var lst := ap.get_animation_list()
		for a in spec["anims"]:
			if not ap.has_animation(a):
				_fail("falta la animación " + a)
		for a in lst:
			var an := ap.get_animation(a)
			print("  anim %-18s %.3f s  pistas=%d" % [a, an.length, an.get_track_count()])
	root.free()


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null


func _all(n: Node, cls: String) -> Array:
	var out: Array = []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(_all(c, cls))
	return out


func _find_name(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var r := _find_name(c, nm)
		if r:
			return r
	return null
