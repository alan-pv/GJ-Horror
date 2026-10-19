extends SceneTree
## Comprueba los .glb de utilería: nodos esperados y dimensiones (AABB en espacio del modelo).
## Uso: godot --headless --path . --script res://tools/check_props.gd   (tras importar)

const DIR := "res://assets/models/props/"
const TOL := 0.012

# archivo: [nodos esperados, tamaño esperado (x, y, z) o null, mínimo/máximo Y opcional]
var casos := {
	"table.glb": [["Table"], Vector3(1.34, 0.72, 0.94)],
	"chair.glb": [["Chair"], Vector3(0.44, 0.92, 0.44)],
	"board.glb": [["Board", "BoardSquares", "BoardFrame"], Vector3(0.50, 0.026, 0.50)],
	"lamp.glb": [["Lamp", "LampShade", "LampCable", "LampBulb", "LightAnchor"], Vector3(0.60, 1.20, 0.60)],
	"chess_clock.glb": [["ClockBody", "Button_A", "Button_B", "Face_A", "Face_B",
		"Hand_A_Left", "Hand_A_Right", "Hand_B_Left", "Hand_B_Right"], null],
	"scoresheet.glb": [["Clipboard", "Sheet", "SheetLines"], Vector3(0.16, 0.0155, 0.23)],
	"pen.glb": [["Pen"], Vector3(0.14, 0.011, 0.011)],
	"pistol.glb": [["PistolBody", "Muzzle"], null],
	"pieces/pawn.glb": [["Pawn"], Vector3(0.04, 0.045, 0.04)],
	"pieces/rook.glb": [["Rook"], Vector3(0.04, 0.05, 0.04)],
	"pieces/knight.glb": [["Knight"], null],
	"pieces/bishop.glb": [["Bishop"], Vector3(0.04, 0.06, 0.04)],
	"pieces/queen.glb": [["Queen"], Vector3(0.04, 0.075, 0.04)],
	"pieces/king.glb": [["King"], Vector3(0.04, 0.095, 0.04)],
	"pillar.glb": [["Pillar"], null],
	"door.glb": [["Door", "DoorFrame", "DoorLeaf_L", "DoorLeaf_R"], null],
	"wall_panel.glb": [["WallPanel"], null],
	"banner.glb": [["Banner"], null],
}


func _init() -> void:
	var fallos := 0
	for f in casos:
		var ps := load(DIR + f) as PackedScene
		if ps == null:
			print("FALLO ", f, ": no se pudo cargar")
			fallos += 1
			continue
		var raiz := ps.instantiate() as Node3D
		root.add_child(raiz)
		for n in casos[f][0]:
			if raiz.name != n and raiz.find_child(n, true, false) == null:
				print("FALLO ", f, ": falta el nodo ", n)
				fallos += 1
		var bb := _aabb(raiz, Transform3D.IDENTITY)
		var esp: Variant = casos[f][1]
		var ok := true
		if esp != null:
			var d: Vector3 = (bb.size - (esp as Vector3)).abs()
			ok = d.x <= TOL and d.y <= TOL and d.z <= TOL
		print("%s %s  aabb pos=%s size=%s" % ["ok   " if ok else "FALLO", f, bb.position.snappedf(0.001), bb.size.snappedf(0.001)])
		if not ok:
			fallos += 1
		raiz.queue_free()
	print("check_props: ", "TODO BIEN" if fallos == 0 else "%d fallos" % fallos)
	quit(1 if fallos > 0 else 0)


func _aabb(n: Node, t: Transform3D) -> AABB:
	var r := AABB()
	var primero := true
	var tn := t
	if n is Node3D:
		tn = t * (n as Node3D).transform
	if n is MeshInstance3D:
		r = tn * (n as MeshInstance3D).get_aabb()
		primero = false
	for c in n.get_children():
		var b := _aabb(c, tn)
		if b.size == Vector3.ZERO and b.position == Vector3.ZERO:
			continue
		r = b if primero else r.merge(b)
		primero = false
	return r
