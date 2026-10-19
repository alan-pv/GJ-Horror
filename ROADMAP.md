# ROADMAP

Solo lo **pendiente**. Lo implementado se describe en [`docs/arquitectura.md`](docs/arquitectura.md) y se borra de aquí en el mismo commit que lo termina (ver `CLAUDE.md`). Cada hito se divide en frentes que implementan subagentes en paralelo.

## Ronda de pulido 1 (2026-10-19)

### Oleada 2 — integración (depende de la oleada 1)

- **R6. Personajes y manos realistas**
  - [ ] Personajes low-poly en lugar de primitivas (rival, jugador y mesas de fondo).
  - [ ] Brazo con IK sobre el esqueleto nuevo; el codo nunca atraviesa la mesa.
  - [ ] Secuencia física de cada jugada: mover, pulsar el reloj y anotar en la planilla.
  - [ ] Lanzar `BeginnerHelper.precompute_async` también al empezar la partida y cuando el tablero cambie en el turno del humano (hoy solo tras la jugada del bot).
  - [ ] Subir `config.arbiter_delay` a ~6-7 s para que el árbitro llegue y revise las planillas.
  - [ ] Bloquear la entrada del jugador durante su ejecución en primera persona.
  - [ ] Encender `MatchConfig.require_clock_press` (el servidor ya lo soporta) e impedir `press_clock` con la mano ocupada en una trampa.

## Pendiente de la etapa anterior

- [ ] Las partidas de fondo empiezan desde la posición inicial; podrían arrancar de un medio juego (`Hall.mid_game_fen`) para que los tableros se vean avanzados.
- [ ] Pasillo entre filas de ~1,16 m entre sillas (`HallLayout.SPACING_Z` = 3,2): subirlo si el árbitro pasa justo.

- [ ] `BotController.opponent_elo` nunca se asigna (Maia siempre ve un rival de 1200).
- [ ] El humano no tiene tecla para sus eventos de distracción (toser, tirar una pieza).

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
