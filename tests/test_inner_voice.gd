extends TestCase
## Monólogo interior: cola de frases, disparadores puros y condiciones del discurso.


func _queue() -> VoiceQueue:
	VoiceQueue.reset_tournament()
	var q := VoiceQueue.new()
	q.rng.seed = 7
	return q


func test_all_lines_are_well_formed() -> void:
	for id in VoiceLines.LINES:
		var d: Dictionary = VoiceLines.LINES[id]
		check(d.has("prio") and d.has("texts") and not d.texts.is_empty(), "entrada válida: %s" % id)


func test_basic_say_and_next() -> void:
	var q := _queue()
	check(q.say(&"cheat_abort", 0.0), "se acepta")
	var l := q.next(0.0)
	check_eq(l.text, "Too close.", "texto")
	check(q.next(0.1).is_empty(), "ya no queda nada")


func test_higher_priority_goes_first() -> void:
	var q := _queue()
	q.say(&"cheat_abort", 0.0)   # baja
	q.say(&"cheat_seen", 0.0)    # media
	q.say(&"accused", 0.0)       # alta
	check_eq(q.next(0.0).id, &"accused", "alta primero")
	# La media espera al tope global (la alta suena ahora).
	check(q.next(1.0).is_empty(), "media bloqueada por el tope")
	check_eq(q.next(6.5).id, &"cheat_seen", "media tras el tope")


func test_global_gap_blocks_non_high() -> void:
	var q := _queue()
	q.say(&"cheat_seen", 0.0)
	q.next(0.0)
	q.say(&"queen_lost", 0.5)
	check(q.next(VoiceQueue.GLOBAL_GAP - 0.5).is_empty(), "antes del tope global no")
	check_eq(q.next(VoiceQueue.GLOBAL_GAP + 0.1).id, &"queen_lost", "después sí")


func test_high_ignores_gap_and_cuts_lower() -> void:
	var q := _queue()
	q.say(&"cheat_seen", 0.0)
	q.next(0.0)
	q.say(&"accused", 0.5)
	check_eq(q.next(0.5).id, &"accused", "alta corta a media")


func test_higher_cuts_lower_still_speaking_even_within_gap() -> void:
	var q := _queue()
	q.say(&"cheat_abort", 0.0)   # baja
	q.next(0.0)
	q.say(&"cheat_seen", 0.3)    # media
	check_eq(q.next(0.3).id, &"cheat_seen", "media corta a baja que suena")


func test_equal_priority_does_not_cut() -> void:
	var q := _queue()
	q.say(&"accused", 0.0)
	q.next(0.0)
	q.say(&"champion", 0.2)
	check(q.next(0.2).is_empty(), "alta no corta a alta")
	check_eq(q.next(3.5).id, &"champion", "habla al terminar")


func test_low_priority_dropped_when_late() -> void:
	var q := _queue()
	q.say(&"cheat_seen", 0.0)
	q.next(0.0)
	q.say(&"cheat_abort", 1.0)   # baja, lista a 1.0, bloqueada por el tope
	check(q.next(3.5).is_empty(), "bloqueada")
	check(q.next(8.0).is_empty(), "descartada por tardía")
	check_eq(q.pending_count(), 0, "ya no está en cola")


func test_medium_survives_when_late() -> void:
	var q := _queue()
	q.say(&"cheat_seen", 0.0)
	q.next(0.0)
	q.say(&"queen_lost", 1.0)
	check_eq(q.next(8.0).id, &"queen_lost", "media no se descarta")


func test_delay_holds_line() -> void:
	var q := _queue()
	q.say(&"queen_lost", 0.0, 5.0)
	check(q.next(4.9).is_empty(), "aún no")
	check_eq(q.next(5.0).id, &"queen_lost", "ya")


func test_once_per_tournament_and_reset() -> void:
	var q := _queue()
	q.say(&"cheat_first", 0.0)
	q.next(0.0)
	check(not q.say(&"cheat_first", 20.0), "no se repite en el torneo")
	# Una escena nueva del mismo torneo conserva el estado.
	var q2 := VoiceQueue.new()
	check(not q2.say(&"cheat_first", 0.0), "estático entre colas")
	VoiceQueue.reset_tournament()
	check(q2.say(&"cheat_first", 0.0), "torneo nuevo lo borra")


func test_once_per_match_is_per_instance() -> void:
	var q := _queue()
	q.say(&"clock_30", 0.0)
	q.next(0.0)
	check(not q.say(&"clock_30", 10.0), "una vez por partida")
	var q2 := VoiceQueue.new()
	check(q2.say(&"clock_30", 0.0), "otra partida sí")


func test_group_wait() -> void:
	var q := _queue()
	q.say_first(&"distracted_first", &"distracted", 0.0)
	q.next(0.0)
	check(not q.say(&"distracted", 30.0), "dentro de la espera de 40 s")
	check(q.say(&"distracted", 41.0), "pasada la espera")


func test_say_first_falls_back() -> void:
	var q := _queue()
	q.say_first(&"blackout_first", &"blackout", 0.0)
	check_eq(q.next(0.0).id, &"blackout_first", "primera vez")
	q.say_first(&"blackout_first", &"blackout", 10.0)
	check_eq(q.next(10.0).id, &"blackout", "después la normal")


func test_pending_not_duplicated() -> void:
	var q := _queue()
	check(q.say(&"queen_lost", 0.0, 3.0), "")
	check(not q.say(&"queen_lost", 0.1, 3.0), "ya en cola")
	check_eq(q.pending_count(), 1, "una sola")


func test_sequence_plays_in_order_apart() -> void:
	var q := _queue()
	q.say(&"cheat_hint", 0.0)
	check_eq(DialogueText.plain(q.next(0.0).text), "...Caught. He said caught.", "primera")
	check(q.next(VoiceQueue.SEQ_GAP - 0.1).is_empty(), "aún no")
	check_eq(q.next(8.0).text, "I'm not good enough to win this clean.", "segunda")
	check_eq(q.next(16.0).text, "So I just can't get caught.", "tercera")
	check(q.next(20.0).is_empty(), "fin")


func test_mute_silences_everything() -> void:
	var q := _queue()
	q.mute(0.0, 3.5)
	q.say(&"accused", 0.0)
	check(q.next(3.0).is_empty(), "callada")
	check_eq(q.next(3.6).id, &"accused", "después habla")


func test_variants_do_not_repeat_last() -> void:
	var q := _queue()
	var last := ""
	for i in 30:
		VoiceQueue.reset_tournament()
		var t := float(i) * 100.0
		q.say(&"rival_executed", t)
		var l := q.next(t)
		check(l.text != last, "sin repetir")
		last = l.text


func test_format_args() -> void:
	var q := _queue()
	q.say(&"context_players", 0.0, 0.0, [VoiceRules.count_word(32)])
	check_eq(q.next(0.0).text, "Thirty-two players. One walks out.", "con N en palabras")


func test_chance_can_reject() -> void:
	var q := _queue()
	var accepted := 0
	for i in 200:
		var t := float(i) * 100.0
		if q.say(&"shot_next", t):
			accepted += 1
			q.next(t)
	check(accepted > 60 and accepted < 140, "ronda el 50 %% (%d)" % accepted)


# --- Disparadores puros ---------------------------------------------------------------------------

func test_count_words() -> void:
	check_eq(VoiceRules.count_word(16), "Sixteen", "16")
	check_eq(VoiceRules.count_word(2), "Two", "2")
	check_eq(VoiceRules.count_word(7), "7", "dígitos")


func test_round_start_lines() -> void:
	check_eq(VoiceRules.round_start(8, false, true).id, &"round_left", "quedan 8")
	check_eq(VoiceRules.round_start(8, false, true).fmt, ["Eight"], "en palabras")
	check_eq(VoiceRules.round_start(4, false, true).id, &"round_semi", "semifinal")
	check_eq(VoiceRules.round_start(2, true, true).id, &"round_final", "final")
	check(VoiceRules.round_start(2, true, false).is_empty(), "segunda de la final: nada")


func test_crossed() -> void:
	check(VoiceRules.crossed(31.0, 29.5, 30.0), "cruza")
	check(not VoiceRules.crossed(29.0, 28.0, 30.0), "ya estaba debajo")
	check(not VoiceRules.crossed(35.0, 31.0, 30.0), "aún no")


func test_queen_count_and_material() -> void:
	var b := BoardState.start_position()
	check_eq(VoiceRules.count_queens(b, ChessPiece.WHITE), 1, "una dama")
	check_eq(VoiceRules.material_balance(b, ChessPiece.WHITE), 0, "igualado")
	var b2 := BoardState.from_fen("rnb1kbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
	check_eq(VoiceRules.count_queens(b2, ChessPiece.BLACK), 0, "sin dama negra")
	check(VoiceRules.material_balance(b2, ChessPiece.BLACK) < 0, "negras pierden material")


func test_is_behind_by_clock() -> void:
	var b := BoardState.start_position()
	var c := ChessClock.new(100.0, 150.0)
	check(VoiceRules.is_behind(b, c, ChessPiece.WHITE), "menos reloj")
	check(not VoiceRules.is_behind(b, c, ChessPiece.BLACK), "más reloj")


func test_gaze_watch_fires_once_after_threshold() -> void:
	var w := VoiceRules.GazeWatch.new()
	check(not w.update(1.0, true, false), "aún no")
	check(w.update(0.3, true, false), "salta a 1,3 s")
	check(not w.update(1.0, true, false), "solo una vez")
	check(w.is_distracted(), "sigue distraído")
	w.update(0.1, true, true)
	check(not w.is_distracted(), "mira otra vez")
	check(w.update(1.3, true, false), "se rearma")


func test_gaze_watch_inactive_resets() -> void:
	var w := VoiceRules.GazeWatch.new()
	w.update(1.0, true, false)
	w.update(0.1, false, false)
	check(not w.update(0.5, true, false), "el tiempo se reinició")


func test_intro_conditions() -> void:
	check(IntroModule.should_play({}, 1, false, true), "ronda 1 normal")
	check(not IntroModule.should_play({}, 2, false, true), "ronda 2")
	check(not IntroModule.should_play({}, 1, true, true), "final")
	check(not IntroModule.should_play({}, 1, false, false), "sin partida")
	check(not IntroModule.should_play({"autoplay": true}, 1, false, true), "autoplay")
	check(not IntroModule.should_play({"screenshot": "x.png"}, 1, false, true), "screenshot")
	check(not IntroModule.should_play({"walk-demo": true}, 1, false, true), "walk-demo")
	check(not IntroModule.should_play({"no-intro": true}, 1, false, true), "no-intro")
	check(not IntroModule.should_play({"start-round": "3"}, 1, false, true), "start-round")
	check(IntroModule.should_play({"intro": true, "screenshot": "x.png"}, 1, false, true), "--intro fuerza")


func test_intro_text() -> void:
	check_eq(IntroModule.FULL_LINES.size(), 8, "8 frases")
	check_eq(DialogueText.plain(IntroModule.FULL_LINES[5]), "Anyone caught cheating is eliminated.", "frase 6")
	check_eq(IntroModule.SHORT_LINES[0], "Another night. The same rules.", "corto")
	check_eq(DialogueText.plain(IntroModule.FULL_LINES[7]), "The last player in this room walks out free of debt. And very rich.", "última frase")
	for l in IntroModule.FULL_LINES + IntroModule.SHORT_LINES:
		check(not l.contains("Begin") and not l.contains("sat where"), "el discurso no incluye 'Begin.' ni el giro: " + l)
	check_eq(IntroModule.SKIP_LINE, "Begin.", "Begin. aparte")


func test_play_only_lines_drop_when_match_ends() -> void:
	var q := _queue()
	q.say(&"cheat_abort", 0.0)
	q.say(&"last_execution", 0.0)
	q.drop_play_only()
	var l := q.next(0.0)
	check_eq(l.text, "That was the last one.", "queda la que no depende de la partida")
	check(q.next(10.0).is_empty(), "la de partida se descartó")


func test_blackout_lines_are_high_and_cut_a_mid_line() -> void:
	check_eq(VoiceLines.LINES[&"blackout_first"].prio, VoiceLines.HIGH, "la primera es alta")
	check_eq(VoiceLines.LINES[&"blackout"].prio, VoiceLines.HIGH, "las siguientes, también")
	var q := _queue()
	q.say(&"cheat_seen", 0.0)
	q.next(0.0)
	q.say_first(&"blackout_first", &"blackout", 0.5)
	check_eq(q.next(0.5).id, &"blackout_first", "sale de inmediato aunque otra esté sonando")


func test_blackout_lines_speak_before_the_dark() -> void:
	# Dichas antes del apagón: nada de "dark again", las luces aún no se han ido.
	for id in [&"blackout_first", &"blackout"]:
		for t in VoiceLines.LINES[id].texts:
			check(not t.to_lower().contains("dark again"), "texto compatible con 'antes': " + t)
	check(VoiceLines.LINES[&"blackout"].get("play", false), "solo con la partida en juego")


func test_blackout_lead_is_short() -> void:
	check(EventModule.BLACKOUT_LEAD >= 1.0 and EventModule.BLACKOUT_LEAD <= 2.5, "adelanto breve")


func test_rival_cheating_hint_once_per_tournament() -> void:
	var q := _queue()
	check(q.say(&"rival_cheating", 0.0, 0.0, [], 0), "se acepta")
	var l := q.next(0.0)
	check_eq(l.id, &"rival_cheating", "sale")
	check_eq(DialogueText.plain(l.text), "He's cheating... I can accuse him. [A]", "texto plano con la tecla")
	check_eq(l.prio, VoiceLines.HIGH, "prioridad alta")
	check(not q.say(&"rival_cheating", 100.0, 0.0, [], 0), "una vez por torneo")
	# Sobrevive a otra partida del mismo torneo (estado estático) y se borra con un torneo nuevo.
	var q2 := VoiceQueue.new()
	check(not q2.say(&"rival_cheating", 0.0), "tampoco en la siguiente partida")
	VoiceQueue.reset_tournament()
	check(q2.say(&"rival_cheating", 0.0), "torneo nuevo: otra vez")


func test_rival_cheating_hint_is_play_only() -> void:
	var q := _queue()
	q.say(&"rival_cheating", 5.0, 0.0, [], 0)
	q.drop_play_only()
	check(q.next(6.0).is_empty(), "si la partida terminó antes de decirse, se descarta")
	# Descartada sin decirse: no cuenta como dicha y se reintenta en la siguiente trampa del rival.
	check(q.say(&"rival_cheating", 20.0, 0.0, [], 0), "se reintenta")
	check_eq(q.next(20.0).id, &"rival_cheating", "ahora sí sale")


func test_rival_cheating_unseen_variant_and_never_lost() -> void:
	var q := _queue()
	check(q.say(&"rival_cheating", 0.0, 0.0, [], 1), "variante a oscuras")
	var l := q.next(0.0)
	check_eq(DialogueText.plain(l.text), "Something moved on the board... If he's cheating, I can accuse him. [A]", "texto")
	# Prioridad alta: ni el tope global ni la ayuda de principiantes (mute corto) la pierden.
	var q2 := _queue()
	q2.say(&"cheat_seen", 0.0)
	q2.next(0.0)
	q2.mute(0.0, 3.5)
	q2.say(&"rival_cheating", 0.5, 0.8, [], 0)
	check(q2.next(1.0).is_empty(), "callada por el mute")
	check_eq(q2.next(4.0).id, &"rival_cheating", "sale al terminar el mute, sin tope global")


func test_arbiter_near_once_per_tournament() -> void:
	var q := _queue()
	check(q.say(&"arbiter_near", 0.0), "primera vez")
	q.next(0.0)
	check(not q.say(&"arbiter_near", 500.0), "no se repite")
	var q2 := VoiceQueue.new()
	check(not q2.say(&"arbiter_near", 0.0), "ni en la siguiente partida del torneo")
	VoiceQueue.reset_tournament()
	check(q2.say(&"arbiter_near", 0.0), "torneo nuevo: otra vez")


func test_arbiter_cheating_does_not_burst() -> void:
	var q := _queue()
	check(q.say(&"arbiter_cheating", 0.0), "primera")
	q.next(0.0)
	check(not q.say(&"arbiter_cheating", 20.0), "no en ráfaga")
	check(q.say(&"arbiter_cheating", 41.0), "pasado el tiempo, sí")


func test_tutorial_lines_once_per_tournament_and_short() -> void:
	for id in [&"tut_select", &"tut_rival_piece", &"tut_eyes", &"tut_cover"]:
		var d: Dictionary = VoiceLines.LINES[id]
		check_eq(d.once, "tournament", "una vez por torneo: %s" % id)
		check(d.get("play", false), "solo con partida en juego: %s" % id)
		for t in d.texts:
			check(DialogueText.plain(t).length() <= 60, "frase corta: %s" % t)
	var q := _queue()
	check(q.say(&"tut_select", 0.0), "se acepta")
	var l := q.next(0.0)
	check_eq(l.text, "Green squares are legal moves.", "primero lo verde")
	check_eq(q.next(10.0).text, "Orange and red ones are cheats. The redder, the riskier.", "luego naranja y rojo")
	check(not q.say(&"tut_select", 50.0), "no se repite")
	# `say_first` pasa a la de la pieza rival cuando ya se explicó el mapa de calor.
	check(q.say_first(&"tut_select", &"tut_rival_piece", 60.0), "pieza rival")
	check_eq(q.next(60.0).id, &"tut_rival_piece", "explica las piezas rivales")


func test_can_see_rival_cheat() -> void:
	check(VoiceRules.can_see_rival_cheat(true, false), "mira y hay luz")
	check(not VoiceRules.can_see_rival_cheat(false, false), "no mira")
	check(not VoiceRules.can_see_rival_cheat(true, true), "a oscuras")


func test_dialogues_are_brisk() -> void:
	# Permanencias ágiles (el usuario pidió diálogos más rápidos).
	check(Hud.hold_for(40) < 2.0, "subtítulo de 40 letras: menos de 2 s tras escribirse")
	check(IntroModule.phrase_seconds("x".repeat(60)) < 2.6, "frase del discurso de 60 letras")
	check(IntroModule.PHRASE_GAP <= 0.25, "hueco corto entre frases")
	check(VoiceQueue.SEQ_GAP <= 2.0, "secuencias más juntas")
	# La escritura del discurso más largo sigue el balbuceo entero.
	var longest := DialogueText.plain(IntroModule.FULL_LINES[6])
	var typing := DialogueText.typing_seconds(VoiceBlips.Speaker.ARBITER, longest)
	check(absf(typing - VoiceBlips.duration(VoiceBlips.Speaker.ARBITER, longest)) < 0.2, "voz = escritura")


func test_hud_pointer_follows_real_state() -> void:
	var hud := Hud.new()
	tree.root.add_child(hud)
	var cross: Control = hud._crosshair
	check(not cross.visible, "sin ratón capturado no hay punto de mira")
	hud.set_mouse_captured(true)
	check(cross.visible, "capturado y libre: se ve")
	hud.set_input_locked(true)
	check(not cross.visible, "entrada bloqueada (discurso): oculto")
	hud.set_input_locked(false)
	check(cross.visible, "al desbloquear vuelve sin otra señal de captura")
	hud.set_mouse_captured(false)
	check(not cross.visible, "suelto: oculto")
	hud.free()
