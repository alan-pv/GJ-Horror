class_name UiTheme
extends RefCounted
## Tema de los menús, construido en código: negro, rojo apagado y una tipografía
## antigua (IM Fell Double Pica SC, licencia OFL; ver `assets/CREDITS.md`).

const FONT_PATH := "res://assets/fonts/IMFellDoublePicaSC.ttf"

const BLACK := Color(0.02, 0.016, 0.02)
const PANEL := Color(0.055, 0.04, 0.045, 0.96)
const TEXT := Color(0.80, 0.76, 0.70)
const DIM := Color(0.50, 0.46, 0.44)
const BLOOD := Color(0.55, 0.07, 0.07)
const BLOOD_BRIGHT := Color(0.78, 0.14, 0.12)

static var _theme: Theme = null


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func font() -> Font:
	return load(FONT_PATH) as Font


static func _box(bg: Color, border: Color, border_width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(2)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func _build() -> Theme:
	var t := Theme.new()
	var f := font()
	if f != null:
		t.default_font = f
	t.default_font_size = 24

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1.0, 0.86, 0.80))
	t.set_color("font_pressed_color", "Button", Color(1.0, 0.86, 0.80))
	t.set_color("font_focus_color", "Button", Color(1.0, 0.86, 0.80))
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_font_size("font_size", "Button", 30)

	t.set_stylebox("normal", "Button", _box(Color(0.04, 0.03, 0.035, 0.85), Color(0.25, 0.1, 0.1)))
	t.set_stylebox("hover", "Button", _box(Color(0.16, 0.035, 0.04, 0.95), BLOOD_BRIGHT))
	t.set_stylebox("pressed", "Button", _box(Color(0.28, 0.04, 0.05, 1.0), BLOOD_BRIGHT))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), BLOOD, 2))
	t.set_stylebox("disabled", "Button", _box(Color(0.04, 0.03, 0.035, 0.5), Color(0.15, 0.1, 0.1)))

	t.set_stylebox("panel", "PanelContainer", _box(PANEL, Color(0.30, 0.09, 0.09), 2))

	# Controles de los ajustes: deslizador y casilla en rojo apagado.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.13, 0.09, 0.09)
	track.set_corner_radius_all(2)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = BLOOD
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_font_size("font_size", "CheckButton", 24)
	return t
