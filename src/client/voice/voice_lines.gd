class_name VoiceLines
extends RefCounted
## Tabla de frases del monólogo interior (lo que se oye en la cabeza del jugador). Todo el texto
## que ve el jugador está en inglés. Para añadir o cambiar una frase basta con editar `LINES`.
##
## Campos de cada entrada:
##   prio    LOW / MID / HIGH. Las altas ignoran el tope global y cortan a las menores.
##   texts   frases. Por defecto se elige una al azar (sin repetir la última); con `seq` suenan todas
##           en orden, separadas ~3 s. Pueden llevar `%s` (lo rellena quien la pide).
##   seq     true = decir todas las frases en orden.
##   once    "" = sin límite, "match" = una vez por partida, "tournament" = una vez por torneo.
##   wait    segundos mínimos desde la última vez que habló el grupo (descarta lo que llegue antes).
##   group   grupo que comparte la espera (por defecto, el propio id).
##   chance  probabilidad de que la frase se acepte (por defecto 1).
##   play    true = solo tiene sentido con la partida en juego: se descarta si termina antes de decirse.

const LOW := 0
const MID := 1
const HIGH := 2

const LINES := {
	# --- Historia: tras el discurso completo (concluye que hay que hacer trampa sin ser visto) -----------------------------------------------------
	&"cheat_hint": {
		"prio": HIGH, "once": "tournament", "seq": true,
		"texts": ["...Caught. He said caught.", "I'm not good enough to win this clean.", "So I just can't get caught."],
	},
	# --- Contexto de ronda -------------------------------------------------------------------------
	&"context_players": {"prio": MID, "once": "tournament", "texts": ["%s players. One walks out."]},
	&"round_left": {"prio": MID, "texts": ["%s left. The others aren't getting up."]},
	&"round_semi": {"prio": MID, "texts": ["Four of us. The room is so quiet now."]},
	&"round_final": {"prio": MID, "texts": ["One more opponent. Just one."]},
	# --- Disparos -----------------------------------------------------------------------------------
	&"first_shot": {
		"prio": HIGH, "once": "tournament", "seq": true,
		"texts": ["...Eliminated. That's what he meant.", "That was real."],
	},
	&"shot_next": {
		"prio": LOW, "chance": 0.5, "wait": 25.0,
		"texts": ["Don't look. Keep your eyes on the board.", "Another one.", "That could be me.", "Breathe."],
	},
	&"rival_executed": {"prio": HIGH, "texts": ["It was them or me.", "...I'm sorry."]},
	# --- Apagón -----------------------------------------------------------------------------------
	# Se dicen justo ANTES del apagón (`InnerVoice.announce_blackout`): las luces están por apagarse.
	&"blackout_first": {
		"play": true, "prio": HIGH, "once": "tournament", "group": "blackout",
		"texts": ["The lights are failing... Nobody will see my hands."],
	},
	&"blackout": {
		"play": true, "prio": HIGH, "group": "blackout",
		"texts": ["The lights are going out. Now's my chance.", "Here it goes. Now's my chance.", "Wait for the dark... Now's my chance."],
	},
	# --- Rival distraído y empujón a hacer trampa ---------------------------------------------------
	&"distracted_first": {"play": true, 
		"prio": MID, "once": "tournament", "wait": 40.0, "group": "distracted",
		"texts": ["They're not looking..."],
	},
	&"distracted": {"play": true, 
		"prio": MID, "wait": 40.0, "group": "distracted",
		"texts": ["Eyes off the board. Now.", "They looked away."],
	},
	&"nudge_hands": {"play": true, "prio": LOW, "once": "match", "texts": ["Nobody's watching my hands."]},
	&"nudge_fair": {"play": true, "prio": MID, "once": "tournament", "texts": ["Playing fair won't get me out of here."]},
	# --- Árbitro cerca -----------------------------------------------------------------------------
	&"arbiter_near": {"play": true, 
		"prio": MID, "wait": 45.0,
		"texts": ["Footsteps. Keep your hands where he can see them."],
	},
	&"arbiter_cheating": {"play": true, "prio": HIGH, "wait": 10.0, "texts": ["Not now. Not now."]},
	# --- Trampas del humano --------------------------------------------------------------------------
	&"cheat_first": {"play": true, "prio": MID, "once": "tournament", "texts": ["My hand is shaking."]},
	&"cheat_unseen": {"play": true, "prio": LOW, "wait": 30.0, "texts": ["Nobody saw. ...I think."]},
	&"cheat_seen": {"play": true, "prio": MID, "texts": ["Did they see that?"]},
	&"cheat_abort": {"play": true, "prio": LOW, "texts": ["Too close."]},
	# --- Acusaciones --------------------------------------------------------------------------------
	&"accused": {"prio": HIGH, "texts": ["No. No, no, no."]},
	&"accused_false": {"prio": MID, "texts": ["...They were wrong. Breathe."]},
	&"my_false_1": {"prio": MID, "group": "my_accusation", "texts": ["Wrong. I can't do that again."]},
	&"my_false_2": {"prio": MID, "group": "my_accusation", "texts": ["One more and I'm done."]},
	&"my_correct": {"prio": MID, "group": "my_accusation", "texts": ["I saw you."]},
	# --- Material -----------------------------------------------------------------------------------
	&"queen_lost": {"play": true, "prio": MID, "texts": ["My queen..."]},
	&"queen_taken": {"play": true, "prio": MID, "texts": ["Their queen. I can win this."]},
	&"check_given": {"play": true, "prio": LOW, "wait": 30.0, "texts": ["Check. Think."]},
	# --- Reloj --------------------------------------------------------------------------------------
	&"clock_30": {"play": true, "prio": MID, "once": "match", "texts": ["Thirty seconds. Move."]},
	&"clock_10": {"play": true, "prio": HIGH, "once": "match", "texts": ["Move, move, move."]},
	&"clock_rival_20": {"play": true, "prio": LOW, "once": "match", "texts": ["They're running out of time."]},
	# --- Final de ronda y de torneo -------------------------------------------------------------------
	&"last_execution": {"prio": MID, "texts": ["That was the last one."]},
	&"condemned": {"prio": HIGH, "texts": ["I just wanted to go home."]},
	&"champion": {"prio": HIGH, "texts": ["...It's over. Is it over?"]},
}
