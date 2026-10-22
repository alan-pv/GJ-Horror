class_name SettingsPanel
extends Control
## Panel de ajustes superpuesto (menú principal y pausa): volumen de Master,
## Music y SFX, sensibilidad del ratón y pantalla completa. Lee y escribe a
## través de `AudioManager` y `GameSettings`, que lo guardan en disco.
##
##     var panel := SettingsPanel.new()
##     add_child(panel)
##     panel.open()

signal closed

## Buses con fila de volumen, en orden.
const BUSES := ["Master", "Music", "SFX"]

## Con false no se cierra con Esc (lo cierra quien lo aloja, p. ej. la pausa).
var close_on_escape: bool = true

## Los autoloads se piden por ruta (no por identificador) para que este script
## compile también en las pruebas `--script`, donde no existen.
@onready var _audio: Node = get_node("/root/AudioManager")
@onready var _game: Node = get_node("/root/GameSettings")
var _rows: VBoxContainer
var _amounts: Dictionary = {}
var _sens_amount: Label
var _back: Button


func _ready() -> void:
	# Usable con el juego en pausa y fuera de la animación de entrada de la escena.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("no_intro")
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var caption := Label.new()
	caption.text = "Settings"
	caption.add_theme_font_size_override("font_size", 44)
	caption.add_theme_color_override("font_color", UiTheme.BLOOD_BRIGHT)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	box.add_child(_rows)

	_back = Button.new()
	_back.text = "Back"
	_back.pressed.connect(close)
	box.add_child(_back)


func open() -> void:
	_rebuild_rows()
	visible = true
	_back.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	_audio.save_settings()
	_game.save_settings()
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and close_on_escape and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


# Las filas se rehacen en cada apertura: los buses y los ajustes son la verdad.

func _rebuild_rows() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_amounts.clear()
	for bus_name in BUSES:
		if _audio.bus_names().has(bus_name):
			_add_row(bus_name, _audio.bus_volume(bus_name), 0.0, 1.0,
					_on_volume_changed.bind(bus_name), bus_name)
	_sens_amount = _add_row("Mouse sensitivity", _game.mouse_sensitivity,
			_game.SENSITIVITY_MIN, _game.SENSITIVITY_MAX,
			_on_sensitivity_changed, "sens")
	if _game.fullscreen_supported():
		var full := CheckButton.new()
		full.text = "Fullscreen"
		full.button_pressed = _game.fullscreen
		full.toggled.connect(func(on: bool) -> void: _game.set_fullscreen(on))
		_rows.add_child(full)


## Fila con título, porcentaje y deslizador. Devuelve la etiqueta del porcentaje.
func _add_row(title: String, value: float, min_v: float, max_v: float, callback: Callable, key: String) -> Label:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var header := HBoxContainer.new()
	row.add_child(header)
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var amount := Label.new()
	amount.custom_minimum_size = Vector2(70, 0)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.add_theme_color_override("font_color", UiTheme.DIM)
	header.add_child(amount)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = 0.01
	slider.value = value
	slider.custom_minimum_size = Vector2(0, 24)
	slider.value_changed.connect(callback)
	# Se guarda en disco al soltar el deslizador, no en cada píxel del arrastre.
	slider.drag_ended.connect(func(changed: bool) -> void:
		if changed:
			_audio.save_settings()
			_game.save_settings())
	row.add_child(slider)
	_rows.add_child(row)
	_amounts[key] = amount
	amount.text = "%d%%" % roundi(value * 100.0)
	return amount


func _on_volume_changed(value: float, bus_name: String) -> void:
	_audio.set_bus_volume(bus_name, value)
	(_amounts[bus_name] as Label).text = "%d%%" % roundi(value * 100.0)


func _on_sensitivity_changed(value: float) -> void:
	_game.set_mouse_sensitivity(value)
	_sens_amount.text = "%d%%" % roundi(value * 100.0)
