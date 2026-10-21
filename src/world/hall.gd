class_name Hall
extends Node3D
## El salón del torneo: una sala oscura con las 16 mesas de `HallLayout` en
## cuadrícula 4x4 (todas con la misma orientación; blancas en +Z, negras en -Z),
## columnas, puertas, zócalos y estandartes. Cada mesa lleva su lámpara cónica
## (`SpotLight3D` + cono falso aditivo para el haz); solo la lámpara de la mesa del
## humano proyecta sombras. Los modelos son los `.glb` de `assets/models/props/`.
##
## La mesa del humano (`HallLayout.human_table`) está en el origen del mundo: la sala
## (suelo, muros, techo, podio) cuelga de un nodo `Sala` que se desplaza
## (`HallLayout.room_offset`) y cada mesa se coloca con `HallLayout.table_position`. Hay que
## fijar `HallLayout.set_human_table` ANTES de `build()`.
##
## Qué hay en cada mesa:
##  - mesa del humano: solo mesa, sillas y lámpara; lo de encima (tablero, piezas, reloj,
##    planillas) lo ponen el cliente y las manos;
##  - las demás: además tablero, reloj y dos planillas con pluma, fusionados en una
##    sola malla estática, y un nodo de piezas (`set_table_board`) que muestra una
##    posición cualquiera.
## Todas llevan una tarjeta con el número de mesa (legible desde la silla del humano) y su
## lujo crece con el número bajo (`HallLayout.richness`): mantel, marco dorado del tablero,
## candelabros y lámpara dorada; las mesas 1 y 2 están sobre el podio (tarima con rampas).
## Las figuras sentadas no son de esta clase: las crea `BackgroundTable`.
##
## Renderer GL Compatibility: sin niebla volumétrica; el haz de cada lámpara es un
## cono con un shader aditivo y sin iluminación. Para no pasar el límite de luces por
## objeto, el suelo se divide en una baldosa por mesa y el decorado se fusiona por muro.

const ROOM_HALF_X := 9.0
const ROOM_HALF_Z := 9.5
const CEILING_Y := 3.0
## El `.glb` de la lámpara cuelga del ancla; el foco queda 1,07 m más abajo (`LightAnchor`).
const LAMP_ANCHOR_Y := 3.0
const LIGHT_OFFSET := 1.07
## Altura del foco sobre el suelo (~1,93 m).
const LAMP_Y := LAMP_ANCHOR_Y - LIGHT_OFFSET
const SPOT_ANGLE := 31.0
## Mesa: 1,30 × 0,90 m. Sillas a ±SEAT_Z sobre el eje Z de la mesa.
const TABLE_SIZE := Vector2(1.3, 0.9)
const SEAT_Z := 0.80

## Energía de las lámparas de las mesas (encendidas del todo) y de la del humano.
const DECOR_ENERGY := 2.2
const MAIN_ENERGY := 0.8
const BULB_ON := Color(1.0, 0.9, 0.7)
const BULB_OFF := Color(0.06, 0.05, 0.045)
const FADE_SECONDS := 1.4
const STONE := Color(0.07, 0.065, 0.065)
const FLOOR_COLOR := Color(0.075, 0.062, 0.055)

## Compatibilidad con quien lea la disposición de las mesas por índice:
## [posición XZ, giro Y en grados, ocupantes iniciales]. La del humano no tiene ocupantes
## propios (los pone el cliente). Se deriva de `HallLayout` cada vez que se lee.
static var DECOR_TABLES: Array:
	get:
		var out: Array = []
		for i in HallLayout.table_count():
			var p := HallLayout.table_position(i)
			out.append([Vector2(p.x, p.z), 0.0, 0 if i == HallLayout.human_table else 2])
		return out

const PROPS := "res://assets/models/props/"

## Foco de la mesa del humano (con sombras).
var spot: SpotLight3D
## Estado de cada mesa (índice de `HallLayout`): {root, pieces, chairs, light, bulb_mat, cone, cone_mat,
## cone_strength, base_energy, level, active, tween, main}.
var _tables: Array[Dictionary] = []
var _scenes: Dictionary = {}
var _stone_mat: StandardMaterial3D
var _wall_wood_mat: StandardMaterial3D
var _piece_mats: Array[StandardMaterial3D] = []
## Piezas de las mesas ricas (marfil y ébano pulidos): se usan desde la riqueza 2.
var _rich_piece_mats: Array[StandardMaterial3D] = []
## Materiales del lujo de las mesas (mantel por riqueza, dorado, cera, llama).
var _cloth_mats: Array[StandardMaterial3D] = []
var _gold_mat: StandardMaterial3D
var _wax_mat: StandardMaterial3D
var _flame_mat: StandardMaterial3D
var _card_mats: Array[StandardMaterial3D] = []
var _ceiling: MeshInstance3D
## Todo lo fijo de la sala (suelo, muros, techo, podio), desplazado para que la mesa del humano
## quede en el origen.
var _room: Node3D


func build() -> void:
	name = "Salon"
	_stone_mat = _mat(STONE, 0.9)
	_piece_mats = [StaticBoard.make_material(StaticBoard.WHITE_COLOR), StaticBoard.make_material(StaticBoard.BLACK_COLOR)]
	_make_luxury_materials()
	_room = Node3D.new()
	_room.name = "Sala"
	_room.position = HallLayout.room_offset()
	add_child(_room)
	_build_room()
	for i in HallLayout.table_count():
		_build_table(i)
	spot = _tables[HallLayout.human_table].light


# --- Consultas ---------------------------------------------------------------------

## Posiciones (centro de la mesa, a ras de suelo) de las 16 mesas; índice = número de mesa.
static func table_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in HallLayout.table_count():
		out.append(HallLayout.table_position(i))
	return out


func table_count() -> int:
	return _tables.size()


## Posición del centro de la mesa `index` (a ras de suelo; sin la altura del podio).
func table_position(index: int) -> Vector3:
	if index < 0 or index >= _tables.size():
		return Vector3.ZERO
	return HallLayout.table_position(index)


## Nodo raíz de la mesa `index` (mesa, sillas, lámpara y lo que se le cuelgue).
func table_root(index: int) -> Node3D:
	if index < 0 or index >= _tables.size():
		return null
	return _tables[index].root


## Silla del asiento `seat` (0 = blancas, +Z; 1 = negras, -Z).
func chair(index: int, seat: int) -> Node3D:
	if index < 0 or index >= _tables.size():
		return null
	return _tables[index].chairs[seat]


## Posición local (en la mesa) del centro del asiento de `seat`.
static func seat_local(seat: int) -> Vector3:
	return Vector3(0.0, 0.0, SEAT_Z if seat == ChessPiece.WHITE else -SEAT_Z)


## Transformación MUNDIAL del asiento: origen en el centro de la silla, a ras de suelo, con
## +Z mirando hacia la mesa (la orientación que debe tener una figura sentada, que mira a +Z).
func seat_transform(index: int, seat: int) -> Transform3D:
	var root := table_root(index)
	var yaw := PI if seat == ChessPiece.WHITE else 0.0
	var local := Transform3D(Basis(Vector3.UP, yaw), seat_local(seat))
	if root == null:
		return local
	return (root.global_transform if root.is_inside_tree() else root.transform) * local


## Luz de la lámpara de la mesa `index` (-1 = la del humano).
func table_lamp(index: int) -> SpotLight3D:
	if index < 0:
		return spot
	if index >= _tables.size():
		return null
	return _tables[index].light


func is_table_active(index: int) -> bool:
	return index < 0 or (index < _tables.size() and _tables[index].active)


## Nivel de luz de la mesa (0 apagada, 1 encendida del todo).
func table_level(index: int) -> float:
	if index < 0 or index >= _tables.size():
		return 1.0
	return _tables[index].level


# --- Lámparas ------------------------------------------------------------------------

## Enciende o apaga la lámpara de una mesa (con atenuación si `animated`).
func set_table_active(index: int, on: bool, animated: bool = true) -> void:
	if index < 0 or index >= _tables.size():
		return
	_tables[index].active = on
	set_table_level(index, 1.0 if on else 0.0, animated)


## Fija el nivel de la lámpara (0..1) con atenuación opcional. Con `flicker` titila
## antes de asentarse en el nivel (la lámpara de una mesa donde acaban de ejecutar a alguien).
func set_table_level(index: int, level: float, animated: bool = true, flicker: bool = false) -> void:
	if index < 0 or index >= _tables.size():
		return
	var t: Dictionary = _tables[index]
	if t.tween != null and (t.tween as Tween).is_valid():
		(t.tween as Tween).kill()
	t.tween = null
	level = clampf(level, 0.0, 1.0)
	if not animated or not is_inside_tree():
		_apply_level(t, level)
		return
	var prev: float = t.level
	var start: float = prev
	var tw := create_tween()
	t.tween = tw
	var step := func(v: float) -> void: _apply_level(t, v)
	if flicker:
		for k in [0.15, 0.7, 0.05, 0.55, 0.0, 0.35]:
			var v: float = start * k
			tw.tween_method(step, prev, v, 0.06)
			tw.tween_interval(0.05)
			prev = v
	tw.tween_method(step, prev, level, FADE_SECONDS)


func _apply_level(t: Dictionary, k: float) -> void:
	t.level = k
	var light: SpotLight3D = t.light
	light.light_energy = t.base_energy * k
	light.visible = k > 0.003
	var bulb: StandardMaterial3D = t.bulb_mat
	bulb.emission_energy_multiplier = 3.0 * k
	bulb.albedo_color = BULB_OFF.lerp(BULB_ON, k)
	(t.cone_mat as ShaderMaterial).set_shader_parameter("strength", t.cone_strength * k)
	(t.cone as Node3D).visible = k > 0.003


# --- Piezas estáticas ----------------------------------------------------------------

## Muestra en la mesa `index` las piezas de `squares` (64 casillas, a1 = 0). La mesa del
## humano no tiene piezas propias (las pone el cliente).
func set_table_board(index: int, squares: PackedInt32Array) -> void:
	if index < 0 or index >= _tables.size():
		return
	var mi: MeshInstance3D = _tables[index].pieces
	if mi == null:
		return
	var mats := _rich_piece_mats if HallLayout.richness(index) >= 2 else _piece_mats
	mi.mesh = StaticBoard.build_mesh(squares, mats[0], mats[1], BoardView.TABLE_TOP + 0.015)
	mi.visible = true


func set_table_fen(index: int, fen: String) -> void:
	set_table_board(index, BoardState.from_fen(fen).squares)


## Posición inicial en la mesa `index` vista por quien se sienta en el lado +Z con el color
## `human_color` (el tablero gira 180° si es negro, como en `BoardView`).
func set_table_start_position(index: int, human_color: int) -> void:
	var sq := BoardState.start_position().squares
	if human_color == ChessPiece.BLACK:
		var rot := PackedInt32Array()
		rot.resize(64)
		for i in 64:
			rot[63 - i] = sq[i]
		sq = rot
	set_table_board(index, sq)


## Deja la lámpara de la mesa `index` como la de la mesa del humano (más tenue, más ancha,
## con relleno), animando la energía durante `seconds`. Sirve para que, al llegar caminando, la
## luz de la mesa sea la que tendrá la escena nueva. No cambia las sombras.
func make_lamp_like_main(index: int, seconds: float = 1.0) -> void:
	if index < 0 or index >= _tables.size():
		return
	var t: Dictionary = _tables[index]
	if t.main:
		return
	var l: SpotLight3D = t.light
	l.spot_angle = SPOT_ANGLE
	l.spot_range = 4.0
	l.spot_attenuation = 1.0
	l.spot_angle_attenuation = 1.6
	l.light_color = Color(1.0, 0.9, 0.78)
	t.base_energy = MAIN_ENERGY
	var level: float = t.level
	if seconds > 0.0 and is_inside_tree():
		var tw := create_tween()
		tw.tween_property(l, "light_energy", MAIN_ENERGY * level, seconds)
		# El haz falso y el relleno, igual que `_build_lamp(main)`.
		tw.parallel().tween_method(func(v: float) -> void:
			(t.cone_mat as ShaderMaterial).set_shader_parameter("strength", v), t.cone_strength * level, 0.10 * level, seconds)
	else:
		l.light_energy = MAIN_ENERGY * level
		(t.cone_mat as ShaderMaterial).set_shader_parameter("strength", 0.10 * level)
	t.cone_strength = 0.10
	var anchor := l.get_parent() as Node3D
	for sgn in [-1.0, 1.0]:
		var fill := OmniLight3D.new()
		fill.name = "Relleno"
		fill.position = Vector3(0.0, BoardView.TABLE_TOP + 0.38, sgn * 0.62) - Vector3(0.0, LAMP_Y, 0.0)
		fill.omni_range = 1.5
		fill.omni_attenuation = 1.4
		fill.light_energy = 0.2 * level
		fill.light_color = Color(1.0, 0.8, 0.6)
		fill.shadow_enabled = false
		anchor.add_child(fill)


## Quita las piezas de la mesa (mesa vacía).
func clear_table_board(index: int) -> void:
	if index < 0 or index >= _tables.size():
		return
	var mi: MeshInstance3D = _tables[index].pieces
	if mi != null:
		mi.visible = false


## Posición de medio juego propia de la mesa `index` (varía entre mesas).
static func mid_game_fen(index: int) -> String:
	return StaticBoard.MID_GAME_FENS[index % StaticBoard.MID_GAME_FENS.size()]


## Para vistas de depuración desde arriba: quita o pone el techo.
func set_ceiling_visible(on: bool) -> void:
	if _ceiling != null:
		_ceiling.visible = on


# --- Construcción: utilidades -----------------------------------------------------------

func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _scene(prop: String) -> PackedScene:
	if not _scenes.has(prop):
		_scenes[prop] = load(PROPS + prop + ".glb")
	return _scenes[prop]


func _inst(prop: String) -> Node3D:
	return _scene(prop).instantiate() as Node3D


## Funde un modelo (transformación `xf`) dentro de `baker` y libera la instancia.
func _bake_prop(baker: MeshBaker, prop: String, xf: Transform3D, tweak: Callable = Callable()) -> void:
	var n := _inst(prop)
	if tweak.is_valid():
		tweak.call(n)
	baker.add_tree(n, xf)
	n.free()


## Mismos colores que el tablero de la partida (`BoardView._dim_materials`), para que los tableros
## decorativos y el de la mesa del humano sean iguales al llegar a una mesa.
static func _recolor_board(model: Node3D) -> void:
	var colors := {"Light": BoardView.SQUARE_LIGHT, "Dark": BoardView.SQUARE_DARK, "Board_Frame": BoardView.FRAME_COLOR}
	# Las casillas quedan coplanares con la base: se suben unas décimas de milímetro (como `BoardView`).
	var squares := model.find_child("BoardSquares", true, false) as Node3D
	if squares != null:
		squares.position.y += 0.0007
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as StandardMaterial3D
			if mat != null and colors.has(mat.resource_name):
				var copy := mat.duplicate() as StandardMaterial3D
				copy.albedo_color = colors[mat.resource_name]
				copy.roughness = 0.8
				(mi as MeshInstance3D).set_surface_override_material(i, copy)


static func _xf(pos: Vector3, yaw: float = 0.0, scale: float = 1.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), pos)


# --- Sala ---------------------------------------------------------------------------------

func _build_room() -> void:
	_wall_wood_mat = _mat(Color(0.05, 0.035, 0.025), 0.8)
	var floor_mat := _mat(FLOOR_COLOR, 0.8)
	# Suelo: una baldosa por mesa (cada objeto toca pocas luces) más cuatro bandas de borde.
	var cw := HallLayout.SPACING_X
	var cd := HallLayout.SPACING_Z
	var tile := PlaneMesh.new()
	tile.size = Vector2(cw, cd)
	# Extremos de la cuadrícula en el marco de la sala.
	var x0 := HallLayout.room_position(HallLayout.index_at(0, 0)).x - cw * 0.5
	var x1 := HallLayout.room_position(HallLayout.index_at(HallLayout.COLS - 1, 0)).x + cw * 0.5
	var z0 := HallLayout.room_position(0).z - cd * 0.5
	var z1 := HallLayout.room_position(HallLayout.COLS * (HallLayout.ROWS - 1)).z + cd * 0.5
	for i in HallLayout.table_count():
		var mi := MeshInstance3D.new()
		mi.name = "Baldosa%d" % i
		mi.mesh = tile
		mi.material_override = floor_mat
		mi.position = HallLayout.room_position(i)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_room.add_child(mi)
	_build_podium()
	_floor_strip(Rect2(-ROOM_HALF_X, -ROOM_HALF_Z, x0 + ROOM_HALF_X, ROOM_HALF_Z * 2.0), floor_mat)
	_floor_strip(Rect2(x1, -ROOM_HALF_Z, ROOM_HALF_X - x1, ROOM_HALF_Z * 2.0), floor_mat)
	_floor_strip(Rect2(x0, -ROOM_HALF_Z, x1 - x0, z0 + ROOM_HALF_Z), floor_mat)
	_floor_strip(Rect2(x0, z1, x1 - x0, ROOM_HALF_Z - z1), floor_mat)
	# Techo: sin iluminación (las lámparas apuntan abajo), así no cuenta para el límite de luces.
	var ceil_mat := StandardMaterial3D.new()
	ceil_mat.albedo_color = Color(0.015, 0.014, 0.014)
	ceil_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var cm := PlaneMesh.new()
	cm.size = Vector2(ROOM_HALF_X * 2.0, ROOM_HALF_Z * 2.0)
	cm.flip_faces = true
	_ceiling = MeshInstance3D.new()
	_ceiling.name = "Techo"
	_ceiling.mesh = cm
	_ceiling.material_override = ceil_mat
	_ceiling.position = Vector3(0.0, CEILING_Y, 0.0)
	_ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_room.add_child(_ceiling)
	_build_walls()


func _floor_strip(r: Rect2, mat: Material) -> void:
	if r.size.x <= 0.01 or r.size.y <= 0.01:
		return
	var mi := MeshInstance3D.new()
	mi.name = "SueloBorde"
	var pm := PlaneMesh.new()
	pm.size = r.size
	mi.mesh = pm
	mi.material_override = mat
	mi.position = Vector3(r.position.x + r.size.x * 0.5, 0.0, r.position.y + r.size.y * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_room.add_child(mi)


## Cuatro muros; cada uno es una sola malla fusionada con losa, zócalo, columnas, puertas y estandartes.
func _build_walls() -> void:
	var hx := ROOM_HALF_X
	var hz := ROOM_HALF_Z
	var h := CEILING_Y
	# Norte (-Z, delante del jugador): mira a +Z.
	var north := MeshBaker.new()
	north.add_box(Vector3(hx * 2.0 + 0.6, h, 0.3), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, -hz - 0.15)), _stone_mat)
	_wall_panels(north, Vector3(-hx + 0.5, 0, -hz), Vector3(1, 0, 0), 0.0, int(hx * 2.0) - 1, [-6.0])
	_bake_prop(north, "door", _xf(Vector3(-6.0, 0, -hz + 0.14), 0.0))
	_bake_prop(north, "banner", _xf(Vector3(0.0, 2.95, -hz + 0.05), 0.0, 1.6))
	for sx in [-3.3, 3.3]:
		_bake_prop(north, "banner", _xf(Vector3(sx, 2.95, -hz + 0.05), 0.0, 1.2))
	for px in [-8.0, -2.0, 2.0, 5.0, 8.0]:
		_bake_prop(north, "pillar", _xf(Vector3(px, 0, -hz + 0.6)))
	_add_wall("MuroNorte", north)
	# Sur (+Z, a la espalda): mira a -Z.
	var south := MeshBaker.new()
	south.add_box(Vector3(hx * 2.0 + 0.6, h, 0.3), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, hz + 0.15)), _stone_mat)
	_wall_panels(south, Vector3(-hx + 0.5, 0, hz), Vector3(1, 0, 0), PI, int(hx * 2.0) - 1, [5.0])
	_bake_prop(south, "door", _xf(Vector3(5.0, 0, hz - 0.14), PI))
	_bake_prop(south, "banner", _xf(Vector3(-4.0, 2.95, hz - 0.05), PI, 1.2))
	for px in [-8.0, -4.0, 0.0, 2.0, 8.0]:
		_bake_prop(south, "pillar", _xf(Vector3(px, 0, hz - 0.6)))
	_add_wall("MuroSur", south)
	# Oeste (-X, a la izquierda): mira a +X.
	var west := MeshBaker.new()
	west.add_box(Vector3(0.3, h, hz * 2.0), Transform3D(Basis.IDENTITY, Vector3(-hx - 0.15, h * 0.5, 0)), _stone_mat)
	_wall_panels(west, Vector3(-hx, 0, -hz + 0.5), Vector3(0, 0, 1), PI * 0.5, int(hz * 2.0) - 1, [-2.0])
	_bake_prop(west, "door", _xf(Vector3(-hx + 0.14, 0, -2.0), PI * 0.5))
	_bake_prop(west, "banner", _xf(Vector3(-hx + 0.05, 2.95, -6.0), PI * 0.5, 1.2))
	_bake_prop(west, "banner", _xf(Vector3(-hx + 0.05, 2.95, 3.0), PI * 0.5, 1.2))
	for pz in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		_bake_prop(west, "pillar", _xf(Vector3(-hx + 0.6, 0, pz)))
	_add_wall("MuroOeste", west)
	# Este (+X, a la derecha): mira a -X.
	var east := MeshBaker.new()
	east.add_box(Vector3(0.3, h, hz * 2.0), Transform3D(Basis.IDENTITY, Vector3(hx + 0.15, h * 0.5, 0)), _stone_mat)
	_wall_panels(east, Vector3(hx, 0, -hz + 0.5), Vector3(0, 0, 1), -PI * 0.5, int(hz * 2.0) - 1, [])
	_bake_prop(east, "banner", _xf(Vector3(hx - 0.05, 2.95, -4.5), -PI * 0.5, 1.2))
	_bake_prop(east, "banner", _xf(Vector3(hx - 0.05, 2.95, 4.5), -PI * 0.5, 1.2))
	for pz in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		_bake_prop(east, "pillar", _xf(Vector3(hx - 0.6, 0, pz)))
	_add_wall("MuroEste", east)


## Zócalos cada metro a lo largo del muro (salvo donde hay puertas: `gaps` = centros).
func _wall_panels(baker: MeshBaker, start: Vector3, step: Vector3, yaw: float, count: int, gaps: Array) -> void:
	for k in count:
		var p := start + step * float(k)
		var along := p.x if step.x != 0.0 else p.z
		var skip := false
		for g in gaps:
			if absf(along - float(g)) < 1.3:
				skip = true
		if not skip:
			_bake_prop(baker, "wall_panel", _xf(p, yaw))


func _add_wall(node_name: String, baker: MeshBaker) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = baker.build()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_room.add_child(mi)


# --- Podio -----------------------------------------------------------------------------------

## Tarima de las mesas 1 y 2, con rampas en los bordes. Dos mallas (una por mesa) para no pasar el
## límite de luces por objeto; el borde interior entre ambas queda plano.
func _build_podium() -> void:
	var c := HallLayout.podium_center() - HallLayout.ROOM_ORIGIN
	var half := HallLayout.podium_half()
	var h := HallLayout.PODIUM_HEIGHT
	var r := HallLayout.PODIUM_RAMP
	var top_mat := _mat(Color(0.20, 0.035, 0.04), 0.9)
	var side_mat := _mat(Color(0.075, 0.045, 0.03), 0.8)
	for k in 2:
		# k = 0: mitad izquierda (mesa de la columna 1); k = 1: derecha.
		var sgn := -1.0 if k == 0 else 1.0
		var x_out := sgn * half.x          # borde exterior (relativo al centro)
		var x_in := 0.0                    # borde interior (pegado a la otra mitad)
		var zf := half.y
		var zb := -half.y
		var st_top := SurfaceTool.new()
		st_top.begin(Mesh.PRIMITIVE_TRIANGLES)
		var st_side := SurfaceTool.new()
		st_side.begin(Mesh.PRIMITIVE_TRIANGLES)
		var xo_t := x_out - sgn * r
		# Cara superior.
		_quad(st_top, Vector3(x_in, h, zb + r), Vector3(xo_t, h, zb + r), Vector3(xo_t, h, zf - r), Vector3(x_in, h, zf - r), Vector3.UP)
		# Rampa exterior (X), rampa frontal (+Z) y trasera (-Z).
		_quad(st_side, Vector3(xo_t, h, zb + r), Vector3(x_out, 0, zb), Vector3(x_out, 0, zf), Vector3(xo_t, h, zf - r), Vector3(sgn, 1.0, 0.0))
		_quad(st_side, Vector3(x_in, h, zf - r), Vector3(xo_t, h, zf - r), Vector3(x_out, 0, zf), Vector3(x_in, 0, zf), Vector3(0.0, 1.0, 1.0))
		_quad(st_side, Vector3(xo_t, h, zb + r), Vector3(x_in, h, zb + r), Vector3(x_in, 0, zb), Vector3(x_out, 0, zb), Vector3(0.0, 1.0, -1.0))
		var mesh := ArrayMesh.new()
		st_top.generate_normals()
		st_top.commit(mesh)
		mesh.surface_set_material(0, top_mat)
		st_side.generate_normals()
		st_side.commit(mesh)
		mesh.surface_set_material(1, side_mat)
		var mi := MeshInstance3D.new()
		mi.name = "Podio%d" % k
		mi.mesh = mesh
		mi.position = Vector3(c.x, 0.0, c.z)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_room.add_child(mi)


## Cuadrilátero a-b-c-d como dos triángulos con el orden de vértices que deja la cara mirando
## hacia `out` (en Godot la cara frontal es la de sentido horario).
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3) -> void:
	var flip := (b - a).cross(c - a).dot(out) > 0.0
	var tris: Array = [[a, c, b], [a, d, c]] if flip else [[a, b, c], [a, c, d]]
	for t in tris:
		for v in t:
			st.add_vertex(v)


# --- Mesas ---------------------------------------------------------------------------------

func _make_luxury_materials() -> void:
	_rich_piece_mats = [StaticBoard.make_material(Color(0.88, 0.86, 0.79)), StaticBoard.make_material(Color(0.07, 0.045, 0.035))]
	for m in _rich_piece_mats:
		m.roughness = 0.3
	_cloth_mats = [null, _mat(Color(0.06, 0.14, 0.09), 0.95), _mat(Color(0.28, 0.045, 0.06), 0.9), _mat(Color(0.36, 0.035, 0.07), 0.85)]
	_gold_mat = _mat(Color(0.30, 0.21, 0.08), 0.8)
	_wax_mat = _mat(Color(0.85, 0.8, 0.68), 0.7)
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.albedo_color = Color(1.0, 0.82, 0.45)
	_card_mats = [_mat(Color(0.62, 0.58, 0.48), 0.8), _mat(Color(0.66, 0.62, 0.5), 0.8), _mat(Color(0.40, 0.32, 0.17), 0.85), _mat(Color(0.42, 0.32, 0.14), 0.85)]


func _build_table(index: int) -> void:
	var main := index == HallLayout.human_table
	var tier := HallLayout.richness(index)
	var root := Node3D.new()
	root.name = "Mesa%d" % index
	root.position = HallLayout.table_position(index)
	root.position.y = HallLayout.floor_height(index) - HallLayout.floor_height(HallLayout.human_table)
	add_child(root)

	# Mesa (y, en las demás, tablero, reloj y planillas) fusionada en una sola malla.
	var kit := MeshBaker.new()
	_bake_prop(kit, "table", Transform3D.IDENTITY)
	_dress_table(kit, tier)
	if not main:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7919 * (index + 1)
		_bake_prop(kit, "board", Transform3D(Basis.IDENTITY, Vector3(0, BoardView.TABLE_TOP + 0.015, 0)), _recolor_board)
		var top := BoardView.TABLE_TOP
		_bake_prop(kit, "chess_clock", _xf(Vector3(0.47, top, 0.0), rng.randf_range(-0.25, 0.25)))
		# Planillas: la blanca delante-izquierda de las blancas; la negra, en diagonal opuesta.
		_bake_prop(kit, "scoresheet", _xf(Vector3(-0.40, top, 0.27), rng.randf_range(-0.15, 0.15)))
		_bake_prop(kit, "scoresheet", _xf(Vector3(0.40, top, -0.27), PI + rng.randf_range(-0.15, 0.15)))
		_bake_prop(kit, "pen", _xf(Vector3(-0.38, top + 0.0135, 0.30), rng.randf_range(-0.6, 0.6)))
		_bake_prop(kit, "pen", _xf(Vector3(0.38, top + 0.0135, -0.30), PI + rng.randf_range(-0.6, 0.6)))
	var kit_mi := MeshInstance3D.new()
	kit_mi.name = "MesaBase"
	kit_mi.mesh = kit.build()
	kit_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if not main else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(kit_mi)
	_add_number_card(root, index, tier)

	# Sillas (nodos reales: el árbitro o las figuras pueden moverlas). La de las blancas se
	# llama "Silla" y va a +Z girada 180°; la de las negras, "Silla2", a -Z sin girar.
	var chairs: Array[Node3D] = []
	for seat in 2:
		var c := _inst("chair")
		c.name = "Silla" if seat == ChessPiece.WHITE else "Silla2"
		c.position = seat_local(seat)
		c.rotation.y = PI if seat == ChessPiece.WHITE else 0.0
		root.add_child(c)
		chairs.append(c)

	# Piezas (solo mesas con partida): malla propia para poder cambiarla.
	var pieces: MeshInstance3D = null
	if not main:
		pieces = MeshInstance3D.new()
		pieces.name = "Piezas"
		pieces.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pieces.visible = false
		root.add_child(pieces)

	var t := _build_lamp(root, main)
	t["root"] = root
	t["chairs"] = chairs
	t["pieces"] = pieces
	t["main"] = main
	_tables.append(t)


## Lujo creciente según la riqueza: mantel (1+), ribete dorado, marco dorado del tablero y
## candelabros (2+), segundo candelabro (3). Todo fusionado en la malla de la mesa.
func _dress_table(kit: MeshBaker, tier: int) -> void:
	if tier <= 0:
		return
	var top := BoardView.TABLE_TOP
	var cloth := _cloth_mats[tier]
	var w := TABLE_SIZE.x + 0.08
	var d := TABLE_SIZE.y + 0.08
	kit.add_box(Vector3(w, 0.006, d), Transform3D(Basis.IDENTITY, Vector3(0, top + 0.003, 0)), cloth)
	# Faldón corto (la mesa lleva las rodillas debajo: no baja más de 5 cm).
	for sz in [-1.0, 1.0]:
		kit.add_box(Vector3(w, 0.05, 0.006), Transform3D(Basis.IDENTITY, Vector3(0, top - 0.022, sz * d * 0.5)), cloth)
	for sx in [-1.0, 1.0]:
		kit.add_box(Vector3(0.006, 0.05, d), Transform3D(Basis.IDENTITY, Vector3(sx * w * 0.5, top - 0.022, 0)), cloth)
	if tier < 2:
		return
	# Ribete dorado en el borde del mantel y marco dorado alrededor del tablero.
	var inset := 0.035
	for sz in [-1.0, 1.0]:
		kit.add_box(Vector3(w - 0.02, 0.0068, 0.012), Transform3D(Basis.IDENTITY, Vector3(0, top + 0.0034, sz * (d * 0.5 - inset))), _gold_mat)
	for sx in [-1.0, 1.0]:
		kit.add_box(Vector3(0.012, 0.0068, d - 0.02), Transform3D(Basis.IDENTITY, Vector3(sx * (w * 0.5 - inset), top + 0.0034, 0)), _gold_mat)
	var ring := 0.262
	for sz in [-1.0, 1.0]:
		kit.add_box(Vector3(ring * 2.0 + 0.016, 0.011, 0.016), Transform3D(Basis.IDENTITY, Vector3(0, top + 0.0055, sz * ring)), _gold_mat)
	for sx in [-1.0, 1.0]:
		kit.add_box(Vector3(0.016, 0.011, ring * 2.0 - 0.016), Transform3D(Basis.IDENTITY, Vector3(sx * ring, top + 0.0055, 0)), _gold_mat)
	# Candelabros en el costado izquierdo del jugador (-X), a los lados de la tarjeta.
	_bake_candlestick(kit, Vector3(-0.60, top + 0.006, 0.22), 0.85 if tier == 2 else 1.0)
	if tier >= 3:
		_bake_candlestick(kit, Vector3(-0.60, top + 0.006, -0.30), 1.0)


## Candelero dorado con vela y llama (la llama no es luz: material sin sombreado).
func _bake_candlestick(kit: MeshBaker, base: Vector3, scale: float) -> void:
	var s := scale
	var cyl := func(radius: float, height: float, y: float, mat: Material, top_r: float = -1.0) -> void:
		var cm := CylinderMesh.new()
		cm.bottom_radius = radius
		cm.top_radius = radius if top_r < 0.0 else top_r
		cm.height = height
		cm.radial_segments = 8
		cm.rings = 1
		kit.add_mesh(cm, Transform3D(Basis.IDENTITY, base + Vector3(0, y, 0)), mat)
	cyl.call(0.045 * s, 0.012 * s, 0.006 * s, _gold_mat, 0.03 * s)
	cyl.call(0.010 * s, 0.13 * s, 0.077 * s, _gold_mat)
	cyl.call(0.024 * s, 0.016 * s, 0.150 * s, _gold_mat, 0.032 * s)
	cyl.call(0.014 * s, 0.075 * s, 0.1955 * s, _wax_mat)
	var sm := SphereMesh.new()
	sm.radius = 0.0095 * s
	sm.height = 0.026 * s
	sm.radial_segments = 6
	sm.rings = 3
	kit.add_mesh(sm, Transform3D(Basis.IDENTITY, base + Vector3(0, 0.248 * s, 0)), _flame_mat)


## Tarjeta con el número de mesa, en pie a la izquierda del tablero (-X), girada hacia la silla (+Z). Se lee desde el asiento. El lujo cambia su material.
func _add_number_card(root: Node3D, index: int, tier: int) -> void:
	var card := Node3D.new()
	card.name = "Tarjeta"
	card.position = Vector3(-0.40, BoardView.TABLE_TOP + 0.05, -0.16)
	card.rotation = Vector3(deg_to_rad(-14.0), deg_to_rad(33.0), 0.0)
	root.add_child(card)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.17, 0.10, 0.008)
	box.mesh = bm
	box.material_override = _card_mats[tier]
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	card.add_child(box)
	var ink := Color(0.05, 0.035, 0.03)
	var num := Label3D.new()
	num.name = "Numero"
	num.text = str(HallLayout.number_of(index))
	num.font_size = 128
	num.pixel_size = 0.00055
	num.modulate = ink
	num.outline_size = 0
	num.shaded = false
	num.position = Vector3(0.0, -0.008, 0.0045)
	card.add_child(num)
	var cap := Label3D.new()
	cap.name = "Rotulo"
	cap.text = "TABLE"
	cap.font_size = 40
	cap.pixel_size = 0.00055
	cap.modulate = ink
	cap.outline_size = 0
	cap.shaded = false
	cap.position = Vector3(0.0, 0.034, 0.0045)
	card.add_child(cap)


## Lámpara del `.glb` colgada del techo, su foco y el cono falso. Devuelve el estado de la mesa.
func _build_lamp(root: Node3D, main: bool) -> Dictionary:
	var lamp := _inst("lamp")
	lamp.name = "Lampara"
	lamp.position = Vector3(0.0, LAMP_ANCHOR_Y, 0.0)
	root.add_child(lamp)
	var anchor := lamp.find_child("LightAnchor", true, false) as Node3D
	# La bombilla lleva su propio material emisivo (se apaga con la lámpara y con los apagones).
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = BULB_ON
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.85, 0.6)
	bulb_mat.emission_energy_multiplier = 3.0
	bulb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var bulb := lamp.find_child("LampBulb", true, false) as MeshInstance3D
	if bulb != null:
		bulb.material_override = bulb_mat
	var l := SpotLight3D.new()
	l.name = "Foco"
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.light_color = Color(1.0, 0.9, 0.78) if main else Color(1.0, 0.78, 0.55)
	if main:
		l.spot_angle = SPOT_ANGLE
		l.spot_range = 4.0
		l.spot_attenuation = 1.0
		l.spot_angle_attenuation = 1.6
		l.light_energy = MAIN_ENERGY
		l.shadow_enabled = true
		l.shadow_bias = 0.02
		l.shadow_normal_bias = 0.8
	else:
		l.spot_angle = 38.0
		l.spot_range = 2.9
		l.light_energy = DECOR_ENERGY
		l.shadow_enabled = false
	anchor.add_child(l)
	var strength := 0.10 if main else 0.06
	var cone := _light_cone(anchor, SPOT_ANGLE if main else 38.0, LAMP_Y, strength)
	if main:
		# Relleno suave a los dos lados del tablero: simula el rebote de la luz y deja
		# leer los costados de las piezas (la lámpara las ilumina casi solo por arriba).
		for sgn in [-1.0, 1.0]:
			var fill := OmniLight3D.new()
			fill.name = "Relleno"
			fill.position = Vector3(0.0, BoardView.TABLE_TOP + 0.38, sgn * 0.62) - Vector3(0.0, LAMP_Y, 0.0)
			fill.omni_range = 1.5
			fill.omni_attenuation = 1.4
			fill.light_energy = 0.2
			fill.light_color = Color(1.0, 0.8, 0.6)
			fill.shadow_enabled = false
			anchor.add_child(fill)
	return {
		"light": l, "bulb_mat": bulb_mat, "cone": cone, "cone_mat": cone.material_override,
		"cone_strength": strength, "base_energy": l.light_energy, "level": 1.0, "active": true, "tween": null,
	}


## Cono de luz falso: malla aditiva sin iluminación que se desvanece hacia abajo.
## `height` = altura del foco sobre el suelo; el cono cuelga de `parent` (en el foco).
func _light_cone(parent: Node3D, angle_deg: float, height: float, strength: float) -> MeshInstance3D:
	var cone := MeshInstance3D.new()
	cone.name = "Haz"
	var cm := CylinderMesh.new()
	cm.height = height - 0.05
	cm.top_radius = 0.05
	cm.bottom_radius = tan(deg_to_rad(angle_deg)) * cm.height
	cm.radial_segments = 24
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	cone.mesh = cm
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.82, 0.55, 1.0);
uniform float strength = 0.1;
void fragment() {
	float fade = pow(1.0 - UV.y, 1.4);
	float edge = pow(clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 0.8);
	ALBEDO = tint.rgb * strength * fade * (0.25 + 0.75 * edge);
	ALPHA = 1.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("strength", strength)
	cone.material_override = mat
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.position = Vector3(0, -cm.height * 0.5, 0)
	parent.add_child(cone)
	return cone
