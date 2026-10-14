class_name MaiaHistory
extends RefCounted
## Reconstruye el historial de posiciones FÍSICAS que necesita Maia-3 (las 8 últimas).
##
## El cerebro solo recibe el tablero actual, y un bot solo pide política en su turno,
## así que entre dos peticiones pasan dos jugadas (la suya y la del rival). La posición
## intermedia se deduce buscando la pareja de jugadas legales que lleva de la posición
## anterior a la actual. Si el tablero cambió por fuera de las reglas (una trampa) y no
## hay explicación, se anota la posición actual sin hueco rellenado: el modelo recibe el
## mejor historial disponible y, en el peor caso, la posición repetida (el relleno de maia3).

## Instantáneas, de la más antigua a la actual.
var trail: Array[BoardState] = []


## Registra el tablero actual y devuelve el historial (máx. 8) que termina en él.
func observe(board: BoardState) -> Array:
	var cur := board.clone()
	var inicio := BoardState.start_position()
	if cur.position_key() == inicio.position_key():
		trail = [cur]  # partida nueva
		return trail.duplicate()
	# En la primera petición se parte de la posición inicial (un bot negro empieza en el ply 1).
	var sembrado := trail.is_empty()
	if sembrado:
		trail = [inicio]
	# Se prueba desde la última instantánea hacia atrás: la petición pudo ser sobre
	# una posición hipotética (p. ej. al planear una trampa) que no se jugó.
	var intentos := mini(4, trail.size())
	for k in intentos:
		var idx := trail.size() - 1 - k
		if _igual(trail[idx], cur):  # misma posición pedida otra vez
			trail = trail.slice(0, idx)
			trail.append(cur)
			return trail.duplicate()
		var puente: Variant = _puente(trail[idx], cur)
		if puente != null:
			trail = trail.slice(0, idx + 1)
			trail.append_array(puente)
			trail.append(cur)
			_recortar()
			return trail.duplicate()
	if sembrado:
		trail = [cur]  # la partida no empezó en la posición estándar
		return trail.duplicate()
	trail.append(cur)  # sin explicación (trampa): se sigue sin la posición intermedia
	_recortar()
	return trail.duplicate()


func reset() -> void:
	trail.clear()


func _recortar() -> void:
	if trail.size() > MaiaEncoding.HISTORIA:
		trail = trail.slice(trail.size() - MaiaEncoding.HISTORIA)


## Posiciones intermedias entre `prev` y `cur` (0 o 1), o null si ninguna secuencia de
## una o dos jugadas legales lleva de una a otra.
static func _puente(prev: BoardState, cur: BoardState) -> Variant:
	if cur.side_to_move != prev.side_to_move:
		for m in ChessRules.legal_moves(prev):
			var c := prev.clone()
			ChessRules.apply_move(c, m)
			if _igual(c, cur):
				return []
		return null
	for m1 in ChessRules.legal_moves(prev):
		var mid := prev.clone()
		ChessRules.apply_move(mid, m1)
		# La jugada del rival solo toca casillas donde `mid` y `cur` difieren.
		var difs := PackedInt32Array()
		for sq in 64:
			if mid.squares[sq] != cur.squares[sq]:
				difs.append(sq)
		if difs.is_empty() or difs.size() > 4:
			continue
		for m2 in ChessRules.legal_moves(mid):
			if not (difs.has(m2.from) and difs.has(m2.to)):
				continue
			var fin := mid.clone()
			ChessRules.apply_move(fin, m2)
			if _igual(fin, cur):
				return [mid]
	return null


static func _igual(a: BoardState, b: BoardState) -> bool:
	return a.side_to_move == b.side_to_move and a.squares == b.squares
