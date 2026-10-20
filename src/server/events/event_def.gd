class_name EventDef
extends Resource
## Un evento de ambiente como datos. El director de tensión elige entre los de
## tipo GLOBAL y DETERRENT; los del rival (RIVAL) los pide un jugador o un bot
## a través de `MatchServer.trigger_rival_event`.

enum Kind {
	GLOBAL,    ## Lo ven todos (apagón, ruido, acusación ajena...).
	RIVAL,     ## Lo provoca un jugador sobre su propio personaje (toser, tirar pieza).
	DETERRENT, ## Frena las trampas (el árbitro pasa detrás).
}

## De dónde sale el evento.
enum Origin {
	TABLE,   ## Una mesa decorativa del salón.
	BEHIND,  ## Detrás de la silla del jugador.
	CENTER,  ## Todo el salón (sin punto concreto).
}

@export var id: StringName
@export var display_name: String
@export var kind: Kind = Kind.GLOBAL
@export var origin_mode: Origin = Origin.TABLE
## Segundos que dura el evento (sirve también para el árbitro y el apagón).
@export var duration: float = 3.0
## Peso al sortear entre eventos.
@export var weight: float = 1.0
## Segundos mínimos antes de que este mismo evento pueda repetirse.
@export var cooldown: float = 30.0
## Clave del sonido sintetizado (ver `EventSounds`).
@export var sound: StringName = &""
## 0..1: qué tan fuerte llama la atención. Escala la probabilidad de que un bot voltee.
@export_range(0.0, 1.0) var intensity: float = 0.6
## Tensión mínima (0 = salón lleno, 1 = quedan los últimos) para que el director
## pueda sortear este evento. Sirve para reservar los más duros para el final.
@export_range(0.0, 1.0) var min_tension: float = 0.0
## Probabilidad base (0..1) de que un bot o una figura sentada voltee hacia el evento, antes del
## factor de personalidad. 0 = no hace voltear (banqueta, guardias, puerta...).
@export_range(0.0, 1.0) var turn_chance: float = 0.0
## Tipo de distracción (ver `Distraction.SPECS`): define cómo mira (de reojo o de frente), cuánto
## tiempo y si sobresalta. Vacío = no es una distracción.
@export var distraction: StringName = &""
