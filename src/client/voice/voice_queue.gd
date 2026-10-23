class_name VoiceQueue
extends RefCounted
## Cola de frases del monólogo interior (lógica pura, sin nodos; el tiempo `now` lo pone quien la usa).
## Las frases vienen de `VoiceLines.LINES`. Reglas:
##  - Prioridad: gana la mayor; a igual prioridad, la que lleva más esperando.
##  - Tope global: una frase cada `GLOBAL_GAP` s, salvo las de prioridad alta (y las continuaciones
##    de una secuencia). Una de prioridad mayor corta a otra menor que aún suena.
##  - Una baja que llega más de `LATE_LOW` s tarde se descarta.
##  - "Una vez" por partida (estado de la instancia) o por torneo (estado estático: `reset_tournament`).
##  - Espera por grupo (`wait`): se rechaza lo que pide el grupo antes de tiempo.
##  - Las variantes se eligen al azar sin repetir la última.
##  - `mute()` calla todo un rato (p. ej. tras un aviso de la ayuda para principiantes).

const GLOBAL_GAP := 6.0
const LATE_LOW := 2.0
## Separación mínima entre las frases de una secuencia (si una tarda más en escribirse, espera a que termine).
const SEQ_GAP := 3.0

## Ids ya dichos en el torneo en curso (sobrevive a la recarga de la escena).
static var tournament_done: Dictionary = {}

var rng := RandomNumberGenerator.new()
## Ids ya dichos en esta partida.
var match_done: Dictionary = {}

var _pending: Array[Dictionary] = []
var _group_last: Dictionary = {}
var _last_variant: Dictionary = {}
var _last_at: float = -1000.0
var _speaking_until: float = -1.0
var _speaking_prio: int = -1
var _mute_until: float = -1.0


static func reset_tournament() -> void:
	tournament_done.clear()


## Pide la frase `id` para dentro de `delay` s. `fmt` rellena los `%s`. Devuelve si se aceptó.
func say(id: StringName, now: float, delay: float = 0.0, fmt: Array = []) -> bool:
	var def: Dictionary = VoiceLines.LINES.get(id, {})
	if def.is_empty() or is_done(id) or is_pending(id):
		return false
	var group: StringName = StringName(def.get("group", id))
	var wait: float = def.get("wait", 0.0)
	if wait > 0.0 and now < float(_group_last.get(group, -1000.0)) + wait:
		return false
	if def.get("chance", 1.0) < 1.0 and rng.randf() >= float(def.chance):
		return false
	var texts: Array = def.texts
	var entry := {
		"id": id, "group": group, "prio": int(def.prio), "ready_at": now + delay,
		"bypass": false, "fmt": fmt, "rest": [],
	}
	if def.get("seq", false):
		entry.text = texts[0]
		entry.rest = texts.slice(1)
	else:
		entry.text = _pick(id, texts)
	_pending.append(entry)
	return true


## Dice `first` si aún no se dijo ni está en cola en este torneo; si no, `later`.
func say_first(first: StringName, later: StringName, now: float, delay: float = 0.0, fmt: Array = []) -> bool:
	if not is_done(first) and not is_pending(first):
		return say(first, now, delay, fmt)
	return say(later, now, delay, fmt)


## ¿Ya se dijo (según su `once`)?
func is_done(id: StringName) -> bool:
	var once: String = VoiceLines.LINES.get(id, {}).get("once", "")
	if once == "tournament":
		return tournament_done.has(id)
	if once == "match":
		return match_done.has(id)
	return false


func is_pending(id: StringName) -> bool:
	for e in _pending:
		if e.id == id:
			return true
	return false


func pending_count() -> int:
	return _pending.size()


## Calla todo hasta `now + seconds`.
func mute(now: float, seconds: float) -> void:
	_mute_until = maxf(_mute_until, now + seconds)


## Descarta todo lo pendiente (p. ej. al terminar la partida).
func clear() -> void:
	_pending.clear()


## Descarta las frases pendientes que solo valen con la partida en juego (`play` en `VoiceLines`).
func drop_play_only() -> void:
	var i := _pending.size() - 1
	while i >= 0:
		if bool(VoiceLines.LINES.get(_pending[i].id, {}).get("play", false)):
			_pending.remove_at(i)
		i -= 1


## La frase que toca decir ahora, o `{}`. Devuelve `{id, text, prio, seconds}`.
func next(now: float) -> Dictionary:
	# Las bajas muy atrasadas se pierden.
	var i := _pending.size() - 1
	while i >= 0:
		var e := _pending[i]
		if e.prio == VoiceLines.LOW and now - float(e.ready_at) > LATE_LOW:
			_pending.remove_at(i)
		i -= 1
	if now < _mute_until:
		return {}
	var best := -1
	for k in _pending.size():
		var e := _pending[k]
		if e.ready_at > now or not _allowed(e, now):
			continue
		if best < 0 or e.prio > _pending[best].prio \
				or (e.prio == _pending[best].prio and e.ready_at < _pending[best].ready_at):
			best = k
	if best < 0:
		return {}
	var e := _pending[best]
	_pending.remove_at(best)
	var text: String = e.text
	if not e.fmt.is_empty():
		text = text % e.fmt
	var seconds := duration_of(text)
	var typing := DialogueText.typing_seconds(VoiceBlips.Speaker.PLAYER, DialogueText.plain(text))
	_last_at = now
	_speaking_until = now + typing + seconds
	_speaking_prio = e.prio
	_group_last[e.group] = now
	_mark_done(e.id)
	if not e.rest.is_empty():
		_pending.append({
			"id": e.id, "group": e.group, "prio": e.prio, "ready_at": now + maxf(SEQ_GAP, typing + seconds),
			"bypass": true, "fmt": e.fmt, "text": e.rest[0], "rest": e.rest.slice(1),
		})
	return {"id": e.id, "text": text, "prio": e.prio, "seconds": seconds}


## Segundos que permanece un subtítulo en pantalla DESPUÉS de escribirse (el texto puede llevar bbcode).
static func duration_of(text: String) -> float:
	return Hud.hold_for(DialogueText.plain(text).length())


func _allowed(e: Dictionary, now: float) -> bool:
	if e.bypass:
		return true
	var speaking := now < _speaking_until
	if speaking and e.prio <= _speaking_prio:
		return false
	if e.prio == VoiceLines.HIGH:
		return true
	return now - _last_at >= GLOBAL_GAP or (speaking and e.prio > _speaking_prio)


func _mark_done(id: StringName) -> void:
	var once: String = VoiceLines.LINES.get(id, {}).get("once", "")
	if once == "tournament":
		tournament_done[id] = true
	elif once == "match":
		match_done[id] = true


func _pick(id: StringName, texts: Array) -> String:
	if texts.size() == 1:
		return texts[0]
	var last: int = _last_variant.get(id, -1)
	var k := rng.randi_range(0, texts.size() - 1)
	if k == last:
		k = (k + 1 + rng.randi_range(0, texts.size() - 2)) % texts.size()
	_last_variant[id] = k
	return texts[k]
