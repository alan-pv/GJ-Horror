class_name Hall
extends Node3D
## El salón del torneo: una sala oscura con las 16 mesas de `HallLayout` en
## cuadrícula 4x4 (todas con la misma orientación; blancas en +Z, negras en -Z),
## columnas, puertas, zócalos y estandartes. Cada mesa lleva su lámpara cónica
## (`SpotLight3D` + cono falso aditivo para el haz); solo la lámpara de la mesa del
## humano proyecta sombras. Los modelos son los `.glb` de `assets/models/props/`.
##
## Qué hay en cada mesa:
##  - mesa del humano (`HallLayout.HUMAN_TABLE`): solo mesa, sillas y lámpara; lo de
##    encima (tablero, piezas, reloj, planillas) lo ponen el cliente y las manos;
##  - las demás: además tablero, reloj y dos planillas con pluma, fusionados en una
##    sola malla estática, y un nodo de piezas (`set_table_board`) que muestra una
##    posición cualquiera.
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
const MAIN_ENERGY := 1.4
const BULB_ON := Color(1.0, 0.9, 0.7)
const BULB_OFF := Color(0.06, 0.05, 0.045)
const FADE_SECONDS := 1.4
const STONE := Color(0.07, 0.065, 0.065)
const FLOOR_COLOR := Color(0.075, 0.062, 0.055)

## Compatibilidad con quien lea la disposición de las mesas por índice:
## [posición XZ, giro Y en grados, ocupantes iniciales]. La del humano no tiene ocupantes
## propios (los pone el cliente). Se deriva de `HallLayout`.
const DECOR_TABLES := [
	[Vector2(-3.0, -6.4), 0.0, 2], [Vector2(0.0, -6.4), 0.0, 2], [Vector2(3.0, -6.4), 0.0, 2], [Vector2(6.0, -6.4), 0.0, 2],
	[Vector2(-3.0, -3.2), 0.0, 2], [Vector2(0.0, -3.2), 0.0, 2], [Vector2(3.0, -3.2), 0.0, 2], [Vector2(6.0, -3.2), 0.0, 2],
	[Vector2(-3.0, 0.0), 0.0, 2], [Vector2(0.0, 0.0), 0.0, 0], [Vector2(3.0, 0.0), 0.0, 2], [Vector2(6.0, 0.0), 0.0, 2],
	[Vector2(-3.0, 3.2), 0.0, 2], [Vector2(0.0, 3.2), 0.0, 2], [Vector2(3.0, 3.2), 0.0, 2], [Vector2(6.0, 3.2), 0.0, 2],
]

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
var _ceiling: MeshInstance3D


func build() -> void:
	name = "Salon"
	_stone_mat = _mat(STONE, 0.9)
	_piece_mats = [StaticBoard.make_material(StaticBoard.WHITE_COLOR), StaticBoard.make_material(StaticBoard.BLACK_COLOR)]
	_build_room()
	for i in HallLayout.table_count():
		_build_table(i)
	spot = _tables[HallLayout.HUMAN_TABLE].light


# --- Consultas ---------------------------------------------------------------------

## Posiciones (centro de la mesa, a ras de suelo) de las 16 mesas; índice = número de mesa.
static func table_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in HallLayout.table_count():
		out.append(HallLayout.table_position(i))
	return out


func table_count() -> int:
	return _tables.size()


## Posición del centro de la mesa `index` (a ras de suelo).
func table_position(index: int) -> Vector3:
	if index < 0 or index >= _tables.size():
		return Vector3.ZERO
	return (_tables[index].root as Node3D).position


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
	mi.mesh = StaticBoard.build_mesh(squares, _piece_mats[0], _piece_mats[1], BoardView.TABLE_TOP + 0.015)
	mi.visible = true


func set_table_fen(index: int, fen: String) -> void:
	set_table_board(index, BoardState.from_fen(fen).squares)


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
	var x0 := HallLayout.table_position(0).x - cw * 0.5
	var x1 := HallLayout.table_position(HallLayout.COLS - 1).x + cw * 0.5
	var z0 := HallLayout.table_position(0).z - cd * 0.5
	var z1 := HallLayout.table_position(HallLayout.COLS * (HallLayout.ROWS - 1)).z + cd * 0.5
	for i in HallLayout.table_count():
		var mi := MeshInstance3D.new()
		mi.name = "Baldosa%d" % i
		mi.mesh = tile
		mi.material_override = floor_mat
		mi.position = HallLayout.table_position(i)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
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
	add_child(_ceiling)
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
	add_child(mi)


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
	add_child(mi)


# --- Mesas ---------------------------------------------------------------------------------

func _build_table(index: int) -> void:
	var main := index == HallLayout.HUMAN_TABLE
	var root := Node3D.new()
	root.name = "Mesa%d" % index
	root.position = HallLayout.table_position(index)
	add_child(root)

	# Mesa (y, en las demás, tablero, reloj y planillas) fusionada en una sola malla.
	var kit := MeshBaker.new()
	_bake_prop(kit, "table", Transform3D.IDENTITY)
	if not main:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7919 * (index + 1)
		_bake_prop(kit, "board", Transform3D(Basis.IDENTITY, Vector3(0, BoardView.TABLE_TOP + 0.015, 0)))
		var top := BoardView.TABLE_TOP
		_bake_prop(kit, "chess_clock", _xf(Vector3(0.47, top, 0.0), rng.randf_range(-0.25, 0.25)), func(n: Node3D) -> void:
			for hand in ["Hand_A_Left", "Hand_A_Right", "Hand_B_Left", "Hand_B_Right"]:
				var hn := n.find_child(hand, true, false) as Node3D
				if hn != null:
					hn.rotation.z = rng.randf() * TAU)
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
	l.light_color = Color(1.0, 0.88, 0.72) if main else Color(1.0, 0.78, 0.55)
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
			fill.light_energy = 0.28
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
