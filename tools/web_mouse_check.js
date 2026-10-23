// Prueba de ratón en la build web (Chromium con ventana, bajo Xvfb).
//
// Qué comprueba: que tras un clic dentro del iframe de itch.io (SIN pantalla completa) el navegador
// concede el bloqueo de puntero, que llegan movementX/Y y que la cámara gira en proporción.
//
// Cómo correrla (desde la raíz del repo, con la build ya exportada con tools/build_web.sh):
//   python3 -m http.server -d build/web 8765 &
//   xvfb-run -a -s "-screen 0 1280x800x24" node tools/web_mouse_check.js [opciones]
// Opciones:
//   --mode=iframe|direct|fullscreen   iframe 1100x650 tipo itch (por defecto), página directa, o
//                                     iframe llevado a pantalla completa con requestFullscreen()
//   --url=http://localhost:8765       servidor de build/web
//   --out=/ruta                       carpeta de capturas (por defecto ./build/mouse_check)
//   --dx=300 --steps=30               desplazamiento total (px) y número de eventos
//   --deny                            simula un navegador que deniega SIEMPRE el bloqueo (pointerlockerror):
//                                     debe activarse el modo libre y la cámara seguir girando
//   --esc                             tras la prueba, suelta el bloqueo (como Esc) y comprueba que un clic
//                                     inmediato lo recupera o, si Chrome lo deniega (~1 s), el siguiente
// Necesita Playwright global (`npm i -g playwright`) y Chromium (PLAYWRIGHT_BROWSERS_PATH).
// Debe ser con ventana (headless:false): el bloqueo de puntero en headless no es fiable.
// Sale con código 0 si el bloqueo se concede y la cámara gira; 1 en caso contrario.
const fs = require('fs');
const path = require('path');
const { chromium } = require(require('child_process').execSync('npm root -g').toString().trim() + '/playwright');

const args = Object.fromEntries(process.argv.slice(2).map(a => {
	const m = a.match(/^--([^=]+)(?:=(.*))?$/);
	return [m[1], m[2] === undefined ? true : m[2]];
}));
const MODE = args.mode || 'iframe';
const URL = args.url || 'http://localhost:8765';
const OUT = args.out || path.join(process.cwd(), 'build', 'mouse_check');
const DX = Number(args.dx || 300), STEPS = Number(args.steps || 30);
fs.mkdirSync(OUT, { recursive: true });

const sleep = ms => new Promise(r => setTimeout(r, ms));

// Host mínimo tipo itch.io: iframe 1100x650 con los permisos que da itch.
const HOST = `<!doctype html><html><body style="margin:0;background:#333">
<iframe id="g" src="index.html" width="1100" height="650" frameborder="0" allowfullscreen
 allow="autoplay; fullscreen *; geolocation; microphone; camera; midi; monetization; xr-spatial-tracking; gamepad; gyroscope; accelerometer; xr; cross-origin-isolated; web-share"
 style="margin:20px"></iframe></body></html>`;

// Registra eventos de bloqueo en cada marco (antes de que cargue el juego).
const SPY = () => {
	window.__spy = { changes: [], errors: [], moves: 0, movesLocked: 0, sumX: 0, sumY: 0 };
	document.addEventListener('pointerlockchange', () =>
		window.__spy.changes.push(!!document.pointerLockElement), true);
	document.addEventListener('pointerlockerror', () => window.__spy.errors.push(performance.now() | 0), true);
	document.addEventListener('mousemove', e => {
		window.__spy.moves++;
		if (document.pointerLockElement) { window.__spy.movesLocked++; }
		window.__spy.sumX += e.movementX; window.__spy.sumY += e.movementY;
	}, true);
};

(async () => {
	const browser = await chromium.launch({
		headless: false,
		args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
			'--window-size=1280,800', '--no-sandbox'],
	});
	const ctx = await browser.newContext({ viewport: { width: 1280, height: 760 } });
	await ctx.addInitScript(SPY);
	if (args.deny) {
		await ctx.addInitScript(() => {
			Element.prototype.requestPointerLock = function () {
				setTimeout(() => document.dispatchEvent(new Event('pointerlockerror')), 5);
				return Promise.reject(new DOMException('denegado (prueba)', 'NotAllowedError'));
			};
		});
	}
	const page = await ctx.newPage();
	page.on('console', m => { if (/error|warn/i.test(m.type())) console.log('[consola]', m.text().slice(0, 200)); });
	if (MODE === 'direct') {
		await page.goto(URL + '/index.html');
	} else {
		await page.route('**/__host.html', r => r.fulfill({ contentType: 'text/html', body: HOST }));
		// El host debe ser del mismo origen que el juego (itch sirve ambos desde su CDN).
		await page.goto(URL + '/__host.html');
	}
	await page.waitForSelector(MODE === 'direct' ? 'canvas' : '#g', { timeout: 60000 });
	const frame = MODE === 'direct' ? page.mainFrame() : page.frames().find(f => f !== page.mainFrame());
	await frame.waitForSelector('canvas', { timeout: 60000 });
	const canvasBox = async () => {
		const box = await frame.evaluate(() => {
			const r = document.querySelector('canvas').getBoundingClientRect();
			return { x: r.x, y: r.y, w: r.width, h: r.height };
		});
		if (MODE === 'direct') return box;
		const f = await page.locator('#g').boundingBox();
		return { x: f.x + box.x, y: f.y + box.y, w: box.w, h: box.h };
	};
	const state = () => frame.evaluate(() => ({
		lock: !!document.pointerLockElement,
		fs: !!document.fullscreenElement,
		look: window.__look ? { mode: window.__look.mode, unadj: window.__look.unadj, yaw: window.__look.yaw,
			pitch: window.__look.pitch, err: window.__look.err, events: window.__look.events } : null,
		spy: window.__spy,
	}));

	console.log('Esperando al menú...');
	await sleep(25000);
	let b = await canvasBox();
	await page.screenshot({ path: path.join(OUT, `${MODE}-1-menu.png`) });
	// Play: centro horizontal, 357/720 de alto.
	await page.mouse.click(b.x + b.w / 2, b.y + b.h * 357 / 720);
	console.log('Play pulsado; saltando el discurso...');
	for (let i = 0; i < 40; i++) { await page.keyboard.press('Space'); await sleep(500); }
	await page.screenshot({ path: path.join(OUT, `${MODE}-2-partida.png`) });

	if (MODE === 'fullscreen') {
		await page.mouse.click(5, 5);   // activación del usuario en el marco superior
		await page.evaluate(() => document.querySelector('#g').requestFullscreen()).catch(e => console.log('fullscreen:', e.message));
		await sleep(1500);
		b = await canvasBox();
	}
	const s0 = await state();
	console.log('Antes del clic:', JSON.stringify(s0));

	// Clic de captura (gesto real del usuario) en el centro del lienzo.
	const cx = b.x + b.w / 2, cy = b.y + b.h / 2;
	await page.mouse.move(cx, cy);
	await page.mouse.down(); await page.mouse.up();
	await sleep(1500);
	const s1 = await state();
	console.log('Tras el clic:  ', JSON.stringify(s1));

	// Movimiento: STEPS eventos que suman DX píxeles hacia la derecha.
	const per = DX / STEPS;
	for (let i = 1; i <= STEPS; i++) { await page.mouse.move(cx + per * i, cy); await sleep(16); }
	await sleep(600);
	const s2 = await state();
	console.log('Tras mover:    ', JSON.stringify(s2));
	await page.keyboard.press('F3');   // panel de diagnóstico
	await sleep(800);
	await page.screenshot({ path: path.join(OUT, `${MODE}-3-tras-mover-F3.png`) });

	if (args.esc) {
		await frame.evaluate(() => document.exitPointerLock());
		await sleep(300);
		await page.mouse.down(); await page.mouse.up();   // clic inmediato (<1 s tras salir)
		await sleep(800);
		const e1 = await state();
		await sleep(1500);
		await page.mouse.down(); await page.mouse.up();   // segundo clic, ya pasado el segundo
		await sleep(800);
		const e2 = await state();
		console.log(`Esc: bloqueo tras clic inmediato=${e1.lock} (modo ${e1.look && e1.look.mode}); tras segundo clic=${e2.lock} (modo ${e2.look && e2.look.mode})`);
	}
	const yaw0 = s1.look ? s1.look.yaw : null, yaw1 = s2.look ? s2.look.yaw : null;
	const dyaw = yaw0 !== null ? (yaw1 - yaw0) : null;
	const lockOk = args.deny ? (s2.look && s2.look.mode === 'free') : s1.lock;
	const turned = dyaw !== null ? Math.abs(dyaw) > 0.05 : s2.spy.movesLocked > 0;
	console.log(`\nRESULTADO ${MODE}: bloqueo=${lockOk} eventos_con_bloqueo=${s2.spy.movesLocked} `
		+ `suma_movementX=${s2.spy.sumX} errores_bloqueo=${s2.spy.errors.length} `
		+ `yaw_antes=${yaw0} yaw_despues=${yaw1} giro_rad=${dyaw} (esperado ~${(DX * 0.0022).toFixed(3)} rad con sens 1.0)`);
	await browser.close();
	process.exit(lockOk && turned ? 0 : 1);
})().catch(e => { console.error(e); process.exit(2); });
