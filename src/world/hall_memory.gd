class_name HallMemory
extends RefCounted
## Memoria visual del salón entre recargas de escena (variables estáticas, como
## `TournamentSession`). Guarda, por mesa de una ronda pasada, la posición final de las piezas para
## que `GameRoot` las vuelva a poner tras recargar. Las mesas recordadas quedan sin nadie (los
## ganadores se fueron a su mesa nueva y los cadáveres desaparecen con el primer parpadeo del
## paseo), con la lámpara atenuada. Es solo vista: nada de esto lo lee el servidor. Una mesa se
## olvida cuando se reutiliza en una ronda nueva (`release_used`) y todo se borra con un torneo
## nuevo (`clear`).

## Mesa (índice de `HallLayout`) -> `{squares: PackedInt32Array}`.
static var tables: Dictionary = {}


## Apunta la mesa `table`: casillas del tablero físico (a1 = 0).
static func remember(table: int, squares: PackedInt32Array) -> void:
	if table < 0:
		return
	tables[table] = {"squares": squares.duplicate()}


static func has(table: int) -> bool:
	return tables.has(table)


## Datos de la mesa, o diccionario vacío si no se recuerda nada.
static func entry(table: int) -> Dictionary:
	return tables.get(table, {})


## Mesas recordadas, ordenadas.
static func remembered() -> Array[int]:
	var out: Array[int] = []
	for t in tables:
		out.append(int(t))
	out.sort()
	return out


## Las mesas 0..`used_count`-1 se usan en la ronda (nueva): se borran sus recuerdos.
static func release_used(used_count: int) -> void:
	for t in tables.keys():
		if int(t) < used_count:
			tables.erase(t)


## Torneo nuevo: el salón se olvida de todo.
static func clear() -> void:
	tables.clear()


## Mesas de la ronda nueva (0..`used_count`-1) salvo `keep` (la destino del humano, que prepara el
## paseo): se repueblan con los nuevos emparejamientos sentados y las piezas en su sitio.
static func tables_to_fill(used_count: int, keep: int) -> Array[int]:
	var out: Array[int] = []
	for t in used_count:
		if t != keep:
			out.append(t)
	return out


## Mesas fuera de la ronda nueva (`used_count` en adelante, salvo `keep`) que quedan vacías porque no
## guardan recuerdo (p. ej. donde alguien descansó). Las que sí lo tienen conservan las piezas.
## Con `tables_to_fill` y las recordadas cubre todo el salón.
static func tables_to_empty(table_count: int, used_count: int, keep: int) -> Array[int]:
	var out: Array[int] = []
	for t in range(used_count, table_count):
		if t != keep and not tables.has(t):
			out.append(t)
	return out
