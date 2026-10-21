class_name HallMemory
extends RefCounted
## Memoria visual del salón entre recargas de escena (variables estáticas, como
## `TournamentSession`). Guarda, por mesa de una ronda pasada, la posición final de las piezas y el
## cadáver del perdedor (aspecto y asiento) para que `GameRoot` los vuelva a poner tras recargar.
## Es solo vista: nada de esto lo lee el servidor. Una mesa se olvida cuando se reutiliza en una
## ronda nueva (`release_used`) y todo se borra con un torneo nuevo (`clear`).

## Mesa (índice de `HallLayout`) -> `{squares: PackedInt32Array, seat: int, look: Dictionary}`.
## `seat` = color del asiento del cadáver, o -1 si no quedó ninguno (sin ejecución).
static var tables: Dictionary = {}


## Apunta la mesa `table`: casillas del tablero físico (a1 = 0) y, si lo hay, el cadáver del
## perdedor en el asiento `seat` con su aspecto `look`.
static func remember(table: int, squares: PackedInt32Array, seat: int = -1, look: Dictionary = {}) -> void:
	if table < 0:
		return
	tables[table] = {"squares": squares.duplicate(), "seat": seat, "look": look.duplicate(true)}


static func has(table: int) -> bool:
	return tables.has(table)


## Datos de la mesa, o diccionario vacío si no se recuerda nada.
static func entry(table: int) -> Dictionary:
	return tables.get(table, {})


static func has_corpse(table: int) -> bool:
	return tables.has(table) and int(tables[table].seat) >= 0


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


## Mesas que quedan vacías de golpe (sin figuras, cadáveres ni piezas) cuando empieza una ronda
## que usa las mesas 0..`used_count`-1: esas, salvo `keep` (la mesa destino del humano), más las
## que no tienen recuerdo (p. ej. donde alguien descansó). Las demás conservan su recuerdo.
static func tables_to_empty(table_count: int, used_count: int, keep: int) -> Array[int]:
	var out: Array[int] = []
	for t in table_count:
		if t == keep:
			continue
		if t < used_count or not tables.has(t):
			out.append(t)
	return out
