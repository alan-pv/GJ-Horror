class_name EventSounds
extends RefCounted
## Sonidos de los eventos sintetizados por código (no hay assets todavía).
## Cada uno es un `AudioStreamWAV` mono de 16 bits a 22 kHz que se genera la
## primera vez que se pide y se guarda en caché: ruido con envolventes,
## tonos y filtros de un polo. Ligero para la versión web.

const RATE := 22050

static var _cache: Dictionary = {}


static func get_stream(key: StringName) -> AudioStreamWAV:
	if _cache.has(key):
		return _cache[key]
	var samples := _generate(key)
	var s := _to_stream(samples)
	_cache[key] = s
	return s


static func _generate(key: StringName) -> PackedFloat32Array:
	match key:
		&"slam":
			return _slam()
		&"thud":
			return _thud()
		&"cough":
			return _cough()
		&"clack":
			return _clack()
		&"bulb_pop":
			return _bulb_pop()
		&"struggle":
			return _struggle()
		&"steps":
			return _steps()
		&"swoosh":
			return _swoosh()
		&"flag":
			return _flag()
	return _thud()


# --- Utilidades ---------------------------------------------------------------

static func _buffer(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


static func _to_stream(buf: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for v in buf:
		peak = maxf(peak, absf(v))
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	var gain := 0.9 / peak
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i] * gain, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	return s


## Suma `src` a `dst` desde el segundo `at`.
static func _mix(dst: PackedFloat32Array, src: PackedFloat32Array, at: float, vol: float = 1.0) -> PackedFloat32Array:
	var o := int(at * RATE)
	var out := dst
	var need := o + src.size()
	if need > out.size():
		out.resize(need)
	for i in src.size():
		out[o + i] += src[i] * vol
	return out


## Ruido filtrado con un polo: `cutoff` 0..1 (1 = sin filtrar), envolvente exponencial.
static func _noise(rng: RandomNumberGenerator, seconds: float, cutoff: float, decay: float, attack: float = 0.004) -> PackedFloat32Array:
	var b := _buffer(seconds)
	var y := 0.0
	for i in b.size():
		var t := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * cutoff
		b[i] = y * minf(t / attack, 1.0) * exp(-t * decay)
	return b


static func _tone(seconds: float, freq: float, decay: float, glide: float = 0.0) -> PackedFloat32Array:
	var b := _buffer(seconds)
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		phase += TAU * (freq + glide * t) / RATE
		b[i] = sin(phase) * exp(-t * decay) * minf(t / 0.003, 1.0)
	return b


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


# --- Sonidos -----------------------------------------------------------------

## Portazo: golpe grave y ruido que se apaga, con un eco cerca.
static func _slam() -> PackedFloat32Array:
	var r := _rng(11)
	var b := _noise(r, 0.9, 0.18, 6.0)
	b = _mix(b, _tone(0.7, 62.0, 7.0, -18.0), 0.0, 1.4)
	b = _mix(b, _noise(r, 0.5, 0.3, 11.0), 0.13, 0.35)
	return b


## Golpe sordo de un objeto pesado que cae.
static func _thud() -> PackedFloat32Array:
	var r := _rng(12)
	var b := _tone(0.5, 85.0, 12.0, -40.0)
	b = _mix(b, _noise(r, 0.3, 0.12, 22.0), 0.0, 0.9)
	return b


## Dos toses: ráfagas de ruido con timbre de garganta (zumbido grave modulado).
static func _cough() -> PackedFloat32Array:
	var r := _rng(13)
	var b := _buffer(0.1)
	for k in 2:
		var at := 0.0 if k == 0 else 0.26
		var burst := _noise(r, 0.2, 0.42, 14.0, 0.012)
		var voiced := _buffer(0.2)
		var ph := 0.0
		for i in voiced.size():
			var t := float(i) / RATE
			ph += TAU * (150.0 - 220.0 * t) / RATE
			voiced[i] = (sin(ph) + 0.5 * sin(ph * 2.0)) * exp(-t * 15.0) * minf(t / 0.01, 1.0)
		b = _mix(b, burst, at, 1.0)
		b = _mix(b, voiced, at, 0.5)
	return b


## Pieza que cae y rebota sobre madera/piso: clics agudos cada vez más juntos.
static func _clack() -> PackedFloat32Array:
	var r := _rng(15)
	var b := _buffer(0.1)
	var times := [0.0, 0.17, 0.30, 0.39, 0.45]
	for i in times.size():
		var vol := pow(0.55, i)
		var hit := _noise(r, 0.12, 0.55, 55.0, 0.001)
		hit = _mix(hit, _tone(0.12, 1250.0 - i * 90.0, 45.0), 0.0, 0.8)
		b = _mix(b, hit, times[i], vol)
	return b


## Chasquido de bombilla que revienta con un zumbido breve.
static func _bulb_pop() -> PackedFloat32Array:
	var r := _rng(16)
	var b := _noise(r, 0.25, 0.8, 40.0, 0.001)
	b = _mix(b, _tone(1.2, 100.0, 3.0), 0.02, 0.35)
	b = _mix(b, _noise(r, 0.15, 0.6, 50.0, 0.001), 0.35, 0.5)
	return b


## Forcejeo: ruido grave modulado, golpes de tela y un gruñido corto.
static func _struggle() -> PackedFloat32Array:
	var r := _rng(17)
	var seconds := 3.0
	var b := _buffer(seconds)
	var y := 0.0
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		y += (r.randf_range(-1.0, 1.0) - y) * 0.12
		var wob := 0.5 + 0.5 * sin(t * 11.0) * sin(t * 3.7)
		ph += TAU * (95.0 + 25.0 * sin(t * 7.0)) / RATE
		var env := minf(t / 0.2, 1.0) * (1.0 - smoothstep(2.2, seconds, t))
		b[i] = (y * 1.3 + sin(ph) * 0.35) * wob * env
	b = _mix(b, _thud(), 0.7, 0.7)
	b = _mix(b, _thud(), 1.6, 0.6)
	return b


## Pasos lentos de zapatos de suela dura.
static func _steps() -> PackedFloat32Array:
	var r := _rng(18)
	var b := _buffer(0.1)
	for k in 6:
		var step := _noise(r, 0.14, 0.2, 30.0, 0.002)
		step = _mix(step, _tone(0.12, 140.0, 30.0), 0.0, 0.7)
		b = _mix(b, step, 0.1 + k * 0.55, 0.8)
	return b


## Soplo de tela/aire rápido (alguien pasa cerca).
static func _swoosh() -> PackedFloat32Array:
	var r := _rng(19)
	var seconds := 0.7
	var b := _buffer(seconds)
	var y := 0.0
	for i in b.size():
		var t := float(i) / RATE
		y += (r.randf_range(-1.0, 1.0) - y) * (0.05 + 0.25 * sin(PI * t / seconds))
		b[i] = y * sin(PI * t / seconds)
	return b


## Pitido de reloj de ajedrez cuando cae la bandera: tres pitidos agudos y secos.
static func _flag() -> PackedFloat32Array:
	var b := _buffer(0.1)
	for k in 3:
		var beep := _tone(0.11, 2350.0, 6.0)
		beep = _mix(beep, _tone(0.11, 4700.0, 9.0), 0.0, 0.25)
		b = _mix(b, beep, k * 0.2, 0.8)
	return b
