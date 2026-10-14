class_name PieceFactory
extends RefCounted
## Fábrica de piezas de ajedrez provisionales hechas solo con primitivas y
## perfiles de revolución generados en código (sin arte importado).
##
## ESCALA DEL MUNDO: 1 unidad = 1 metro. Tablero de torneo, casilla de 5,5 cm
## (tablero de 44 cm). Alturas reales aproximadas: rey 9,5 cm, dama 8,5 cm,
## alfil 7 cm, caballo 6 cm, torre 5 cm, peón 4,5 cm. El origen de cada pieza
## está en el centro de su base, con +Y hacia arriba y el hocico del caballo
## hacia -Z (el tablero las gira para que miren al rival).

const SQUARE := 0.055
const SEGMENTS := 24
const MM := 0.001

const IVORY := Color(0.80, 0.77, 0.68)
const DARK_WOOD := Color(0.17, 0.09, 0.05)

## Alturas totales en metros por tipo de pieza.
const HEIGHTS := {
	ChessPiece.PAWN: 0.045,
	ChessPiece.KNIGHT: 0.060,
	ChessPiece.BISHOP: 0.070,
	ChessPiece.ROOK: 0.050,
	ChessPiece.QUEEN: 0.085,
	ChessPiece.KING: 0.095,
}

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}


## Altura total de una pieza (por código o tipo).
static func height_of(piece: int) -> float:
	return HEIGHTS[ChessPiece.type_of(piece)]


## Altura (desde la base) donde la pinza sujeta la pieza: cerca de la cabeza.
static func grip_height(piece: int) -> float:
	return height_of(piece) * 0.82


static func material_for(color: int) -> StandardMaterial3D:
	if not _materials.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = IVORY if color == ChessPiece.WHITE else DARK_WOOD
		m.roughness = 0.38 if color == ChessPiece.WHITE else 0.5
		m.metallic = 0.0
		m.metallic_specular = 0.6
		_materials[color] = m
	return _materials[color]


## Construye la pieza con el código de `ChessPiece` (tipo | color << 3).
static func build(piece: int) -> Node3D:
	var type := ChessPiece.type_of(piece)
	var color := ChessPiece.color_of(piece)
	var mat := material_for(color)
	var root := Node3D.new()
	root.name = "Pieza_" + ChessPiece.to_char(piece)
	root.set_meta("code", piece)
	root.add_child(_mesh_node(_body_mesh(type), mat))
	match type:
		ChessPiece.PAWN:
			pass
		ChessPiece.ROOK:
			for i in 4:
				var a := PI / 4.0 + i * PI / 2.0
				var m := _box(Vector3(5, 5, 5), Vector3(cos(a) * 8.6, 47.5, sin(a) * 8.6), mat)
				m.rotation.y = -a
				root.add_child(m)
		ChessPiece.BISHOP:
			root.add_child(_sphere(3.0, Vector3(0, 71.5, 0), mat))
			# Hendidura de la mitra: una cuña oscura que la distingue de la dama.
			var slit := _box(Vector3(1.2, 11, 12), Vector3(0, 62, -4), _slit_material())
			slit.rotation.x = deg_to_rad(-25)
			root.add_child(slit)
		ChessPiece.QUEEN:
			root.add_child(_sphere(4.5, Vector3(0, 80, 0), mat))
			for i in 8:
				var a := i * TAU / 8.0
				root.add_child(_sphere(2.4, Vector3(cos(a) * 11.5, 74, sin(a) * 11.5), mat))
		ChessPiece.KING:
			root.add_child(_box(Vector3(4.5, 17, 4.5), Vector3(0, 84.5, 0), mat))
			root.add_child(_box(Vector3(13, 4.5, 4.5), Vector3(0, 87, 0), mat))
		ChessPiece.KNIGHT:
			_add_knight_head(root, mat)
	return root


static func _slit_material() -> StandardMaterial3D:
	if not _materials.has("slit"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.05, 0.03, 0.02)
		m.roughness = 0.9
		_materials["slit"] = m
	return _materials["slit"]


static func _add_knight_head(root: Node3D, mat: Material) -> void:
	root.add_child(_sphere(9.5, Vector3(0, 27, -1.5), mat))
	var neck := _box(Vector3(12, 30, 15), Vector3(0, 34, 0.5), mat)
	neck.rotation.x = deg_to_rad(-18)
	root.add_child(neck)
	var muzzle := _box(Vector3(10, 10, 19), Vector3(0, 45, -11), mat)
	muzzle.rotation.x = deg_to_rad(-14)
	root.add_child(muzzle)
	var mane := _box(Vector3(4, 26, 8), Vector3(0, 34, 7), mat)
	mane.rotation.x = deg_to_rad(-18)
	root.add_child(mane)
	for s in [-1.0, 1.0]:
		var ear := _box(Vector3(2.6, 7, 3), Vector3(s * 3.2, 51, 0.5), mat)
		ear.rotation.x = deg_to_rad(-18)
		root.add_child(ear)


# --- Perfiles de revolución -------------------------------------------------

static func _body_mesh(type: int) -> ArrayMesh:
	if not _meshes.has(type):
		_meshes[type] = _lathe(_profile(type))
	return _meshes[type]


## Perfil (radio, altura) en milímetros, de abajo hacia arriba.
static func _profile(type: int) -> PackedVector2Array:
	var pts: Array = []
	match type:
		ChessPiece.PAWN:
			pts = [[0, 0], [14, 0], [14, 2.5], [12, 4], [8, 6.5], [5.5, 11], [4.3, 19], [4.6, 22.5],
				[7.2, 24.5], [7.2, 26], [4.6, 27.5], [5.6, 30], [7, 33], [7.3, 36], [6.4, 39],
				[4.5, 41.5], [2, 43], [0, 43.5]]
		ChessPiece.ROOK:
			pts = [[0, 0], [16, 0], [16, 3], [13.5, 5], [9.5, 8], [7.8, 15], [7.4, 28], [10.5, 31],
				[10.5, 33.5], [8.8, 35], [8.8, 42], [11.5, 43], [11.5, 46], [8.5, 46], [0, 46]]
		ChessPiece.BISHOP:
			pts = [[0, 0], [16, 0], [16, 3], [13, 5.5], [8.5, 9], [5.5, 17], [4.6, 36], [9, 40],
				[9, 42], [5, 44], [6.5, 48], [9.2, 54], [9.6, 59], [8, 64], [4.5, 68], [0, 70]]
		ChessPiece.QUEEN:
			pts = [[0, 0], [17, 0], [17, 3], [14, 5.5], [9, 9.5], [6, 20], [5, 42], [9.5, 49],
				[9.5, 51], [5.5, 53], [8, 58], [11.5, 64], [12.5, 70], [10, 73], [6, 74], [0, 74]]
		ChessPiece.KING:
			pts = [[0, 0], [17.5, 0], [17.5, 3], [14.5, 5.5], [9.5, 9.5], [6.2, 21], [5.2, 44], [10, 52],
				[10, 54], [5.8, 56], [8.5, 61], [12, 68], [12.5, 74], [9.5, 77], [5, 78], [0, 78]]
		ChessPiece.KNIGHT:
			pts = [[0, 0], [15, 0], [15, 3], [12.5, 5], [9, 8], [7.5, 14], [7.5, 18], [9, 22], [0, 24]]
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p[0] * MM, p[1] * MM))
	return out


static func _lathe(profile: PackedVector2Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var n := profile.size()
	for i in n:
		var prev := profile[maxi(i - 1, 0)]
		var next := profile[mini(i + 1, n - 1)]
		var t := (next - prev)
		var nrm := Vector2(t.y, -t.x).normalized()
		for j in SEGMENTS:
			var a := j * TAU / SEGMENTS
			var c := cos(a)
			var s := sin(a)
			verts.append(Vector3(profile[i].x * c, profile[i].y, profile[i].x * s))
			normals.append(Vector3(nrm.x * c, nrm.y, nrm.x * s).normalized())
	for i in n - 1:
		for j in SEGMENTS:
			var a := i * SEGMENTS + j
			var b := i * SEGMENTS + (j + 1) % SEGMENTS
			var c := (i + 1) * SEGMENTS + j
			var d := (i + 1) * SEGMENTS + (j + 1) % SEGMENTS
			indices.append_array([c, a, b, c, b, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- Ayudas de primitivas (medidas en milímetros) ----------------------------

static func _mesh_node(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func _box(size_mm: Vector3, pos_mm: Vector3, mat: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size_mm * MM
	var mi := _mesh_node(bm, mat)
	mi.position = pos_mm * MM
	return mi


static func _sphere(radius_mm: float, pos_mm: Vector3, mat: Material) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = radius_mm * MM
	sm.height = radius_mm * 2.0 * MM
	sm.radial_segments = 12
	sm.rings = 6
	var mi := _mesh_node(sm, mat)
	mi.position = pos_mm * MM
	return mi
