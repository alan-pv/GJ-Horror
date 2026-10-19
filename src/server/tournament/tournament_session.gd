class_name TournamentSession
extends RefCounted
## Estado del torneo que sobrevive a la recarga de la escena entre partidas
## (variables estáticas). `GameRoot` lo consulta al armar cada partida.

static var manager: TournamentManager = null
## Segundos acumulados de todas las escenas (para `--quit-after`).
static var elapsed: float = 0.0
## Torneos completados o abandonados desde el arranque (solo informativo).
static var tournaments_started: int = 0


static func ensure(player_count: int, seed_value: int) -> TournamentManager:
	if manager == null:
		manager = TournamentManager.new(player_count, seed_value)
		tournaments_started += 1
	return manager
