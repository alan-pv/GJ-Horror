class_name CheatPanel
extends CanvasLayer
## Panel discreto de trampas, abajo a la derecha: una fila por trampa con su
## tecla, la armada resaltada y una línea de estado ("elige una pieza...").
## Es solo vista: la lógica vive en `CheatArmState` y `CheatInput`.

const TEXT := Color(0.80, 0.74, 0.62)
const DIM := Color(0.50, 0.46, 0.40)
const ACCENT := Color(1.0, 0.78, 0.35)

var _rows: Array[Label] = []
var _status: Label
var _box: PanelContainer


## `names`: nombre visible de cada trampa, en orden de tecla 1..N.
func setup(names: Array[String]) -> void:
	layer = 11
	_box = PanelContainer.new()
	_box.anchor_left = 1.0
	_box.anchor_right = 1.0
	_box.anchor_top = 1.0
	_box.anchor_bottom = 1.0
	_box.offset_left = -270
	_box.offset_right = -18
	_box.offset_top = -190
	_box.offset_bottom = -18
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.03, 0.025, 0.62)
	style.border_color = Color(0.35, 0.27, 0.15, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(10)
	_box.add_theme_stylebox_override("panel", style)
	add_child(_box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	_box.add_child(col)
	var title := Label.new()
	title.text = "Under the table"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", DIM)
	col.add_child(title)
	for i in names.size():
		var l := Label.new()
		l.text = "   [%d]  %s" % [i + 1, names[i]]
		l.add_theme_font_size_override("font_size", 17)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l)
		_rows.append(l)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", ACCENT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(220, 0)
	col.add_child(_status)
	set_state(-1, "")


## Resalta la trampa armada (`armed` = -1 ninguna) y muestra el texto de estado.
func set_state(armed: int, status: String) -> void:
	for i in _rows.size():
		var on := i == armed
		_rows[i].add_theme_color_override("font_color", ACCENT if on else TEXT)
		_rows[i].text = ("> " if on else "   ") + _rows[i].text.substr(3)
	_status.text = status
	_status.visible = status != ""
