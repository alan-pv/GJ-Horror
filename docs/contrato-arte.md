# Contrato de animaciones (código ↔ arte)

El código no pide clips por nombre: pide **roles** (`src/client/character/anim_roles.gd`, `AnimRoles`). Un clip del `.glb` cumple un rol si se llama `<rol>` o `<rol>__<variante>` (doble guion bajo), p. ej. `sit_wait__crossed`. Si hay varias variantes de un rol, se elige una al azar sin repetir la última. Añadir una variante es exportar un clip con el nombre correcto, sin tocar código. Si el modelo no trae ninguna, se usa el respaldo; si tampoco hay, `play_role` avisa y no reproduce nada.

Los modelos y sus animaciones se **generan por script** (`art/characters/build_player.py`); no se editan a mano.

## API (`FigureBase`)

- `variants(rol)`, `has_role(rol)` (el respaldo no cuenta).
- `play_role(rol, rng = null, velocidad = 1.0)` devuelve el clip elegido.
- `play_role_once(rol, rng = null)` es una corrutina y solo admite roles no cíclicos.
- La mezcla (`blend`) y si el clip es cíclico salen de la tabla de roles, no de quien llama.

## Roles

| Rol | Cíclico | Respaldo | Mezcla (s) | Qué es |
| --- | --- | --- | --- | --- |
| `sit_wait` | sí | `sit_idle` | 0,8 | Esperar el turno rival (manos fuera del tablero) |
| `sit_think` | sí | `sit_think` | 0,6 | Pensar la propia jugada, inclinado al tablero |
| `sit_nervous` | sí | `sit_nervous` | 0,5 | Nervioso |
| `sit_startle` | no | ninguno | 0,15 | Respingo breve (~1 s); vuelve al reposo sentado |
| `sit_cough` | no | ninguno | 0,4 | Tos |
| `sit_pick_up` | no | ninguno | 0,5 | Recoger algo del suelo |
| `stand_accuse` | no | ninguno | 0,6 | Levantarse, señalar y gritar; acaba de pie señalando |
| `stand_accuse_hold` | sí | ninguno | 0,3 | De pie señalando (empalma con `stand_accuse`) |
| `dragged` | sí | ninguno | 0,5 | Cuerpo flácido llevado por dos guardias |
| `stand_up` | no | ninguno | 0,5 | De sentado a de pie |
| `walk` | sí | ninguno | 0,4 | Caminar (jugador 1,1 m/s, paso doble 1,1 m; árbitro 0,744 m/s) |
| `sit_down` | no | ninguno | 0,5 | De pie a sentado |

**Clips directos** (sin rol, se piden por nombre): `sit_idle`, `sit_look_left/right`, `sit_move_piece`, `sit_press_clock`, `sit_write`, `sit_beg`, `sit_cry`, `sit_frozen`, `stand_flee`, `stand_flee_cycle`, `death_slump_table`, `death_fall_back`, `death_standing` (jugador); `idle`, `inspect_sheets`, `aim`, `aim_hold`, `shoot`, `lower_gun`, `point_accuse` (árbitro).

## Reglas

- Los clips cíclicos cierran sin salto (primer y último fotograma iguales). Las transiciones se piensan para mezclarse en 0,5-0,8 s.
- Los clips de una vez empiezan y acaban en el reposo sentado. Excepciones: `stand_accuse` acaba en la pose de `stand_accuse_hold`; `stand_up` y `sit_down` acaban de pie y sentado.
- **Manos fuera del tablero** en los roles sentados de espera, pensar y reacción: las puntas de los dedos quedan en y ≥ −0,47 m en espacio del personaje (marco del tablero con la silla a 0,72 m). Las manos pueden apoyarse en la mesa entre el canto y el tablero, descansar en el regazo o estar en la cara.
- Ningún clip atraviesa el canto de la mesa ni el respaldo de la silla.
- `stand_up`, `stand_accuse` y `sit_down` suponen que el código retira la silla al menos 0,40 m hacia atrás mientras sube la pelvis.
- Las poses con la mano en la cara (`__chin`, `__head`, `__temple`, `sit_cough`) solo se ven si el IK de ese brazo está apagado.

## Cómo comprobarlo

```
blender --background --python art/characters/build_player.py     # regenera, exporta y verifica mesa, tablero y respaldo
godot --headless --path . --import
godot --headless --path . --script res://tools/check_characters.gd   # informe del contrato: variantes por rol, respaldos, avisos de nombres
godot --headless --path . --script res://tests/run_tests.gd -- --filter=character_figure
DISPLAY=:0 godot --path . --script res://tools/anim_preview.gd -- --role=sit_wait --out=/ruta [--clip=x] [--times=0,0.5] [--seat=0.72|0.80] [--views=side,front,top]
```

El informe del contrato avisa de nombres casi correctos: un solo guion bajo antes de la variante, rol desconocido, mayúsculas.
