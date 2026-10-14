class_name Gaze
## "Mirar el tablero" = el centro del tablero cae dentro de un cono frente a la cámara.
## Lo usan por igual el jugador y los bots (cámara virtual).


static func is_looking(eye: Vector3, forward: Vector3, target: Vector3, cos_threshold: float) -> bool:
	var to_target := target - eye
	if to_target.length_squared() < 0.0001 or forward.length_squared() < 0.0001:
		return false
	return forward.normalized().dot(to_target.normalized()) >= cos_threshold


## Dirección de mirada a partir de giro (yaw) e inclinación (pitch), en radianes.
## Con yaw = 0 y pitch = 0 se mira hacia -Z, como una Camera3D sin rotar.
static func forward_from_angles(yaw: float, pitch: float) -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD
