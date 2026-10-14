class_name CheatArmState
extends RefCounted
## Máquina de estados de la entrada de trampas, sin nodos ni entrada real:
## reposo → trampa armada (teclas 1-4) → pieza elegida → destino → ejecutar.
## `on_square` decide qué hacer al hacer clic y deja el estado actualizado.

enum Phase { IDLE, ARMED, PIECE }

var phase: Phase = Phase.IDLE
## Índice de la trampa armada (-1 si ninguna).
var index: int = -1
## Casilla de la pieza elegida (-1 si ninguna).
var from: int = -1
## Destinos válidos de la pieza elegida.
var targets: Array[int] = []


func is_armed() -> bool:
	return phase != Phase.IDLE


## Arma la trampa `i`; si ya estaba armada, la desarma. Devuelve true si queda armada.
func toggle(i: int) -> bool:
	if phase != Phase.IDLE and index == i:
		cancel()
		return false
	phase = Phase.ARMED
	index = i
	from = -1
	targets = []
	return true


func cancel() -> void:
	phase = Phase.IDLE
	index = -1
	from = -1
	targets = []


## Atrás un paso: de pieza elegida a trampa armada; de armada a reposo.
func back() -> void:
	if phase == Phase.PIECE:
		phase = Phase.ARMED
		from = -1
		targets = []
	else:
		cancel()


## Resultado de un clic sobre `sq` con la trampa armada `def`.
## Devuelve {action, from, to, reason}; `action`:
##   "none"    nada que hacer (reposo)
##   "select"  se eligió una pieza (ver `from` y `targets`)
##   "back"    se des-eligió la pieza
##   "execute" hay que llamar `start_cheat(from, to)` (el estado vuelve a reposo)
##   "reject"  clic inválido, `reason` explica por qué (el estado no cambia)
func on_square(sq: int, b: BoardState, color: int, def: CheatDef) -> Dictionary:
	var res := {"action": "none", "from": from, "to": -1, "reason": ""}
	if phase == Phase.IDLE or def == null:
		return res
	if sq < 0:
		res.action = "back"
		back()
		return res
	if phase == Phase.PIECE:
		if sq == from:
			res.action = "back"
			back()
			return res
		if sq in targets:
			res.action = "execute"
			res.to = sq
			cancel()
			return res
		# Clic en otra pieza elegible: se cambia la selección; si no, rechazo.
		if CheatTargeting.targets(b, color, def, sq).is_empty():
			res.action = "reject"
			res.reason = "destino inválido"
			return res
	var t := CheatTargeting.targets(b, color, def, sq)
	if t.is_empty():
		res.action = "reject"
		res.reason = CheatTargeting.why_not(b, color, def, sq)
		return res
	if def.kind == CheatDef.Kind.STEAL:
		res.action = "execute"
		res.from = sq
		res.to = -1
		cancel()
		return res
	phase = Phase.PIECE
	from = sq
	targets = t
	res.action = "select"
	res.from = sq
	return res
