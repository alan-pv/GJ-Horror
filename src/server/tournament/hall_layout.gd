class_name HallLayout
extends RefCounted
## Disposición fija de las mesas del salón: cuadrícula de 4x4 (16 mesas, 32
## jugadores). Índice = fila * COLS + columna; la fila 0 es la más lejana (-Z),
## al frente del jugador. La mesa del humano es la 9 (fila 2, columna 1): dos
## filas delante, una detrás, una columna a la izquierda y dos a la derecha.
## Todas las mesas tienen la misma orientación (jugadores en +Z y -Z).

const COLS := 4
const ROWS := 4
const SPACING_X := 3.0
const SPACING_Z := 3.2
const HUMAN_TABLE := 9


static func table_count() -> int:
	return COLS * ROWS


## Centro de la mesa `index` a ras de suelo; la mesa del humano es el origen.
static func table_position(index: int) -> Vector3:
	var col := index % COLS
	var row := index / COLS
	var human_col := HUMAN_TABLE % COLS
	var human_row := HUMAN_TABLE / COLS
	return Vector3((col - human_col) * SPACING_X, 0.0, (row - human_row) * SPACING_Z)


## Todas las mesas ordenadas por distancia a la del humano (empate: menor índice).
static func tables_by_distance() -> Array[int]:
	var idx: Array[int] = []
	for i in table_count():
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool:
		var da := table_position(a).length_squared()
		var db := table_position(b).length_squared()
		if not is_equal_approx(da, db):
			return da < db
		return a < b)
	return idx
