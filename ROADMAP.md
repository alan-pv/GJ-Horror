# ROADMAP

Solo lo **pendiente**. Lo implementado se describe en [`docs/arquitectura.md`](docs/arquitectura.md) y se borra de aquí en el mismo commit que lo termina (ver `CLAUDE.md`). Cada hito se divide en frentes que implementan subagentes en paralelo.

## Ronda de pulido 1 (2026-10-19)

### Oleada 1 — bases independientes

- **R2. Rendimiento del turno** (`src/bots/`, `beginner_helper.gd`, `chess_rules.gd`, `board_state.gd`)
  - [ ] Eliminar el tirón al terminar de elegir la jugada (medir: ayuda para principiantes, cerebro del bot, historial de Maia).
- **R3. Arte low-poly en Blender** (`art/`, `assets/models/`)
  - [ ] Personaje sentado con esqueleto apto para IK y animaciones: reposo, pensar, escribir, pulsar el reloj, mover pieza, suplicar, llorar, levantarse e intentar huir, muerte por disparo.
  - [ ] Árbitro con pistola: caminar, revisar planillas, apuntar y disparar.
  - [ ] Utilería: mesa, silla, reloj de dos caras, planilla y pluma, pistola, lámpara, piezas.
  - [ ] Scripts de Blender sin interfaz que generan los `.blend` editables y exportan `.glb`.
- **R4. Menús, HUD y reloj** (`autoloads/`, `src/ui/`, `hud.gd`, `clock_view.gd`)
  - [ ] Menú inicial, configuración y pausa reutilizados de tic-tac-toe, en inglés.
  - [ ] Se ven los dos tiempos (el propio y el del rival) en el reloj 3D y en el HUD.
  - [ ] Tic-tac del reloj.
  - [ ] HUD sin lista de nombres: solo número de ronda y rondas restantes.
- **R5. Sonidos** (`assets/audio/sfx/`, `tools/`)
  - [ ] Tic-tac, pasos del árbitro, disparo, cuerpo que cae, silla que se arrastra, sollozos y súplicas.

### Oleada 2 — integración (depende de la oleada 1)

- **R6. Personajes y manos realistas**
  - [ ] Personajes low-poly en lugar de primitivas (rival, jugador y mesas de fondo).
  - [ ] Brazo con IK sobre el esqueleto nuevo; el codo nunca atraviesa la mesa.
  - [ ] Secuencia física de cada jugada: mover, pulsar el reloj y anotar en la planilla.
  - [ ] Encender `MatchConfig.require_clock_press` (el servidor ya lo soporta) e impedir `press_clock` con la mano ocupada en una trampa.
- **R7. Salón en cuadrícula y mesas vivas**
  - [ ] Salón con 16 mesas en cuadrícula 4x4 que rodean al jugador.
  - [ ] Jugadores de fondo animados (piensan, mueven, pulsan el reloj, anotan, miran alrededor), aunque sus partidas no se vean.
  - [ ] Entre rondas se conservan las mesas, vacías las de los eliminados.
- **R8. Árbitro verdugo y eliminaciones**
  - [ ] Árbitro que patrulla el salón todo el tiempo, con pasos espaciales que se oyen acercarse y alejarse.
  - [ ] Al perder, el árbitro va a la mesa y dispara a la cabeza; el cuerpo queda en la mesa hasta el fin de la ronda.
  - [ ] Mesas visibles frente al jugador con eliminaciones variadas (suplicar, llorar, intentar huir, quedarse inmóvil).
  - [ ] Eliminación del propio jugador en primera persona.
  - [ ] Revisión de las dos planillas al acusar.

## Pendiente de la etapa anterior

- [ ] `BotController.opponent_elo` nunca se asigna (Maia siempre ve un rival de 1200).
- [ ] `tests/run_tests.gd` lista `test_beginner_helper.gd`, que no existe.
- [ ] El humano no tiene tecla para sus eventos de distracción (toser, tirar una pieza).
- [ ] Al eliminar a alguien de una mesa de fondo, su lámpara no se apaga hasta el fin de la ronda.

- [ ] **Repo público el día que se publique el juego** en itch.io (AGPL de Maia-3).
- [ ] Exportación web real (plantillas de Godot) y prueba de Maia-3 en navegador.
- [ ] Rendimiento: IK lejano con menos frecuencia, medir 16 mesas visibles en una máquina modesta.
- [ ] Audio ambiente (relojes, piezas, murmullos que disminuyen al vaciarse el salón).
- [ ] Tutorial corto (mover, mirar, hacer trampa, acusar).
- [ ] Ajuste de balance con bots: ¿más tiempo para blancas (Armageddon)?, cono de visión, duraciones de trampas.

## Lanzamiento — Multijugador

- [ ] Servidor headless de Godot con la API de alto nivel (`@rpc`, `MultiplayerSynchronizer` para mirada y manos).
- [ ] Información oculta: enviar la animación de una trampa solo a quien puede verla.
- [ ] Lista completa de trampas y eventos; modo espectador o cola al ser eliminado.
- [ ] Emparejamiento por rating; ayuda solo en tutorial y liga de principiantes.

## Decisiones abiertas (configurables en `MatchConfig`)

| Decisión | Valor actual |
| --- | --- |
| ¿El reloj se pausa mientras llega el árbitro? | Sí |
| ¿Una acusación correcta borra una advertencia? | No |
| Ventana de acusación | Desde la última jugada del acusador (las planillas son visuales) |
| Ritmo | 3 min + 2 s por jugada |
| ¿Más tiempo para blancas? | No |
| Jugadores por torneo | 32 en cuadrícula 4x4 (configurable con `--players`) |
| Título del juego | Pendiente |
| Motor de los bots | Maia-3 5M (AGPL); Maia-2 (MIT) queda en el historial como plan B |
