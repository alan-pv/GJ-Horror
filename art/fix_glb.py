#!/usr/bin/env python3
"""Limpia un .glb exportado/editado a mano (solo biblioteca estándar de Python).

Uso:
    python3 art/fix_glb.py <entrada.glb> <salida.glb>
        [--remove-anims a,b,c] [--rename-anim viejo=nuevo ...] [--keep-suffixes]

Hace, en este orden:
  1. Borra las animaciones indicadas con --remove-anims (lista separada por comas).
  2. Renombra animaciones con --rename-anim (se aplica DESPUÉS de borrar, así se puede
     borrar `walk` y renombrar `walk.001` a `walk`). Admite varias veces la opción.
  3. Quita el sufijo `.NNN` de Blender de mallas y materiales (salvo --keep-suffixes).
  4. Elimina accessors y bufferViews que ya nadie usa y recompacta el buffer binario,
     para que el archivo no cargue datos muertos.
Ejemplo (player.glb con el set del árbitro colado):
    python3 art/fix_glb.py in.glb out.glb \\
        --remove-anims aim,aim_hold,idle,inspect_sheets,lower_gun,point_accuse,shoot,walk \\
        --rename-anim walk.001=walk
"""
import argparse
import json
import re
import struct
import sys

SUFFIX = re.compile(r"\.\d{3}$")


def leer(ruta):
    datos = open(ruta, "rb").read()
    magic, _ver, _total = struct.unpack("<4sII", datos[:12])
    if magic != b"glTF":
        sys.exit("no es un .glb")
    pos, doc, binario = 12, None, b""
    while pos < len(datos):
        largo, tipo = struct.unpack("<I4s", datos[pos:pos + 8])
        trozo = datos[pos + 8:pos + 8 + largo]
        if tipo == b"JSON":
            doc = json.loads(trozo)
        elif tipo == b"BIN\0":
            binario = trozo
        pos += 8 + largo
    return doc, binario


def escribir(ruta, doc, binario):
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    binario += b"\0" * (-len(binario) % 4)
    total = 12 + 8 + len(js) + 8 + len(binario)
    with open(ruta, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(js), b"JSON") + js)
        f.write(struct.pack("<I4s", len(binario), b"BIN\0") + binario)


def accessors_usados(doc):
    """Índices de accessors referenciados por mallas, skins y animaciones."""
    usados = set()
    for m in doc.get("meshes", []):
        for p in m["primitives"]:
            usados.update(p.get("attributes", {}).values())
            if "indices" in p:
                usados.add(p["indices"])
            for t in p.get("targets", []):
                usados.update(t.values())
    for s in doc.get("skins", []):
        if "inverseBindMatrices" in s:
            usados.add(s["inverseBindMatrices"])
    for a in doc.get("animations", []):
        for s in a["samplers"]:
            usados.update((s["input"], s["output"]))
    return usados


def compactar(doc, binario):
    """Quita accessors/bufferViews sin uso y reescribe el buffer sin huecos."""
    usados = sorted(accessors_usados(doc))
    mapa_acc = {v: i for i, v in enumerate(usados)}
    accs = [doc["accessors"][i] for i in usados]
    vistas_usadas = sorted({a["bufferView"] for a in accs if "bufferView" in a})
    mapa_vista = {v: i for i, v in enumerate(vistas_usadas)}
    nuevo, vistas = bytearray(), []
    for v in vistas_usadas:
        vw = dict(doc["bufferViews"][v])
        nuevo += b"\0" * (-len(nuevo) % 4)
        ini = vw.get("byteOffset", 0)
        trozo = binario[ini:ini + vw["byteLength"]]
        vw["byteOffset"] = len(nuevo)
        vw["buffer"] = 0
        nuevo += trozo
        vistas.append(vw)
    for a in accs:
        if "bufferView" in a:
            a["bufferView"] = mapa_vista[a["bufferView"]]
    doc["accessors"], doc["bufferViews"] = accs, vistas
    doc["buffers"] = [{"byteLength": len(nuevo)}]
    for m in doc.get("meshes", []):
        for p in m["primitives"]:
            p["attributes"] = {k: mapa_acc[v] for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = mapa_acc[p["indices"]]
            for t in p.get("targets", []):
                for k in t:
                    t[k] = mapa_acc[t[k]]
    for s in doc.get("skins", []):
        if "inverseBindMatrices" in s:
            s["inverseBindMatrices"] = mapa_acc[s["inverseBindMatrices"]]
    for a in doc.get("animations", []):
        for s in a["samplers"]:
            s["input"], s["output"] = mapa_acc[s["input"]], mapa_acc[s["output"]]
    return bytes(nuevo)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("entrada")
    ap.add_argument("salida")
    ap.add_argument("--remove-anims", default="")
    ap.add_argument("--rename-anim", action="append", default=[], metavar="VIEJO=NUEVO")
    ap.add_argument("--keep-suffixes", action="store_true")
    a = ap.parse_args()
    doc, binario = leer(a.entrada)
    quitar = {n for n in a.remove_anims.split(",") if n}
    anims = doc.get("animations", [])
    nombres = {x["name"] for x in anims}
    for n in quitar - nombres:
        print("aviso: no existe la animación", n)
    doc["animations"] = [x for x in anims if x["name"] not in quitar]
    for par in a.rename_anim:
        viejo, nuevo = par.split("=", 1)
        for x in doc["animations"]:
            if x["name"] == viejo:
                x["name"] = nuevo
    if not a.keep_suffixes:
        for clave in ("meshes", "materials"):
            for e in doc.get(clave, []):
                if "name" in e:
                    e["name"] = SUFFIX.sub("", e["name"])
    antes = len(binario)
    binario = compactar(doc, binario)
    escribir(a.salida, doc, binario)
    print("buffer %d -> %d bytes; animaciones: %s" % (
        antes, len(binario), ", ".join(x["name"] for x in doc["animations"])))


if __name__ == "__main__":
    main()
