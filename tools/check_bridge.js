// Prueba web/maia_bridge.js en Node con el onnxruntime-web INCLUIDO en web/ort/ (el mismo
// runtime wasm que usa el navegador) contra el fixture de PyTorch.
// Uso:  node tools/check_bridge.js          (no necesita node_modules)
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const raiz = path.resolve(__dirname, "..");
const dirOrt = path.join(raiz, "web/ort") + path.sep;

// ort.wasm.min.js es un script clasico que define `var ort`; se evalua como lo hace el navegador.
globalThis.window = globalThis;
vm.runInThisContext(fs.readFileSync(dirOrt + "ort.wasm.min.js", "utf8") + "\n;globalThis.ort = ort;", { filename: "ort.wasm.min.js", importModuleDynamically: vm.constants.USE_MAIN_CONTEXT_DEFAULT_LOADER });
globalThis.ort.env.wasm.wasmPaths = require("url").pathToFileURL(dirOrt).href;
globalThis.ort.env.wasm.numThreads = 1;
// En Node se pasa el modelo como bytes: se envuelve create() para leer del disco.
const create = ort.InferenceSession.create.bind(ort.InferenceSession);
ort.InferenceSession.create = (p, o) => create(fs.readFileSync(p), o);
require(path.join(raiz, "web/maia_bridge.js"));

const moves = JSON.parse(fs.readFileSync(path.join(raiz, "data/maia3/moves.json")));
const idx = Object.fromEntries(moves.map((m, i) => [m, i]));
const casos = JSON.parse(fs.readFileSync(path.join(raiz, "tests/fixtures/maia3_reference.json"))).casos;
const espejar = (u) => u[0] + (9 - +u[1]) + u[2] + (9 - +u[3]) + u.slice(4);
const pedir = (id, texto) => new Promise((ok) => MaiaBridge.request(id, texto, (s) => ok(JSON.parse(s))));

(async () => {
	await MaiaBridge.init(path.join(raiz, "web/maia3_5m.onnx"));
	console.log("listo:", MaiaBridge.isReady());
	let fallos = 0, n = 0;
	for (const c of casos) {
		// El turno de la ultima posicion decide el espejado de las jugadas.
		const negras = c.fens[c.fens.length - 1].split(" ")[1] === "b";
		const legal = c.legal_uci.map((u) => idx[negras ? espejar(u) : u]);
		for (const e of c.elos) {
			n++;
			if (legal.length === 0) {
				const r = await pedir(n, JSON.stringify({ tokens: c.tokens, elo_self: e.elo_self, elo_oppo: e.elo_oppo, legal }));
				const ok = !!r.error;
				if (!ok) { fallos++; }
				console.log(ok ? "OK " : "MAL", c.fens[c.fens.length - 1].slice(0, 40).padEnd(40), "sin jugadas legales ->", r.error);
				continue;
			}
			const res = await pedir(n, JSON.stringify({ tokens: c.tokens, elo_self: e.elo_self, elo_oppo: e.elo_oppo, legal }));
			if (res.error) { console.log("MAL", c.jugadas, res.error); fallos++; continue; }
			const pol = c.legal_uci.map((u, i) => [u, res.probs[i]]).sort((a, b) => b[1] - a[1]);
			const err = Math.max(...e.top5.map((t) => Math.abs(res.probs[c.legal_uci.indexOf(t.uci)] - t.p)));
			// El orden solo se exige si el top-1 no es un empate dentro del error permitido.
			const dudoso = e.top5.length > 1 && e.top5[0].p - e.top5[1].p < 4e-3;
			const ok = (pol[0][0] === e.top5[0].uci || dudoso) && err < 2e-3 && Math.abs(res.probs.reduce((a, b) => a + b) - 1) < 1e-6;
			if (!ok) { fallos++; }
			console.log(ok ? "OK " : "MAL", c.fens[c.fens.length - 1].slice(0, 40).padEnd(40),
				`${e.elo_self}/${e.elo_oppo}`.padEnd(10), pol[0][0].padEnd(6), "err", err.toExponential(1));
		}
	}
	const malo = await pedir(9000, "{malo");
	console.log("error controlado:", JSON.stringify(malo));
	if (!malo.error || malo.id !== 9000) { fallos++; }
	const corto = await pedir(9001, JSON.stringify({ tokens: [0, 1], elo_self: 1500, elo_oppo: 1500, legal: [1] }));
	console.log("tokens invalidos:", JSON.stringify(corto));
	if (!corto.error) { fallos++; }
	console.log("fallos:", fallos);
	process.exit(fallos ? 1 : 0);
})();
