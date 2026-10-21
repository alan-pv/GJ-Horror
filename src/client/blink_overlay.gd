class_name BlinkOverlay
extends CanvasLayer
## Párpados negros que se cierran y se abren sobre toda la pantalla (arriba y abajo, con el borde
## curvo y suave). Un único `ColorRect` con un shader de canvas (vale en Compatibility/web).
## API awaitable: `close()`, `open()`, `blink()`. `closed` va de 0 (abierto) a 1 (negro).
##
## Para esconder un corte de escena: se cierra, se pone `pending_open = true` y se recarga; la escena
## nueva llama a `BlinkOverlay.resume_if_pending(self)` en su arranque y abre los ojos.

## Marca estática que sobrevive a `reload_current_scene()`: la escena nueva debe abrir los ojos.
static var pending_open: bool = false

const SHADER := """
shader_type canvas_item;
uniform float closed : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	float s = UV.x * 2.0 - 1.0;
	float edge = closed * (0.62 - 0.1 * s * s);
	float soft = 0.025 + 0.03 * closed;
	float top = 1.0 - smoothstep(edge - soft, edge + soft, UV.y);
	float bottom = 1.0 - smoothstep(edge - soft, edge + soft, 1.0 - UV.y);
	COLOR = vec4(0.0, 0.0, 0.0, max(top, bottom) * step(0.0001, closed));
}
"""

var closed: float = 0.0:
	set(v):
		closed = clampf(v, 0.0, 1.0)
		if _mat != null:
			_mat.set_shader_parameter("closed", closed)
		if _rect != null:
			_rect.visible = closed > 0.0

var _rect: ColorRect
var _mat: ShaderMaterial


func _init() -> void:
	layer = 120
	name = "Parpadeo"
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


## Cierra los ojos en `seconds` (corrutina).
func close(seconds: float = 0.22) -> void:
	await _go(1.0, seconds)


## Abre los ojos en `seconds` (corrutina).
func open(seconds: float = 0.28) -> void:
	await _go(0.0, seconds)


## Cierra, ~0,1 s a negro y abre (corrutina).
func blink() -> void:
	await close()
	await get_tree().create_timer(0.1).timeout
	await open()


func _go(target: float, seconds: float) -> void:
	if not is_inside_tree():
		closed = target
		return
	var tw := create_tween()
	tw.tween_property(self, "closed", target, maxf(seconds, 0.001)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


## Si la escena anterior terminó con los ojos cerrados, instala un parpadeo ya cerrado bajo `root`
## y los abre tras una breve pausa. Llamar en el arranque de la escena, tras crear el HUD.
static func resume_if_pending(root: Node) -> void:
	if not pending_open:
		return
	pending_open = false
	var b := BlinkOverlay.new()
	b.closed = 1.0
	root.add_child(b)
	b._reopen()


func _reopen() -> void:
	await get_tree().create_timer(0.1).timeout
	await open()
	queue_free()
