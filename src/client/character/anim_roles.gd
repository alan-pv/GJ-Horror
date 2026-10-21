class_name AnimRoles
extends RefCounted
## Contrato entre código y arte: el código pide ROLES de animación, no clips por nombre.
##
## Un clip del `.glb` cumple un rol si se llama `<rol>` o `<rol>__<variante>` (doble guion bajo),
## p. ej. `sit_wait__crossed`. Varias variantes del mismo rol se eligen al azar; si el modelo no
## trae ninguna se usa el respaldo (`fallback`: otro rol o un clip exacto). Añadir una variante
## nueva es solo exportarla con el nombre correcto: no hay que tocar código.
## Texto completo del contrato: `docs/contrato-arte.md`.

## Separador entre el rol y la variante.
const SEP := "__"

## rol -> { loop: bool (clip cíclico), fallback: StringName ("" = ninguno), blend: float (s de mezcla
## al entrar), desc: String }. Las manos de los roles `sit_*` de espera/pensar/reacción quedan
## FUERA del tablero (ver `HAND_LIMIT_Y` en `art/characters/build_player.py`).
const ROLES := {
	&"sit_wait": {
		"loop": true, "fallback": &"sit_idle", "blend": 0.8,
		"desc": "Sentado esperando el turno rival; manos fuera del tablero.",
	},
	&"sit_think": {
		"loop": true, "fallback": &"sit_think", "blend": 0.6,
		"desc": "Sentado pensando la propia jugada, inclinado hacia el tablero.",
	},
	&"sit_nervous": {
		"loop": true, "fallback": &"sit_nervous", "blend": 0.5,
		"desc": "Sentado nervioso (poco tiempo en el reloj, acusado).",
	},
	&"sit_startle": {
		"loop": false, "fallback": &"", "blend": 0.15,
		"desc": "Respingo breve (~1 s) ante una distracción; vuelve a la pose de reposo sentada.",
	},
	&"sit_cough": {
		"loop": false, "fallback": &"", "blend": 0.4,
		"desc": "Tos con el puño en la boca (una vez).",
	},
	&"stand_up": {
		"loop": false, "fallback": &"", "blend": 0.5,
		"desc": "De sentado a de pie (la silla debe retirarse >= 0,40 m hacia atrás).",
	},
	&"walk": {
		"loop": true, "fallback": &"", "blend": 0.4,
		"desc": "Ciclo de caminar sin deslizamiento (jugador: 1,1 m/s; árbitro: 0,744 m/s).",
	},
	&"sit_down": {
		"loop": false, "fallback": &"", "blend": 0.5,
		"desc": "De pie a sentado (inversa de `stand_up`).",
	},
}

## Clips que el código aún pide por nombre exacto (no son roles; no se avisa de ellos).
const DIRECT_CLIPS: Array[StringName] = [
	&"sit_idle", &"sit_move_piece", &"sit_press_clock", &"sit_write",
	&"sit_cry", &"sit_frozen", &"death_slump_table",
	# árbitro
	&"idle", &"inspect_sheets", &"aim", &"aim_hold", &"shoot", &"lower_gun", &"point_accuse",
]


## Rol de un clip (`"sit_wait__chin"` -> `&"sit_wait"`), o `&""` si no cumple ninguno.
static func role_of(clip: StringName) -> StringName:
	var base := String(clip).get_slice(SEP, 0)
	return StringName(base) if ROLES.has(StringName(base)) else &""


static func is_role(role: StringName) -> bool:
	return ROLES.has(role)


## True si el clip pertenece a un rol cíclico.
static func is_loop_clip(clip: StringName) -> bool:
	var r := role_of(clip)
	return r != &"" and bool(ROLES[r]["loop"])


static func loop_of(role: StringName) -> bool:
	return bool(ROLES[role]["loop"]) if ROLES.has(role) else false


static func fallback_of(role: StringName) -> StringName:
	return ROLES[role]["fallback"] if ROLES.has(role) else &""


static func blend_of(role: StringName) -> float:
	return float(ROLES[role]["blend"]) if ROLES.has(role) else 0.3


## Si el nombre del clip parece un intento fallido de seguir la convención, devuelve el motivo;
## si está bien (o es un clip directo conocido), cadena vacía.
static func naming_problem(clip: StringName) -> String:
	if role_of(clip) != &"" or DIRECT_CLIPS.has(clip):
		return ""
	var s := String(clip)
	if s.contains(SEP):
		return "rol desconocido '%s' antes de '__'" % s.get_slice(SEP, 0)
	for r in ROLES:
		var rs := String(r)
		if s.begins_with(rs + "_"):
			return "un solo guion bajo: ¿'%s__%s'?" % [rs, s.substr(rs.length() + 1)]
		if s.to_lower() == rs and s != rs:
			return "mayúsculas: debería ser '%s'" % rs
	return "no sigue la convención <rol>[__variante] ni es un clip directo conocido"
