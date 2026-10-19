class_name Hud
extends CanvasLayer
## Interfaz mínima: subtítulo (murmullos del personaje), veredicto del árbitro,
## contador de advertencias, pista de controles, pantalla de resultado y una
## viñeta oscura sobre toda la imagen.

const TEXT_COLOR := Color(0.93, 0.89, 0.80)

var _subtitle: Label
var _arbiter: Label
var _warnings: Label
var _hint: Label
var _capture_prompt: Label
var _crosshair: ColorRect
var _result_panel: ColorRect
var _result_title: Label
var _result_reason: Label
var _result_restart: Label
var _round_info: Label
var _rounds_left: Label
var _own_clock: Label
var _rival_clock: Label
var _pace: Label
var _status: Label
var _subtitle_tween: Tween
var _arbiter_tween: Tween


func _ready() -> void:
	layer = 10
	_build_vignette()
	_subtitle = _label(26, TEXT_COLOR)
	_subtitle.anchor_left = 0.1
	_subtitle.anchor_right = 0.9
	_subtitle.anchor_top = 1.0
	_subtitle.anchor_bottom = 1.0
	_subtitle.offset_top = -110
	_subtitle.offset_bottom = -60
	_subtitle.modulate.a = 0.0
	_arbiter = _label(30, Color(1.0, 0.82, 0.45))
	_arbiter.anchor_left = 0.1
	_arbiter.anchor_right = 0.9
	_arbiter.anchor_top = 0.14
	_arbiter.anchor_bottom = 0.14
	_arbiter.offset_top = 0
	_arbiter.offset_bottom = 50
	_arbiter.modulate.a = 0.0
	_warnings = _label(18, TEXT_COLOR)
	_warnings.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_warnings.position = Vector2(20, 14)
	_warnings.size = Vector2(320, 30)
	_hint = _label(15, Color(0.7, 0.67, 0.6))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint.position = Vector2(20, 40)
	_hint.size = Vector2(700, 24)
	_hint.text = "Click: pick and move · 1-4: cheat · A: accuse · Esc: pause"
	_crosshair = ColorRect.new()
	_crosshair.color = Color(1, 1, 1, 0.55)
	_crosshair.anchor_left = 0.5
	_crosshair.anchor_right = 0.5
	_crosshair.anchor_top = 0.5
	_crosshair.anchor_bottom = 0.5
	_crosshair.offset_left = -2
	_crosshair.offset_right = 2
	_crosshair.offset_top = -2
	_crosshair.offset_bottom = 2
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.visible = false
	add_child(_crosshair)
	_capture_prompt = _label(22, Color(1.0, 0.85, 0.5))
	_capture_prompt.anchor_left = 0.1
	_capture_prompt.anchor_right = 0.9
	_capture_prompt.anchor_top = 0.5
	_capture_prompt.anchor_bottom = 0.5
	_capture_prompt.offset_top = -200
	_capture_prompt.offset_bottom = -160
	_capture_prompt.text = "Click to take control of the mouse"
	_capture_prompt.visible = false
	# Torneo: ronda y jugadores restantes arriba a la derecha, cuadro de la ronda debajo.
	_round_info = _label(22, Color(1.0, 0.82, 0.45))
	_round_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_round_info.anchor_left = 1.0
	_round_info.anchor_right = 1.0
	_round_info.offset_left = -420
	_round_info.offset_right = -20
	_round_info.offset_top = 12
	_round_info.offset_bottom = 44
	_rounds_left = _label(16, Color(0.78, 0.74, 0.66))
	_rounds_left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rounds_left.anchor_left = 1.0
	_rounds_left.anchor_right = 1.0
	_rounds_left.offset_left = -420
	_rounds_left.offset_right = -20
	_rounds_left.offset_top = 44
	_rounds_left.offset_bottom = 70
	_build_clocks()
	# Estado de espera ("Waiting for the other tables...") sin tapar el salón.
	_status = _label(24, Color(0.93, 0.89, 0.80))
	_status.anchor_left = 0.1
	_status.anchor_right = 0.9
	_status.anchor_top = 0.0
	_status.anchor_bottom = 0.0
	_status.offset_top = 70
	_status.offset_bottom = 130
	_status.visible = false
	_build_result_panel()
	set_warnings(0, 3)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _build_vignette() -> void:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = dot(uv, uv) * 1.6;
	COLOR = vec4(0.0, 0.0, 0.0, smoothstep(0.12, 0.62, d) * 0.75);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	add_child(rect)


func _build_result_panel() -> void:
	_result_panel = ColorRect.new()
	_result_panel.color = Color(0, 0, 0, 0.72)
	_result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_panel.visible = false
	add_child(_result_panel)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_panel.add_child(box)
	_result_title = Label.new()
	_result_title.add_theme_font_size_override("font_size", 72)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_title)
	_result_reason = Label.new()
	_result_reason.add_theme_font_size_override("font_size", 28)
	_result_reason.add_theme_color_override("font_color", TEXT_COLOR)
	_result_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_reason)
	_result_restart = Label.new()
	_result_restart.add_theme_font_size_override("font_size", 22)
	_result_restart.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6))
	_result_restart.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_restart.text = "\nPress R to restart"
	box.add_child(_result_restart)


## Murmullo del personaje, p. ej. "...no, eso deja la dama colgada".
func show_subtitle(text: String, seconds: float = 3.5) -> void:
	_subtitle.text = text
	if _subtitle_tween != null and _subtitle_tween.is_valid():
		_subtitle_tween.kill()
	_subtitle.modulate.a = 1.0
	_subtitle_tween = create_tween()
	_subtitle_tween.tween_interval(seconds)
	_subtitle_tween.tween_property(_subtitle, "modulate:a", 0.0, 0.6)


## Mensajes del árbitro ("viene a la mesa...", veredicto).
func show_arbiter(text: String, seconds: float = 3.0) -> void:
	_arbiter.text = text
	if _arbiter_tween != null and _arbiter_tween.is_valid():
		_arbiter_tween.kill()
	_arbiter.modulate.a = 1.0
	_arbiter_tween = create_tween()
	_arbiter_tween.tween_interval(seconds)
	_arbiter_tween.tween_property(_arbiter, "modulate:a", 0.0, 0.6)


func set_warnings(count: int, maximum: int) -> void:
	_warnings.text = "Warnings: %d/%d" % [count, maximum]


func set_hint(text: String) -> void:
	_hint.text = text


## Falso en el modo captura (`--screenshot`): el aviso del ratón no sale en las imágenes.
var show_capture_prompt: bool = true


func set_mouse_captured(captured: bool) -> void:
	_crosshair.visible = captured
	_capture_prompt.visible = show_capture_prompt and not captured and not _result_panel.visible


func show_result(won: bool, reason: String) -> void:
	show_screen("You won" if won else "Eliminated", reason.substr(0, 1).to_upper() + reason.substr(1),
			"\nPress R to restart", Color(0.85, 0.8, 0.55) if won else Color(0.75, 0.12, 0.1))


## Pantalla completa sobre el salón (entre rondas, eliminado, campeón).
func show_screen(title: String, body: String, footer: String = "", color: Color = Color(0.85, 0.8, 0.55)) -> void:
	_result_title.text = title
	_result_title.add_theme_color_override("font_color", color)
	_result_reason.text = body
	_result_restart.text = footer
	_result_panel.visible = true
	_capture_prompt.visible = false


func hide_screen() -> void:
	_result_panel.visible = false


func is_screen_visible() -> bool:
	return _result_panel.visible


## Ronda en curso (arriba a la derecha): "Round 2 / 5", cuántas faltan
## ("3 rounds left" / "Final") y los jugadores que quedan. Sin nombres.
func set_round_info(round_no: int, total_rounds: int, is_final: bool, players_left: int) -> void:
	if is_final:
		_round_info.text = "Final"
		_rounds_left.text = "%d players left" % players_left
		return
	_round_info.text = "Round %d / %d" % [round_no, total_rounds]
	var left := maxi(total_rounds - round_no, 0)
	var rounds := "Final next" if left <= 1 else "%d rounds left" % left
	_rounds_left.text = "%s · %d players left" % [rounds, players_left]


## Dos relojes arriba al centro: el propio y el del rival; resalta el que corre.
func set_clocks(own_seconds: float, rival_seconds: float, own_running: bool, rival_running: bool) -> void:
	_set_clock(_own_clock, "You", own_seconds, own_running)
	_set_clock(_rival_clock, "Opponent", rival_seconds, rival_running)


func _set_clock(l: Label, who: String, seconds: float, running: bool) -> void:
	var t := "%s  %s" % [who, ClockView.format_time(seconds)]
	if l.text != t:
		l.text = t
	var low := seconds < 20.0
	if running:
		l.add_theme_color_override("font_color", Color(1.0, 0.3, 0.22) if low else Color(1.0, 0.85, 0.5))
	else:
		l.add_theme_color_override("font_color", Color(0.55, 0.5, 0.42))


## Ritmo de juego discreto bajo los relojes (p. ej. "3+2"); "" lo oculta.
func set_pace(text: String) -> void:
	_pace.text = text
	_pace.visible = text != ""


func _build_clocks() -> void:
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -170
	box.offset_right = 170
	box.offset_top = 10
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_rival_clock = _clock_label(box, 22)
	_own_clock = _clock_label(box, 28)
	_pace = _clock_label(box, 14)
	_pace.add_theme_color_override("font_color", Color(0.5, 0.46, 0.4))
	_pace.visible = false


func _clock_label(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.55, 0.5, 0.42))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## Mensaje persistente bajo la barra superior; "" lo oculta.
func set_status(text: String) -> void:
	_status.text = text
	_status.visible = text != ""
