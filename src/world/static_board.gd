class_name StaticBoard
extends RefCounted
## Piezas de un tablero decorativo fusionadas en una malla de dos superficies
## (blancas y negras), a partir de los modelos de `assets/models/props/pieces/`.
## Se reconstruye entera en cada cambio: son ~32 piezas de unos 100 triángulos.

const SQUARE := 0.055
const PIECE_NAMES := {
	ChessPiece.PAWN: "pawn", ChessPiece.KNIGHT: "knight", ChessPiece.BISHOP: "bishop",
	ChessPiece.ROOK: "rook", ChessPiece.QUEEN: "queen", ChessPiece.KING: "king",
}
const WHITE_COLOR := Color(0.80, 0.77, 0.68)
const BLACK_COLOR := Color(0.15, 0.085, 0.05)

## Posiciones plausibles de medio juego para tableros sin partida real (una por mesa).
const MID_GAME_FENS: Array[String] = [
	"r1bq1rk1/ppp2ppp/2np1n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQ1RK1 w - - 0 7",
	"r2q1rk1/pp2bppp/2n1pn2/2pp1b2/3P1B2/2PBPN2/PP1N1PPP/R2QK2R w KQ - 4 9",
	"r1bqk2r/pp2bppp/2n1pn2/3p4/3P4/2NBPN2/PP3PPP/R1BQK2R w KQkq - 2 8",
	"2rq1rk1/pp1bbppp/2n1pn2/3p4/2PP4/2N1PN2/PPQBBPPP/R4RK1 b - - 5 10",
	"r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/2NP1N2/PPP1QPPP/R4RK1 w - - 6 9",
	"3r1rk1/pp3ppp/2p1bn2/q7/3P4/2N1PB2/PP3PPP/R2Q1RK1 b - - 1 14",
	"r1b2rk1/2q1bppp/p1n1pn2/1p6/3NP3/1BN1BP2/PPPQ2PP/2KR3R w - - 3 12",
	"8/pp3kpp/2p5/4p3/2P1P3/1P3PP1/P5KP/3R4 w - - 0 28",
]

static var _geom: Dictionary = {}


## Transformación de la pieza `piece` en la casilla `sq` (a1 = 0) con la superficie a altura `y`.
static func piece_xform(sq: int, piece: int, y: float) -> Transform3D:
	var file := sq % 8
	var rank := sq / 8
	var pos := Vector3((file - 3.5) * SQUARE, y, (3.5 - rank) * SQUARE)
	# Las negras miran hacia las blancas; un pequeño giro fijo por casilla evita el aspecto de clones.
	var yaw := PI if ChessPiece.color_of(piece) == ChessPiece.BLACK else 0.0
	if ChessPiece.type_of(piece) != ChessPiece.KNIGHT:
		yaw += ((sq * 7) % 9 - 4) * 0.12
	return Transform3D(Basis(Vector3.UP, yaw), pos)


## Malla de las piezas de `squares` (64 casillas, a1 = 0) con la superficie del tablero a
## altura `y`. Superficie 0 = blancas, 1 = negras (solo existen las que tengan piezas).
static func build_mesh(squares: PackedInt32Array, white_mat: Material, black_mat: Material, y: float) -> ArrayMesh:
	var whites := MeshBaker.new()
	var blacks := MeshBaker.new()
	for sq in mini(squares.size(), 64):
		var p := squares[sq]
		if p == ChessPiece.NONE:
			continue
		var m := _piece_mesh(ChessPiece.type_of(p))
		if m == null:
			continue
		var xf := piece_xform(sq, p, y)
		if ChessPiece.color_of(p) == ChessPiece.WHITE:
			whites.add_mesh(m, xf, white_mat)
		else:
			blacks.add_mesh(m, xf, black_mat)
	var out := ArrayMesh.new()
	for baker in [whites, blacks]:
		var part: ArrayMesh = (baker as MeshBaker).build()
		for s in part.get_surface_count():
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part.surface_get_arrays(s))
			out.surface_set_material(out.get_surface_count() - 1, part.surface_get_material(s))
	return out


static func _piece_mesh(type: int) -> Mesh:
	if _geom.has(type):
		return _geom[type]
	var scene := load("res://assets/models/props/pieces/%s.glb" % PIECE_NAMES[type]) as PackedScene
	var mesh: Mesh = null
	if scene != null:
		var inst := scene.instantiate()
		for n in inst.find_children("*", "MeshInstance3D", true, false):
			mesh = (n as MeshInstance3D).mesh
			break
		inst.free()
	_geom[type] = mesh
	return mesh


static func make_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.55
	return m
