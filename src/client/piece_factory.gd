class_name PieceFactory
extends RefCounted
## Fábrica de piezas de ajedrez a partir de los modelos de Blender
## (`assets/models/props/pieces/*.glb`, un solo material `Piece` que aquí se recolorea
## en marfil o madera oscura). Las piezas se construyen una vez por tipo y se reusa la malla.
##
## ESCALA DEL MUNDO: 1 unidad = 1 metro. Tablero de torneo, casilla de 5,5 cm
## (tablero de 44 cm). Alturas reales aproximadas: rey 9,5 cm, dama 8,5 cm,
## alfil 7 cm, caballo 6 cm, torre 5 cm, peón 4,5 cm. El origen de cada pieza
## está en el centro de su base, con +Y hacia arriba y el hocico del caballo
## hacia -Z (el tablero las gira para que miren al rival).

const SQUARE := 0.055
const MODEL_DIR := "res://assets/models/props/pieces/"
const MODEL_NAMES := {
	ChessPiece.PAWN: "pawn", ChessPiece.ROOK: "rook", ChessPiece.KNIGHT: "knight",
	ChessPiece.BISHOP: "bishop", ChessPiece.QUEEN: "queen", ChessPiece.KING: "king",
}

const IVORY := Color(0.80, 0.77, 0.68)
const DARK_WOOD := Color(0.17, 0.09, 0.05)

## Alturas totales en metros por tipo de pieza.
const HEIGHTS := {
	ChessPiece.PAWN: 0.045,
	ChessPiece.KNIGHT: 0.059,
	ChessPiece.BISHOP: 0.060,
	ChessPiece.ROOK: 0.050,
	ChessPiece.QUEEN: 0.075,
	ChessPiece.KING: 0.095,
}

static var _meshes: Dictionary = {}  # tipo -> Mesh del modelo
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
	var root := Node3D.new()
	root.name = "Pieza_" + ChessPiece.to_char(piece)
	root.set_meta("code", piece)
	var mi := MeshInstance3D.new()
	mi.mesh = _model_mesh(type)
	mi.material_override = material_for(color)
	root.add_child(mi)
	return root


## Malla del modelo `.glb` del tipo (se carga una sola vez).
static func _model_mesh(type: int) -> Mesh:
	if not _meshes.has(type):
		var scene := load(MODEL_DIR + MODEL_NAMES[type] + ".glb") as PackedScene
		var inst := scene.instantiate()
		var found := _first_mesh(inst)
		_meshes[type] = found.mesh
		inst.free()
	return _meshes[type]


static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r != null:
			return r
	return null
