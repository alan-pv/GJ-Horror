extends SceneTree
## Verifica los modelos de personajes (assets/models/characters/*.glb) contra la convención.
## Uso: godot --headless --path . --script res://tools/check_characters.gd
## Imprime huesos, animaciones y duraciones; termina con código 1 si falta algo.

const BASE_BONES := ["Hips", "Spine", "Chest", "Neck", "Head"]
const SIDE_BONES := ["Shoulder", "UpperArm", "Forearm", "Hand", "Thigh", "Shin", "Foot",
	"Thumb1", "Thumb2", "Thumb3", "Index1", "Index2", "Index3", "Middle1", "Middle2", "Middle3",
	"Ring1", "Ring2", "Ring3", "Pinky1", "Pinky2", "Pinky3"]
const BONE_COUNT := 49   # 5 del tronco/cabeza + 22 por lado
const MATERIALS := ["Skin", "Shirt", "Jacket", "Pants", "Shoes", "Hair"]

const CHARACTERS := {
	"res://assets/models/characters/player.glb": {
		"anims": ["sit_idle", "sit_think", "sit_nervous", "sit_move_piece",
			"sit_press_clock", "sit_write", "sit_cry", "sit_frozen", "stand_flee", "stand_flee_cycle",
			"death_slump_table", "death_standing",
			"sit_startle", "sit_cough", "sit_pick_up",
			"stand_accuse", "stand_accuse_hold", "dragged", "stand_up", "walk", "sit_down"],
		"nodes": ["Hair_Short", "Hair_Long", "Hair_Bald"],
	},
	"res://assets/models/characters/arbiter.glb": {
		"anims": ["idle", "walk", "inspect_sheets", "aim", "aim_hold", "shoot", "lower_gun", "point_accuse"],
		"nodes": ["Pistol", "Muzzle", "Hair_Short"],
		"roles": ["walk"],
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
	if names.size() != BONE_COUNT:
		_fail("se esperaban %d huesos y hay %d" % [BONE_COUNT, names.size()])
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
			var loops := AnimRoles.is_loop_clip(a)
			print("  anim %-22s %.3f s  pistas=%d%s" % [a, an.length, an.get_track_count(),
				"  [rol cíclico]" if loops else ""])
		_contract_report(lst, spec.get("roles", []))
	root.free()


## INFORME DEL CONTRATO: por rol, variantes encontradas o respaldo; avisa de nombres casi correctos.
func _contract_report(clips: PackedStringArray, only: Array = []) -> void:
	print("  -- INFORME DEL CONTRATO (roles de animación, ver docs/contrato-arte.md) --")
	for role in AnimRoles.ROLES:
		if not only.is_empty() and not only.has(String(role)):
			continue
		var vs: Array[String] = []
		for c in clips:
			if AnimRoles.role_of(StringName(c)) == role:
				vs.append(c)
		vs.sort()
		var info: Dictionary = AnimRoles.ROLES[role]
		var tipo := "cíclico" if info["loop"] else "una vez"
		if not vs.is_empty():
			print("  rol %-18s [%s] %d variante(s): %s" % [role, tipo, vs.size(), ", ".join(vs)])
			continue
		var fb: StringName = info["fallback"]
		if fb != &"" and clips.has(String(fb)):
			print("  rol %-18s [%s] sin variantes: usa respaldo '%s'" % [role, tipo, fb])
		elif fb != &"":
			print("  rol %-18s [%s] sin variantes y SIN respaldo '%s' en este modelo" % [role, tipo, fb])
		else:
			print("  rol %-18s [%s] sin variantes (sin respaldo: el código no lo usará)" % [role, tipo])
	for c in clips:
		var problem := AnimRoles.naming_problem(StringName(c))
		if problem != "":
			print("  AVISO nombre '%s': %s" % [c, problem])


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
