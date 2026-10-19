class_name MaiaBrain
extends ChessBrain
## Cerebro basado en Maia-3 5M (Chessformer), una red que imita jugadas HUMANAS según
## el Elo de quien juega y de su rival (continuo, sin categorías). En la exportación web
## corre en el navegador con onnxruntime-web (web/maia_bridge.js) vía JavaScriptBridge.
## Fuera del navegador (editor, escritorio) o si el puente no está listo / tarda
## demasiado, delega en FallbackBrain.
##
## Maia-3 también ve las 7 posiciones anteriores: MaiaHistory las reconstruye con las
## posiciones físicas que este cerebro ha visto (ver ese archivo).
##
## Maia-3: (c) CSSLab, Universidad de Toronto, licencia AGPL-3.0.

const MODEL_URL := "maia3_5m.onnx"
## Segundos máximos de espera a una respuesta del navegador antes de usar el respaldo.
const TIMEOUT := 3.0

## Se emite con el id de la petición cuando llega su respuesta o vence el tiempo.
signal _respuesta(id: int)

var _fallback := FallbackBrain.new()
var _historial := MaiaHistory.new()
var _bridge: JavaScriptObject = null
## Hay que conservar la referencia: si se libera, el navegador pierde el callback.
var _callback: JavaScriptObject = null
var _next_id := 1
## id -> resultado (String JSON) una vez recibido; ausente si no está pendiente.
var _pendientes: Dictionary = {}
var _iniciado := false
var _usar_web := false


func _init(usar_web: bool = true) -> void:
	_usar_web = usar_web and OS.has_feature("web")
	if _usar_web:
		_iniciar_puente()
		MaiaEncoding.moves()  # carga el vocabulario ahora y no en la primera petición


func brain_name() -> String:
	return "Maia-3 5M (navegador)" if _web_listo() else "respaldo (GDScript)"


func is_ready() -> bool:
	return true


func get_policy(board: BoardState, elo_self: int, elo_oppo: int) -> Dictionary:
	if not _web_listo():
		return await _fallback.get_policy(board, elo_self, elo_oppo)
	var mapa := MaiaEncoding.legal_index_map(board)
	if mapa.is_empty():
		return {}
	var posiciones := _historial.observe(board)
	var indices := mapa.keys()
	var id := _next_id
	_next_id += 1
	var peticion := {
		"tokens": Array(MaiaEncoding.encode_history(posiciones)),
		"elo_self": MaiaEncoding.elo_value(elo_self),
		"elo_oppo": MaiaEncoding.elo_value(elo_oppo),
		"legal": indices,
	}
	_pendientes[id] = null
	_bridge.request(id, JSON.stringify(peticion), _callback)
	var tree := Engine.get_main_loop() as SceneTree
	tree.create_timer(TIMEOUT).timeout.connect(_respuesta.emit.bind(id))
	while _pendientes.get(id) == null:
		if not is_instance_valid(tree) or tree.root == null:
			break
		var quien: int = await _respuesta
		if quien == id:
			break
	var texto: Variant = _pendientes.get(id)
	_pendientes.erase(id)
	var probs := _parsear(texto, indices.size())
	if probs.is_empty():
		push_warning("MaiaBrain: sin respuesta válida del navegador, uso respaldo.")
		return await _fallback.get_policy(board, elo_self, elo_oppo)
	var policy := {}
	for i in indices.size():
		policy[mapa[indices[i]]] = probs[i]
	return policy


func _iniciar_puente() -> void:
	if _iniciado:
		return
	_iniciado = true
	_bridge = JavaScriptBridge.get_interface("MaiaBridge")
	if _bridge == null:
		push_warning("MaiaBrain: window.MaiaBridge no existe (¿falta maia_bridge.js?).")
		return
	_callback = JavaScriptBridge.create_callback(_on_js_respuesta)
	_bridge.init(MODEL_URL)


func _web_listo() -> bool:
	return _usar_web and _bridge != null and _callback != null and bool(_bridge.isReady())


## Llamado desde JS con un único argumento: el JSON {id, probs} o {id, error}.
func _on_js_respuesta(args: Array) -> void:
	if args.is_empty():
		return
	var texto := str(args[0])
	var datos: Variant = JSON.parse_string(texto)
	if not (datos is Dictionary):
		return
	var id := int(datos.get("id", -1))
	if not _pendientes.has(id):
		return  # llegó tarde: ya se usó el respaldo
	_pendientes[id] = texto
	_respuesta.emit(id)


static func _parsear(texto: Variant, esperados: int) -> Array:
	if not (texto is String):
		return []
	var datos: Variant = JSON.parse_string(texto)
	if not (datos is Dictionary) or datos.has("error") or not (datos.get("probs") is Array):
		return []
	var probs: Array = datos["probs"]
	return probs if probs.size() == esperados else []
