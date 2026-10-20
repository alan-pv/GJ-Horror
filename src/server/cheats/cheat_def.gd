class_name CheatDef
extends Resource
## Clase de trampa como datos. El jugador no elige la clase: el servidor la
## deduce de la pieza que agarra (propia o rival) y de adónde la pone.

enum Kind {
	OWN_MOVE,    ## Mueve una pieza propia a una casilla vacía que no es jugada legal.
	MOVE_ENEMY,  ## Mueve una pieza rival a otra casilla vacía.
	STEAL,       ## Quita una pieza rival y la deja en la pila de capturas propia.
}

@export var id: StringName
@export var display_name: String
@export var kind: Kind
@export_multiline var description: String
## Segundos que la mano tarda aunque no recorra distancia.
@export var base_time: float = 1.0
## Segundos extra por casilla recorrida por la mano (distancia de rey).
@export var time_per_square: float = 0.3
## Evidencia (0 nada, 1 descarado) según el nivel de sospecha; el índice es el
## nivel y los niveles mayores usan el último valor. Lo usan los bots al vigilar.
@export var evidence_by_level: PackedFloat32Array = PackedFloat32Array([0.0, 0.5])
## Cuánto queda descentrada la pieza, en fracciones de casilla.
@export_range(0.0, 0.45) var offset_amount: float = 0.15


## Evidencia de una trampa de este nivel.
func evidence_for(level: int) -> float:
	if evidence_by_level.is_empty():
		return 0.5
	return evidence_by_level[clampi(level, 0, evidence_by_level.size() - 1)]


## Duración de la trampa según la distancia recorrida por la mano.
func duration_for(distance: int) -> float:
	return base_time + time_per_square * distance
