/* Puente entre Godot (JavaScriptBridge) y Maia-2 corriendo en onnxruntime-web.
 *
 * API (window.MaiaBridge):
 *   init(modelUrl[, ortUrl]) -> Promise   carga onnxruntime-web (backend wasm, 1 hilo:
 *                                          no necesita COOP/COEP) y el modelo .onnx
 *   isReady() -> bool
 *   request(id, jsonString, callback)     jsonString = {board:[18*64 floats], elo_self,
 *                                          elo_oppo (categorias 0..10), legal:[indices]}
 *                                          callback(string JSON) = {id, probs:[...]} con
 *                                          softmax SOLO sobre `legal` (mismo orden), o {id, error}
 * Maia-2 (c) CSSLab, licencia MIT: https://github.com/CSSLab/maia2
 */
(function () {
	"use strict";
	var ORT_URL = "https://cdn.jsdelivr.net/npm/onnxruntime-web@1.20.1/dist/ort.min.js";
	var ORT_BASE = "https://cdn.jsdelivr.net/npm/onnxruntime-web@1.20.1/dist/";
	var session = null;
	var initPromise = null;
	var cola = Promise.resolve();

	function cargarScript(url) {
		return new Promise(function (ok, fallo) {
			var s = document.createElement("script");
			s.src = url;
			s.onload = ok;
			s.onerror = function () { fallo(new Error("no se pudo cargar " + url)); };
			document.head.appendChild(s);
		});
	}

	function init(modelUrl, ortUrl) {
		if (initPromise) { return initPromise; }
		initPromise = Promise.resolve()
			.then(function () { return window.ort ? null : cargarScript(ortUrl || ORT_URL); })
			.then(function () {
				window.ort.env.wasm.numThreads = 1;
				window.ort.env.wasm.proxy = false;
				if (!ortUrl) { window.ort.env.wasm.wasmPaths = ORT_BASE; }
				return window.ort.InferenceSession.create(modelUrl, {
					executionProviders: ["wasm"],
					graphOptimizationLevel: "all"
				});
			})
			.then(function (s) { session = s; return true; })
			.catch(function (e) {
				console.error("MaiaBridge.init:", e);
				initPromise = null; // permite reintentar
				throw e;
			});
		return initPromise;
	}

	function isReady() { return session !== null; }

	function ejecutar(id, texto) {
		var req = JSON.parse(texto);
		var ort = window.ort;
		var feeds = {
			board: new ort.Tensor("float32", Float32Array.from(req.board), [1, 18, 8, 8]),
			elo_self: new ort.Tensor("int64", BigInt64Array.from([BigInt(req.elo_self)]), [1]),
			elo_oppo: new ort.Tensor("int64", BigInt64Array.from([BigInt(req.elo_oppo)]), [1])
		};
		return session.run(feeds).then(function (out) {
			var logits = out.logits.data;
			var legal = req.legal;
			var maxv = -Infinity, i;
			for (i = 0; i < legal.length; i++) { maxv = Math.max(maxv, logits[legal[i]]); }
			var probs = new Array(legal.length), suma = 0;
			for (i = 0; i < legal.length; i++) { probs[i] = Math.exp(logits[legal[i]] - maxv); suma += probs[i]; }
			for (i = 0; i < legal.length; i++) { probs[i] /= suma; }
			return { id: id, probs: probs };
		});
	}

	function request(id, texto, callback) {
		// Serializa las peticiones: una sola sesion wasm de un hilo.
		cola = cola.then(function () {
			if (!session) { throw new Error("modelo no cargado"); }
			return ejecutar(id, texto);
		}).catch(function (e) {
			return { id: id, error: String(e && e.message || e) };
		}).then(function (res) {
			callback(JSON.stringify(res));
		});
	}

	window.MaiaBridge = { init: init, isReady: isReady, request: request };
})();
