class_name HallLayout
extends RefCounted
## Disposición fija de las mesas del salón: cuadrícula de 4x4 (16 mesas, 32
## jugadores). Todas tienen la misma orientación (jugadores en +Z y -Z).
##
## Numeración: la mesa de índice `i` es la mesa número `i + 1`. Las mesas 1-4 forman
## la fila del fondo (fila 0, la más lejana, en -Z, delante del jugador) y las 13-16 la
## más cercana. Dentro de cada fila el orden es 3-1-2-4 (de izquierda a derecha): las
## mesas 1 y 2 quedan en el centro del fondo, sobre el podio. Con 32 jugadores las
## partidas ocupan las mesas 1..N de cada ronda y el humano la N (16, 8, 4, 2, 1), así que
## sube por el lado derecho hacia el podio y el salón se vacía desde atrás.
##
## La vista supone la mesa del humano en `Vector3.ZERO`: `table_position` es relativa a
## ella y cambia con `human_table` (lo fija `GameRoot` al montar cada escena); el salón
## entero se desplaza alrededor. La altura del suelo (el podio es una tarima) se consulta
## con `floor_y`.

const COLS := 4
const ROWS := 4
const SPACING_X := 3.0
const SPACING_Z := 3.2
## Columna de cada posición dentro de la fila (`índice % COLS`): 3-1-2-4 de izquierda a derecha.
const SLOT_COLUMNS: Array[int] = [1, 2, 0, 3]
## Las primeras mesas (1 y 2) están sobre el podio.
const PODIUM_TABLES := 2
const PODIUM_HEIGHT := 0.18
## Horizontal que ocupa la rampa de cada borde del podio (se sube caminando).
const PODIUM_RAMP := 0.4
## Posición absoluta (en la cuadrícula) del origen del marco de la sala: la celda (1, 2). Los
## muros y el decorado se construyen en torno a él y se desplazan para que la mesa del humano
## quede en el origen del mundo.
const ROOM_ORIGIN := Vector3(1.0 * SPACING_X, 0.0, 2.0 * SPACING_Z)

## Índice de la mesa del humano en la escena actual. Por defecto la 16 (ronda 1 con 32 jugadores).
static var human_table: int = 15
## Alias obsoleto de `human_table` (antes era una constante). Usar `human_table`.
static var HUMAN_TABLE: int:
	get:
		return human_table


static func table_count() -> int:
	return COLS * ROWS


## Fija la mesa del humano (índice 0..15); a partir de aquí `table_position` es relativa a ella.
static func set_human_table(index: int) -> void:
	human_table = clampi(index, 0, table_count() - 1)


## Mesa del humano cuando la ronda usa `total` mesas (partidas + descansos): la de número más alto.
static func human_table_for(total: int) -> int:
	return clampi(total, 1, table_count()) - 1


## Número visible de la mesa (1..16).
static func number_of(index: int) -> int:
	return index + 1


## Celda (columna, fila) de la mesa en la cuadrícula; la fila 0 es la del fondo.
static func cell_of(index: int) -> Vector2i:
	return Vector2i(SLOT_COLUMNS[index % COLS], index / COLS)


## Mesa que ocupa la celda (columna, fila).
static func index_at(col: int, row: int) -> int:
	return row * COLS + SLOT_COLUMNS.find(col)


## Posición absoluta del centro de la mesa en la cuadrícula (no depende de `human_table`).
static func grid_position(index: int) -> Vector3:
	var c := cell_of(index)
	return Vector3(c.x * SPACING_X, 0.0, c.y * SPACING_Z)


## Centro de la mesa `index` a ras de suelo en la escena: la mesa del humano es el origen.
static func table_position(index: int) -> Vector3:
	return grid_position(index) - grid_position(human_table)


## Posición de la mesa en el marco de la sala (fijo; el origen es `ROOM_ORIGIN`).
static func room_position(index: int) -> Vector3:
	return grid_position(index) - ROOM_ORIGIN


## Desplazamiento de la sala en la escena (X, Z) y baja si el humano está sobre el podio
## (Y), para que su mesa quede en el origen.
static func room_offset() -> Vector3:
	var o := ROOM_ORIGIN - grid_position(human_table)
	o.y = -floor_height(human_table)
	return o


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


# --- Podio y riqueza -------------------------------------------------------------------

static func is_podium(index: int) -> bool:
	return index < PODIUM_TABLES


## Altura absoluta del suelo de la mesa (el podio es una tarima).
static func floor_height(index: int) -> float:
	return PODIUM_HEIGHT if is_podium(index) else 0.0


## Centro (X, Z) y mitad de la extensión del podio en la cuadrícula: ocupa las celdas de las
## mesas 1 y 2 (columnas 1 y 2 de la fila 0).
static func podium_center() -> Vector3:
	return (grid_position(0) + grid_position(1)) * 0.5


static func podium_half() -> Vector2:
	return Vector2(SPACING_X, SPACING_Z * 0.5)


## Altura del suelo en el punto `p` de la escena (coordenadas relativas a la mesa del humano,
## y = 0 es el suelo bajo ella): sube por las rampas del borde del podio.
static func floor_y(p: Vector3) -> float:
	var a := p + grid_position(human_table)
	var c := podium_center()
	var h := podium_half()
	var d := minf(h.x - absf(a.x - c.x), h.y - absf(a.z - c.z))
	var raw := PODIUM_HEIGHT * clampf(d / PODIUM_RAMP, 0.0, 1.0)
	return raw - floor_height(human_table)


## Riqueza de la mesa (0 sencilla ... 3 podio): las finales son más lujosas.
## 9-16 sencillas, 5-8 con mantel, 3-4 con mantel, marco y candelabro, 1-2 (podio) con todo.
static func richness(index: int) -> int:
	if index < PODIUM_TABLES:
		return 3
	if index < 4:
		return 2
	if index < 8:
		return 1
	return 0
