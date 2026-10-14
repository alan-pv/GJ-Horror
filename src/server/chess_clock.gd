class_name ChessClock
extends RefCounted
## Reloj de ajedrez sin incremento. El servidor lo avanza con `tick()`.

signal flagged(color: int)

var remaining: PackedFloat64Array = [180.0, 180.0]
## Color cuyo reloj corre, o -1 si está detenido.
var running: int = -1
var paused: bool = false
var flag_fallen: int = -1


func _init(white_seconds: float = 180.0, black_seconds: float = 180.0) -> void:
	remaining = [white_seconds, black_seconds]


func start(color: int) -> void:
	running = color


func stop() -> void:
	running = -1


## Termina el turno de `color`: su reloj se detiene y arranca el del rival.
func press(color: int) -> void:
	if flag_fallen >= 0:
		return
	running = ChessPiece.opposite(color)


func tick(delta: float) -> void:
	if running < 0 or paused or flag_fallen >= 0:
		return
	remaining[running] = maxf(0.0, remaining[running] - delta)
	if remaining[running] <= 0.0:
		flag_fallen = running
		var c := running
		running = -1
		flagged.emit(c)
