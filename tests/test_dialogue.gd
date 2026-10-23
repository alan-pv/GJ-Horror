extends TestCase
## Textos de diálogo: bbcode -> texto plano, división en trozos, revelado letra a letra al ritmo de
## los blips, DialogueBox, controles del menú y frases del monólogo (rival = él).

const P := VoiceBlips.Speaker.PLAYER
const A := VoiceBlips.Speaker.ARBITER


func _fits(n: int) -> Callable:
	return func(t: String) -> bool: return t.length() <= n


# --- Texto plano ---------------------------------------------------------------------------------

func test_plain_strips_tags() -> void:
	check_eq(DialogueText.plain("a [shake rate=20 level=5]b[/shake] c"), "a b c", "etiquetas con parámetros")
	check_eq(DialogueText.plain("[wave]x[/wave]"), "x", "simple")
	check_eq(DialogueText.plain("[color=#ffd070][lb]A[rb][/color]"), "[A]", "corchetes literales")
	check_eq(DialogueText.plain("[A] sin etiqueta"), "[A] sin etiqueta", "mayúscula no es etiqueta")
	check_eq(DialogueText.plain(""), "", "vacío")


# --- División ------------------------------------------------------------------------------------

func test_split_short_text_is_untouched() -> void:
	var r := DialogueText.split("Hello there.", _fits(40))
	check_eq(r.size(), 1, "un trozo")
	check_eq(r[0], "Hello there.", "igual")


func test_split_by_sentences_first() -> void:
	var r := DialogueText.split("One two. Three four. Five six.", _fits(21))
	check_eq(r.size(), 2, "dos trozos")
	check_eq(r[0], "One two. Three four.", "agrupa frases")
	check_eq(r[1], "Five six.", "resto")


func test_split_by_words_when_sentence_too_long() -> void:
	var r := DialogueText.split("aaa bbb ccc ddd eee fff", _fits(11))
	check_eq(r.size(), 3, "tres trozos")
	check_eq(r[0], "aaa bbb ccc", "palabras")
	check_eq(r[1], "ddd eee fff", "palabras 2")
	var r2 := DialogueText.split("aaa bbb ccc ddd eee fff", _fits(7))
	check_eq(r2, ["aaa bbb", "ccc ddd", "eee fff"], "palabras justas")


func test_split_every_chunk_fits_and_keeps_all_words() -> void:
	var text := "Anyone caught cheating is eliminated. If you see your opponent cheat, call me. If you are wrong, you will be warned."
	for limit in [20, 30, 45, 60]:
		var r := DialogueText.split(text, _fits(limit))
		var joined := ""
		for c in r:
			check(c.length() <= limit, "cabe (%d)" % limit)
			joined += (" " if joined != "" else "") + c
		check_eq(joined, text, "no se pierde nada (%d)" % limit)


func test_split_word_longer_than_limit_goes_alone() -> void:
	var r := DialogueText.split("hi supercalifragilistic yo", _fits(8))
	check_eq(r, ["hi", "supercalifragilistic", "yo"], "palabra larga sola")


func test_split_keeps_bbcode_balanced() -> void:
	var r := DialogueText.split("Aaa bbb [shake]ccc ddd eee[/shake] fff", _fits(11))
	check_eq(r.size(), 3, "tres trozos")
	check_eq(r[0], "Aaa bbb", "sin etiqueta")
	check_eq(r[1], "[shake]ccc ddd[/shake]", "cierra al final")
	check_eq(r[2], "[shake]eee[/shake] fff", "reabre y cierra")
	var plain_all := ""
	for c in r:
		plain_all += DialogueText.plain(c) + " "
	check_eq(plain_all.strip_edges(), "Aaa bbb ccc ddd eee fff", "texto plano completo")


# --- Revelado letra a letra ----------------------------------------------------------------------

func test_reveal_times_follow_blips() -> void:
	var text := "Hi, you"
	var plan := VoiceBlips.plan(P, text)
	var t := DialogueText.reveal_times(plan, text)
	check_eq(t.size(), text.length(), "uno por carácter")
	check_eq(t[0], 0.0, "la primera letra con el primer blip")
	check_eq(t[1], float(plan[1].t), "segunda letra, segundo blip")
	check_eq(t[2], t[1], "la coma aparece con la letra anterior")
	check_eq(t[3], t[1], "el espacio también")
	check_eq(t[4], float(plan[2].t), "'y' con el tercer blip")
	check_eq(t[6], float(plan[4].t), "'u' con el quinto blip")
	for i in range(1, t.size()):
		check(t[i] >= t[i - 1], "no decreciente")


func test_reveal_count() -> void:
	var text := "abc def"
	var t := DialogueText.reveal_times(VoiceBlips.plan(P, text), text)
	check_eq(DialogueText.reveal_count(t, 0.0), 1, "al inicio, la primera letra")
	check_eq(DialogueText.reveal_count(t, 100.0), text.length(), "al final, todo")
	var step := float(VoiceBlips.params(P).interval)
	check_eq(DialogueText.reveal_count(t, step * 1.01), 2, "segunda letra")


func test_reveal_tail_after_blip_cap() -> void:
	var text := "word ".repeat(80)
	var plan := VoiceBlips.plan(A, text)
	check(plan.size() < text.replace(" ", "").length(), "el balbuceo se corta")
	var t := DialogueText.reveal_times(plan, text)
	var last_blip_t := float(plan[-1].t)
	check(t[t.size() - 1] > last_blip_t, "el resto sigue después")
	check(t[t.size() - 1] <= last_blip_t + DialogueText.TAIL_RATE * text.length() + 0.01, "a ritmo constante")
	check(DialogueText.typing_seconds(A, text) >= t[t.size() - 1], "la escritura termina con la última letra")
	# Sin tope: la escritura dura lo que el balbuceo.
	check(absf(DialogueText.typing_seconds(P, "Hello") - VoiceBlips.duration(P, "Hello")) < 0.2, "duración = balbuceo")


# --- DialogueBox ---------------------------------------------------------------------------------

func test_box_types_then_holds_then_fades() -> void:
	var box := DialogueBox.new()
	box.fits_override = _fits(100)
	var heard: Array[String] = []
	box.chunk_started.connect(func(p: String) -> void: heard.append(p))
	var total := box.say("Hello there", 2.0)
	check_eq(heard, ["Hello there"], "suena el texto plano")
	var typing := DialogueText.typing_seconds(P, "Hello there")
	check(absf(total - (typing + 2.0)) < 0.001, "duración = escritura + permanencia")
	check_eq(box.visible_characters, 1, "empieza con la primera letra")
	box.advance(typing * 0.5)
	check(box.visible_characters > 1 and box.visible_characters < 11, "a mitad de escritura")
	box.advance(typing)
	check_eq(box.visible_characters, -1, "terminó de escribirse")
	box.advance(1.9)
	check(box.modulate.a == 1.0, "sigue visible: la permanencia cuenta desde que termina de escribirse")
	box.advance(0.2)
	box.advance(1.0)
	check(box.is_idle(), "se desvaneció")
	box.free()


func test_box_chunks_play_in_order_with_own_voice() -> void:
	var box := DialogueBox.new()
	box.fits_override = _fits(12)
	var heard: Array[String] = []
	box.chunk_started.connect(func(p: String) -> void: heard.append(p))
	box.say("First part. Second part.", 4.0, "[wave]", "[/wave]")
	check_eq(box.chunks().size(), 2, "dos trozos")
	check_eq(heard.size(), 1, "solo suena el primero")
	for i in 400:
		box.advance(0.05)
	check_eq(heard, ["First part.", "Second part."], "cada trozo con su voz, en orden")
	check(box.is_idle(), "al final se desvanece")
	box.free()


func test_box_silent_does_not_emit_voice() -> void:
	var box := DialogueBox.new()
	box.fits_override = _fits(100)
	box.voice = false
	var n := [0]
	box.chunk_started.connect(func(_p: String) -> void: n[0] += 1)
	box.say("Quiet text", 1.0)
	check_eq(n[0], 0, "sin voz")
	check_eq(box.visible_characters, 1, "pero se escribe")
	box.free()


func test_real_font_wraps_long_text_into_chunks() -> void:
	var box := DialogueBox.new()
	box.add_theme_font_size_override("normal_font_size", 26)
	box.available_width = 500.0
	var long_text := "Anyone caught cheating is eliminated. If you see your opponent cheat, call me. If you are wrong, you will be warned. The third warning is an elimination."
	box.say(long_text, 1.0)
	check(box.chunks().size() >= 2, "no cabe en dos filas: se divide")
	for c in box.chunks():
		check(box._fits(DialogueText.plain(c)), "cada trozo cabe en dos filas")
	box.available_width = 5000.0
	box.say("Short line", 1.0)
	check_eq(box.chunks().size(), 1, "un texto corto no se divide")
	box.free()


# --- Controles -----------------------------------------------------------------------------------

func test_controls_help_is_current() -> void:
	var text := ""
	for r in ControlsHelp.ROWS:
		text += "%s %s\n" % [r[0], r[1]]
	check(not text.to_lower().contains("abort"), "sin 'abort'")
	for r in ControlsHelp.ROWS:
		check(r[0] != "X", "sin la tecla X")
	var keys: Array = ControlsHelp.ROWS.map(func(r: Array) -> String: return r[0])
	for k in ["Mouse", "Left click", "Right click", "A", "Esc", "Space"]:
		check(k in keys, "incluye " + k)
	check_eq(ControlsHelp.layout_order(6, false), [0, 3, 1, 4, 2, 5], "dos columnas")
	check_eq(ControlsHelp.layout_order(5, false), [0, 3, 1, 4, 2, -1], "hueco al final")
	check_eq(ControlsHelp.layout_order(3, true), [0, 1, 2], "una columna")


# --- Frases del monólogo -------------------------------------------------------------------------

func test_rival_is_he_not_they() -> void:
	var re := RegEx.create_from_string("\\b(they|them|their|they're|theirs)\\b")
	var allowed := ["round_left"]   # "The others aren't getting up": plural real
	for id in VoiceLines.LINES:
		for t in VoiceLines.LINES[id].texts:
			var p := DialogueText.plain(t)
			if re.search(p.to_lower()) != null:
				check(id in allowed, "plural referido al rival en %s: %s" % [id, p])
	for t in IntroModule.FULL_LINES:
		var p := DialogueText.plain(t)
		if re.search(p.to_lower()) != null:
			check(p.begins_with("Good evening"), "solo el plural real del discurso: " + p)


func test_voice_lines_bbcode_is_valid() -> void:
	var tag := RegEx.create_from_string("\\[(/?)([a-z_]+)[^\\]]*\\]")
	var all_texts: Array = []
	for id in VoiceLines.LINES:
		all_texts.append_array(VoiceLines.LINES[id].texts)
	all_texts.append_array(IntroModule.FULL_LINES)
	for t in all_texts:
		var depth := {}
		for m in tag.search_all(t):
			var n := m.get_string(2)
			if n in ["lb", "rb"]:
				continue
			depth[n] = int(depth.get(n, 0)) + (-1 if m.get_string(1) == "/" else 1)
		for n in depth:
			check_eq(depth[n], 0, "etiquetas equilibradas en: " + t)
