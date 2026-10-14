class_name CheatTargeting
## Lógica pura para elegir objetivos de una trampa (sin nodos): qué destinos
## son válidos para una pieza y por qué una pieza no sirve.
## Se apoya en `CheatRules.validate`, que es la misma validación del servidor.


## Destinos válidos de `from` para la trampa `def`. En el robo no hay destino:
## devuelve [-1] si se puede robar la pieza y [] si no.
static func targets(b: BoardState, color: int, def: CheatDef, from: int) -> Array[int]:
	var out: Array[int] = []
	if def.kind == CheatDef.Kind.STEAL:
		if CheatRules.validate(b, color, def, from, -1).ok:
			out.append(-1)
		return out
	for to in 64:
		if to != from and CheatRules.validate(b, color, def, from, to).ok:
			out.append(to)
	return out


## Motivo por el que una pieza no sirve para esta trampa ("" si tiene objetivos).
static func why_not(b: BoardState, color: int, def: CheatDef, from: int) -> String:
	if from < 0 or from > 63:
		return "casilla inválida"
	if b.squares[from] == ChessPiece.NONE:
		return "no hay pieza"
	if not targets(b, color, def, from).is_empty():
		return ""
	# El rechazo "de pieza" (rey, propia/enemiga) explica mejor que "sin destinos".
	var probe := CheatRules.validate(b, color, def, from, from)
	for r in ["los reyes no se tocan", "solo piezas propias", "solo piezas enemigas"]:
		if probe.reason == r:
			return r
	return "esa pieza no tiene destinos posibles"
