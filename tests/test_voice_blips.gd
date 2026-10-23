extends TestCase
## Voz de 8 bits: síntesis y plan de blips (lógica pura).

const P := VoiceBlips.Speaker.PLAYER
const A := VoiceBlips.Speaker.ARBITER


func _zero_crossings(buf: PackedFloat32Array) -> int:
	var n := 0
	for i in range(1, buf.size()):
		if (buf[i - 1] < 0.0) != (buf[i] < 0.0):
			n += 1
	return n


func test_blip_count_follows_letters() -> void:
	check_eq(VoiceBlips.plan(P, "Hi").size(), 2, "una por letra")
	check_eq(VoiceBlips.plan(P, "a b").size(), 2, "el espacio no suena")
	check_eq(VoiceBlips.plan(P, "...!?").size(), 0, "solo puntuación: nada")
	check(VoiceBlips.plan(P, "Dark again now").size() > VoiceBlips.plan(P, "Dark").size(), "más texto, más blips")


func test_voice_lasts_the_whole_text() -> void:
	# Un texto largo (dos filas de subtítulo) suena entero: ya no se corta a los pocos segundos.
	var text := "If you see your opponent cheat, call me. If you are wrong, you will be warned."
	for sp in [P, A]:
		var n := 0
		for ch in text:
			if DialogueText.is_alnum(ch):
				n += 1
		check_eq(VoiceBlips.plan(sp, text).size(), n, "un blip por letra, sin cortar")
		check(VoiceBlips.duration(sp, text) > 4.5, "pasa de los 4,5 s de antes")
		check(absf(DialogueText.typing_seconds(sp, text) - VoiceBlips.duration(sp, text)) < 0.2, "voz = escritura")
		check(VoiceBlips.build(sp, text).data.size() / 2 >= int(VoiceBlips.duration(sp, text) * VoiceBlips.RATE), "stream completo")


func test_voices_are_brisk() -> void:
	check(VoiceBlips.params(A).interval <= 0.06, "árbitro ágil")
	check(VoiceBlips.params(P).interval <= 0.04, "jugador ágil")
	check(VoiceBlips.params(A).length <= VoiceBlips.params(A).interval * 1.3, "blips que no se pisan")


func test_duration_is_bounded() -> void:
	var long_text := "Anyone caught cheating is eliminated. ".repeat(20)
	check(VoiceBlips.duration(A, long_text) <= VoiceBlips.MAX_SECONDS + 0.01, "acotada")
	check(VoiceBlips.duration(P, long_text) <= VoiceBlips.MAX_SECONDS + 0.01, "acotada (jugador)")
	check(VoiceBlips.duration(P, "Hello there friend") > VoiceBlips.duration(P, "Hi"), "proporcional al texto")
	check_eq(VoiceBlips.duration(P, ""), 0.0, "vacío")


func test_plan_is_deterministic_and_times_increase() -> void:
	var a := VoiceBlips.plan(A, "Nothing irregular.")
	var b := VoiceBlips.plan(A, "Nothing irregular.")
	check_eq(a, b, "determinista")
	for i in range(1, a.size()):
		check(a[i].t > a[i - 1].t, "tiempos crecientes")


func test_pitch_varies_a_little() -> void:
	var freqs := {}
	for b in VoiceBlips.plan(P, "They looked away"):
		freqs[snappedf(b.freq, 0.01)] = true
	check(freqs.size() > 1, "hay variación de tono")


func test_arbiter_is_lower_than_player() -> void:
	check(VoiceBlips.base_freq(A) < VoiceBlips.base_freq(P) * 0.35, "frecuencia base mucho más baja")
	var fa := 0.0
	var fp := 0.0
	for b in VoiceBlips.plan(A, "Begin"):
		fa = maxf(fa, b.freq)
	fp = 1e9
	for b in VoiceBlips.plan(P, "Begin"):
		fp = minf(fp, b.freq)
	check(fa < fp, "el blip más agudo del árbitro es más grave que el más grave del jugador")
	# Lo medido en la onda: el árbitro cruza por cero menos veces por segundo.
	var ra := _zero_crossings(VoiceBlips.synth_blip(A, VoiceBlips.base_freq(A))) / VoiceBlips.params(A).length
	var rp := _zero_crossings(VoiceBlips.synth_blip(P, VoiceBlips.base_freq(P))) / VoiceBlips.params(P).length
	check(ra < rp, "la onda del árbitro es más grave")


func test_synth_blip_length_and_range() -> void:
	for sp in [P, A]:
		var buf := VoiceBlips.synth_blip(sp, 300.0)
		check_eq(buf.size(), int(float(VoiceBlips.params(sp).length) * VoiceBlips.RATE), "longitud")
		var peak := 0.0
		for v in buf:
			peak = maxf(peak, absf(v))
		check(peak > 0.2 and peak <= 1.0, "amplitud audible y sin pasarse")


func test_build_stream_cached_and_sized() -> void:
	var s := VoiceBlips.build(P, "Too close.")
	check(s != null and s.mix_rate == VoiceBlips.RATE, "stream válido")
	check(s.data.size() / 2 >= int(VoiceBlips.duration(P, "Too close.") * VoiceBlips.RATE), "cubre todo el balbuceo")
	check(VoiceBlips.build(P, "Too close.") == s, "cacheado")
	check(VoiceBlips.build(P, "...") == null, "sin letras no hay stream")
	var sa := VoiceBlips.build(A, "Too close.")
	check(sa != s, "hablantes distintos, streams distintos")


func test_accuser_shout_is_high_fast_and_rising() -> void:
	var C := VoiceBlips.Speaker.ACCUSER
	var plan := VoiceBlips.plan(C, "Cheater!")
	check_eq(plan.size(), 7, "un blip por letra")
	check(VoiceBlips.base_freq(C) > VoiceBlips.base_freq(P), "más agudo que el jugador")
	check(VoiceBlips.volume_db(C) > VoiceBlips.volume_db(P), "más fuerte que el jugador")
	check(VoiceBlips.params(C).interval < VoiceBlips.params(P).interval, "más rápido")
	check(float(plan[-1].freq) > float(plan[0].freq) * 1.5, "el tono sube a lo largo de la palabra")
	check(VoiceBlips.duration(C, "Cheater!") < 0.5, "grito corto")
	check_eq(plan, VoiceBlips.plan(C, "Cheater!"), "determinista")
	# Las otras voces no suben de tono (la subida es solo del acusador).
	check_eq(VoiceBlips.params(P).get("rise", 0.0), 0.0, "jugador sin subida")


func test_accuser_stream_is_built() -> void:
	var s := VoiceBlips.build(VoiceBlips.Speaker.ACCUSER, "Cheater!")
	check(s != null and s.data.size() > 1000, "stream sintetizado")
	check(VoiceBlips.build(VoiceBlips.Speaker.ACCUSER, "!!") == null, "sin letras: nada")
	var blip := VoiceBlips.synth_blip(VoiceBlips.Speaker.ACCUSER, 800.0)
	var peak := 0.0
	for v in blip:
		peak = maxf(peak, absf(v))
	check(peak > 0.3 and peak <= 1.0, "amplitud razonable")
