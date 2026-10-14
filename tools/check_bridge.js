// Prueba web/maia_bridge.js en Node con onnxruntime-web (mismo runtime wasm que el navegador)
// contra el fixture de PyTorch.  Uso:  NODE_PATH=<dir con node_modules/onnxruntime-web> node tools/check_bridge.js
const fs = require("fs");
const path = require("path");
const raiz = path.resolve(__dirname, "..");
const ort = require("onnxruntime-web");
globalThis.window = globalThis;
globalThis.ort = ort;
require(path.join(raiz, "web/maia_bridge.js"));

const moves = JSON.parse(fs.readFileSync(path.join(raiz, "data/maia2/moves.json")));
const idx = Object.fromEntries(moves.map((m, i) => [m, i]));
const casos = JSON.parse(fs.readFileSync(path.join(raiz, "tests/fixtures/maia2_reference.json"))).casos;
const espejar = (u) => u[0] + (9 - +u[1]) + u[2] + (9 - +u[3]) + u.slice(4);
// En Node se pasa el modelo como bytes: se envuelve create() para leer del disco.
const create = ort.InferenceSession.create.bind(ort.InferenceSession);
ort.InferenceSession.create = (p, o) => create(fs.readFileSync(p), o);

(async () => {
	await MaiaBridge.init(path.join(raiz, "web/maia2_blitz.onnx"), "ya-cargado");
	let fallos = 0;
	for (const c of casos) {
		const negras = c.fen.split(" ")[1] === "b";
		const legal = c.legal_uci.map((u) => idx[negras ? espejar(u) : u]);
		const res = await new Promise((ok) => MaiaBridge.request(1, JSON.stringify(
			{ board: c.board, elo_self: c.cat_self, elo_oppo: c.cat_oppo, legal }), (s) => ok(JSON.parse(s))));
		if (res.error) { console.log("MAL", c.fen, res.error); fallos++; continue; }
		const pol = c.legal_uci.map((u, i) => [u, res.probs[i]]).sort((a, b) => b[1] - a[1]);
		const err = Math.max(...c.top5.map((t) => Math.abs(res.probs[c.legal_uci.indexOf(t.uci)] - t.p)));
		const ok = pol[0][0] === c.top5[0].uci && err < 2e-3 && Math.abs(res.probs.reduce((a, b) => a + b) - 1) < 1e-6;
		if (!ok) { fallos++; }
		console.log(ok ? "OK " : "MAL", c.fen.slice(0, 40).padEnd(40), pol[0][0], "err", err.toExponential(1));
	}
	const e = await new Promise((ok) => MaiaBridge.request(9, "{malo", (s) => ok(JSON.parse(s))));
	console.log("error controlado:", JSON.stringify(e));
	console.log("fallos:", fallos);
	process.exit(fallos ? 1 : 0);
})();
