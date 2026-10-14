class_name CheatDef
extends Resource
## Definición de una trampa como datos. Ajustar o agregar una no exige tocar código.

enum Kind {
	NUDGE,       ## Avanza una pieza propia una casilla.
	SLIDE,       ## Mueve una pieza propia varias casillas en línea.
	STEAL,       ## Quita una pieza enemiga y la esconde en la mano.
	MOVE_ENEMY,  ## Mueve una pieza enemiga a otra casilla.
}

@export var id: StringName
@export var display_name: String
@export var kind: Kind
@export_multiline var description: String
## Segundos que la mano tarda aunque no recorra distancia.
@export var base_time: float = 1.0
## Segundos extra por casilla recorrida (distancia de rey).
@export var time_per_square: float = 0.3
## Distancia máxima en casillas (0 = sin límite).
@export var max_distance: int = 0
## Nivel de evidencia que queda (0 nada, 1 descarado). Lo usan los bots al vigilar.
@export_range(0.0, 1.0) var evidence: float = 0.5
## Cuánto queda descentrada la pieza, en fracciones de casilla.
@export_range(0.0, 0.45) var offset_amount: float = 0.15
