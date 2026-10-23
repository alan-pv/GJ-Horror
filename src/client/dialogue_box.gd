class_name DialogueBox
extends RichTextLabel
## Texto de diálogo del HUD (subtítulos del jugador, discurso del árbitro): `RichTextLabel` con bbcode
## y efectos de Godot, que se escribe letra a letra al ritmo del balbuceo de `VoiceBlips` y ocupa
## como mucho dos filas. Si el texto no cabe en dos filas se divide en trozos (`DialogueText.split`)
## que se muestran uno tras otro, cada uno con su máquina de escribir y su voz.
##
## Tiempo: cada trozo se escribe (`DialogueText.reveal_times`) y luego permanece `hold` s en pantalla
## (la permanencia cuenta desde que termina de escribirse); tras el último, se desvanece.
## `advance(delta)` mueve el reloj (lo llama `_process`; las pruebas lo llaman a mano).

## Empieza a sonar la voz de un trozo (texto plano). Lo escucha `Hud.speak`.
signal chunk_started(plain: String)

const MAX_ROWS := 2
const MIN_HOLD := 1.0
const FADE_SECONDS := 0.6

enum Phase { IDLE, TYPING, HOLD, FADE }

var speaker: VoiceBlips.Speaker = VoiceBlips.Speaker.PLAYER
## Ancho (px) disponible para el texto; lo fija quien lo muestra según el tamaño de la ventana.
var available_width: float = 0.0
## Para las pruebas: sustituye la medición de la fuente. Recibe el texto plano.
var fits_override: Callable = Callable()
## Con falso (`voice=false`) el texto se escribe igual pero no emite `chunk_started`.
var voice: bool = true

var _chunks: Array[String] = []
var _holds: Array[float] = []
var _index: int = 0
var _times: PackedFloat32Array = PackedFloat32Array()
var _typing_end: float = 0.0
var _clock: float = 0.0
var _hold_left: float = 0.0
var _phase: Phase = Phase.IDLE
var _open: String = ""
var _close: String = ""


func _init() -> void:
	bbcode_enabled = true
	fit_content = true
	scroll_active = false
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	set_process(false)


## Muestra `markup` (bbcode); `open`/`close` envuelven cada trozo (el efecto por defecto). `hold` es la
## permanencia total tras escribir (se reparte entre los trozos). Devuelve la duración total.
func say(markup: String, hold: float, open: String = "", close: String = "") -> float:
	_open = open
	_close = close
	var fits := fits_override if fits_override.is_valid() else Callable(self, "_fits")
	_chunks = DialogueText.split(markup, fits)
	_holds.clear()
	var total_len := 0
	for c in _chunks:
		total_len += DialogueText.plain(c).length()
	var total := 0.0
	for c in _chunks:
		var share := float(DialogueText.plain(c).length()) / maxf(1.0, float(total_len))
		var h := hold if _chunks.size() == 1 else maxf(MIN_HOLD, hold * share)
		_holds.append(h)
		total += DialogueText.typing_seconds(speaker, DialogueText.plain(c)) + h
	_index = -1
	modulate.a = 1.0
	_next_chunk()
	set_process(true)
	return total


## Corta lo que se esté mostrando.
func clear_now() -> void:
	_phase = Phase.IDLE
	modulate.a = 0.0
	set_process(false)


func is_idle() -> bool:
	return _phase == Phase.IDLE


## Trozos en que se dividió el texto actual (con su bbcode, sin el envoltorio del efecto).
func chunks() -> Array[String]:
	return _chunks


func chunk_index() -> int:
	return _index


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	match _phase:
		Phase.TYPING:
			_clock += delta
			if _clock >= _typing_end:
				visible_characters = -1
				_phase = Phase.HOLD
				_hold_left = _holds[_index]
			else:
				visible_characters = DialogueText.reveal_count(_times, _clock)
		Phase.HOLD:
			_hold_left -= delta
			if _hold_left <= 0.0:
				if _index + 1 < _chunks.size():
					_next_chunk()
				else:
					_phase = Phase.FADE
		Phase.FADE:
			modulate.a = maxf(0.0, modulate.a - delta / FADE_SECONDS)
			if modulate.a <= 0.0:
				_phase = Phase.IDLE
				set_process(false)


func _next_chunk() -> void:
	_index += 1
	var markup := _chunks[_index]
	var plain_text := DialogueText.plain(markup)
	text = _open + markup + _close
	_times = DialogueText.reveal_times(VoiceBlips.plan(speaker, plain_text), plain_text)
	_typing_end = DialogueText.typing_seconds(speaker, plain_text)
	_clock = 0.0
	visible_characters = DialogueText.reveal_count(_times, 0.0)
	_phase = Phase.TYPING
	if voice:
		chunk_started.emit(plain_text)


## ¿Cabe `plain_text` en `MAX_ROWS` filas del ancho disponible? Mide con la fuente del control.
func _fits(plain_text: String) -> bool:
	var font := get_theme_font("normal_font")
	var size := get_theme_font_size("normal_font_size")
	var width := available_width if available_width > 0.0 else 900.0
	var line_h := font.get_height(size)
	var h := font.get_multiline_string_size(plain_text, HORIZONTAL_ALIGNMENT_LEFT, width, size).y
	return int(roundf(h / line_h)) <= MAX_ROWS
