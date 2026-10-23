class_name VoiceBlips
extends RefCounted
## Voz de 8 bits: un "blip" corto por letra, con ligera variación de tono, como en los juegos
## retro. Todo se sintetiza en memoria (`AudioStreamWAV` mono de 16 bits, cacheada), sin archivos ni
## procesos externos, así que funciona en web. Lógica pura: `plan` y `synth_blip` no tocan nodos;
## quien reproduce es `Hud` (un reproductor por hablante: la voz nueva corta la anterior).
##
## Dos hablantes: el jugador (agudo y suave: seno/triángulo) y el árbitro (grave y áspero:
## cuadrada + diente de sierra desafinados, vibrato lento y un eco corto). Un tercero, el
## acusador (`ACCUSER`), es el grito de "Cheater!": pulso estrecho agudo, blips cortos y
## rápidos, tono que sube a lo largo de la palabra y más volumen.

enum Speaker { PLAYER, ARBITER, ACCUSER }

const RATE := 22050
## Tope de seguridad del balbuceo. La voz dura lo que la escritura de cada trozo (un trozo cabe en
## dos filas, unos 10 s como mucho), así que en la práctica no se alcanza.
const MAX_SECONDS := 30.0
## Cuántos balbuceos distintos se guardan (por texto y hablante); al llenarse se vacía.
const CACHE_LIMIT := 64
## Niveles de cuantización (el "bit crush" que da el sabor 8 bits).
const CRUSH_LEVELS := 24.0

static var _cache: Dictionary = {}


## Parámetros de cada voz. `interval` = separación entre blips; `length` = duración de cada uno.
static func params(speaker: Speaker) -> Dictionary:
	if speaker == Speaker.ACCUSER:
		# `rise` = semitonos que sube el tono de cada blip respecto al anterior (grito creciente).
		return {
			"base": 700.0, "interval": 0.042, "length": 0.05, "volume_db": -2.0,
			"scale": [0, 4, 7, 12, 5, 9], "echo_delay": 0.0, "echo_gain": 0.0, "rise": 0.9,
		}
	if speaker == Speaker.ARBITER:
		return {
			"base": 92.0, "interval": 0.055, "length": 0.07, "volume_db": -4.0,
			"scale": [0, -2, 3, -5, 1, -7, 5], "echo_delay": 0.11, "echo_gain": 0.3,
		}
	return {
		"base": 560.0, "interval": 0.04, "length": 0.036, "volume_db": -10.0,
		"scale": [0, 2, 4, 7, 9, 12], "echo_delay": 0.0, "echo_gain": 0.0,
	}


## Frecuencia base (Hz) de la voz.
static func base_freq(speaker: Speaker) -> float:
	return params(speaker).base


static func volume_db(speaker: Speaker) -> float:
	return params(speaker).volume_db


## Instantes y tonos de los blips para `text`: `[{t, freq}]`. Una letra o cifra = un blip; el
## espacio añade una pausa corta y la puntuación una más larga. Solo se corta en `MAX_SECONDS`.
static func plan(speaker: Speaker, text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var p := params(speaker)
	var scale: Array = p.scale
	var step: float = p.interval
	var rise: float = p.get("rise", 0.0)
	var t := 0.0
	for i in text.length():
		var c := text.unicode_at(i)
		var ch := text[i]
		if ch == " ":
			t += step * 0.7
			continue
		if ch in ",;:—-…":
			t += step * 2.0
			continue
		if ch in ".?!":
			t += step * 3.5
			continue
		if not _is_alnum(c):
			continue
		if t + float(p.length) > MAX_SECONDS:
			break
		# Tono determinista según la letra y su posición (suena a "habla" y no a escala).
		var semis: int = scale[(c * 5 + i * 3) % scale.size()]
		var up := rise * float(out.size())
		out.append({"t": t, "freq": float(p.base) * pow(2.0, (semis + up) / 12.0)})
		t += step
	return out


## Segundos que dura el balbuceo de `text` (0 si no hay letras).
static func duration(speaker: Speaker, text: String) -> float:
	var blips := plan(speaker, text)
	if blips.is_empty():
		return 0.0
	return float(blips[-1].t) + float(params(speaker).length)


## Un blip suelto de frecuencia `freq` (muestras en -1..1, ya cuantizadas).
static func synth_blip(speaker: Speaker, freq: float) -> PackedFloat32Array:
	var p := params(speaker)
	var n := int(float(p.length) * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	var phase2 := 0.0
	var lp := 0.0
	for i in n:
		var u := float(i) / float(n)
		var time := float(i) / RATE
		# Envolvente: ataque rapidísimo y caída suave.
		var env := minf(1.0, float(i) / 40.0) * pow(1.0 - u, 1.4)
		var v: float
		if speaker == Speaker.ARBITER:
			# Vibrato lento y deslizamiento hacia abajo; dos osciladores desafinados.
			var f := freq * (1.0 + 0.02 * sin(TAU * 6.0 * time)) * (1.0 - 0.08 * u)
			phase = fposmod(phase + f / RATE, 1.0)
			phase2 = fposmod(phase2 + f * 1.012 / RATE, 1.0)
			var square := 1.0 if phase < 0.4 else -1.0
			var saw := phase2 * 2.0 - 1.0
			v = 0.55 * square + 0.45 * saw
			# Un polo para quitarle el filo más agudo (suena más sordo).
			lp += (v - lp) * 0.35
			v = lp
		elif speaker == Speaker.ACCUSER:
			# Pulso estrecho (25 %) con deslizamiento hacia arriba: chillido de chip.
			var f3 := freq * (1.0 + 0.18 * u)
			phase = fposmod(phase + f3 / RATE, 1.0)
			v = 1.0 if phase < 0.25 else -1.0
			lp += (v - lp) * 0.6
			v = lp
		else:
			var f2 := freq * (1.0 + 0.05 * u)
			phase = fposmod(phase + f2 / RATE, 1.0)
			# Triángulo: suave pero con carácter de chip.
			v = 4.0 * absf(phase - 0.5) - 1.0
		buf[i] = roundf(v * env * CRUSH_LEVELS) / CRUSH_LEVELS
	return buf


## El balbuceo completo de `text` como `AudioStreamWAV`, o `null` si no tiene letras. Cacheado.
static func build(speaker: Speaker, text: String) -> AudioStreamWAV:
	var key := "%d|%s" % [speaker, text]
	if _cache.has(key):
		return _cache[key]
	var blips := plan(speaker, text)
	if blips.is_empty():
		return null
	var p := params(speaker)
	var total := int((float(blips[-1].t) + float(p.length) + float(p.echo_delay) * 2.0 + 0.05) * RATE)
	var buf := PackedFloat32Array()
	buf.resize(total)
	for b in blips:
		var blip := synth_blip(speaker, b.freq)
		var o := int(float(b.t) * RATE)
		for i in blip.size():
			buf[o + i] += blip[i]
	# Eco corto (solo el árbitro): copia atenuada y retrasada.
	var delay := int(float(p.echo_delay) * RATE)
	if delay > 0:
		for i in range(total - 1, delay - 1, -1):
			buf[i] += buf[i - delay] * float(p.echo_gain)
	var stream := _to_stream(buf)
	if _cache.size() >= CACHE_LIMIT:
		_cache.clear()
	_cache[key] = stream
	return stream


static func _is_alnum(c: int) -> bool:
	return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c >= 192


static func _to_stream(buf: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for v in buf:
		peak = maxf(peak, absf(v))
	var gain := 0.85 / peak
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i] * gain, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	return s
