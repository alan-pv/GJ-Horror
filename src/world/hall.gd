class_name Hall
extends Node3D
## El salón: suelo, paredes y columnas oscuras, la mesa principal con sus
## sillas, la lámpara cónica (SpotLight3D con sombras + cono falso para el
## haz) y varias mesas decorativas tenues con siluetas sentadas.
##
## Renderer GL Compatibility: no hay niebla volumétrica; el haz de la
## lámpara es un cono con un shader aditivo y sin iluminación.

const ROOM_HALF_X := 11.0
const ROOM_HALF_Z := 13.0
const CEILING_Y := 4.6
const LAMP_Y := 1.95
const SPOT_ANGLE := 31.0
## Mesa principal: 1,30 × 0,90 m.
const TABLE_SIZE := Vector2(1.3, 0.9)

const WOOD := Color(0.13, 0.075, 0.04)
const STONE := Color(0.07, 0.065, 0.065)

## Mesas decorativas: [posición XZ, giro Y en grados, ocupantes (0-2)].
const DECOR_TABLES := [
	[Vector2(-3.6, -1.8), 20.0, 2],
	[Vector2(3.9, -2.6), -35.0, 2],
	[Vector2(-3.8, 3.2), 70.0, 1],
	[Vector2(3.6, 3.6), 5.0, 2],
	[Vector2(0.4, -5.6), 90.0, 2],
	[Vector2(-6.4, 0.2), 0.0, 0],
	[Vector2(6.6, 0.6), 45.0, 2],
	[Vector2(-1.2, 6.4), 100.0, 2],
	[Vector2(2.4, 7.8), -20.0, 1],
]

var spot: SpotLight3D
var _wood_mat: StandardMaterial3D
var _stone_mat: StandardMaterial3D


func build() -> void:
	name = "Salon"
	_wood_mat = _mat(WOOD, 0.6)
	_stone_mat = _mat(STONE, 0.9)
	_build_room()
	_build_table(Vector3.ZERO, 0.0, true)
	_build_main_lamp()
	for i in DECOR_TABLES.size():
		var d: Array = DECOR_TABLES[i]
		_build_decor_table(Vector3(d[0].x, 0.0, d[0].y), deg_to_rad(d[1]), d[2], i)


## Posiciones (centro de la mesa, a ras de suelo) de las mesas decorativas,
## en el mismo orden que DECOR_TABLES. Índice = número de mesa.
static func table_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for d in DECOR_TABLES:
		out.append(Vector3(d[0].x, 0.0, d[0].y))
	return out


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


# --- Sala --------------------------------------------------------------------

func _build_room() -> void:
	var floor_mat := _mat(Color(0.075, 0.062, 0.055), 0.8)
	_box(self, Vector3(ROOM_HALF_X * 2.0, 0.2, ROOM_HALF_Z * 2.0), Vector3(0, -0.1, 0), floor_mat)
	_box(self, Vector3(ROOM_HALF_X * 2.0, 0.2, ROOM_HALF_Z * 2.0), Vector3(0, CEILING_Y + 0.1, 0), _stone_mat)
	var h := CEILING_Y
	_box(self, Vector3(0.3, h, ROOM_HALF_Z * 2.0), Vector3(-ROOM_HALF_X, h * 0.5, 0), _stone_mat)
	_box(self, Vector3(0.3, h, ROOM_HALF_Z * 2.0), Vector3(ROOM_HALF_X, h * 0.5, 0), _stone_mat)
	_box(self, Vector3(ROOM_HALF_X * 2.0, h, 0.3), Vector3(0, h * 0.5, -ROOM_HALF_Z), _stone_mat)
	_box(self, Vector3(ROOM_HALF_X * 2.0, h, 0.3), Vector3(0, h * 0.5, ROOM_HALF_Z), _stone_mat)
	# Columnas a lo largo de las paredes laterales.
	var col_mat := _mat(Color(0.09, 0.085, 0.08), 0.8)
	for x in [-8.0, 8.0]:
		for z in [-9.0, -3.0, 3.0, 9.0]:
			var c := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.35
			cm.bottom_radius = 0.4
			cm.height = h
			cm.radial_segments = 14
			c.mesh = cm
			c.material_override = col_mat
			c.position = Vector3(x, h * 0.5, z)
			add_child(c)
	# Una puerta en la pared de atrás del jugador (ruidos futuros).
	var door_mat := _mat(Color(0.12, 0.07, 0.04), 0.7)
	_box(self, Vector3(1.2, 2.2, 0.1), Vector3(-3.0, 1.1, ROOM_HALF_Z - 0.2), door_mat)
	_box(self, Vector3(1.4, 2.35, 0.06), Vector3(-3.0, 1.175, ROOM_HALF_Z - 0.16), _mat(Color(0.05, 0.04, 0.03), 0.8))


# --- Mesas ------------------------------------------------------------------------

## Mesa con sus sillas. La mesa principal usa más detalle.
func _build_table(pos: Vector3, yaw: float, main: bool) -> Node3D:
	var t := Node3D.new()
	t.name = "MesaPrincipal" if main else "MesaDecor"
	t.position = pos
	t.rotation.y = yaw
	add_child(t)
	var top_y := BoardView.TABLE_TOP
	_box(t, Vector3(TABLE_SIZE.x, 0.04, TABLE_SIZE.y), Vector3(0, top_y - 0.02, 0), _wood_mat)
	# Faldón y patas.
	_box(t, Vector3(TABLE_SIZE.x - 0.1, 0.08, TABLE_SIZE.y - 0.1), Vector3(0, top_y - 0.08, 0), _wood_mat)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(t, Vector3(0.07, top_y - 0.04, 0.07), Vector3(sx * (TABLE_SIZE.x * 0.5 - 0.08), (top_y - 0.04) * 0.5, sz * (TABLE_SIZE.y * 0.5 - 0.08)), _wood_mat)
	_build_chair(t, 1.0)
	_build_chair(t, -1.0)
	return t


## Silla a +Z (sgn = 1) o -Z (sgn = -1), mirando hacia la mesa.
func _build_chair(parent: Node3D, sgn: float) -> void:
	var c := Node3D.new()
	c.name = "Silla"
	c.position = Vector3(0, 0, sgn * 0.80)
	parent.add_child(c)
	var m := _wood_mat
	_box(c, Vector3(0.44, 0.04, 0.44), Vector3(0, 0.45, 0), m)
	_box(c, Vector3(0.44, 0.5, 0.04), Vector3(0, 0.72, sgn * 0.21), m)
	for lx in [-1.0, 1.0]:
		for lz in [-1.0, 1.0]:
			_box(c, Vector3(0.04, 0.43, 0.04), Vector3(lx * 0.19, 0.215, lz * 0.19), m)


func _build_decor_table(pos: Vector3, yaw: float, occupants: int, index: int) -> void:
	var t := _build_table(pos, yaw, false)
	# Tablero plano con dos tonos y unas piezas oscuras como volumen.
	var board_mat := _mat(Color(0.16, 0.10, 0.06), 0.6)
	_box(t, Vector3(0.46, 0.02, 0.46), Vector3(0, BoardView.TABLE_TOP + 0.01, 0), board_mat)
	var light_mat := _mat(Color(0.4, 0.32, 0.22), 0.6)
	for i in 6:
		var p := Vector3(sin(index * 3.1 + i * 2.3) * 0.15, BoardView.TABLE_TOP + 0.045, cos(index * 1.7 + i * 1.9) * 0.15)
		_box(t, Vector3(0.025, 0.05, 0.025), p, light_mat if i % 2 == 0 else _stone_mat)
	var cloths := [Color(0.10, 0.09, 0.13), Color(0.13, 0.07, 0.07), Color(0.07, 0.10, 0.09)]
	for s in occupants:
		var sgn := 1.0 if s == 0 else -1.0
		var fig := OpponentAvatar.build_figure(Color(0.45, 0.34, 0.28), cloths[(index + s) % 3], false, true)
		var root: Node3D = fig.root
		root.position = Vector3(0, 0, sgn * 0.55)
		# La figura mira hacia -Z local; para estar en +Z y mirar la mesa no gira.
		root.rotation.y = 0.0 if sgn > 0.0 else PI
		# Inclinación leve de la cabeza para que no sean clones.
		fig.head.rotation.y = sin(index * 2.1 + s) * 0.5
		t.add_child(root)
	# Lámpara tenue sin sombras.
	var lamp := Node3D.new()
	lamp.position = Vector3(0, LAMP_Y + 0.1, 0)
	t.add_child(lamp)
	_lamp_fixture(lamp, 0.16)
	var l := SpotLight3D.new()
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.spot_angle = 38.0
	l.spot_range = 3.4
	l.light_energy = 2.2
	l.light_color = Color(1.0, 0.78, 0.55)
	l.shadow_enabled = false
	lamp.add_child(l)
	_light_cone(lamp, 38.0, LAMP_Y + 0.1, 0.06)


# --- Lámpara principal --------------------------------------------------------------

func _build_main_lamp() -> void:
	var lamp := Node3D.new()
	lamp.name = "Lampara"
	lamp.position = Vector3(0, LAMP_Y, 0)
	add_child(lamp)
	_lamp_fixture(lamp, 0.22)
	spot = SpotLight3D.new()
	spot.name = "Foco"
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.spot_angle = SPOT_ANGLE
	spot.spot_range = 4.0
	spot.spot_attenuation = 1.0
	spot.spot_angle_attenuation = 1.6
	spot.light_energy = 1.4
	spot.light_color = Color(1.0, 0.88, 0.72)
	spot.shadow_enabled = true
	spot.shadow_bias = 0.02
	spot.shadow_normal_bias = 0.8
	lamp.add_child(spot)
	_light_cone(lamp, SPOT_ANGLE, LAMP_Y, 0.10)
	# Relleno suave a los dos lados del tablero: simula el rebote de la luz y deja
	# leer los costados de las piezas (la lámpara las ilumina casi solo por arriba).
	for sgn in [-1.0, 1.0]:
		var fill := OmniLight3D.new()
		fill.name = "Relleno"
		fill.position = Vector3(0.0, BoardView.TABLE_TOP + 0.38, sgn * 0.62) - lamp.position
		fill.omni_range = 1.5
		fill.omni_attenuation = 1.4
		fill.light_energy = 0.28
		fill.light_color = Color(1.0, 0.8, 0.6)
		fill.shadow_enabled = false
		lamp.add_child(fill)


## Pantalla cónica, bombilla y cable hasta el techo.
func _lamp_fixture(lamp: Node3D, radius: float) -> void:
	var shade := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = radius
	cm.height = radius * 0.9
	cm.radial_segments = 20
	shade.mesh = cm
	shade.material_override = _mat(Color(0.05, 0.12, 0.08), 0.4)
	shade.position = Vector3(0, radius * 0.45, 0)
	lamp.add_child(shade)
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.08
	bulb.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(1.0, 0.9, 0.7)
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.85, 0.6)
	bm.emission_energy_multiplier = 3.0
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bulb.material_override = bm
	bulb.position = Vector3(0, 0.0, 0)
	lamp.add_child(bulb)
	var cable := MeshInstance3D.new()
	var cc := CylinderMesh.new()
	var cable_len := CEILING_Y - lamp.position.y - radius * 0.9
	cc.top_radius = 0.008
	cc.bottom_radius = 0.008
	cc.height = cable_len
	cc.radial_segments = 6
	cable.mesh = cc
	cable.material_override = _mat(Color(0.02, 0.02, 0.02), 0.9)
	cable.position = Vector3(0, radius * 0.9 + cable_len * 0.5, 0)
	lamp.add_child(cable)


## Cono de luz falso: malla aditiva sin iluminación que se desvanece hacia abajo.
func _light_cone(lamp: Node3D, angle_deg: float, height: float, strength: float) -> void:
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.height = height - 0.05
	cm.top_radius = 0.05
	cm.bottom_radius = tan(deg_to_rad(angle_deg)) * cm.height
	cm.radial_segments = 32
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
	lamp.add_child(cone)
