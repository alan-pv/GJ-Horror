"""Genera art/characters/player.blend y assets/models/characters/player.glb (Blender 5.x).

    blender --background --python art/characters/build_player.py

Personaje base de los jugadores (rival, jugador en primera persona y fondo). Todo se construye
desde cero: malla, materiales, esqueleto, pesos y acciones. Ver el final del archivo para el resumen.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
from chartools import *          # noqa: F401,F403
from body import build_body
import chartools as C
from chartools import V

SH = Shape(1.0, 1.0)
CFG = dict(
    colors={
        "Skin": ((.62, .42, .32), .9), "Shirt": ((.62, .62, .58), .9), "Jacket": ((.13, .17, .24), .95),
        "Pants": ((.12, .11, .13), .95), "Shoes": ((.05, .045, .045), .8), "Hair": ((.07, .045, .03), .9),
        "Eyes": ((.015, .015, .015), .5), "Tie": ((.2, .02, .03), .9),
    },
    round_hand=True, finger_scale=1.1, hem=.85, nose=False, ears=False, eyes=True, tie=False, n=12,
)

# ----------------------------------------------------------------------------
# Escena
# ----------------------------------------------------------------------------
C.reset_scene()
col_char = C.new_collection("Character")
col_ref = C.new_collection("Reference")
arm = C.build_armature(SH)
C.link_only(arm, col_char)
meshes = build_body(arm, SH, CFG, col_char)
ref_objs = C.build_reference(col_ref)
rig = C.Rig(arm)
rig.fist_boost = 0.3
HIP_Z = rig.rest["Hips"].translation.z


# ----------------------------------------------------------------------------
# Poses base
# ----------------------------------------------------------------------------
def fit_sit_legs(sp, hip_z, ankle_z=0.075):
    best = None
    for a10 in range(500, 1000, 5):
        a = a10 / 10
        t = C.clone(sp)
        for sd in "LR":
            t["thigh" + sd] = (a, 0, 0)
            t["shin" + sd] = (-a, 0, 0)
        rig.solve(t)
        e = abs(rig.head("Foot.L").z - ankle_z)
        if best is None or e < best[0]:
            best = (e, a)
    return best[1]


# Zona segura de las manos sentado: el tablero (marco incluido) empieza a 0,47 m del centro de la silla
# cuando la silla esta a 0,72 m (mesa del humano y del rival) y a 0,55 m si esta a 0,80 m (fondo). Las
# manos en reposo dejan las puntas de los dedos a y >= HAND_LIMIT_Y (-0,47) y descansan sobre la mesa
# entre su canto (y -0,27 / -0,35) y el tablero.
HAND_LIMIT_Y = -0.47


def rest_hand(sp, sd, x=.20, y=-.29, z=.79, curl=34.0, hdir=None, thumb=None, pole=None):
    """Mano relajada apoyada de plano sobre la mesa, cerca del canto (fuera del tablero)."""
    s = 1 if sd == "L" else -1
    C.arm_set(sp, sd, "abs", (s * x, y, z), pole=pole or (s * .35, 1, -.45),
              hdir=hdir or (-s * .10, -1, -.05), thumb=thumb or (-s, 0, .3), curl=curl, thumb_curl=curl * .4)
    return sp


def make_sit():
    sp = rig.default_spec()
    sp["hips_off"] = V((0, -0.03, 0.54 - HIP_Z))
    # Espalda casi recta; la cabeza baja con el cuello (no con una joroba en Spine/Chest).
    sp.update(spine=(3, 0, 0), chest=(3, 0, 0), neck=(2, 0, 0), head=(6, 0, 0))
    a = fit_sit_legs(sp, 0.54)
    for sd in "LR":
        sp["thigh" + sd] = (a, 0, 0)
        sp["shin" + sd] = (-a, 0, 0)
        s = 1 if sd == "L" else -1
        rest_hand(sp, sd)
    return sp



SIT = make_sit()
rig.solve(SIT)
EYE_Z = rig.head("Head").z + 0.17
print("Sentado en reposo: ojos z~%.3f, hombros z=%.3f" % (EYE_Z, rig.head("UpperArm.L").z))
ANKLE = {sd: rig.head("Foot." + sd) for sd in "LR"}

sin, cos, pi = math.sin, math.cos, math.pi
clone, tw, arm_set, seq = C.clone, C.tw, C.arm_set, C.seq
ANIMS = []


def anim(name, dur, loop=False, step=0.1):
    def deco(fn):
        ANIMS.append((name, dur, loop, step, fn))
        return fn
    return deco


def breathe(sp, w, k=1.0):
    tw(sp, "spine", (0.8 * k * sin(w), 0, 0))
    tw(sp, "chest", (1.2 * k * sin(w - .6), 0, 0))
    tw(sp, "shL", (0, 0, 0.8 * k * sin(w - .6)))
    tw(sp, "shR", (0, 0, 0.8 * k * sin(w - .6)))


def lean(sp, spine, chest, yaw=0.0, hips_y=0.0):
    tw(sp, "spine", (spine, yaw * .5, 0))
    tw(sp, "chest", (chest, yaw * .5, 0))
    tw(sp, "hips_off", (0, hips_y, 0))


# ----------------------------------------------------------------------------
# Sentado: reposo, pensar, nervioso
# ----------------------------------------------------------------------------
@anim("sit_idle", 4.0, True, 0.2)
def _(t, u):
    sp = clone(SIT)
    w = 2 * pi * u
    bump = (0.5 - 0.5 * cos(w)) ** 2
    breathe(sp, w)
    tw(sp, "head", (1.2 * sin(2 * w) + 5 * bump, 3.0 * sin(w), 1.0 * sin(w + 1)))
    tw(sp, "hips_off", (0.004 * sin(w), 0, 0))
    sp["armR"]["curl"] += 5 * sin(2 * w)
    return sp


def think_base():
    sp = clone(SIT)
    sp.update(spine=(7, 0, 2), chest=(5, 0, 0), neck=(6, 0, 0), head=(9, 4, -6))
    arm_set(sp, "R", "att", (-0.062, -0.045, 0.085), bone="Head", pole=(-.4, .5, -1),
            hdir=(.45, .35, .85), thumb=(-1, 0, 0), curl=70.0, thumb_curl=15.0)
    return sp


@anim("sit_think", 5.0, True, 0.25)
def _(t, u):
    sp = think_base()
    w = 2 * pi * u
    breathe(sp, w, .7)
    tw(sp, "head", (2.0 * sin(w), 3.0 * sin(w + 1.2), 1.5 * sin(2 * w)))
    sp["armL"]["curl"] += 10 * max(0, sin(4 * w))
    return sp


@anim("sit_nervous", 2.4, True, 0.1)
def _(t, u):
    sp = clone(SIT)
    w = 2 * pi * u
    breathe(sp, 3 * w, 1.6)
    yaw = seq(t, [(0, dict(y=0.0)), (0.5, dict(y=26.0)), (0.9, dict(y=2.0)), (1.5, dict(y=-28.0)),
                  (2.0, dict(y=-4.0)), (2.4, dict(y=0.0))])["y"]
    tw(sp, "head", (3 * sin(w * 2), yaw, 0))
    tw(sp, "neck", (0, yaw * .3, 0))
    bounce = sin(6 * w)
    tb = 0.5 + 0.5 * bounce       # solo sube la rodilla (nunca se hunde en el asiento)
    tw(sp, "thighR", (-3.5 * tb, 0, 0))
    tw(sp, "shinR", (3.5 * tb - 1.5 * abs(bounce), 0, 0))
    tw(sp, "hips_off", (0.0, 0.0, 0.004 * bounce))
    tw(sp, "shL", (0, 0, 2.5)), tw(sp, "shR", (0, 0, 2.5))
    sp["armL"]["curl"] += 14 * max(0, sin(5 * w))
    sp["armR"]["curl"] += 14 * max(0, sin(5 * w + 2))
    return sp


# ----------------------------------------------------------------------------
# Sentado: acciones de juego
# ----------------------------------------------------------------------------
PINCH_DIR = V((0, -.55, -.83)).normalized()


def reach(spec_base, tip, curl, yaw=-6.0, lift=0.0, spine=9, chest=11, hips_y=-0.05):
    sp = clone(spec_base)
    lean(sp, spine, chest, yaw, hips_y)
    tw(sp, "head", (-8, 0, 0))
    wr = V(tip) - PINCH_DIR * 0.155 + V((0, 0, lift))
    arm_set(sp, "R", "abs", wr, pole=(-.7, .5, -.2), hdir=PINCH_DIR, thumb=(1, 0, 0),
            curl=curl, thumb_curl=curl * .5)
    return sp


@anim("sit_move_piece", 1.8, False, 0.05)
def _(t, u):
    src = board_pt(4, 1, TABLE_TOP + .045)
    dst = board_pt(4, 3, TABLE_TOP + .045)
    keys = [
        (0.00, clone(SIT)),
        (0.17, reach(SIT, V((-.20, -.29, .79)).lerp(src - PINCH_DIR * .155, .3) + PINCH_DIR * .155, 8, lift=.12,
                     yaw=-2, spine=4, chest=5, hips_y=-.01)),
        (0.35, reach(SIT, src, 8, lift=.09)),
        (0.52, reach(SIT, src, 8, lift=.0)),
        (0.62, reach(SIT, src, 42, lift=.0)),
        (0.80, reach(SIT, src.lerp(dst, .2), 42, lift=.12)),
        (1.05, reach(SIT, dst, 42, lift=.12, yaw=-5)),
        (1.22, reach(SIT, dst, 42, lift=.0, yaw=-5)),
        (1.32, reach(SIT, dst, 8, lift=.0, yaw=-5)),
        (1.45, reach(SIT, dst, 8, lift=.08, yaw=-5)),
        (1.62, reach(SIT, dst.lerp(V((-.20, -.29, .79)) + PINCH_DIR * .155, .6), 8, lift=.10, yaw=-2,
                     spine=4, chest=5, hips_y=-.01)),
        (1.80, clone(SIT)),
    ]
    return seq(t, keys)


CLOCK_TOP = TABLE_TOP + .09


def clock_pose(z, lean_k=1.0):
    sp = clone(SIT)
    lean(sp, 12 * lean_k, 14 * lean_k, -12, -0.06 * lean_k)
    tw(sp, "head", (-8, 0, 0))
    arm_set(sp, "R", "abs", (CLOCK_POS.x + .04, CLOCK_POS.y + .12, z), pole=(-.8, .5, .2),
            hdir=(0, -1, -.15), thumb=(1, 0, 0), curl=10.0, thumb_curl=5.0)
    return sp


@anim("sit_press_clock", 0.7, False, 0.025)
def _(t, u):
    keys = [
        (0.00, clone(SIT)),
        (0.16, clock_pose(CLOCK_TOP + .17, .8)),
        (0.27, clock_pose(CLOCK_TOP + .03, 1.0)),
        (0.33, clock_pose(CLOCK_TOP + .018, 1.1)),
        (0.45, clock_pose(CLOCK_TOP + .03, 1.0)),
        (0.70, clone(SIT)),
    ]
    return seq(t, keys)


@anim("sit_write", 2.5, True, 0.05)
def _(t, u):
    sp = clone(SIT)
    w = 2 * pi * u
    lean(sp, 14, 16, -10, -0.03)
    tw(sp, "neck", (6, -8, 0))
    tw(sp, "head", (14, -14, -3))
    dx = 0.028 * sin(w) + 0.006 * sin(7 * w)
    dy = -0.045 + 0.012 * sin(5 * w + 1) + 0.015 * sin(w + 2)
    tip = V((SHEET_POS.x + dx, SHEET_POS.y + dy, TABLE_TOP + .045))
    d = V((.3, -.6, -.75)).normalized()
    arm_set(sp, "R", "abs", tip - d * 0.14, pole=(-.8, .6, -.1), hdir=d, thumb=(.5, .3, .6),
            curl=58.0, thumb_curl=22.0)
    arm_set(sp, "L", "abs", (.07 + .004 * sin(w), -.50, .768), pole=(.9, .6, .6),
            hdir=(-.1, -1, -.05), thumb=(-1, 0, .3), curl=14.0, thumb_curl=6.0)
    breathe(sp, w, .6)
    return sp


# ----------------------------------------------------------------------------
# Eliminacion: suplicar, llorar, congelarse
# ----------------------------------------------------------------------------
@anim("sit_cry", 2.4, True, 0.1)
def _(t, u):
    sp = clone(SIT)
    w = 2 * pi * u
    sob = 0.5 + 0.5 * sin(3 * w)
    sp.update(spine=(10 + 4 * sob, 0, 0), chest=(8 + 4 * sob, 0, 0), neck=(6, 0, 0), head=(16 + 5 * sob, 0, 0))
    tw(sp, "hips_off", (0, -0.03, 0))
    for sd, s in (("L", 1), ("R", -1)):
        arm_set(sp, sd, "att", (s * .04, -.005 + .006 * sob, .11), bone="Head", pole=(s * .5, .8, -.2),
                hdir=(0, .5, .85), thumb=(s, 0, 0), curl=18.0, thumb_curl=8.0)
    tw(sp, "shL", (0, 0, 3 * sob)), tw(sp, "shR", (0, 0, 3 * sob))
    tw(sp, "head", (0, 0, 2 * sin(6 * w)))
    return sp


@anim("sit_frozen", 2.0, True, 0.05)
def _(t, u):
    sp = clone(SIT)
    w = 2 * pi * u
    sp.update(spine=(-1, 0, 0), chest=(-2, 0, 0), neck=(-3, 0, 0), head=(-5, 0, 0))
    tw(sp, "hips_off", (0, 0.0, 0))
    for sd, s in (("L", 1), ("R", -1)):
        j = 0.003 * sin(7 * w + (0 if sd == "L" else 2))
        arm_set(sp, sd, "abs", (s * .145, -.14 + j, .628 + j), pole=(s * .9, .5, 0),
                hdir=(0, -.9, -.3), thumb=(-s, 0, .1), curl=75.0, thumb_curl=30.0)
    tw(sp, "head", (0, 0, 0.7 * sin(6 * w))), tw(sp, "head", (0.5 * sin(8 * w), 0.5 * sin(5 * w), 0))
    tw(sp, "shL", (0, 0, 1.2 * sin(5 * w + 1))), tw(sp, "shR", (0, 0, 1.2 * sin(5 * w)))
    return sp


# ----------------------------------------------------------------------------
# De pie (IK de piernas)
# ----------------------------------------------------------------------------
LEGL = rig.rest["Shin.L"].translation  # rodilla en reposo (referencia)
LEG_LEN = rig.length["Thigh.L"] + rig.length["Shin.L"]
ANK_Z = ANKLE["L"].z


def legs_ik(sp, la, ra, la_p=0.0, ra_p=0.0, kp=(0, -1, 0)):
    for sd, a, p in (("L", la, la_p), ("R", ra, ra_p)):
        s = 1 if sd == "L" else -1
        sp["legik" + sd] = dict(ankle=V(a), pitch=p, pole=V((s * .05 + kp[0], kp[1], kp[2])))
    return sp


def seated_ik():
    sp = clone(SIT)
    return legs_ik(sp, ANKLE["L"], ANKLE["R"])


def stand_spec(hip_y=0.0, hip_z=None, la=None, ra=None):
    """De pie con las piernas por IK."""
    sp = rig.default_spec()
    hz = hip_z if hip_z is not None else ANK_Z + LEG_LEN * 0.975
    sp["hips_off"] = V((0, hip_y, hz - HIP_Z))
    la = la or (0.088, hip_y, ANK_Z)
    ra = ra or (-0.088, hip_y, ANK_Z)
    return legs_ik(sp, la, ra)


def arms_rel(sp, l, r, curl=10.0, hands_up=True):
    for sd, v in (("L", l), ("R", r)):
        s = 1 if sd == "L" else -1
        arm_set(sp, sd, "rel", v, pole=(s * .6, .9, -.2), curl=curl, thumb_curl=curl * .4,
                hdir=(s * .1, -.7, .5 if hands_up else -.5), thumb=(-s, -.2, .2))
    return sp


@anim("stand_flee", 2.0, False, 0.05)
def _(t, u):
    S0 = seated_ik()
    # recula en la silla
    s1 = seated_ik()
    s1.update(spine=(-8, 0, 0), chest=(-10, 0, 0), neck=(-6, 0, 0), head=(-14, 0, 0))
    arms_rel(s1, V((.22, -.30, .05)), V((-.22, -.30, .05)))
    tw(s1, "hips_off", (0, 0.04, 0))
    # impulso: se levanta apoyando las manos
    s2 = stand_spec(-0.14, 0.78, la=ANKLE["L"], ra=ANKLE["R"])
    s2.update(spine=(14, 0, 0), chest=(16, 0, 0), neck=(-4, 0, 0), head=(-8, 0, 0))
    arms_rel(s2, V((.15, -.42, -.28)), V((-.15, -.42, -.28)), hands_up=False)
    # erguido, retrocede
    s3 = stand_spec(-0.02, 0.83, la=(.1, -.3, .075), ra=(-.1, -.18, .17))
    s3.update(spine=(-6, 0, 0), chest=(-8, 0, 0), neck=(-4, 0, 0), head=(-8, 0, 0))
    arms_rel(s3, V((.26, -.34, .12)), V((-.26, -.34, .12)))
    s4 = stand_spec(0.10, 0.83, la=(.1, -.16, .075), ra=(-.1, .04, .075))
    s4.update(spine=(-10, 0, 3), chest=(-10, 0, 3), neck=(0, 0, 0), head=(-6, 0, 0))
    arms_rel(s4, V((.42, -.12, .2)), V((-.34, -.30, .1)))
    s5 = stand_spec(0.22, 0.83, la=(.1, .06, .17), ra=(-.1, .02, .075))
    s5.update(spine=(8, 0, -3), chest=(4, 0, -3), neck=(-2, 0, 0), head=(-6, 0, 0))
    arms_rel(s5, V((.3, -.3, .05)), V((-.46, -.1, .22)))
    s6 = stand_spec(0.32, 0.83, la=(.1, .26, .075), ra=(-.1, .02, .075))
    s6.update(spine=(-12, 0, 0), chest=(-12, 0, 0), neck=(-2, 0, 0), head=(-6, 0, 0))
    arms_rel(s6, V((.4, -.2, .2)), V((-.36, -.2, .2)))
    s7 = stand_spec(0.40, 0.82, la=(.11, .28, .075), ra=(-.11, .20, .17))
    s7.update(spine=(-14, 0, 0), chest=(-12, 0, 0), neck=(0, 0, 0), head=(-6, 0, 0))
    arms_rel(s7, V((.3, -.32, .2)), V((-.3, -.32, .2)))
    s8 = stand_spec(0.44, 0.82, la=(.11, .28, .075), ra=(-.11, .42, .075))
    s8.update(spine=(-10, 0, 0), chest=(-10, 0, 0), neck=(0, 0, 0), head=(-6, 0, 0))
    arms_rel(s8, V((.26, -.36, .22)), V((-.26, -.36, .22)))
    s0b = seated_ik()       # primero levanta las manos de la mesa
    for sd in "LR":
        rest_hand(s0b, sd, y=-.30, z=.86, curl=20)
    keys = [(0.0, S0), (0.06, s0b), (0.14, s1), (0.55, s2), (0.8, s3), (1.05, s4), (1.25, s5), (1.45, s6), (1.7, s7), (2.0, s8)]
    return seq(t, keys)


FLEE_T, FLEE_D = 1.0, 0.30


@anim("stand_flee_cycle", FLEE_T, True, 0.05)
def _(t, u):
    hz = ANK_Z + math.sqrt((LEG_LEN * .93) ** 2 - (FLEE_D / 2) ** 2)
    sp = stand_spec(0.0, hz)
    C.gait(sp, t, FLEE_T, FLEE_D, ANK_Z, lift=0.06, forward=False)
    w = 2 * pi * u
    sp.update(spine=(-8, 0, 0), chest=(-8, 0, 0), neck=(-2, 0, 0), head=(-6, 0, 0))
    tw(sp, "hips_off", (0, 0, -0.012 * abs(sin(2 * w))))
    tw(sp, "spine", (0, 3 * sin(2 * w), 0))
    tw(sp, "head", (1.2 * sin(6 * w), 0, 1.0 * sin(5 * w)))
    arms_rel(sp, V((.3, -.33 + .01 * sin(6 * w), .22)), V((-.3, -.33 + .01 * sin(6 * w + 1), .22)), curl=6.0)
    return sp


# ----------------------------------------------------------------------------
# Muertes
# ----------------------------------------------------------------------------
def slump_final():
    sp = clone(SIT)
    sp.update(spine=(24, 0, 0), chest=(26, 0, 0), neck=(10, 0, 0), head=(4, 0, -14))
    tw(sp, "hips_off", (0, 0.035, 0.02))
    arm_set(sp, "R", "abs", (-.20, -.60, .79), pole=(-.9, .4, .2), hdir=(.1, -1, -.05), thumb=(1, 0, .3),
            curl=20.0, thumb_curl=8.0)
    arm_set(sp, "L", "rel", (.26, .12, -.48), pole=(.6, 1, 0), hdir=(0, -.2, -1), thumb=(0, -1, 0), curl=30.0,
            thumb_curl=10.0)
    tw(sp, "shL", (0, 0, -6))
    return sp


def shot_snap():
    sp = clone(SIT)
    sp.update(spine=(-3, 0, 0), chest=(-4, 0, 0), neck=(-14, 0, 0), head=(-34, 0, 0))
    tw(sp, "hips_off", (0, 0.01, 0))
    for sd, s in (("L", 1), ("R", -1)):
        arm_set(sp, sd, "abs", (s * .21, -.46, .81), pole=(s * .9, .6, .1), hdir=(0, -1, .1), thumb=(-s, 0, .3),
                curl=2.0, thumb_curl=0.0)
    return sp


@anim("death_slump_table", 1.5, False, 0.05)
def _(t, u):
    mid = clone(slump_final())
    mid.update(spine=(16, 0, 0), chest=(14, 0, 0), neck=(4, 0, 0), head=(-4, 0, -6))
    over = clone(slump_final())
    over.update(spine=(30, 0, 0), chest=(34, 0, 0), neck=(12, 0, 0), head=(10, 0, -10))
    keys = [(0.0, clone(SIT)), (0.07, shot_snap()), (0.2, shot_snap()), (0.5, mid), (0.85, over),
            (1.1, slump_final()), (1.5, slump_final())]
    return seq(t, keys)


def prone(hip_y, hip_z):
    sp = stand_spec(hip_y, hip_z, la=(.15, hip_y + .72, .09), ra=(-.15, hip_y + .76, .09))
    sp["hips_rot"] = (88, 0, 0)
    sp.update(spine=(-4, 0, 0), chest=(-6, 0, 0), neck=(-4, 0, 0), head=(0, 80, 0))
    legs_ik(sp, (.15, hip_y + .70, .10), (-.15, hip_y + .74, .10), 78, 80, kp=(0, .2, 1.2))
    arm_set(sp, "L", "abs", (.42, hip_y - .62, .09), pole=(.6, .2, 1), hdir=(.2, -.9, -.2), thumb=(-1, 0, 0), curl=20.0,
            thumb_curl=5.0)
    arm_set(sp, "R", "abs", (-.36, hip_y - .5, .09), pole=(-.6, .2, 1), hdir=(-.3, -.8, -.2), thumb=(1, 0, 0),
            curl=30.0, thumb_curl=5.0)
    return sp


@anim("death_standing", 1.5, False, 0.05)
def _(t, u):
    s0 = stand_spec(0.0)
    arms_rel(s0, V((.12, -.03, -.5)), V((-.12, -.03, -.5)), hands_up=False)
    s1 = stand_spec(0.0)
    s1.update(spine=(-6, 0, 0), chest=(-8, 0, 0), neck=(-12, 0, 0), head=(-34, 0, 0))
    arms_rel(s1, V((.34, .02, .25)), V((-.34, .02, .25)))
    s2 = stand_spec(-0.06, 0.66)
    s2.update(spine=(8, 0, 0), chest=(8, 0, 0), neck=(2, 0, 0), head=(6, 0, 0))
    arms_rel(s2, V((.3, -.1, .1)), V((-.3, -.1, .1)), hands_up=False)
    s3 = stand_spec(-0.30, 0.42, la=(.1, 0.0, .075), ra=(-.1, 0.04, .075))
    s3["hips_rot"] = (42, 0, 0)
    s3.update(spine=(14, 0, 0), chest=(10, 0, 0), neck=(4, 0, 0), head=(10, 20, 0))
    arms_rel(s3, V((.3, -.4, -.2)), V((-.3, -.4, -.2)), hands_up=False)
    s4 = prone(-0.60, 0.12)
    s5 = prone(-0.62, 0.11)
    keys = [(0.0, s0), (0.06, s0), (0.17, s1), (0.45, s2), (0.8, s3), (1.15, s4), (1.5, s5)]
    return seq(t, keys)


# ----------------------------------------------------------------------------
# Reacciones breves (una vez): sobresalto, tos, recoger del suelo
# ----------------------------------------------------------------------------
def startle_pose(k=1.0):
    """Respingo simetrico: tronco atras, hombros arriba, sin girar a un lado (el lado lo pone la mirada)."""
    sp = clone(SIT)
    tw(sp, "spine", (-6 * k, 0, 0)), tw(sp, "chest", (-9 * k, 0, 0))
    tw(sp, "neck", (-5 * k, 0, 0)), tw(sp, "head", (-8 * k, 0, 0))
    tw(sp, "shL", (0, 0, 9 * k)), tw(sp, "shR", (0, 0, 9 * k))
    tw(sp, "hips_off", (0, 0.008 * k, 0.006 * k))
    for sd in "LR":
        rest_hand(sp, sd, y=-.29 + .035 * k, z=.78 + .045 * k, curl=34 + 22 * k)
    return sp


@anim("sit_startle", 1.0, False, 0.05)
def _(t, u):
    keys = [(0.0, clone(SIT)), (0.13, startle_pose(1.0)), (0.28, startle_pose(1.1)),
            (0.60, startle_pose(.45)), (1.0, clone(SIT))]
    return seq(t, keys)



def cough_pose(k=1.0, hunch=0.0):
    sp = clone(SIT)
    sp.update(spine=(4 + hunch, 0, 0), chest=(3 + hunch * 1.4, 0, 0), neck=(2 * k, 0, 0), head=(-2 + hunch, 10 * k, 0))
    tw(sp, "hips_off", (0, -0.01 * k, 0))
    arm_set(sp, "R", "att", (-.035 * k - .09 * (1 - k), .04 + .1 * (1 - k), .125 + .1 * (1 - k)), bone="Head",
            pole=(-.5, 1.3, -1.2), hdir=(.2, -.4, .9), thumb=(0, 1, 0), curl=80.0, thumb_curl=40.0)
    return sp


@anim("sit_cough", 1.8, False, 0.05)
def _(t, u):
    up = cough_pose(1.0)
    keys = [(0.0, clone(SIT)), (0.35, up), (0.55, cough_pose(1.0, 0)), (0.62, cough_pose(1.0, 7)),
            (0.70, cough_pose(1.0, 0)), (0.79, cough_pose(1.0, 9)), (0.88, cough_pose(1.0, 1)),
            (0.97, cough_pose(1.0, 6)), (1.10, cough_pose(1.0, 1)), (1.30, up), (1.80, clone(SIT))]
    sp = seq(t, keys)
    if 0.5 < t < 1.2:   # espasmos de los hombros
        tw(sp, "shL", (0, 0, 3 * sin(t * 40))), tw(sp, "shR", (0, 0, 3 * sin(t * 40)))
    return sp


def pickup_pose(reach, hold=False, curl=12.0):
    """reach 0 = sentado, 1 = mano al suelo, a la derecha de la silla. Se inclina de lado (no hacia la mesa)."""
    sp = clone(SIT)
    r = reach
    tw(sp, "hips_off", (-0.05 * r, 0.01 * r, 0))
    sp["hips_rot"] = (0, 0, 9 * r)
    sp.update(spine=(8 * r + 4, 0, 30 * r), chest=(6 * r + 4, 0, 26 * r),
              neck=(6 * r, 0, -12 * r), head=(14 * r + 6, -12 * r, -14 * r))
    if r > 0.01:
        # primero retira la mano de la mesa hacia el regazo y despues baja al suelo
        a_, b_ = smooth(min(1.0, r * 2.5)), smooth(max(0.0, (r - .25) / .75))
        tgt = V((-.20 - .18 * b_, -.29 + .24 * a_, .79 - .70 * b_))
        arm_set(sp, "R", "abs", tgt, pole=(-1, .3, -.4),
                hdir=V((-.1, -1, -.05)).lerp(V((-.1, -.3, -1)), b_), thumb=(1, 0, .3),
                curl=curl, thumb_curl=curl * .4)
    return sp


@anim("sit_pick_up", 2.8, False, 0.05)
def _(t, u):
    keys = [(0.0, clone(SIT)), (0.35, pickup_pose(.18)), (0.55, pickup_pose(.38)), (0.72, pickup_pose(.62)),
            (1.0, pickup_pose(1.0)), (1.25, pickup_pose(1.0)),
            (1.45, pickup_pose(1.0, curl=62.0)), (1.65, pickup_pose(1.0, curl=62.0)),
            (1.9, pickup_pose(.62, curl=62.0)), (2.15, pickup_pose(.3, curl=62.0)), (2.8, clone(SIT))]
    return seq(t, keys)


# ----------------------------------------------------------------------------
# Levantarse / sentarse / acusar / ser arrastrado / caminar
# La silla debe retirarse >= 0,40 m hacia atras (+Y del personaje) mientras la pelvis sube: de pie los pies
# quedan donde estaba el asiento. Con la silla a 0,72 m el vientre queda a >= 8 cm del canto de la mesa.
# ----------------------------------------------------------------------------
STAND_Y = -0.03      # y de la pelvis de pie junto a la mesa


def seated_ik_hands():
    """Sentado con piernas por IK y manos en reposo (base de levantarse/sentarse)."""
    return seated_ik()


def side_hands(sp, y, z, x=.27, curl=16.0, hdir=(0, -.35, -1)):
    """Manos junto a los costados (por fuera del tronco y de la mesa), relajadas."""
    for sd in "LR":
        s = 1 if sd == "L" else -1
        arm_set(sp, sd, "abs", (s * x, y, z), pole=(s * .9, .8, -.3), hdir=hdir, thumb=(-s, -.2, 0),
                curl=curl, thumb_curl=curl * .4)
    return sp


def rise_keys():
    """Subida (sentado -> de pie, brazos colgando), 1,7 s: se adelanta con los pies recogidos (peso a los
    pies), luego sube la pelvis y al final se endereza. Las manos suben del tablero, vuelven por encima del
    canto de la mesa y bajan por fuera de las caderas (nunca atraviesan la mesa)."""
    k0 = seated_ik_hands()
    # 1) tronco adelante, pies recogidos bajo las rodillas, manos fuera de la mesa
    k1 = seated_ik_hands()
    legs_ik(k1, (.088, -.26, ANK_Z), (-.088, -.26, ANK_Z))
    k1.update(spine=(20, 0, 0), chest=(16, 0, 0), neck=(-4, 0, 0), head=(-8, 0, 0))
    tw(k1, "hips_off", (0, -0.05, 0.0))
    side_hands(k1, -.16, .92, hdir=(0, -.8, -.3))
    # 2) la pelvis sube sobre los pies
    k2 = stand_spec(-0.10, 0.70, la=(.088, -.15, ANK_Z), ra=(-.088, -.15, ANK_Z))
    k2.update(spine=(24, 0, 0), chest=(18, 0, 0), neck=(-8, 0, 0), head=(-10, 0, 0))
    side_hands(k2, -.12, .70)
    # 3) casi erguido
    k3 = stand_spec(-0.05, 0.83, la=(.088, -.09, ANK_Z), ra=(-.088, -.09, ANK_Z))
    k3.update(spine=(10, 0, 0), chest=(8, 0, 0), neck=(-2, 0, 0), head=(-4, 0, 0))
    side_hands(k3, -.06, .70, x=.26)
    # 4) de pie, brazos colgando
    k4 = stand_spec(STAND_Y)
    k4.update(spine=(2, 0, 0), chest=(2, 0, 0), neck=(0, 0, 0), head=(2, 0, 0))
    side_hands(k4, -.04, .68, x=.25)
    return [(0.0, k0), (0.40, k1), (0.85, k2), (1.25, k3), (1.70, k4)]


@anim("stand_up", 1.7, False, 0.05)
def _(t, u):
    return seq(t, rise_keys())


@anim("sit_down", 1.7, False, 0.05)
def _(t, u):
    # La subida al reves: de pie -> manos a la mesa -> se deja caer en la silla.
    return seq(1.7 - t, rise_keys())


def accuse_pose(lunge=0.0, shake=0.0, arm_y=-.62):
    """De pie, el brazo derecho señalando al frente a la altura del hombro; la mano izquierda apoyada en la mesa."""
    sp = stand_spec(STAND_Y)
    sp.update(spine=(4 + 6 * lunge, 0, 0), chest=(5 + 7 * lunge, 0, 0), neck=(-3, 0, 0), head=(-6 + 8 * lunge, 0, 0))
    tw(sp, "hips_off", (0, -0.015 * lunge, 0))
    arm_set(sp, "R", "abs", (-.17, arm_y, 1.235 + shake), pole=(-.3, .7, -1), hdir=(-.02, -1, .06),
            thumb=(1, 0, .3), curl=2.0, thumb_curl=0.0)
    rest_hand(sp, "L", x=.21, y=-.33, z=.815, curl=60.0, hdir=(-.1, -1, .05))
    return sp


def raise_arm_keys():
    # el brazo derecho sube desde la mesa mientras el torso se endereza
    k3 = rise_keys()[3][1]
    k4 = clone(k3)
    side_hands(k4, -.06, .70, x=.26)
    k4.update(spine=(4, 0, 0), chest=(3, 0, 0), neck=(-2, 0, 0), head=(-4, 0, 0))
    k4["legikL"], k4["legikR"] = clone(stand_spec(STAND_Y)["legikL"]), clone(stand_spec(STAND_Y)["legikR"])
    k4["hips_off"] = stand_spec(STAND_Y)["hips_off"]
    rest_hand(k4, "L", x=.21, y=-.33, z=.815, curl=60.0, hdir=(-.1, -1, .05))
    arm_set(k4, "R", "abs", (-.30, -.30, 1.0), pole=(-.6, .7, -1), hdir=(-.1, -1, .1), thumb=(1, 0, .3), curl=15.0)
    return k4


@anim("stand_accuse", 2.6, False, 0.05)
def _(t, u):
    rk = rise_keys()
    keys = rk[:4] + [(1.45, raise_arm_keys()), (1.85, accuse_pose(-.4, 0, -.50)), (2.15, accuse_pose(1.0)),
                     (2.6, accuse_pose(0.0))]
    return seq(t, keys)


@anim("stand_accuse_hold", 1.2, True, 0.05)
def _(t, u):
    w = 2 * pi * u
    sp = accuse_pose(0.0, 0.004 * sin(3 * w), -.62 + .004 * sin(w))
    tw(sp, "spine", (1.2 * sin(w), 0, 0)), tw(sp, "chest", (1.5 * sin(w), 0, 0))
    tw(sp, "head", (-1.5 * sin(w) + 1.0 * sin(2 * w), 1.5 * sin(w), 0))
    sp["armR"]["curl"] += 2 * (1 - cos(2 * w))
    return sp


DRAG_T = 1.2


@anim("dragged", DRAG_T, True, 0.05)
def _(t, u):
    w = 2 * pi * u
    sp = stand_spec(0.0, 0.80)
    sp.update(spine=(24, 0, 0), chest=(18, 0, 0), neck=(16, 0, 0), head=(22, 0, 0))
    tw(sp, "hips_off", (0.01 * sin(w), 0.02, -0.012 * (1 - cos(2 * w)) / 2))
    tw(sp, "hips_rot", (0, 0, 2.5 * sin(w)))
    tw(sp, "spine", (1.5 * sin(2 * w), 0, 2.0 * sin(w))), tw(sp, "chest", (0, 0, -2.0 * sin(w)))
    tw(sp, "head", (3 * sin(2 * w + 1), 4 * sin(w + .5), 7 * sin(w + 1.3)))
    for sd, off in (("L", 0.0), ("R", pi)):
        s = 1 if sd == "L" else -1
        p = w + off
        legs = dict(ankle=V((s * .09, .40 + .05 * sin(p), .17 + .02 * (1 - cos(p)))), pitch=-62.0,
                    pole=V((s * .1, -1, .2)))
        sp["legik" + sd] = legs
        sag = sin(2 * w + (0 if sd == "L" else 1.0))
        arm_set(sp, sd, "rel", (s * .40, -.02 + .02 * sin(p), .06 + .015 * sag), pole=(s * .3, .6, -1),
                hdir=(s * .1, -.3, -1), thumb=(-s, -.2, 0), curl=13.0, thumb_curl=4.0,
                spread=6.0)   # manos colgando, abiertas y un poco curvas
    return sp


WALK_T, WALK_D = 1.0, 0.66
WALK_SPEED = WALK_D / (0.6 * WALK_T)      # m/s con velocidad 1: 1,1 m/s
STRIDE = WALK_SPEED * WALK_T


@anim("walk", WALK_T, True, 0.05)
def _(t, u):
    sp = stand_spec(0.0)
    hz = ANK_Z + math.sqrt((LEG_LEN * .975) ** 2 - (WALK_D / 2) ** 2)
    ph = (t / WALK_T) % 1.0
    sp["hips_off"] = V((0, 0, hz - HIP_Z - 0.014 * (0.5 - 0.5 * cos(4 * pi * ph + .6))))
    C.gait(sp, t, WALK_T, WALK_D, ANK_Z, lift=0.075, forward=True)
    w = 2 * pi * ph
    sw = sin(w)
    tw(sp, "hips_off", (0.012 * sw, 0, 0))
    tw(sp, "hips_rot", (0, 3 * sw, 0)), tw(sp, "spine", (2, -3 * sw, 0)), tw(sp, "chest", (3, -4 * sw, 0))
    tw(sp, "head", (3, 0, 0))
    for sd, k in (("L", 1), ("R", -1)):
        s = 1 if sd == "L" else -1
        arm_set(sp, sd, "rel", (s * .12, -.10 - .12 * sw * k, -.53), pole=(s * .6, 1, -.2), hdir=(0, -.1, -1),
                thumb=(0, -1, .1), curl=20.0, thumb_curl=8.0)
    return sp


# ----------------------------------------------------------------------------
# Verificacion de penetracion contra la mesa
# ----------------------------------------------------------------------------
CHECK_EDGE_Y = -0.27     # canto de la mesa con la silla a 0,72 m (el caso mas estricto)
ARM_GROUPS = ("UpperArm", "Forearm", "Hand", "Shoulder") + tuple(
    f"{f}{i}" for f in C.FINGER_NAMES + ("Thumb",) for i in (1, 2, 3))


def _scan(name, step, fn):
    """Recorre los fotogramas de la accion y llama fn(coord, grupo, frame) por cada vertice del cuerpo."""
    body = bpy.data.objects["Body"]
    act = bpy.data.actions[name]
    arm.animation_data.action = act
    names = [g.name for g in body.vertex_groups]
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    for f in range(f0, f1 + 1, step):
        bpy.context.scene.frame_set(f)
        eo = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
        me = eo.to_mesh()
        orig = body.data.vertices
        grp = [names[max(orig[i].groups, key=lambda x: x.weight).group].split(".")[0] for i in range(len(me.vertices))]
        for i, v in enumerate(me.vertices):
            fn(v.co, grp[i], f)
        # puntos intermedios de cada arista: las bandas finas (asiento, losa) caen entre anillos de vertices
        vs = me.vertices
        for e in me.edges:
            a, b = vs[e.vertices[0]].co, vs[e.vertices[1]].co
            for k in (.25, .5, .75):
                fn(a.lerp(b, k), grp[e.vertices[0]], f)
        eo.to_mesh_clear()


def check_table(name, step=3):
    """Vertices (no de piernas) dentro de la losa de la mesa: z 0,685..0,715 y delante del canto (y < -0,27)."""
    res = [0, 0.0, ""]

    def fn(co, grp, f):
        if grp in ("Thigh", "Shin", "Foot", "Hips"):
            return
        if co.y < CHECK_EDGE_Y and abs(co.x) < .65 and 0.685 < co.z < 0.712:   # 3 mm de tolerancia
            res[0] += 1
            if 0.715 - co.z > res[1]:
                res[1], res[2] = 0.715 - co.z, f"{grp} @{f / FPS:.2f}s"
    _scan(name, step, fn)
    return res[0], res[1], res[2]


def check_hands(name, step=3):
    """Vertices de brazo/mano sobre el tablero (y < -0,47 y por debajo de la cabeza). Devuelve (n, y minimo)."""
    res = [0, 0.0, ""]

    def fn(co, grp, f):
        if grp in ARM_GROUPS and co.z < 1.0 and co.y < HAND_LIMIT_Y:
            res[0] += 1
            if co.y < res[1]:
                res[1], res[2] = co.y, f"{grp} x={co.x:+.2f} @{f / FPS:.2f}s"
    _scan(name, step, fn)
    return res[0], res[1], res[2]


# Silla (props/furniture.py), con su origen en el del personaje; la silla retirada d metros hacia +Y:
#   asiento x +-0,22, y -0,22..0,22, cara superior z 0,45 | patas delanteras en (+-0,19, -0,19) de 4,5 cm, z 0..0,42
#   travesano delantero x +-0,18, y -0,19, z 0,205..0,235 | respaldo: plano y 0,18, z 0,48..0,89, x +-0,20
SEAT_TOP_TOL = 0.42      # el asiento cuenta como atravesado solo por debajo de 0,42 (el cojin cede 3 cm)


def chair_need(co, grp):
    """Retirada de la silla (m hacia +Y) que necesita este vertice para no atravesarla; 0 si no la toca."""
    x, y, z = abs(co.x), co.y, co.z
    need = 0.0
    if x < .22 and 0.39 < z < SEAT_TOP_TOL and -.22 < y < .22 and y + .22 > .012:
        need = max(need, y + .22)                       # asiento: el vertice debe quedar delante del borde
    if x < .18 and 0.205 < z < 0.235 and -.205 < y < .19:
        need = max(need, y + .205)                      # travesano delantero
    if abs(x - .19) < .0225 and z < .42 and -.2125 < y < -.1675:
        need = max(need, y + .2125)                     # patas delanteras
    if x < .20 and 0.48 < z < 0.89 and y > .18 and grp not in ("Thigh", "Shin", "Foot"):
        need = max(need, y - .18)                       # respaldo (solo tronco/cabeza/brazos)
    return need


CHAIR_WHO = {}


def chair_curve(name, step=1):
    """Retirada minima de la silla por fotograma [(t, d)] para que el clip no la atraviese."""
    out = {}
    CHAIR_WHO.clear()

    def fn(co, grp, f):
        n = chair_need(co, grp)
        if n > out.get(f, 0.0):
            out[f] = n
            CHAIR_WHO[f] = f"{grp} x={co.x:+.2f} y={co.y:+.2f} z={co.z:.2f}"
    _scan(name, step, fn)
    body_frames = range(int(bpy.data.actions[name].frame_range[0]), int(bpy.data.actions[name].frame_range[1]) + 1, step)
    return [(f / FPS, out.get(f, 0.0)) for f in body_frames]


def chair_envelope(curve, margin=0.02):
    """Envolvente no decreciente (la silla nunca vuelve hacia el cuerpo mientras se levanta) con margen."""
    res, m = [], 0.0
    for t, d in curve:
        m = max(m, d + margin if d > 0 else 0.0)
        res.append((t, m))
    return res


def check_chair(name, step=3):
    """Atraviesos de silla con la silla en su sitio (d = 0). Devuelve (n vertices, max penetracion en m)."""
    cur = chair_curve(name, step)
    n = sum(1 for _, d in cur if d > 0)
    fmax = max(cur, key=lambda c: c[1])
    return n, fmax[1], f"{CHAIR_WHO.get(round(fmax[0] * FPS), '')} @{fmax[0]:.2f}s" if fmax[1] > 0 else ""


# ----------------------------------------------------------------------------
# Acciones, guardado y exportacion
# ----------------------------------------------------------------------------
if not os.environ.get("CHAR_PREVIEW"):
    for name, dur, loop, step, fn in ANIMS:
        C.make_action(rig, name, dur, fn, step, loop)
        print(f"accion {name}: {dur}s {'loop' if loop else ''}")

    HANDS_OUT = ("sit_idle", "sit_think", "sit_nervous", "sit_startle", "sit_cough")
    SKIP_TABLE = ("walk", "stand_flee_cycle", "dragged", "death_standing")
    RISE = ("stand_up", "sit_down", "stand_accuse", "stand_flee")
    print("== Comprobacion contra la mesa (losa y> -0,27), el tablero (manos y< -0,47) y la silla ==")
    CHAIR_TABLE = {}
    ONLY = [n for n in os.environ.get("CHAR_ONLY", "").split(",") if n]
    for name, dur, loop, step, fn in ANIMS:
        if name in SKIP_TABLE or (ONLY and name not in ONLY):
            continue
        n, worst, wg = check_table(name, 2)
        msg = f"   {name}: mesa {n} vert. dentro, max {worst * 100:.1f} cm ({wg})"
        if name.startswith(HANDS_OUT):
            nh, ymin, who = check_hands(name, 2)
            msg += f" | tablero {nh} vert. (y min {ymin:.3f} {who})"
        if name in RISE:
            cur = chair_curve(name, 2)
            if name == "sit_down":      # la silla vuelve: la retirada necesaria baja con el tiempo
                env = list(reversed(chair_envelope(list(reversed(cur)))))
                env = [(t, d) for (t, _), (_, d) in zip(cur, env)]
            else:
                env = chair_envelope(cur)
            CHAIR_TABLE[name] = env
            msg += " | silla: retirada minima " + " ".join(
                f"{t:.2f}s:{d:.2f}" for t, d in env[::2]) + f" fin:{env[-1][1]:.2f}"
        elif name.startswith("sit_") or name.startswith("death_slump") or name == "stand_flee":
            nc, cmax, cwho = check_chair(name, 2)
            msg += f" | silla {nc} fotogr. ({cmax * 100:.1f} cm {cwho})"
        print(msg)

    if os.environ.get("CHAR_FAST"):     # iterar sin exportar ni guardar
        raise SystemExit(0)

    # pose de reposo limpia y accion activa para editar
    arm.animation_data.action = bpy.data.actions["sit_idle"]
    bpy.context.scene.frame_set(0)
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = 120

    export_objs = [arm] + meshes
    tris = C.count_tris(meshes)
    print("TRIANGULOS:", tris, {m.name: C.count_tris([m]) for m in meshes})

    root = C.repo_root()
    os.makedirs(os.path.join(root, "assets", "models", "characters"), exist_ok=True)
    C.export_glb(os.path.join(root, "assets", "models", "characters", "player.glb"), export_objs)

    # variantes de pelo: solo Hair_Short visible en el .blend (en el .glb van las tres)
    for o in meshes:
        if o.name in ("Hair_Long", "Hair_Bald"):
            o.hide_set(True)
            o.hide_render = True
    C.save_blend(os.path.join(root, "art", "characters", "player.blend"))
    print("OK player")
