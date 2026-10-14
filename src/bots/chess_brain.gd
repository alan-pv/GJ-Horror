class_name ChessBrain
extends RefCounted
## Interfaz común de los motores de los bots. Un cerebro no elige la jugada:
## devuelve una POLÍTICA (probabilidad de cada jugada legal para un humano de
## ese Elo) y el bot la muestrea. Así los errores salen de la misma
## distribución que las buenas jugadas, en lugar de "jugar perfecto y a veces
## regalar una pieza".


## Coroutine: `var policy: Dictionary = await brain.get_policy(...)`.
## Devuelve {uci: probabilidad}. Vacío si no hay jugadas.
func get_policy(_board: BoardState, _elo_self: int, _elo_oppo: int) -> Dictionary:
	return {}


func is_ready() -> bool:
	return true


func brain_name() -> String:
	return "abstracto"


## Elige una jugada de la política con temperatura (1 = tal cual, <1 más fuerte).
static func sample(policy: Dictionary, temperature: float, rng: RandomNumberGenerator) -> String:
	if policy.is_empty():
		return ""
	var keys := policy.keys()
	if temperature <= 0.01:
		var best: String = keys[0]
		for k in keys:
			if policy[k] > policy[best]:
				best = k
		return best
	var weights := PackedFloat64Array()
	var total := 0.0
	for k in keys:
		var w := pow(maxf(policy[k], 1e-9), 1.0 / temperature)
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in keys.size():
		r -= weights[i]
		if r <= 0.0:
			return keys[i]
	return keys[keys.size() - 1]


## Softmax sobre puntuaciones en centipeones.
static func softmax(scores: Dictionary, temperature_cp: float) -> Dictionary:
	var best := -INF
	for k in scores:
		best = maxf(best, scores[k])
	var total := 0.0
	var out := {}
	for k in scores:
		var w := exp((scores[k] - best) / maxf(temperature_cp, 1.0))
		out[k] = w
		total += w
	for k in out:
		out[k] /= total
	return out
