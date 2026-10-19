extends Node
## Autoload "GameSettings": título del juego y ajustes del jugador que sobreviven
## entre escenas y entre sesiones (sensibilidad del ratón y pantalla completa).
## El volumen vive en `AudioManager`, que lo guarda por su cuenta.

## Título provisional del juego (pendiente). Es lo único que hay que cambiar.
const GAME_TITLE := "Checkmate"
const MENU_SCENE := "res://src/ui/main_menu.tscn"
const GAME_SCENE := "res://src/world/main.tscn"

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "game"
const SENSITIVITY_MIN := 0.25
const SENSITIVITY_MAX := 3.0

signal changed

## Multiplicador de la sensibilidad base del ratón (1.0 = la de fábrica).
var mouse_sensitivity: float = 1.0
var fullscreen: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, SENSITIVITY_MIN, SENSITIVITY_MAX)
	changed.emit()


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_fullscreen()
	changed.emit()


func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


func save_settings() -> void:
	var file := ConfigFile.new()
	file.set_value(SECTION, "mouse_sensitivity", mouse_sensitivity)
	file.set_value(SECTION, "fullscreen", fullscreen)
	if file.save(SETTINGS_PATH) != OK:
		push_warning("Could not write %s." % SETTINGS_PATH)


## Un archivo ausente es la primera ejecución normal: quedan los valores de fábrica.
func load_settings() -> void:
	var file := ConfigFile.new()
	if file.load(SETTINGS_PATH) != OK:
		return
	mouse_sensitivity = clampf(float(file.get_value(SECTION, "mouse_sensitivity", 1.0)),
			SENSITIVITY_MIN, SENSITIVITY_MAX)
	fullscreen = bool(file.get_value(SECTION, "fullscreen", false))
	_apply_fullscreen()
