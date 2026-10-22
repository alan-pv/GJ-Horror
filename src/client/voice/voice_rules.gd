class_name VoiceRules
extends RefCounted
## Disparadores puros del monólogo interior (sin nodos): números en palabras, qué frase de inicio
## de ronda toca, cambios de material y de reloj, y el detector de rival distraído.

const WORDS := {32: "Thirty-two", 16: "Sixteen", 8: "Eight", 4: "Four", 2: "Two"}
## Segundos sin mirar el tablero para contar como "distraído".
const DISTRACT_AFTER := 1.2


## 32 -> "Thirty-two"; si no hay palabra, los dígitos.
static func count_word(n: int) -> String:
	return WORDS.get(n, str(n))


## Frase de inicio de ronda >= 2: {id, fmt} o `{}` si no toca ninguna.
## `first_final_game`: primera partida de la final (en la segunda no se dice nada).
static func round_start(remaining: int, is_final: bool, first_final_game: bool) -> Dictionary:
	if is_final:
		return {"id": &"round_final", "fmt": []} if first_final_game else {}
	if remaining <= 4:
		return {"id": &"round_semi", "fmt": []}
	return {"id": &"round_left", "fmt": [count_word(remaining)]}


## ¿Cruzó `threshold` hacia abajo entre `prev` y `cur`?
static func crossed(prev: float, cur: float, threshold: float) -> bool:
	return prev > threshold and cur <= threshold


static func count_queens(b: BoardState, color: int) -> int:
	var q := ChessPiece.make(color, ChessPiece.QUEEN)
	var n := 0
	for p in b.squares:
		if p == q:
			n += 1
	return n


## Material (en centipeones) de `color` menos el del rival.
static func material_balance(b: BoardState, color: int) -> int:
	var total := 0
	for p in b.squares:
		if p == ChessPiece.NONE:
			continue
		var v := ChessPiece.value_of(p)
		total += v if ChessPiece.color_of(p) == color else -v
	return total


## ¿Va perdiendo `color` en material o en reloj?
static func is_behind(b: BoardState, clock: ChessClock, color: int) -> bool:
	return material_balance(b, color) < 0 or clock.remaining[color] < clock.remaining[ChessPiece.opposite(color)]


## Detector de "el rival no mira el tablero": salta una vez cuando lleva `DISTRACT_AFTER` s sin
## mirar; se rearma cuando vuelve a mirar o deja de estar activo.
class GazeWatch extends RefCounted:
	var away: float = 0.0
	var fired: bool = false

	## Devuelve true en el instante en que se cumple el tiempo sin mirar.
	func update(delta: float, active: bool, looking: bool) -> bool:
		if not active or looking:
			away = 0.0
			fired = false
			return false
		away += delta
		if away >= DISTRACT_AFTER and not fired:
			fired = true
			return true
		return false

	## ¿Está distraído ahora?
	func is_distracted() -> bool:
		return away >= DISTRACT_AFTER
