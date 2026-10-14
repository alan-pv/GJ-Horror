class_name PlayerSession
extends RefCounted
## Datos del jugador que viven en el torneo, no en la partida.

var id: int
var display_name: String
var is_bot: bool
## Advertencias por acusaciones falsas; se arrastran entre partidas y se
## reinician al empezar un torneo nuevo.
var warnings: int = 0
## Ayuda para principiantes: activada solo para humanos.
var beginner_help: bool = false


func _init(p_id: int = 0, p_name: String = "", p_is_bot: bool = false) -> void:
	id = p_id
	display_name = p_name
	is_bot = p_is_bot
	beginner_help = not p_is_bot


func reset_for_tournament() -> void:
	warnings = 0
