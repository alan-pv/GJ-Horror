class_name ControlsHelp
extends VBoxContainer
## Cuadro de controles del jugador para el menú principal y el de pausa (el HUD ya no los muestra).
## Cada fila es [tecla, acción]; refleja los controles reales (`PlayerController`, `PieceInteraction`
## y `project.godot`). Dos columnas de parejas, y una sola si la ventana es estrecha.

## [tecla, acción] en el orden en que se muestran.
const ROWS: Array[Array] = [
	["Mouse", "Look around"],
	["Left click", "Pick up a piece, put it down"],
	["Right click", "Put the piece back"],
	["A", "Accuse your opponent"],
	["Esc", "Pause"],
	["Space", "Skip speeches and walks"],
]
## Consejo bajo los controles: en una línea, o en dos si la ventana es estrecha.
const TIP: Array[String] = ["Green squares are legal moves.", "Any other square is a cheat: don't let anyone see it."]
## Colócalo en la parte baja de un menú: `ControlsHelp.dock_bottom(help)`.
static func dock_bottom(help: Control) -> void:
	help.anchor_left = 0.04
	help.anchor_right = 0.96
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_left = 0
	help.offset_right = 0
	help.offset_top = -20
	help.offset_bottom = -20
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN


## Por debajo de este ancho de ventana se usa una sola columna.
const NARROW_WIDTH := 1000.0

var _grid: GridContainer
var _tip: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 20)
	_grid.add_theme_constant_override("v_separation", 4)
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid)
	var tip := Label.new()
	_tip = tip
	tip.add_theme_font_size_override("font_size", 18)
	tip.add_theme_color_override("font_color", UiTheme.DIM)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_OFF
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tip)
	get_viewport().size_changed.connect(_relayout)
	_relayout()


## Orden de las entradas en la rejilla: de izquierda a derecha y de arriba abajo. Con dos columnas
## de parejas, la fila r lleva la entrada r y la r + mitad (`-1` = hueco).
static func layout_order(count: int, narrow: bool) -> Array[int]:
	var out: Array[int] = []
	if narrow:
		for i in count:
			out.append(i)
		return out
	var half := (count + 1) / 2
	for r in half:
		out.append(r)
		out.append(r + half if r + half < count else -1)
	return out


func _relayout() -> void:
	var narrow := get_viewport().get_visible_rect().size.x < NARROW_WIDTH
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_grid.columns = 2 if narrow else 4
	_tip.text = ("\n" if narrow else " ").join(TIP)
	for i in layout_order(ROWS.size(), narrow):
		_pair(ROWS[i] if i >= 0 else ["", ""])


func _pair(row: Array) -> void:
	var key := Label.new()
	key.text = row[0]
	key.add_theme_font_size_override("font_size", 22)
	key.add_theme_color_override("font_color", UiTheme.BLOOD_BRIGHT)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key.custom_minimum_size = Vector2(120, 0)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_child(key)
	var act := Label.new()
	act.text = row[1]
	act.add_theme_font_size_override("font_size", 22)
	act.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_child(act)
