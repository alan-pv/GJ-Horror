/* Puente entre Godot (JavaScriptBridge) y Maia-3 5M corriendo en onnxruntime-web.
 * Todo es local: onnxruntime-web 1.20.1 va incluido en ort/ (sin CDN) y el juego
 * funciona sin conexion una vez cargado.
 *
 * API (window.MaiaBridge):
 *   init(modelUrl[, ortBase]) -> Promise  carga ort/ort.wasm.min.js (ruta relativa a la pagina,
 *                                          o usa window.ort si ya existe) y el modelo .onnx.
 *                                          Backend wasm de 1 hilo: no necesita COOP/COEP.
 *   isReady() -> bool
 *   request(id, jsonString, callback)     jsonString = {tokens:[64*96 floats], elo_self, elo_oppo
 *                                          (Elo continuo), legal:[indices del vocabulario]}
 *                                          callback(string JSON) = {id, probs:[...]} con softmax
 *                                          SOLO sobre `legal` (mismo orden), o {id, error}
 * Maia-3 (c) CSSLab, licencia AGPL-3.0: https://github.com/CSSLab/maia3
 * onnxruntime-web (c) Microsoft, licencia MIT (ver ort/LICENSE-onnxruntime.txt).
 */
(function () {
	"use strict";
	var ORT_DIR = "ort/";
	var ORT_SCRIPT = "ort.wasm.min.js";
	var TOKENS = 64 * 96;
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

	function init(modelUrl, ortBase) {
		if (initPromise) { return initPromise; }
		initPromise = Promise.resolve()
			.then(function () {
				if (window.ort) { return null; } // ya cargado (pruebas en Node)
				// URL absoluta: el import() del .mjs de wasm no debe depender de la ruta del script.
				var base = ortBase || new URL(ORT_DIR, document.baseURI).href;
				return cargarScript(base + ORT_SCRIPT).then(function () {
					window.ort.env.wasm.wasmPaths = base;
				});
			})
			.then(function () {
				window.ort.env.wasm.numThreads = 1;
				window.ort.env.wasm.proxy = false;
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
		if (!req.tokens || req.tokens.length !== TOKENS) { throw new Error("tokens invalidos"); }
		if (!req.legal || req.legal.length === 0) { throw new Error("sin jugadas legales"); }
		var feeds = {
			tokens: new ort.Tensor("float32", Float32Array.from(req.tokens), [1, 64, 96]),
			elo_self: new ort.Tensor("float32", Float32Array.of(req.elo_self), [1]),
			elo_oppo: new ort.Tensor("float32", Float32Array.of(req.elo_oppo), [1])
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
