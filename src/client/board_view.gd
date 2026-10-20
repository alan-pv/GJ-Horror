class_name BoardView
extends Node3D
## Vista 3D del tablero físico: 64 casillas, marco de madera, piezas con su
## desplazamiento fino (descentrado), pilas de captura junto a cada jugador y
## mapa de calor de la pieza elegida (casillas por nivel de sospecha y zona de la pila propia).
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
## Zona de la pila propia donde se suelta una pieza rival para robarla: ancho (X), fondo (Z) y
## centro en Z (el signo depende del lado). Cubre las 4 columnas y unas 4 filas de la pila.
const PILE_ZONE_SIZE := Vector2(0.19, 0.17)
const PILE_ZONE_Z := 0.25
## Margen extra (m) al apuntar con el rayo a la zona de la pila.
const PILE_ZONE_MARGIN := 0.015

## Colores del mapa de calor por nivel de sospecha (0 = jugada legal, 1 sutil, 2+ rojo cada vez
## más oscuro) y su opacidad, que baja con el nivel para no ensuciar el tablero.
const HEAT_COLORS := [
	Color(0.25, 0.85, 0.35), Color(1.0, 0.58, 0.12), Color(0.96, 0.08, 0.08),
	Color(0.76, 0.04, 0.10), Color(0.52, 0.0, 0.12),
]
const HEAT_ALPHAS := [0.55, 0.45, 0.30, 0.12, 0.04]
## Rojo tenue de la zona de la pila.
const PILE_ZONE_COLOR := Color(0.85, 0.12, 0.1, 0.22)
const PILE_ZONE_HOVER_COLOR := Color(0.95, 0.2, 0.15, 0.42)

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
var _sel_marker: Node3D
var _hover_marker: Node3D
## Casillas del mapa de calor (una por casilla, se crean al usarlas) y anillos de captura.
var _heat_tiles: Dictionary = {}
var _capture_rings: Array[MeshInstance3D] = []
## Zona de la pila de capturas propia (rectángulo en la mesa) y su material.
var _pile_zone: MeshInstance3D
var _pile_zone_mat: StandardMaterial3D
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


## Centro local de la zona de la pila de capturas de `by_color` (a la altura de la mesa).
func pile_zone_center(by_color: int) -> Vector3:
	var sgn := 1.0 if by_color == near_color else -1.0
	return Vector3(PILE_X, TABLE_TOP, sgn * PILE_ZONE_Z)


## ¿El punto del mundo cae dentro de la zona de la pila de capturas de `by_color`?
func pile_zone_contains(p: Vector3, by_color: int) -> bool:
	return zone_hit(to_local(p), by_color == near_color)


## Función pura: ¿el punto local (con su Z) cae en la zona de la pila del lado cercano o lejano?
static func zone_hit(local: Vector3, near: bool) -> bool:
	var l := local - Vector3(PILE_X, 0.0, (1.0 if near else -1.0) * PILE_ZONE_Z)
	var half := PILE_ZONE_SIZE * 0.5 + Vector2.ONE * PILE_ZONE_MARGIN
	return absf(l.x) <= half.x and absf(l.z) <= half.y


## ¿El rayo apunta a la zona de la pila de capturas de `by_color`? (corta el plano de la mesa).
func ray_to_pile(origin: Vector3, dir: Vector3, by_color: int) -> bool:
	if absf(dir.y) < 0.0001:
		return false
	var t := (TABLE_TOP - origin.y) / dir.y
	if t < 0.0:
		return false
	return pile_zone_contains(origin + dir * t, by_color)


## Color con opacidad del mapa de calor para un nivel (0 verde, 1 naranja, 2 rojo, 3+ más oscuro).
## Función pura: niveles negativos se tratan como 0 y los altos como el último.
static func heat_color(level: int) -> Color:
	var i := clampi(level, 0, HEAT_COLORS.size() - 1)
	var c: Color = HEAT_COLORS[i]
	c.a = HEAT_ALPHAS[i]
	return c


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

## Mapa de calor de la pieza elegida: colorea cada casilla de `levels` ({casilla: nivel}) según
## `heat_color`, contornea la seleccionada y marca con un anillo las capturas legales (`captures`).
## Si `levels` trae `CheatRules.TO_PILE` (pieza rival) ilumina la zona de la pila propia.
func set_heatmap(selected: int, levels: Dictionary, captures: Array = []) -> void:
	clear_highlights()
	if selected >= 0:
		_sel_marker.global_position = square_to_world(selected) + Vector3(0, 0.0016, 0)
		_sel_marker.visible = true
	for key in levels.keys():
		var sq := int(key)
		if sq < 0 or sq > 63:
			continue
		var tile := _heat_tile(sq)
		(tile.material_override as StandardMaterial3D).albedo_color = heat_color(int(levels[key]))
		tile.global_position = square_to_world(sq) + Vector3(0, 0.0012, 0)
		tile.visible = true
	for i in captures.size():
		var ring := _capture_ring(i)
		ring.global_position = square_to_world(int(captures[i])) + Vector3(0, 0.0018, 0)
		ring.visible = true
	if levels.has(CheatRules.TO_PILE):
		_pile_zone_mat.albedo_color = PILE_ZONE_COLOR
		_pile_zone.visible = true


func clear_highlights() -> void:
	_sel_marker.visible = false
	for tile in _heat_tiles.values():
		tile.visible = false
	for r in _capture_rings:
		r.visible = false
	_pile_zone.visible = false


func set_hover(sq: int) -> void:
	_hover_marker.visible = sq >= 0
	if sq >= 0:
		_hover_marker.global_position = square_to_world(sq) + Vector3(0, 0.0020, 0)


## Resalta la zona de la pila (el rayo del jugador apunta a ella) si está iluminada.
func set_pile_hover(on: bool) -> void:
	if _pile_zone.visible:
		_pile_zone_mat.albedo_color = PILE_ZONE_HOVER_COLOR if on else PILE_ZONE_COLOR


func _heat_tile(sq: int) -> MeshInstance3D:
	var t: MeshInstance3D = _heat_tiles.get(sq)
	if t == null:
		t = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(SQUARE * 0.98, 0.0008, SQUARE * 0.98)
		t.mesh = bm
		t.material_override = _flat_material(Color.WHITE)
		t.visible = false
		_hl_root.add_child(t)
		_heat_tiles[sq] = t
	return t


func _capture_ring(i: int) -> MeshInstance3D:
	while _capture_rings.size() <= i:
		var ring := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.019
		tor.outer_radius = 0.025
		tor.rings = 24
		tor.ring_segments = 6
		ring.mesh = tor
		ring.scale = Vector3(1, 0.2, 1)
		ring.material_override = _flat_material(Color(1.0, 0.25, 0.2, 0.9))
		ring.visible = false
		_hl_root.add_child(ring)
		_capture_rings.append(ring)
	return _capture_rings[i]


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
	_dim_materials(model)
	# Las casillas coinciden con la cara superior del marco: se alzan 0,7 mm contra el parpadeo.
	var squares := model.find_child("BoardSquares", true, false) as Node3D
	if squares != null:
		squares.position.y = 0.0007


## Colores del tablero bajo la lámpara (ambiente de terror: nada quemado): casillas claras de
## hueso/crema apagado, oscuras de madera, marco de madera oscura. Las piezas blancas
## (`PieceFactory.IVORY`) quedan más claras que las casillas claras y las negras más oscuras.
const SQUARE_LIGHT := Color(0.54, 0.49, 0.38)
const SQUARE_DARK := Color(0.27, 0.16, 0.09)
const FRAME_COLOR := Color(0.19, 0.12, 0.075)


## Sustituye los colores del modelo (pensados para luz neutra) por los de `SQUARE_*`/`FRAME_COLOR`.
func _dim_materials(model: Node3D) -> void:
	var colors := {"Light": SQUARE_LIGHT, "Dark": SQUARE_DARK, "Board_Frame": FRAME_COLOR}
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as StandardMaterial3D
			if mat != null and colors.has(mat.resource_name):
				var copy := mat.duplicate() as StandardMaterial3D
				copy.albedo_color = colors[mat.resource_name]
				copy.roughness = 0.8
				(mi as MeshInstance3D).set_surface_override_material(i, copy)


func _build_highlights() -> void:
	_hl_root = Node3D.new()
	_hl_root.name = "Resaltado"
	add_child(_hl_root)
	_sel_marker = _outline(Color(1.0, 0.88, 0.3, 0.95), 0.0035)
	_hover_marker = _outline(Color(1.0, 1.0, 1.0, 0.8), 0.0022)
	# Zona de la pila propia: rectángulo plano sobre la mesa (oculto hasta que se roba).
	_pile_zone = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(PILE_ZONE_SIZE.x, 0.0008, PILE_ZONE_SIZE.y)
	_pile_zone.mesh = bm
	_pile_zone_mat = _flat_material(PILE_ZONE_COLOR)
	_pile_zone.material_override = _pile_zone_mat
	_pile_zone.position = pile_zone_center(near_color) + Vector3(0, 0.0012, 0)
	_pile_zone.visible = false
	_hl_root.add_child(_pile_zone)


## Contorno claro de una casilla (cuatro barras finas); se mueve con `global_position`.
func _outline(c: Color, thickness: float) -> Node3D:
	var holder := Node3D.new()
	var mat := _flat_material(c)
	var half := SQUARE * 0.5
	for side in 4:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var horizontal := side < 2
		bm.size = Vector3(SQUARE if horizontal else thickness, 0.0008, thickness if horizontal else SQUARE)
		bar.mesh = bm
		bar.material_override = mat
		var sgn := -1.0 if side % 2 == 0 else 1.0
		bar.position = Vector3(0.0, 0.0, sgn * (half - thickness * 0.5)) if horizontal \
				else Vector3(sgn * (half - thickness * 0.5), 0.0, 0.0)
		holder.add_child(bar)
	holder.visible = false
	_hl_root.add_child(holder)
	return holder


func _lit_material(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
