class_name PauseMenu
extends CanvasLayer
## Menú de pausa de la partida: Esc pausa el árbol (relojes, bots, tweens) y suelta
## el ratón; Resume, Settings y Main menu. Lo crea `GameRoot` y escucha `opened`
## y `resumed` para soltar o recapturar el ratón del jugador.

signal opened
signal resumed

var _root: Control
var _buttons: Control
var _settings: SettingsPanel
var _resume: Button


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.theme = UiTheme.get_theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.offset_bottom = -150   # la franja de abajo es de los controles
	_root.add_child(col)
	_buttons = col

	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 80)
	title.add_theme_color_override("font_color", UiTheme.BLOOD_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_resume = _button("Resume", resume)
	_button("Settings", func() -> void: _settings.open())
	_button("Main menu", _to_main_menu)

	var help := ControlsHelp.new()
	ControlsHelp.dock_bottom(help)
	_root.add_child(help)

	_settings = SettingsPanel.new()
	_settings.close_on_escape = false
	_root.add_child(_settings)
	_settings.closed.connect(func() -> void: _resume.grab_focus())


func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 54)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(callback)
	_buttons.add_child(b)
	return b


func is_open() -> bool:
	return _root != null and _root.visible


func open() -> void:
	if is_open():
		return
	_root.visible = true
	get_tree().paused = true
	opened.emit()
	_resume.grab_focus()


func resume() -> void:
	if not is_open():
		return
	_settings.close()
	_root.visible = false
	get_tree().paused = false
	resumed.emit()


func _to_main_menu() -> void:
	_root.visible = false
	get_node("/root/SceneSwitcher").go_to("res://src/ui/main_menu.tscn")


## Esc abre la pausa, o cierra los ajustes / la pausa si ya está abierta.
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if not is_open():
		open()
	elif _settings.visible:
		_settings.close()
	else:
		resume()
