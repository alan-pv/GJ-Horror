class_name RoundCut
extends RefCounted
## Corte de ronda (lógica pura). Cuando el humano ya terminó y las demás mesas tardan, solo se
## ve la ejecución de UNA "última mesa"; el resto de las partidas se cierra con resultado
## simulado y sus perdedores se resuelven en silencio (sin pasar por el árbitro).

## Espera (s) entre que el humano se asienta y el corte: se sortea en este rango.
const DELAY := Vector2(10.0, 20.0)


## Elige la última mesa y reparte el resto. Entradas:
##   `current_table`: mesa que el árbitro ejecuta ahora (-1 si ninguna).
##   `next_queued`: mesa que tomaría de la cola (-1 si está vacía).
##   `unfinished`: partidas de fondo sin terminar, `{table, dist}` con `dist` = distancia al árbitro.
## Devuelve `{last_table, close_last, silent}`: `last_table` (-1 si no queda nada), `close_last` si esa
## mesa aún está en juego (hay que cerrarla con `force_end` y ejecutar normal) y `silent`, las
## mesas en juego que se cierran en silencio (todas menos la última).
static func plan(current_table: int, next_queued: int, unfinished: Array) -> Dictionary:
	var last := -1
	var close_last := false
	if current_table >= 0:
		last = current_table
	elif next_queued >= 0:
		last = next_queued
	elif not unfinished.is_empty():
		var best: Dictionary = unfinished[0]
		for e in unfinished:
			var d := float(e.dist)
			var bd := float(best.dist)
			if d < bd or (is_equal_approx(d, bd) and int(e.table) < int(best.table)):
				best = e
		last = int(best.table)
		close_last = true
	var silent: Array[int] = []
	for e in unfinished:
		if int(e.table) != last:
			silent.append(int(e.table))
	return {"last_table": last, "close_last": close_last, "silent": silent}
