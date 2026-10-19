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
    hem=.85, nose=True, eyes=True, tie=False, n=12,
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


def make_sit():
    sp = rig.default_spec()
    sp["hips_off"] = V((0, -0.03, 0.54 - HIP_Z))
    sp.update(spine=(8, 0, 0), chest=(8, 0, 0), neck=(-2, 0, 0), head=(6, 0, 0))
    a = fit_sit_legs(sp, 0.54)
    for sd in "LR":
        sp["thigh" + sd] = (a, 0, 0)
        sp["shin" + sd] = (-a, 0, 0)
        s = 1 if sd == "L" else -1
        C.arm_set(sp, sd, "abs", (s * .19, -.50, .768), pole=(s * .9, .6, .45),
                  hdir=(-s * .12, -1, .02), thumb=(-s, 0, .3), curl=14.0, thumb_curl=6.0)
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
# Sentado: reposo, pensar, nervioso, mirar
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
    sp.update(spine=(13, 0, 2), chest=(9, 0, 0), neck=(2, 0, 0), head=(9, 4, -6))
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
    tw(sp, "thighR", (3.5 * bounce, 0, 0))
    tw(sp, "shinR", (-3.5 * bounce - 1.5 * abs(bounce), 0, 0))
    tw(sp, "hips_off", (0.0, 0.0, 0.004 * bounce))
    tw(sp, "shL", (0, 0, 2.5)), tw(sp, "shR", (0, 0, 2.5))
    sp["armL"]["curl"] += 14 * max(0, sin(5 * w))
    sp["armR"]["curl"] += 14 * max(0, sin(5 * w + 2))
    return sp


def look_pose(sgn):
    sp = clone(SIT)
    tw(sp, "spine", (0, sgn * 8, 0))
    tw(sp, "chest", (0, sgn * 12, 0))
    tw(sp, "neck", (0, sgn * 14, 0))
    tw(sp, "head", (-3, sgn * 32, 0))
    return sp


@anim("sit_look_left", 0.8, False, 0.05)
def _(t, u):
    return seq(t, [(0, clone(SIT)), (0.4, look_pose(1)), (0.8, look_pose(1))])


@anim("sit_look_right", 0.8, False, 0.05)
def _(t, u):
    return seq(t, [(0, clone(SIT)), (0.4, look_pose(-1)), (0.8, look_pose(-1))])


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
        (0.35, reach(SIT, src, 8, lift=.09)),
        (0.52, reach(SIT, src, 8, lift=.0)),
        (0.62, reach(SIT, src, 42, lift=.0)),
        (0.80, reach(SIT, src.lerp(dst, .2), 42, lift=.12)),
        (1.05, reach(SIT, dst, 42, lift=.12, yaw=-5)),
        (1.22, reach(SIT, dst, 42, lift=.0, yaw=-5)),
        (1.32, reach(SIT, dst, 8, lift=.0, yaw=-5)),
        (1.45, reach(SIT, dst, 8, lift=.08, yaw=-5)),
        (1.80, clone(SIT)),
    ]
    return seq(t, keys)


CLOCK_TOP = TABLE_TOP + .09


def clock_pose(z, lean_k=1.0):
    sp = clone(SIT)
    lean(sp, 12 * lean_k, 14 * lean_k, -12, -0.06 * lean_k)
    tw(sp, "head", (-8, 0, 0))
    arm_set(sp, "R", "abs", (CLOCK_POS.x - .02, CLOCK_POS.y + .06, z), pole=(-.8, .5, .2),
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
@anim("sit_beg", 2.4, True, 0.1)
def _(t, u):
    sp = clone(SIT)
    w = 2 * pi * u
    sp.update(spine=(13, 0, 0), chest=(10, 0, 0), neck=(-8, 0, 0), head=(-16, 0, 0))
    lean(sp, 0, 0, 0, -0.04)
    pump = sin(2 * w)
    for sd, s in (("L", 1), ("R", -1)):
        arm_set(sp, sd, "abs", (s * .035, -.34 - .02 * pump, .86 + .03 * pump), pole=(s * .6, .3, -1),
                hdir=(0, -.5, .85), thumb=(0, .85, .5), curl=55.0, thumb_curl=15.0)
    tw(sp, "head", (1.5 * sin(6 * w), 0, 1.2 * sin(5 * w)))
    tw(sp, "shL", (0, 0, 1.5 * sin(6 * w))), tw(sp, "shR", (0, 0, -1.5 * sin(6 * w)))
    tw(sp, "chest", (2.0 * pump, 0, 0))
    return sp


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
    tw(sp, "hips_off", (0, 0.02, 0))
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
    keys = [(0.0, S0), (0.14, s1), (0.55, s2), (0.8, s3), (1.05, s4), (1.25, s5), (1.45, s6), (1.7, s7), (2.0, s8)]
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
    tw(sp, "hips_off", (0, 0.06, 0.012))
    arm_set(sp, "R", "abs", (-.20, -.60, .775), pole=(-.9, .4, .2), hdir=(.1, -1, -.05), thumb=(1, 0, .3),
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
        arm_set(sp, sd, "abs", (s * .21, -.46, .79), pole=(s * .9, .6, .1), hdir=(0, -1, .1), thumb=(-s, 0, .3),
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


def lying_back(hip_y, hip_z, thigh=0.0, shin=0.0):
    sp = clone(SIT)
    sp["hips_off"] = V((0, hip_y, hip_z - HIP_Z))
    sp["hips_rot"] = (-90, 0, 0)
    sp.update(spine=(4, 0, 0), chest=(2, 0, 0), neck=(-6, 8, 0), head=(-4, 22, 0))
    for sd, s in (("L", 1), ("R", -1)):
        sp["thigh" + sd] = (thigh + s * 4, 0, s * 6)
        sp["shin" + sd] = (shin - 6, 0, 0)
        sp["foot" + sd] = (0, 0, 0)
    arm_set(sp, "L", "abs", (.62, hip_y + .55, .09), pole=(.5, 0, 1), hdir=(.8, .3, -.2), thumb=(0, 1, .2), curl=25.0,
            thumb_curl=10.0)
    arm_set(sp, "R", "abs", (-.45, hip_y + .75, .09), pole=(-.5, 0, 1), hdir=(-.5, .8, -.2), thumb=(0, 0, 1), curl=40.0,
            thumb_curl=10.0)
    return sp


@anim("death_fall_back", 1.5, False, 0.05)
def _(t, u):
    snap = shot_snap()
    a1 = clone(SIT)
    a1.update(spine=(-5, 0, 0), chest=(-8, 0, 0), neck=(-10, 0, 0), head=(-28, 0, 0))
    a1["hips_rot"] = (-14, 0, 0)
    tw(a1, "hips_off", (0, 0.05, 0.02))
    for sd in "LR":
        a1["thigh" + sd] = (95, 0, 0)
        a1["shin" + sd] = (-80, 0, 0)
        s = 1 if sd == "L" else -1
        arm_set(a1, sd, "rel", (s * .3, .1, .3), pole=(s * .5, .5, 0), hdir=(s * .3, -.4, .9), thumb=(-s, 0, 0),
                curl=5.0, thumb_curl=0.0)
    a2 = clone(a1)
    a2["hips_rot"] = (-58, 0, 0)
    tw(a2, "hips_off", (0, 0.28, 0.0))
    for sd in "LR":
        a2["thigh" + sd] = (105, 0, 0)
        a2["shin" + sd] = (-45, 0, 0)
    a2.update(spine=(-2, 0, 0), chest=(0, 0, 0), neck=(-8, 0, 0), head=(-14, 0, 0))
    a3 = lying_back(0.78, 0.13, 6, -4)
    a4 = lying_back(0.80, 0.115, 0, 0)
    a4["spine"] = (3, 0, 0)
    keys = [(0.0, clone(SIT)), (0.08, snap), (0.22, a1), (0.7, a2), (1.1, a3), (1.5, a4)]
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
# Verificacion de penetracion contra la mesa
# ----------------------------------------------------------------------------
def check_table(name, step=3):
    """Cuenta vertices de brazo/cabeza/torso dentro de la losa de la mesa (z 0.68..0.72, y < borde)."""
    body = bpy.data.objects["Body"]
    dg = bpy.context.evaluated_depsgraph_get()
    act = bpy.data.actions[name]
    arm.animation_data.action = act
    bad_total, worst, wg = 0, 0.0, ""
    names = [g.name for g in body.vertex_groups]
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    for f in range(f0, f1 + 1, step):
        bpy.context.scene.frame_set(f)
        eo = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
        me = eo.to_mesh()
        orig = body.data.vertices
        for i, v in enumerate(me.vertices):
            if not (v.co.y < TABLE_EDGE_Y and abs(v.co.x) < .65 and 0.685 < v.co.z < 0.715):
                continue
            g = max(orig[i].groups, key=lambda x: x.weight).group
            if names[g].split(".")[0] in ("Thigh", "Shin", "Foot", "Hips"):
                continue
            bad_total += 1
            if 0.715 - v.co.z > worst:
                worst, wg = 0.715 - v.co.z, names[g]
        eo.to_mesh_clear()
    return bad_total, worst, wg


# ----------------------------------------------------------------------------
# Acciones, guardado y exportacion
# ----------------------------------------------------------------------------
if not os.environ.get("CHAR_PREVIEW"):
    for name, dur, loop, step, fn in ANIMS:
        C.make_action(rig, name, dur, fn, step, loop)
        print(f"accion {name}: {dur}s {'loop' if loop else ''}")

    print("== Comprobacion contra la mesa (vertices de brazo/torso/cabeza dentro de la losa) ==")
    for name, dur, loop, step, fn in ANIMS:
        if name.startswith("sit_") or name.startswith("death_slump"):
            n, worst, wg = check_table(name)
            print(f"   {name}: {n} vertices dentro, penetracion max {worst * 100:.1f} cm ({wg})")

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
