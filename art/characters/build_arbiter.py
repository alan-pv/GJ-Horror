"""Genera art/characters/arbiter.blend y assets/models/characters/arbiter.glb (Blender 5.x).

    blender --background --python art/characters/build_arbiter.py

Arbitro/verdugo: alto y delgado, traje oscuro, camisa blanca, guantes, mascara palida sin rasgos.
Pistola: objeto "Pistol" hijo del hueso Hand.R, con el Empty "Muzzle" en la boca del canon.
Decision: la pistola va SIEMPRE en la mano derecha, colgando a un lado con el canon hacia delante
y abajo (idle, walk, etc.). Si se quiere "enfundada", ocultar el nodo Pistol en Godot.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
from mathutils import Matrix
import chartools as C
from chartools import V, board_pt, TABLE_TOP
from body import build_body

KX, KZ = 0.9, 1.13
SH = C.Shape(KX, KZ)
CFG = dict(
    colors={
        "Skin": ((.55, .4, .32), .9), "Shirt": ((.8, .8, .77), .9), "Jacket": ((.035, .035, .045), .9),
        "Pants": ((.04, .04, .05), .9), "Shoes": ((.015, .015, .015), .6), "Hair": ((.02, .02, .02), .8),
        "Gloves": ((.025, .025, .028), .7), "Mask": ((.74, .72, .66), .6), "Tie": ((.16, .015, .02), .9),
        "Eyes": ((.01, .01, .01), .5), "Metal": ((.07, .07, .08), .4), "Grip": ((.03, .02, .015), .8),
    },
    hem=.76, hemw=.17, mask=True, gloves=True, tie=True, nose=False, eyes=False, leg_r=.86, n=12,
)

C.reset_scene()
col_char = C.new_collection("Character")
col_ref = C.new_collection("Reference")
arm = C.build_armature(SH, arm_len=(0.33, 0.3, 0.09, 0.08))
C.link_only(arm, col_char)
meshes = build_body(arm, SH, CFG, col_char)
ref_objs = C.build_reference(col_ref)
rig = C.Rig(arm)
HIP_Z = rig.rest["Hips"].translation.z

# ----------------------------------------------------------------------------
# Pistola (coordenadas locales de la mano: +Y = hacia los dedos = direccion del canon, +Z = pulgar,
# -X = lado de la palma). El canon va paralelo a la mano/antebrazo (hacia abajo en reposo, hacia el
# blanco al apuntar) y la empunadura cruza la palma segun el eje Z, dentro del puno.
# ----------------------------------------------------------------------------
for nm, rgb, r in (("Metal", (.07, .07, .08), .4), ("Grip", (.03, .02, .015), .8)):
    C.make_material(nm, rgb, r, 0.6 if nm == "Metal" else 0.0)
pb_ = C.Builder(["Hand.R"], ["Metal", "Grip"])
W = {"Hand.R": 1}
px = -0.035          # centro de la cavidad del puño (entre la palma y los dedos curvados)
pb_.box(V((px, .13, .046)), (.026, .20, .032), W, "Metal")           # corredera (sobre los nudillos)
pb_.box(V((px, .24, .046)), (.014, .03, .018), W, "Metal")           # canon
pb_.box(V((px, .062, -.004)), (.03, .04, .096), W, "Grip")             # empunadura
pb_.box(V((px, .1, .024)), (.012, .04, .01), W, "Metal")             # guardamonte
pistol = pb_.to_object("Pistol", col_char)
pistol.vertex_groups.clear()
MUZZLE_LOCAL = V((px, .255, .046))
muzzle = bpy.data.objects.new("Muzzle", None)
muzzle.empty_display_type = 'ARROWS'
muzzle.empty_display_size = 0.04
col_char.objects.link(muzzle)
hand_rest = arm.matrix_world @ arm.data.bones["Hand.R"].matrix_local
pistol.parent = arm
pistol.parent_type = 'BONE'
pistol.parent_bone = "Hand.R"
pistol.matrix_world = hand_rest
bpy.context.view_layer.update()
par = arm.matrix_world @ arm.pose.bones["Hand.R"].matrix @ Matrix.Translation((0, rig.length["Hand.R"], 0))
pistol.matrix_parent_inverse = par.inverted() @ hand_rest
muzzle.parent = pistol
muzzle.location = MUZZLE_LOCAL
meshes.append(pistol)

# ----------------------------------------------------------------------------
# Poses
# ----------------------------------------------------------------------------
sin, cos, pi = math.sin, math.cos, math.pi
clone, tw, arm_set, seq = C.clone, C.tw, C.arm_set, C.seq
ANIMS = []


def anim(name, dur, loop=False, step=0.1):
    def deco(fn):
        ANIMS.append((name, dur, loop, step, fn))
        return fn
    return deco


LEG_LEN = rig.length["Thigh.L"] + rig.length["Shin.L"]
rig.solve(rig.default_spec())
ANK_Z = 0.074 * KZ
XOFF = 0.088 * KX
WALK_T, WALK_D = 1.3, 0.58
WALK_SPEED = WALK_D / (0.6 * WALK_T)
STRIDE = WALK_SPEED * WALK_T
print("Altura aprox (cabeza):", round(rig.rest["Head"].translation.z + rig.length["Head"], 3))


def stand_spec(hip_y=0.0, hz=None):
    sp = rig.default_spec()
    hz = hz if hz is not None else ANK_Z + LEG_LEN * 0.985
    sp["hips_off"] = V((0, hip_y, hz - HIP_Z))
    for sd in "LR":
        s = 1 if sd == "L" else -1
        sp["legik" + sd] = dict(ankle=V((s * XOFF, hip_y, ANK_Z)), pitch=0.0, pole=V((s * .05, -1, 0)))
    gun_low(sp)
    arm_set(sp, "L", "rel", (.12, -.1, -.58), pole=(.6, 1, -.2), hdir=(0, -.1, -1), thumb=(0, -1, .1),
            curl=18.0, thumb_curl=8.0)
    return sp


# Agarre de pistola: indice casi recto junto al guardamonte, medio/anular/menique cerrados sobre la
# empunadura y pulgar por el otro lado.
GRIP = dict(curl=58.0, thumb_curl=14.0, fcurl={"Index": 0.12})


def gun_low(sp):
    arm_set(sp, "R", "rel", (-.12, -.12, -.58), pole=(-.6, 1, -.2), hdir=(0, -.18, -1), thumb=(0, -1, -.25),
            **GRIP)
    return sp


@anim("idle", 4.0, True, 0.2)
def _(t, u):
    sp = stand_spec()
    w = 2 * pi * u
    tw(sp, "hips_off", (0.004 * sin(w), 0, -0.004 * sin(2 * w)))
    tw(sp, "spine", (1.0 * sin(w - .5), 0, 0)), tw(sp, "chest", (1.0 * sin(w - .5), 0, 0))
    tw(sp, "head", (3 + 2 * sin(w), 5 * sin(w + 1), 2 * sin(w)))
    tw(sp, "neck", (0, 0, 1.5 * sin(w)))
    return sp


@anim("walk", WALK_T, True, 0.05)
def _(t, u):
    sp = stand_spec()
    hz = ANK_Z + math.sqrt((LEG_LEN * .975) ** 2 - (WALK_D / 2) ** 2)
    ph = (t / WALK_T) % 1.0
    sp["hips_off"] = V((0, 0, hz - HIP_Z - 0.014 * (0.5 - 0.5 * cos(4 * pi * ph + .6))))
    C.gait(sp, t, WALK_T, WALK_D, ANK_Z, lift=0.075, forward=True, xoff=XOFF)
    w = 2 * pi * ph
    tw(sp, "hips_off", (0.012 * sin(w), 0, 0))
    tw(sp, "hips_rot", (0, 3 * sin(w), 0)), tw(sp, "spine", (2, -3 * sin(w), 0)), tw(sp, "chest", (3, -4 * sin(w), 0))
    tw(sp, "head", (4, 0, 0))
    sw = sin(w)
    arm_set(sp, "L", "rel", (.12, -.1 - .15 * sw, -.57), pole=(.6, 1, -.2), hdir=(0, -.1, -1), thumb=(0, -1, .1),
            curl=18.0, thumb_curl=8.0)
    arm_set(sp, "R", "rel", (-.12, -.12 + .04 * sw, -.58), pole=(-.6, 1, -.2), hdir=(0, -.18, -1), thumb=(0, -1, -.25),
            **GRIP)
    return sp


def inspect_pose(lean, yaw, head_yaw):
    sp = stand_spec()
    tw(sp, "hips_rot", (lean * .5, 0, 0)), tw(sp, "hips_off", (0, -0.05 * lean / 30, -0.02 * lean / 30))
    tw(sp, "spine", (lean * .3, yaw * .3, 0)), tw(sp, "chest", (lean * .3, yaw * .4, 0))
    tw(sp, "neck", (0, head_yaw * .3, 0)), tw(sp, "head", (lean * .3 * 0.5 + 8, head_yaw * .7, 0))
    arm_set(sp, "L", "abs", (.22, -.36, TABLE_TOP + .04), pole=(.8, .5, .6), hdir=(-.2, -1, 0.0),
            thumb=(-1, 0, .3), curl=8.0, thumb_curl=3.0)
    return sp


@anim("inspect_sheets", 3.0, False, 0.1)
def _(t, u):
    keys = [(0.0, stand_spec()), (0.7, inspect_pose(34, 0, 0)), (1.2, inspect_pose(36, 8, 28)),
            (1.35, inspect_pose(36, 8, 28)), (2.0, inspect_pose(36, -8, -28)), (2.15, inspect_pose(36, -8, -28)),
            (2.5, inspect_pose(30, 0, 0)), (3.0, stand_spec())]
    return seq(t, keys)


# --- apuntar ---
TARGET_HEAD = V((0, -0.70, 1.05))
MUZ_BACK = 0.07          # el canon queda a 7 cm de la cabeza


def aim_pose(kick=0.0, sway=V((0, 0, 0))):
    g = V((0.05, -1, -0.08)).normalized()
    M = TARGET_HEAD - g * MUZ_BACK + sway
    # el canon va a lo largo de la mano (Y): apunta a g, con el pulgar hacia arriba; el retroceso la alza
    Yh = (g + V((0, 0, kick * 0.8))).normalized()
    up = V((0, 0, 1))
    Zh = (up - Yh * up.dot(Yh)).normalized()
    Xh = Yh.cross(Zh)
    Mh = C.mat_from_axes(Xh, Yh, Zh, V((0, 0, 0)))
    wrist = M - (Mh.to_3x3() @ MUZZLE_LOCAL)
    wrist = wrist - g * kick * 0.07
    sp = stand_spec()
    tw(sp, "head", (6, 0, 0)), tw(sp, "chest", (3, 0, 0)), tw(sp, "spine", (2, 0, 0))
    arm_set(sp, "R", "abs", wrist, pole=(-.7, .6, -.3), hdir=Yh, thumb=Zh, **GRIP)
    arm_set(sp, "L", "rel", (.16, -.12, -.58), pole=(.6, 1, -.2), hdir=(0, -.1, -1), thumb=(0, -1, .1),
            curl=18.0, thumb_curl=8.0)
    return sp


def raising():
    sp = stand_spec()
    arm_set(sp, "R", "rel", (-.14, -.42, -.36), pole=(-.7, .8, -.2), hdir=(0, -.5, -1), thumb=(0, -1, .2),
            **GRIP)
    return sp


@anim("aim", 0.8, False, 0.05)
def _(t, u):
    return seq(t, [(0, stand_spec()), (0.4, raising()), (0.8, aim_pose())])


@anim("aim_hold", 1.2, True, 0.1)
def _(t, u):
    w = 2 * pi * u
    return aim_pose(sway=V((0.003 * sin(w), 0, 0.003 * sin(2 * w + 1))))


@anim("shoot", 0.5, False, 0.025)
def _(t, u):
    kick = seq(t, [(0, dict(k=0.0)), (0.03, dict(k=1.0)), (0.12, dict(k=0.45)), (0.28, dict(k=0.05)), (0.5, dict(k=0.0))])["k"]
    sp = aim_pose(kick)
    tw(sp, "chest", (-3 * kick, 0, 0)), tw(sp, "spine", (-2 * kick, 0, 0))
    tw(sp, "head", (-2 * kick, 0, 0)), tw(sp, "hips_off", (0, 0.012 * kick, 0))
    return sp


@anim("lower_gun", 0.8, False, 0.05)
def _(t, u):
    return seq(t, [(0, aim_pose()), (0.4, raising()), (0.8, stand_spec())])


def accuse_pose(jab=0.0):
    p = V((0.12, -0.95, -0.12)).normalized()
    sp = stand_spec()
    tw(sp, "spine", (4, 6, 0)), tw(sp, "chest", (4, 8, 0)), tw(sp, "head", (4, -4, 0))
    arm_set(sp, "L", "rel", p * (0.54 + jab) + V((0, 0, 0.02)), pole=(.8, .8, .2), hdir=p, thumb=(0, 0, 1),
            curl=10.0, thumb_curl=0.0)
    return sp


@anim("point_accuse", 1.2, False, 0.05)
def _(t, u):
    return seq(t, [(0, stand_spec()), (0.45, accuse_pose()), (0.62, accuse_pose(0.05)), (0.8, accuse_pose(0.0)),
                   (1.2, accuse_pose(0.0))])


# ----------------------------------------------------------------------------
# Acciones, guardado y exportacion
# ----------------------------------------------------------------------------
if not os.environ.get("CHAR_PREVIEW"):
    for name, dur, loop, step, fn in ANIMS:
        C.make_action(rig, name, dur, fn, step, loop)
        print(f"accion {name}: {dur}s {'loop' if loop else ''}")
    print("MARCHA: zancada (ciclo de 2 pasos) %.3f m, paso %.3f m, periodo %.2f s, velocidad %.3f m/s"
          % (STRIDE, STRIDE / 2, WALK_T, WALK_SPEED))
    arm.animation_data.action = bpy.data.actions["idle"]
    bpy.context.scene.frame_set(0)
    export_objs = [arm] + meshes + [muzzle]
    print("TRIANGULOS:", C.count_tris(meshes), {m.name: C.count_tris([m]) for m in meshes})
    root = C.repo_root()
    os.makedirs(os.path.join(root, "assets", "models", "characters"), exist_ok=True)
    C.export_glb(os.path.join(root, "assets", "models", "characters", "arbiter.glb"), export_objs)
    for o in meshes:
        if o.name in ("Hair_Long", "Hair_Bald"):
            o.hide_set(True)
            o.hide_render = True
    C.save_blend(os.path.join(root, "art", "characters", "arbiter.blend"))
    print("OK arbiter")
