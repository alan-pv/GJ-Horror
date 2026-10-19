# Arte (Blender)

`art/` guarda los `.blend` (editables a mano) y los scripts que los generan. Los `.glb` que usa Godot
están en `assets/models/`, reflejando la ruta (`art/props/x.blend` -> `assets/models/props/x.glb`).
`art/.gdignore` evita que Godot intente importar los `.blend`.

## Flujo

1. **Generar** (solo la primera vez o si quieres rehacer todo desde cero):
   `blender --background --python art/props/build_props.py` (todo) o `... -- table chair pieces` (solo esos).
   Guarda `art/props/*.blend` y exporta `assets/models/props/*.glb`.
2. **Editar a mano**: abre el `.blend`, cámbialo y **solo reexporta**. **No regeneres**: el script
   sobrescribe el `.blend` y perderías tus cambios.
3. **Reexportar**: `tools/export_models.sh` (todos los `.blend` bajo `art/`; acepta un filtro de ruta,
   p. ej. `tools/export_models.sh chess_clock`). Uno solo:
   `blender --background art/props/x.blend --python art/export_glb.py -- assets/models/props/x.glb`.
   Se excluyen cámaras, luces y todo lo que esté en una colección llamada `Reference`.
4. **Importar en Godot** (una vez tras exportar): `godot --headless --path . --editor --quit-after 60`.
5. **Comprobar**: `godot --headless --path . --script res://tools/check_props.gd` (nodos y medidas).

## Convenciones

- Metros. Blender Z arriba; al exportar a glTF el eje Y de Blender pasa a **-Z de Godot** (Blender +Y = Godot -Z,
  Blender -Y = Godot +Z, X igual).
- Low-poly, sombreado plano, sin texturas: materiales de color con nombre (`Wood_Dark`, `Brass`, ...).
- Un `.glb` por prop. Los props con partes móviles tienen un Empty raíz y objetos hijos con nombre fijo.
- "Frente" de la ambientación = +Z de Godot (-Y de Blender), con la espalda en el plano y=0.
- Mesa del juego (coordenadas de mesa en Godot): superficie a 0.72 m, mesa 1.3 (X) x 0.9 (Z), sillas en z=±0.80.
- Origen y orientación de cada modelo: ver la tabla.

## Modelos (`art/props/`, scripts: `furniture.py`, `items.py`, `pieces.py`, `ambient.py`, `lib.py`)

| Modelo | Origen | Notas de orientación / nodos |
|---|---|---|
| `table` | suelo, bajo el centro | 1.34 x 0.72 x 0.94 (canto saliente); superficie en y=0.72, 1.3 en X, 0.9 en Z. |
| `chair` | suelo, bajo el centro del asiento | Asiento a 0.45 m, 0.44 x 0.44. Respaldo hacia **-Z de Godot** y el jugador mira a **+Z**: úsala sin girar en z=-0.80; en z=+0.80 gírala 180 grados sobre Y. |
| `board` | centro de la superficie de juego (y=0) | Nodos `Board` (raíz), `BoardSquares` (materiales `Light`/`Dark`), `BoardFrame` (`Board_Frame`). Casillas de 0.055, juego de 0.44, con marco 0.50. El marco baja hasta y=-0.015: colócalo en y = 0.72 + 0.015. a1 (oscura) en la esquina (-X, +Z); columnas a..h hacia +X, filas 1..8 hacia -Z (blancas en +Z). |
| `chess_clock` | suelo del reloj, centro de la base | Caja 0.15 (X) x 0.18 (Z) x 0.085. Cara A hacia **+Z**, cara B hacia **-Z**; cada cara tiene **dos esferas** (izquierda/derecha según la ve el jugador de ese lado). Nodos: `ChessClock` (raíz), `ClockBody`, `Button_A`/`Button_B` (origen en la base del botón sobre la tapa; se hunden en -Y local de Godot), Empties `Face_A`/`Face_B` (en el centro de la cara, entre las esferas; **+Z local = normal hacia fuera**, +Y arriba: un `Label3D` hijo mira al jugador sin girar), agujas `Hand_A_Left`, `Hand_A_Right`, `Hand_B_Left`, `Hand_B_Right` (pivote en el centro de la esfera, apuntan a las 12; se giran sobre su **Z local**; el eje local de cada cara mira hacia fuera, así que **sentido horario visto por el jugador = rotation.z negativa** en las cuatro). |
| `scoresheet` | centro de la cara inferior de la tablilla | Tumbada, papel hacia +Y de Godot. 0.16 x 0.23. Nodos `Clipboard`, `Sheet`, `SheetLines` (renglones y columnas, material `Ink_Line`), `Clip` (pinza en el borde superior de la hoja = **-Z de Godot**; el jugador de +Z la ve al fondo). |
| `pen` | la punta | Se extiende 0.14 m hacia **+X**; el clip hacia +Y. |
| `pistol` | centro de la empuñadura | Revólver ~0.21 m. Cañón hacia **-Z de Godot** (adelante), empuñadura hacia abajo. Nodos `Pistol` (raíz), `PistolBody`, Empty `Muzzle` (punta del cañón, -Z local = dirección de disparo). |
| `lamp` | punto de anclaje en el techo | Cuelga hacia -Y: cable 0.93 m, pantalla cónica de 0.6 m de diámetro y bombilla; largo total 1.2 m. Nodos `Lamp` (raíz), `LampCable`, `LampShade`, `LampBulb` (material `Bulb` emisivo), Empty `LightAnchor` (centro del foco, 1.07 m bajo el origen): ahí va el `SpotLight3D`. Para que la pantalla quede a ~1.8 m sobre el suelo, ancla a y ~3.0. |
| `pieces/pawn,rook,knight,bishop,queen,king` | centro de la base (suelo) | Un `.glb` por pieza, malla `Pawn`... con el material único `Piece` (recolorear en Godot). Base de 0.04 de diámetro; alturas 0.045 / 0.05 / 0.055 / 0.06 / 0.075 / 0.095. El caballo mira hacia **-Z de Godot** (las blancas en +Z miran hacia las negras; las negras se giran 180 grados). |
| `pillar` | suelo, centro | Columna de 8 caras, 3.0 m de alto. |
| `door` | suelo, centro del vano | Puerta doble en un marco (vano 1.7 x 2.4). `DoorFrame`, `DoorLeaf_L`, `DoorLeaf_R` (origen en la bisagra exterior; giran sobre Y). Frente hacia +Z. |
| `wall_panel` | suelo, centro | Zócalo de madera 1.0 x 1.2; espalda en el plano z=0, sobresale hacia +Z. |
| `banner` | centro de la barra superior | Estandarte 0.8 x 1.6 que cuelga hacia -Y; frente hacia +Z. |

Triángulos: ver la salida de `build_props.py` (`[export_glb] ... N triangulos`).
