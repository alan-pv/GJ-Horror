class_name FallbackBrain
extends ChessBrain
## Cerebro de respaldo en GDScript, sin dependencias. Se usa en el editor y en
## escritorio, o si Maia no carga en el navegador. Busca a 2 plies con
## material y tablas de casillas y convierte las puntuaciones en política con
## un softmax cuya temperatura depende del Elo: un 800 reparte probabilidad
## entre jugadas mediocres, un 2000 casi siempre elige la mejor.

## Tablas de casilla (desde el punto de vista de blancas, a1 = índice 0).
const PST_PAWN := [
	0, 0, 0, 0, 0, 0, 0, 0,
	5, 10, 10, -20, -20, 10, 10, 5,
	5, -5, -10, 0, 0, -10, -5, 5,
	0, 0, 0, 20, 20, 0, 0, 0,
	5, 5, 10, 25, 25, 10, 5, 5,
	10, 10, 20, 30, 30, 20, 10, 10,
	50, 50, 50, 50, 50, 50, 50, 50,
	0, 0, 0, 0, 0, 0, 0, 0,
]
const PST_KNIGHT := [
	-50, -40, -30, -30, -30, -30, -40, -50,
	-40, -20, 0, 5, 5, 0, -20, -40,
	-30, 5, 10, 15, 15, 10, 5, -30,
	-30, 0, 15, 20, 20, 15, 0, -30,
	-30, 5, 15, 20, 20, 15, 5, -30,
	-30, 0, 10, 15, 15, 10, 0, -30,
	-40, -20, 0, 0, 0, 0, -20, -40,
	-50, -40, -30, -30, -30, -30, -40, -50,
]
const PST_CENTER := [
	-20, -10, -10, -10, -10, -10, -10, -20,
	-10, 5, 0, 0, 0, 0, 5, -10,
	-10, 10, 10, 10, 10, 10, 10, -10,
	-10, 0, 10, 10, 10, 10, 0, -10,
	-10, 5, 5, 10, 10, 5, 5, -10,
	-10, 0, 5, 10, 10, 5, 0, -10,
	-10, 0, 0, 0, 0, 0, 0, -10,
	-20, -10, -10, -10, -10, -10, -10, -20,
]
const PST_KING := [
	20, 30, 10, 0, 0, 10, 30, 20,
	20, 20, 0, 0, 0, 0, 20, 20,
	-10, -20, -20, -20, -20, -20, -20, -10,
	-20, -30, -30, -40, -40, -30, -30, -20,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
]


## Presupuesto de script por fotograma (microsegundos) al calcular la política: pasado
## este tiempo la corrutina cede el fotograma y sigue en el siguiente, para que el
## cálculo del bot no congele la partida en el momento de soltar la jugada.
const SLICE_USEC := 3000

## Valor de cada pieza en cada casilla, firmado (blancas +, negras -): índice pieza * 64 + casilla.
static var _pv := PackedFloat64Array()


func brain_name() -> String:
	return "respaldo (GDScript)"


## Coroutine: reparte el cálculo entre fotogramas (usa `await`). Para pruebas y
## herramientas sin bucle de fotogramas, `get_policy_sync` calcula de una vez.
func get_policy(board: BoardState, elo_self: int, _elo_oppo: int) -> Dictionary:
	var work := board.clone()
	var moves := ChessRules.legal_moves_int(work)
	if moves.is_empty():
		return {}
	var tree := Engine.get_main_loop() as SceneTree
	var us := work.side_to_move
	var e0 := evaluate(work, us)
	var scores := {}
	var t0 := Time.get_ticks_usec()
	for mv in moves:
		scores[_uci(mv)] = _score_move(work, mv, us, e0)
		if tree != null and Time.get_ticks_usec() - t0 > SLICE_USEC:
			await tree.process_frame
			t0 = Time.get_ticks_usec()
	return softmax(scores, temperature_for_elo(elo_self))


## Misma política que `get_policy`, calculada de una vez sin ceder fotogramas.
func get_policy_sync(board: BoardState, elo_self: int, _elo_oppo: int = 1500) -> Dictionary:
	var work := board.clone()
	var moves := ChessRules.legal_moves_int(work)
	if moves.is_empty():
		return {}
	var us := work.side_to_move
	var e0 := evaluate(work, us)
	var scores := {}
	for mv in moves:
		scores[_uci(mv)] = _score_move(work, mv, us, e0)
	return softmax(scores, temperature_for_elo(elo_self))


static func _uci(mv: int) -> String:
	return ChessMove.new(mv & 63, (mv >> 6) & 63, (mv >> 12) & 7).uci()


## Puntuación a 2 plies de la jugada `mv` (peor respuesta del rival) para `us`.
## `work` se modifica con hacer/deshacer y queda como estaba; `e0` es su evaluación.
static func _score_move(work: BoardState, mv: int, us: int, e0: float) -> float:
	var undo := PackedInt32Array()
	undo.resize(12)
	var undo_r := PackedInt32Array()
	undo_r.resize(12)
	ChessRules.make_int(work, mv, undo)
	var e1 := e0 + _delta(work, undo, us)
	var replies := PackedInt32Array()
	ChessRules.gen_pseudo_int(work, replies)
	var score := INF
	for r in replies:
		if (work.squares[(r >> 6) & 63] & 7) == ChessPiece.KING:
			continue
		ChessRules.make_int(work, r, undo_r)
		if ChessRules.mover_king_safe(work):
			score = minf(score, e1 + _delta(work, undo_r, us))
		ChessRules.unmake_int(work, undo_r)
	if score == INF:
		if ChessRules.in_check(work, work.side_to_move):
			score = 100000.0
		else:
			score = 50000.0 if us == ChessPiece.BLACK else -5000.0
	ChessRules.unmake_int(work, undo)
	return score


## Cambio de evaluación (desde `us`) por las casillas que tocó la última jugada hecha.
static func _delta(b: BoardState, undo: PackedInt32Array, us: int) -> float:
	var d := 0.0
	for i in undo[3]:
		var sq := undo[4 + 2 * i]
		d += _pv[b.squares[sq] * 64 + sq] - _pv[undo[5 + 2 * i] * 64 + sq]
	return d if us == ChessPiece.WHITE else -d


static func temperature_for_elo(elo: int) -> float:
	var t := clampf((elo - 600.0) / 1600.0, 0.0, 1.0)
	return lerpf(220.0, 25.0, t)


static func _init_pv() -> void:
	_pv.resize(16 * 64)
	for p in 16:
		var type := p & 7
		if type == 0 or type > ChessPiece.KING:
			continue
		var white := ((p >> 3) & 1) == ChessPiece.WHITE
		for sq in 64:
			var idx := sq if white else (7 - sq / 8) * 8 + sq % 8
			var v := float(ChessPiece.VALUES[type])
			match type:
				ChessPiece.PAWN: v += PST_PAWN[idx]
				ChessPiece.KNIGHT: v += PST_KNIGHT[idx]
				ChessPiece.BISHOP, ChessPiece.QUEEN: v += PST_CENTER[idx] * 0.5
				ChessPiece.KING: v += PST_KING[idx]
			_pv[p * 64 + sq] = v if white else -v


## Evaluación estática desde el punto de vista de `color`.
static func evaluate(b: BoardState, color: int) -> float:
	if _pv.is_empty():
		_init_pv()
	var total := 0.0
	for sq in 64:
		var p := b.squares[sq]
		if p != 0:
			total += _pv[p * 64 + sq]
	return total if color == ChessPiece.WHITE else -total
