class_name MainMenu
extends Control
## Menú principal: título (`GameSettings.GAME_TITLE`), Play, Settings y Quit.
## Play carga la partida con un torneo nuevo.
##
## Si el juego arranca con argumentos de usuario (`-- --autoplay`, `--screenshot=...`)
## salta directo a la partida, como antes de que hubiera menú. Con `--menu` se
## queda aquí; `--menu-screen=settings` abre los ajustes y `--screenshot=ruta`
## guarda una captura (solo con `--menu`); `--menu-play` pulsa Play solo.

var _settings: SettingsPanel
var _play: Button


func _ready() -> void:
	var args := _user_args()
	if not args.is_empty() and not args.has("menu"):
		get_tree().change_scene_to_file.call_deferred(GameSettings.GAME_SCENE)
		return
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	if str(args.get("menu-screen", "")) == "settings":
		_settings.open()
	if args.has("menu-play"):
		# Prueba del flujo completo: pulsa Play solo (la captura la hace la partida).
		_on_play.call_deferred()
	elif args.has("screenshot"):
		_capture_later(str(args["screenshot"]), float(args.get("shot-delay", 1.5)))


static func _user_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/menu_background.gdshader")
	bg.material = mat
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_to_group("no_intro")
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	add_child(col)

	var title := Label.new()
	title.text = GameSettings.GAME_TITLE
	title.add_theme_font_size_override("font_size", 120)
	title.add_theme_color_override("font_color", UiTheme.BLOOD_BRIGHT)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 5)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	col.add_child(gap)

	_play = _button(col, "Play", _on_play)
	_button(col, "Settings", func() -> void: _settings.open())
	if not OS.has_feature("web"):
		_button(col, "Quit", func() -> void: SceneSwitcher.quit_game())

	_settings = SettingsPanel.new()
	add_child(_settings)
	_settings.closed.connect(func() -> void: _play.grab_focus())
	_play.grab_focus.call_deferred()


func _button(parent: Control, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 58)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(callback)
	parent.add_child(b)
	return b


func _on_play() -> void:
	# Torneo nuevo: GameRoot crea uno si no hay ninguno guardado.
	TournamentSession.manager = null
	TournamentSession.elapsed = 0.0
	SceneSwitcher.go_to(SceneSwitcher.GAME)


func _capture_later(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(path)
		print("[captura] guardada en ", path)
	get_tree().quit()
