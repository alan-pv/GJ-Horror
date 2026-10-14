class_name MatchConfig
extends Resource
## Parámetros de una partida. Varias decisiones de diseño aún abiertas viven
## aquí como opciones, para probarlas sin tocar código.

## 3:00 por jugador. Para probar el modo Armageddon: blancas 180, negras 150.
@export var white_seconds: float = 180.0
@export var black_seconds: float = 180.0
## ¿El reloj se detiene mientras llega el árbitro?
@export var pause_clock_on_accusation: bool = true
## Segundos de suspenso mientras el árbitro camina a la mesa.
@export var arbiter_delay: float = 3.0
## La tercera acusación falsa elimina.
@export var false_accusations_to_eliminate: int = 3
## ¿Una acusación correcta borra una advertencia?
@export var correct_accusation_clears_warning: bool = false
## Ayuda para principiantes (siempre activa en el prototipo).
@export var beginner_help: bool = true
## Umbral de la ayuda en centipeones.
@export var blunder_threshold_cp: int = 300
## Coseno del medio ángulo del cono de visión (0.82 ≈ 35°).
@export var gaze_cos_threshold: float = 0.82
## Posición del centro del tablero en el mundo (el servidor conoce la mesa).
@export var board_center: Vector3 = Vector3.ZERO
## Las trampas disponibles en esta partida.
@export var cheats: Array[CheatDef] = []
## Segundos de espera para repetir un evento propio (toser, tirar una pieza), por jugador.
@export var rival_event_cooldown: float = 20.0
