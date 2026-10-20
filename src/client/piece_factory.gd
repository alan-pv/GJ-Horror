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

## Paso del perfil de radios (m).
const PROFILE_STEP := 0.001
## Por encima de la altura del agarre + esto no cuenta como superficie de contacto (cruz del rey...).
const CONTACT_BAND := 0.012
## Agarre por tipo: altura de la pinza (m), dedos que tocan y pitch de la mano (grados).
## Peón por la cabeza; torre y alfil por el cuerpo; caballo por el cuello; dama y rey por la corona.
const GRASPS := {
	ChessPiece.PAWN: {"style": &"pinch", "height": 0.024, "pitch": 15.0, "roll": 15.0,
		"contact": [ArmPoseModifier.THUMB, ArmPoseModifier.INDEX]},
	ChessPiece.ROOK: {"style": &"pinch", "height": 0.016, "pitch": 15.0, "roll": 15.0,
		"contact": [ArmPoseModifier.THUMB, ArmPoseModifier.INDEX]},
	ChessPiece.KNIGHT: {"style": &"pinch", "height": 0.028, "pitch": 15.0, "roll": 15.0,
		"contact": [ArmPoseModifier.THUMB, ArmPoseModifier.INDEX]},
	ChessPiece.BISHOP: {"style": &"pinch", "height": 0.024, "pitch": 15.0, "roll": 15.0,
		"contact": [ArmPoseModifier.THUMB, ArmPoseModifier.INDEX]},
	ChessPiece.QUEEN: {"style": &"crown", "height": 0.058, "pitch": 15.0, "roll": 15.0,
		"contact": [ArmPoseModifier.THUMB, ArmPoseModifier.INDEX, ArmPoseModifier.MIDDLE]},
	ChessPiece.KING: {"style": &"crown", "height": 0.062, "pitch": 15.0, "roll": 15.0,
		"contact": [ArmPoseModifier.THUMB, ArmPoseModifier.INDEX, ArmPoseModifier.MIDDLE]},
}

static var _grasps: Dictionary = {}
static var _profiles: Dictionary = {}
static var _meshes: Dictionary = {}  # tipo -> Mesh del modelo
static var _materials: Dictionary = {}


## Altura total de una pieza (por código o tipo).
static func height_of(piece: int) -> float:
	return HEIGHTS[ChessPiece.type_of(piece)]


## Altura (desde la base) donde la pinza sujeta la pieza (ver `grasp_for`).
static func grip_height(piece: int) -> float:
	return grasp_for(piece).height


## Datos del agarre de una pieza (por código o tipo). Claves: `style` (&"pinch" pinza de pulgar,
## índice y medio sobre el cuerpo; &"crown" mano sobre la corona), `height` (m desde la base),
## `radius` (radio medido en la malla a esa altura), `contact` (dedos de `ArmPoseModifier` cuya
## yema toca), `pitch` (grados de la mano al agarrar), `top`, `profile` y `step` (radio de la
## malla cada `step` m desde la base).
static func grasp_for(piece: int) -> Dictionary:
	var type := ChessPiece.type_of(piece)
	if not _grasps.has(type):
		var def: Dictionary = GRASPS[type]
		var prof := profile_of(type)
		var h: float = def.height
		_grasps[type] = {
			"type": type, "style": def.style, "height": h, "radius": radius_at(type, h),
			"contact": PackedInt32Array(def.contact), "pitch": def.pitch,
			"top": HEIGHTS[type], "profile": prof.slice(0, mini(int(round((h + CONTACT_BAND) / PROFILE_STEP)) + 1, prof.size())), "step": PROFILE_STEP,
			"roll": def.roll,
		}
	return _grasps[type]


## Radio de la pieza (envolvente de la malla) a la altura `y` sobre la base.
static func radius_at(type: int, y: float) -> float:
	var prof := profile_of(type)
	var fi := clampf(y, 0.0, HEIGHTS[type]) / PROFILE_STEP
	var i := mini(int(fi), prof.size() - 2)
	return lerpf(prof[i], prof[i + 1], fi - float(i))


## Perfil de radios de la malla (cada `PROFILE_STEP` m desde la base): máxima distancia al eje
## de los puntos donde el plano horizontal corta los triángulos.
static func profile_of(type: int) -> PackedFloat32Array:
	if _profiles.has(type):
		return _profiles[type]
	var mesh := _model_mesh(type)
	var n := int(ceil(HEIGHTS[type] / PROFILE_STEP)) + 2
	var prof := PackedFloat32Array()
	prof.resize(n)
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(v.size())
			for k in v.size():
				idx[k] = k
		for t in range(0, idx.size() - 2, 3):
			var a := v[idx[t]]
			var b := v[idx[t + 1]]
			var c := v[idx[t + 2]]
			var lo := minf(a.y, minf(b.y, c.y))
			var hi := maxf(a.y, maxf(b.y, c.y))
			for k in range(maxi(int(floor(lo / PROFILE_STEP)), 0), mini(int(floor(hi / PROFILE_STEP)) + 1, n)):
				var y := float(k) * PROFILE_STEP
				for e in [[a, b], [b, c], [c, a]]:
					var p: Vector3 = e[0]
					var q: Vector3 = e[1]
					if (p.y - y) * (q.y - y) <= 0.0 and absf(p.y - q.y) > 1e-9:
						var m := p.lerp(q, (y - p.y) / (q.y - p.y))
						prof[k] = maxf(prof[k], Vector2(m.x, m.z).length())
	# Huecos entre vértices (caras horizontales): el radio nunca es 0 dentro de la pieza.
	for k in range(1, n):
		if prof[k] == 0.0 and float(k) * PROFILE_STEP <= HEIGHTS[type]:
			prof[k] = prof[k - 1]
	_profiles[type] = prof
	return prof


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
