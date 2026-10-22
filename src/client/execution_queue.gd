class_name ExecutionQueue
extends RefCounted
## Cola de ejecuciones del árbitro (lógica pura). Cada entrada es (mesa, asiento) con
## un indicador de prioridad (la partida del humano). `take_next` elige primero las
## prioritarias y, entre las demás, la más cercana al punto dado. No admite duplicados:
## una petición repetida de lo que ya está en cola, en curso o hecho se ignora.

## Entradas pendientes: {table, seat, priority, spot}.
var pending: Array[Dictionary] = []
## Clave de la ejecución en curso (-1 = ninguna).
var current: int = -1
var _done: Dictionary = {}


static func key(table: int, seat: int) -> int:
	return table * 2 + seat


## Encola. Devuelve false si ya estaba (en cola, en curso o ejecutada).
func push(table: int, seat: int, spot: Vector3, priority: bool = false) -> bool:
	var k := key(table, seat)
	if k == current or _done.has(k) or has(table, seat):
		return false
	pending.append({"table": table, "seat": seat, "priority": priority, "spot": spot})
	return true


func has(table: int, seat: int) -> bool:
	for e in pending:
		if int(e.table) == table and int(e.seat) == seat:
			return true
	return false


func size() -> int:
	return pending.size()


func is_empty() -> bool:
	return pending.is_empty()


## ¿Hay algo en cola o en curso?
func busy() -> bool:
	return current >= 0 or not pending.is_empty()


## Saca la siguiente entrada y la marca en curso; {} si no hay.
func take_next(from: Vector3) -> Dictionary:
	if pending.is_empty():
		return {}
	var best := 0
	for i in range(1, pending.size()):
		if _better(pending[i], pending[best], from):
			best = i
	var e: Dictionary = pending[best]
	pending.remove_at(best)
	current = key(int(e.table), int(e.seat))
	return e


## Como `take_next` pero sin sacarla: la entrada que se tomaría desde `from` ({} si no hay).
func peek_next(from: Vector3) -> Dictionary:
	if pending.is_empty():
		return {}
	var best := 0
	for i in range(1, pending.size()):
		if _better(pending[i], pending[best], from):
			best = i
	return pending[best]


## Descarta las entradas pendientes de mesas distintas de `except_table` y las da por hechas.
## Devuelve las descartadas (corte de ronda: se resuelven en silencio).
func skip_pending(except_table: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var keep: Array[Dictionary] = []
	for e in pending:
		if int(e.table) == except_table:
			keep.append(e)
		else:
			out.append(e)
			_done[key(int(e.table), int(e.seat))] = true
	pending = keep
	return out


## Quita de la cola la entrada de (`table`, `seat`) si está (no la da por hecha).
func drop(table: int, seat: int) -> void:
	for i in pending.size():
		if int(pending[i].table) == table and int(pending[i].seat) == seat:
			pending.remove_at(i)
			return


## Da por hecha una ejecución sin hacerla (el perdedor se resuelve en silencio).
func mark_done(table: int, seat: int) -> void:
	_done[key(table, seat)] = true


## Devuelve una entrada en curso a la cola (p. ej. la interrumpió una acusación).
func requeue(e: Dictionary) -> void:
	current = -1
	pending.append(e)


## La ejecución en curso terminó.
func finish() -> void:
	if current >= 0:
		_done[current] = true
	current = -1


func was_done(table: int, seat: int) -> bool:
	return _done.has(key(table, seat))


func _better(a: Dictionary, b: Dictionary, from: Vector3) -> bool:
	if bool(a.priority) != bool(b.priority):
		return bool(a.priority)
	var da := Vector2(a.spot.x - from.x, a.spot.z - from.z).length_squared()
	var db := Vector2(b.spot.x - from.x, b.spot.z - from.z).length_squared()
	if not is_equal_approx(da, db):
		return da < db
	return key(int(a.table), int(a.seat)) < key(int(b.table), int(b.seat))
