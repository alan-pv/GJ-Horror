# Contrato de animaciones (código ↔ arte)

El código no pide clips por nombre: pide **roles** (`src/client/character/anim_roles.gd`, `AnimRoles`). Un clip del `.glb` cumple un rol si se llama `<rol>` o `<rol>__<variante>` (doble guion bajo). El mecanismo de variantes sigue en el código, pero **la filosofía es un solo clip por acción, sin variantes** (pocos clips, muy pulidos y lo más sencillos posible): `player.glb` trae 21 clips y ningún rol tiene variantes. Si el modelo no trae ninguna, se usa el respaldo; si tampoco hay, `play_role` avisa y no reproduce nada.

Los modelos y sus animaciones se **generan por script** (`art/characters/build_player.py`); no se editan a mano.

## API (`FigureBase`)

- `variants(rol)`, `has_role(rol)` (el respaldo no cuenta).
- `play_role(rol, rng = null, velocidad = 1.0)` devuelve el clip elegido.
- `play_role_once(rol, rng = null)` es una corrutina y solo admite roles no cíclicos.
- La mezcla (`blend`) y si el clip es cíclico salen de la tabla de roles, no de quien llama.

## Roles

| Rol | Cíclico | Respaldo | Mezcla (s) | Qué es |
| --- | --- | --- | --- | --- |
| `sit_wait` | sí | `sit_idle` | 0,8 | Esperar el turno rival (manos fuera del tablero). El `.glb` no trae clip propio: usa el respaldo `sit_idle` |
| `sit_think` | sí | `sit_think` | 0,6 | Pensar la propia jugada, inclinado al tablero |
| `sit_nervous` | sí | `sit_nervous` | 0,5 | Nervioso |
| `sit_startle` | no | ninguno | 0,15 | Respingo simétrico (1 s): tronco atrás y hombros arriba, sin girar; el lado lo pone la mirada aditiva. Vuelve al reposo sentado |
| `sit_cough` | no | ninguno | 0,4 | Tos |
| `sit_pick_up` | no | ninguno | 0,5 | Recoger algo del suelo |
| `stand_accuse` | no | ninguno | 0,6 | Levantarse, señalar y gritar; acaba de pie señalando |
| `stand_accuse_hold` | sí | ninguno | 0,3 | De pie señalando (empalma con `stand_accuse`) |
| `dragged` | sí | ninguno | 0,5 | Cuerpo flácido llevado por dos guardias |
| `stand_up` | no | ninguno | 0,5 | De sentado a de pie |
| `walk` | sí | ninguno | 0,4 | Caminar (jugador 1,1 m/s, paso doble 1,1 m; árbitro 0,744 m/s) |
| `sit_down` | no | ninguno | 0,5 | De pie a sentado |

**Clips directos** (sin rol, se piden por nombre): `sit_idle`, `sit_move_piece`, `sit_press_clock`, `sit_write`, `sit_cry`, `sit_frozen`, `stand_flee`, `stand_flee_cycle`, `death_slump_table`, `death_standing` (jugador); `idle`, `inspect_sheets`, `aim`, `aim_hold`, `shoot`, `lower_gun`, `point_accuse` (árbitro).

Clips finales de `player.glb` (21): `sit_idle`, `sit_think`, `sit_nervous`, `sit_frozen`, `sit_startle`, `sit_cough`, `sit_pick_up`, `sit_move_piece`, `sit_press_clock`, `sit_write`, `sit_cry`, `stand_flee`, `stand_flee_cycle`, `death_slump_table`, `death_standing`, `stand_up`, `sit_down`, `stand_accuse`, `stand_accuse_hold`, `dragged`, `walk`.

## Reglas

- Los clips cíclicos cierran sin salto (primer y último fotograma iguales). Las transiciones se piensan para mezclarse en 0,5-0,8 s.
- Los clips de una vez empiezan y acaban en el reposo sentado. Excepciones: `stand_accuse` acaba en la pose de `stand_accuse_hold`; `stand_up` y `sit_down` acaban de pie y sentado.
- **Manos fuera del tablero** en los roles sentados de espera, pensar y reacción: las puntas de los dedos quedan en y ≥ −0,47 m en espacio del personaje (marco del tablero con la silla a 0,72 m). Las manos pueden apoyarse en la mesa entre el canto y el tablero, descansar en el regazo o estar en la cara.
- Ningún clip atraviesa la mesa (losa z 0,685-0,715 delante de y = -0,27, tolerancia 3 mm), el tablero, el respaldo, el asiento (el cojín cede 3 cm), las patas ni el travesaño delantero de la silla, ni el propio cuerpo. `build_player.py` lo mide en cada regeneración con puntos intermedios de aristas (`check_table`, `check_hands`, `check_chair`).
- `sit_cough` solo se ve con el IK del brazo derecho apagado (la mano va a la boca).
- Los puños se cierran del todo con `curl` ≈ 80 (`Rig.fist_boost`, solo el jugador; el árbitro no cambia) y la palma acaba en nudillos redondeados. Los maniquíes no llevan nariz ni orejas en `player.glb` (`nose=False`, `ears=False`).

## Retirada de la silla en `stand_up`, `stand_accuse` y `sit_down`

La silla (origen en el del personaje; asiento ±0,22 m, cara superior z 0,45; patas delanteras y travesaño a y = −0,19; respaldo en y = 0,18) debe **retirarse hacia atrás (+Y) al menos** `d(t)` metros, con `t` en segundos desde el inicio del clip; entre filas se interpola linealmente. Mayor retirada siempre es segura. Valores medidos por `chair_curve` (retirada que cada fotograma necesita, envolvente creciente, +2 cm de margen y redondeo hacia arriba):

| `stand_up` / `stand_accuse` t (s) | 0 | 0,25 | 0,95 | 1,10 | 1,25 | 1,45 | 1,70 y después |
| --- | --- | --- | --- | --- | --- | --- | --- |
| d (m) | 0 | 0,06 | 0,06 | 0,11 | 0,17 | 0,23 | 0,25 |

`sit_down` es el inverso (la silla vuelve): d(t) = d_subida(1,70 − t).

| `sit_down` t (s) | 0 | 0,25 | 0,45 | 0,60 | 0,75 | 1,45 | 1,70 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| d (m) | 0,25 | 0,23 | 0,17 | 0,11 | 0,06 | 0,06 | 0 |

El clip se pensó así: se inclina con los pies recogidos (peso a los pies), la pelvis sube sobre ellos y al final se endereza; las manos suben del tablero, vuelven por encima del canto y bajan por fuera de las caderas. De pie las espinillas quedan en y ≈ −0,03, así que con la silla en 0,25 m ya no la tocan; el código puede retirarla 0,40 m (más holgura) sin problema. Los clips que se quedan sentados no necesitan retirada (d = 0). `stand_flee` también se levanta: su retirada necesaria llega a ~0,46 m al final (ver la salida de `build_player.py`).

## Cómo comprobarlo

```
blender --background --python art/characters/build_player.py     # regenera, exporta y verifica mesa, tablero y silla (CHAR_FAST=1 CHAR_ONLY=clip1,clip2 para iterar sin exportar)
godot --headless --path . --import
godot --headless --path . --script res://tools/check_characters.gd   # informe del contrato: variantes por rol, respaldos, avisos de nombres
godot --headless --path . --script res://tests/run_tests.gd -- --filter=character_figure
DISPLAY=:0 godot --path . --script res://tools/anim_preview.gd -- --role=sit_wait --out=/ruta [--clip=x] [--times=0,0.5] [--seat=0.72|0.80] [--views=side,front,top,under] [--focus=x,y,z --dist=0.3 --bare]
```

El informe del contrato avisa de nombres casi correctos: un solo guion bajo antes de la variante, rol desconocido, mayúsculas.
