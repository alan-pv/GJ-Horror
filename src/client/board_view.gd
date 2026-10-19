class_name BoardView
extends Node3D
## Vista 3D del tablero físico: 64 casillas, marco de madera, piezas con su
## desplazamiento fino (descentrado), pilas de captura junto a cada jugador y
## resaltado de casilla seleccionada y destinos legales.
##
## Escala: metros (ver PieceFactory). Se espera que este nodo esté en el
## origen del mundo; el centro del tablero queda a la altura de la mesa.
##
## Convive con las animaciones de la mano: mientras haya animaciones en
## curso (`hold_sync`), `sync()` solo anota que hay trabajo pendiente y se
## aplica cuando la última animación termina. Las animaciones mueven los
## nodos con `take_piece`, `put_piece` y `add_to_pile`.

signal motion_released

const SQUARE := PieceFactory.SQUARE
const TABLE_TOP := 0.72
## Altura de la cara superior de las casillas.
const BOARD_TOP := TABLE_TOP + 0.015
const MODEL_PATH := "res://assets/models/props/board.glb"
## Centro de la mesa a la altura del tablero (lo que usa el servidor para la mirada).
const CENTER := Vector3(0.0, BOARD_TOP, 0.0)
## Centros de las pilas de captura (lado +X, a la derecha del humano y a la izquierda del rival).
const PILE_X := 0.42
const PILE_Z := 0.22
const PILE_COLUMNS := 4
const PILE_SPACING := 0.04

## true cuando el humano juega con negras (el tablero se gira para tenerlas cerca).
var flipped: bool = false
## Color del jugador humano (el que está en el lado +Z).
var near_color: int = ChessPiece.WHITE
## sq -> Node3D de la pieza que está sobre esa casilla.
var pieces: Dictionary = {}
## piles[color] = nodos capturados POR ese color, en orden.
var piles: Array = [[], []]

## Cuántas piezas tuvo que corregir `sync` (la animación no las dejó donde el servidor dice).
## Sirve para depurar: tras una partida sin trampas debería quedar en 0.
var sync_fixes: int = 0
var _synced_once: bool = false

var _tiles_root: Node3D
var _pieces_root: Node3D
var _hl_root: Node3D
var _sel_marker: MeshInstance3D
var _hover_marker: MeshInstance3D
var _target_markers: Array[Node3D] = []
var _holds: int = 0
var _pending_sync: BoardState = null
var _motion_busy: bool = false


func setup(p_near_color: int) -> void:
	near_color = p_near_color
	flipped = p_near_color == ChessPiece.BLACK
	_build_board()
	_build_highlights()


# --- Conversión casilla <-> mundo -------------------------------------------

## Centro de la casilla en coordenadas globales (a la altura de la cara del tablero).
func square_to_world(sq: int, with_offset: bool = false, offset: Vector2 = Vector2.ZERO) -> Vector3:
	var p := square_local(sq)
	if with_offset:
		p += offset_to_world(offset)
	return to_global(p)


## Centro de la casilla en coordenadas locales del tablero.
func square_local(sq: int) -> Vector3:
	var f := ChessPiece.file_of(sq)
	var r := ChessPiece.rank_of(sq)
	if flipped:
		return Vector3((3.5 - f) * SQUARE, BOARD_TOP, (r - 3.5) * SQUARE)
	return Vector3((f - 3.5) * SQUARE, BOARD_TOP, (3.5 - r) * SQUARE)


## Desplazamiento fino (fracciones de casilla: x archivo, y fila) a metros en el mundo.
func offset_to_world(offset: Vector2) -> Vector3:
	var sgn := -1.0 if flipped else 1.0
	return Vector3(offset.x * SQUARE * sgn, 0.0, -offset.y * SQUARE * sgn)


## Casilla bajo un punto del mundo (en el plano del tablero) o -1 si cae fuera.
func world_to_square(p: Vector3) -> int:
	var l := to_local(p)
	var f: int
	var r: int
	if flipped:
		f = int(floor(4.0 - l.x / SQUARE))
		r = int(floor(4.0 + l.z / SQUARE))
	else:
		f = int(floor(4.0 + l.x / SQUARE))
		r = int(floor(4.0 - l.z / SQUARE))
	if f < 0 or f > 7 or r < 0 or r > 7:
		return -1
	return ChessPiece.square(f, r)


## Intersección de un rayo con el plano del tablero. Devuelve Vector3.INF si no corta.
func ray_to_board_point(origin: Vector3, dir: Vector3) -> Vector3:
	if absf(dir.y) < 0.0001:
		return Vector3.INF
	var t := (BOARD_TOP - origin.y) / dir.y
	if t < 0.0:
		return Vector3.INF
	return origin + dir * t


## Posición global del hueco `index` de la pila de capturas hecha por `by_color`.
func pile_slot(by_color: int, index: int) -> Vector3:
	var near := by_color == near_color
	var sgn := 1.0 if near else -1.0
	var col := index % PILE_COLUMNS
	var row := index / PILE_COLUMNS
	var jitter := Vector3(sin(index * 12.9898) * 0.004, 0.0, cos(index * 78.233) * 0.004)
	var p := Vector3(PILE_X + (col - (PILE_COLUMNS - 1) * 0.5) * PILE_SPACING, BOARD_TOP - 0.016 + 0.0, sgn * (PILE_Z - 0.04 + row * PILE_SPACING)) + jitter
	p.y = TABLE_TOP
	return to_global(p)


## Dirección en la que miran las piezas de `color` (hacia el asiento rival), como giro en Y.
func piece_yaw(color: int) -> float:
	# El lado cercano mira hacia -Z; el lejano, hacia +Z.
	return 0.0 if color == near_color else PI


func piece_height_at(sq: int) -> float:
	var n: Node3D = pieces.get(sq)
	return PieceFactory.height_of(n.get_meta("code")) if n != null else 0.0


# --- Sincronización con el estado --------------------------------------------

## Conserva el estado pendiente mientras haya animaciones; ver `release_sync`.
func hold_sync() -> void:
	_holds += 1


func release_sync() -> void:
	_holds = maxi(0, _holds - 1)
	if _holds == 0 and _pending_sync != null:
		var s := _pending_sync
		_pending_sync = null
		sync(s)


func is_animating() -> bool:
	return _holds > 0


## Animaciones en cola entre las dos manos (las que aún no terminaron).
func pending_jobs() -> int:
	return _holds


## Reconcilia los nodos con el tablero físico del servidor.
func sync(state: BoardState) -> void:
	if _holds > 0:
		_pending_sync = state
		return
	var unmatched: Array[Node3D] = []
	for sq in pieces.keys():
		var node: Node3D = pieces[sq]
		if state.squares[sq] != int(node.get_meta("code")):
			unmatched.append(node)
			pieces.erase(sq)
			if _synced_once:
				sync_fixes += 1
	for sq in 64:
		var code := state.squares[sq]
		if code == ChessPiece.NONE:
			continue
		var node: Node3D = pieces.get(sq)
		if node == null:
			for i in unmatched.size():
				if int(unmatched[i].get_meta("code")) == code:
					node = unmatched[i]
					unmatched.remove_at(i)
					break
			if node == null:
				node = PieceFactory.build(code)
				_pieces_root.add_child(node)
			pieces[sq] = node
		_place(node, sq, state.offsets[sq])
	for n in unmatched:
		n.queue_free()
	_synced_once = true
	for color in 2:
		_sync_pile(color, state.captured[color])


func _sync_pile(color: int, codes: Array) -> void:
	var pile: Array = piles[color]
	var same := pile.size() == codes.size()
	if same:
		for i in pile.size():
			if int(pile[i].get_meta("code")) != int(codes[i]):
				same = false
				break
	if same:
		return
	for n in pile:
		n.queue_free()
	pile.clear()
	for i in codes.size():
		var node := PieceFactory.build(int(codes[i]))
		_pieces_root.add_child(node)
		node.global_position = pile_slot(color, i)
		node.rotation.y = float(i) * 1.7
		pile.append(node)


func _place(node: Node3D, sq: int, offset: Vector2) -> void:
	node.global_position = square_to_world(sq, true, offset)
	node.global_rotation = Vector3(0.0, piece_yaw(ChessPiece.color_of(int(node.get_meta("code")))), 0.0)


# --- Primitivas para las animaciones ------------------------------------------

## Saca el nodo de la casilla para que la mano lo lleve. Queda en el árbol.
func take_piece(sq: int) -> Node3D:
	var node: Node3D = pieces.get(sq)
	pieces.erase(sq)
	return node


## Deja el nodo en la casilla (quitando cualquier otro que hubiera por error).
func put_piece(node: Node3D, sq: int, offset: Vector2 = Vector2.ZERO) -> void:
	var old: Node3D = pieces.get(sq)
	if old != null and old != node:
		old.queue_free()
	if node.get_parent() != _pieces_root:
		node.reparent(_pieces_root, false)
	pieces[sq] = node
	_place(node, sq, offset)


## Manda el nodo a la pila del color que capturó. Devuelve su hueco.
func add_to_pile(node: Node3D, by_color: int) -> Vector3:
	var pile: Array = piles[by_color]
	if node.get_parent() != _pieces_root:
		node.reparent(_pieces_root, false)
	var slot := pile_slot(by_color, pile.size())
	node.global_position = slot
	node.global_rotation = Vector3(0.0, float(pile.size()) * 1.7, 0.0)
	pile.append(node)
	return slot


## Cambia la pieza de la casilla por otra (coronación).
func replace_piece(sq: int, code: int) -> void:
	var old: Node3D = pieces.get(sq)
	var offset := Vector2.ZERO
	if old != null:
		old.queue_free()
	var node := PieceFactory.build(code)
	_pieces_root.add_child(node)
	pieces[sq] = node
	_place(node, sq, offset)


func acquire_motion() -> void:
	while _motion_busy:
		await motion_released
	_motion_busy = true


func release_motion() -> void:
	_motion_busy = false
	motion_released.emit()


# --- Resaltado -----------------------------------------------------------------

## `targets`: Array de {sq:int, capture:bool}.
func set_highlights(selected: int, targets: Array) -> void:
	clear_highlights()
	if selected >= 0:
		_sel_marker.global_position = square_to_world(selected) + Vector3(0, 0.0012, 0)
		_sel_marker.visible = true
	for i in targets.size():
		var m := _get_target_marker(i)
		m.get_child(0).visible = not targets[i].capture
		m.get_child(1).visible = targets[i].capture
		m.global_position = square_to_world(targets[i].sq) + Vector3(0, 0.0015, 0)
		m.visible = true


func clear_highlights() -> void:
	_sel_marker.visible = false
	for m in _target_markers:
		m.visible = false


func set_hover(sq: int) -> void:
	_hover_marker.visible = sq >= 0
	if sq >= 0:
		_hover_marker.global_position = square_to_world(sq) + Vector3(0, 0.001, 0)


func _get_target_marker(i: int) -> Node3D:
	while _target_markers.size() <= i:
		var holder := Node3D.new()
		var dot := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.0105
		cyl.bottom_radius = 0.0105
		cyl.height = 0.0012
		dot.mesh = cyl
		dot.material_override = _flat_material(Color(0.35, 1.0, 0.45, 0.85))
		var ring := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.019
		tor.outer_radius = 0.025
		tor.rings = 24
		tor.ring_segments = 6
		ring.mesh = tor
		ring.scale = Vector3(1, 0.2, 1)
		ring.material_override = _flat_material(Color(1.0, 0.25, 0.2, 0.9))
		holder.add_child(dot)
		holder.add_child(ring)
		holder.visible = false
		_hl_root.add_child(holder)
		_target_markers.append(holder)
	return _target_markers[i]


func _flat_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.no_depth_test = false
	m.render_priority = 1
	return m


# --- Construcción --------------------------------------------------------------

func _build_board() -> void:
	_tiles_root = Node3D.new()
	_tiles_root.name = "Casillas"
	add_child(_tiles_root)
	_pieces_root = Node3D.new()
	_pieces_root.name = "Piezas"
	add_child(_pieces_root)
	# Modelo de Blender: superficie de juego a y=0 (el marco baja hasta -0,015) y a1 en
	# la esquina (-X, +Z); con el tablero girado (humano con negras) se gira 180 grados.
	var scene := load(MODEL_PATH) as PackedScene
	var model := scene.instantiate() as Node3D
	model.name = "TableroModelo"
	model.position = Vector3(0.0, BOARD_TOP, 0.0)
	model.rotation.y = PI if flipped else 0.0
	_tiles_root.add_child(model)
	# Las casillas coinciden con la cara superior del marco: se alzan 0,7 mm contra el parpadeo.
	var squares := model.find_child("BoardSquares", true, false) as Node3D
	if squares != null:
		squares.position.y = 0.0007


func _build_highlights() -> void:
	_hl_root = Node3D.new()
	_hl_root.name = "Resaltado"
	add_child(_hl_root)
	_sel_marker = _flat_square(Color(1.0, 0.85, 0.2, 0.55))
	_hover_marker = _flat_square(Color(1.0, 1.0, 1.0, 0.2))


func _flat_square(c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(SQUARE * 0.96, 0.0008, SQUARE * 0.96)
	mi.mesh = bm
	mi.material_override = _flat_material(c)
	mi.visible = false
	_hl_root.add_child(mi)
	return mi


func _lit_material(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
