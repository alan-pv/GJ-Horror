class_name TestCase
extends RefCounted
## Base mínima para pruebas: acumula fallos en vez de detener la ejecución.

var failures: Array = []
## Árbol de escena que corre las pruebas (lo asigna run_tests.gd); para pruebas que necesitan fotogramas.
var tree: SceneTree


func check(cond: bool, msg: String = "condición falsa") -> void:
	if not cond:
		failures.append(msg)


func check_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s esperado=%s obtenido=%s" % [msg, str(expected), str(actual)])
