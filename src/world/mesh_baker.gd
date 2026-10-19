class_name MeshBaker
extends RefCounted
## Fusiona varias mallas (con su transformación) en un solo `ArrayMesh` con una
## superficie por material. Sirve para convertir el decorado estático de cada mesa
## (mesa, tablero, reloj, planillas...) en pocas llamadas de dibujo, y para que cada
## objeto toque pocas luces en el renderer Compatibility.

## Material -> {v: PackedVector3Array, n: PackedVector3Array, i: PackedInt32Array}
var _groups: Dictionary = {}
var _order: Array[Material] = []
var _triangles: int = 0


## Añade una malla. `material` (si no es null) sustituye al de cada superficie.
func add_mesh(mesh: Mesh, xf: Transform3D, material: Material = null, mi: MeshInstance3D = null) -> void:
	if mesh == null:
		return
	if mesh is PrimitiveMesh:
		_add_arrays((mesh as PrimitiveMesh).get_mesh_arrays(), xf, material if material != null else (mesh as PrimitiveMesh).material)
		return
	for s in mesh.get_surface_count():
		var mat: Material = material
		if mat == null and mi != null:
			mat = mi.get_surface_override_material(s)
		if mat == null:
			mat = mesh.surface_get_material(s)
		_add_arrays(mesh.surface_get_arrays(s), xf, mat)


## Recorre `node` y sus hijos (sin necesidad de estar en el árbol) y añade todas las
## `MeshInstance3D` visibles. `parent_xf` es la transformación del padre de `node`.
func add_tree(node: Node, parent_xf: Transform3D = Transform3D.IDENTITY) -> void:
	var xf := parent_xf
	if node is Node3D:
		var n3 := node as Node3D
		if not n3.visible:
			return
		xf = parent_xf * n3.transform
		if node is MeshInstance3D:
			add_mesh((node as MeshInstance3D).mesh, xf, null, node as MeshInstance3D)
	for c in node.get_children():
		add_tree(c, xf)


func add_box(size: Vector3, xf: Transform3D, material: Material) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	add_mesh(bm, xf, material)


func triangle_count() -> int:
	return _triangles


func is_empty() -> bool:
	return _order.is_empty()


## Construye la malla fusionada (una superficie por material, en orden de aparición).
func build() -> ArrayMesh:
	var out := ArrayMesh.new()
	for mat in _order:
		var g: Dictionary = _groups[mat]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.v
		arrays[Mesh.ARRAY_NORMAL] = g.n
		arrays[Mesh.ARRAY_INDEX] = g.i
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


func _add_arrays(arrays: Array, xf: Transform3D, mat: Material) -> void:
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
		return
	var src_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if src_v.is_empty():
		return
	var src_n := PackedVector3Array()
	if arrays[Mesh.ARRAY_NORMAL] != null:
		src_n = arrays[Mesh.ARRAY_NORMAL]
	var src_i := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		src_i = arrays[Mesh.ARRAY_INDEX]
	if src_i.is_empty():
		src_i.resize(src_v.size())
		for k in src_v.size():
			src_i[k] = k
	if not _groups.has(mat):
		_groups[mat] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "i": PackedInt32Array()}
		_order.append(mat)
	var g: Dictionary = _groups[mat]
	var vv: PackedVector3Array = g.v
	var nn: PackedVector3Array = g.n
	var ii: PackedInt32Array = g.i
	var base := vv.size()
	var nb := xf.basis.inverse().transposed()
	var has_n := src_n.size() == src_v.size()
	for k in src_v.size():
		vv.append(xf * src_v[k])
		nn.append((nb * src_n[k]).normalized() if has_n else Vector3.UP)
	for k in src_i.size():
		ii.append(base + src_i[k])
	g.v = vv
	g.n = nn
	g.i = ii
	_triangles += src_i.size() / 3
