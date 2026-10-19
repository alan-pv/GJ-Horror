"""Herramientas compartidas para construir los personajes del juego (Blender 5.x).

Uso: lo importan build_player.py y build_arbiter.py (mismo directorio).
Todo se construye por codigo: malla low-poly, materiales, esqueleto, pesos y
acciones. Convenciones:
  * Personaje mirando a -Y, origen en el suelo, escala en metros.
  * Lado .L = +X (izquierda del personaje), .R = -X.
  * Rodilla/codo se doblan sobre el eje X local del hueso (X+ = flexion hacia delante).
"""
import copy
import math
import os

import bpy
import bmesh
from mathutils import Vector, Matrix, Euler

V = Vector
FPS = 30

# ----------------------------------------------------------------------------
# Medidas del juego (en el marco del personaje sentado; mesa delante en -Y)
# ----------------------------------------------------------------------------
TABLE_TOP = 0.72
TABLE_CENTER_Y = -0.80
TABLE_EDGE_Y = -0.35
SEAT_Z = 0.45
BOARD_SQ = 0.055
CLOCK_POS = V((-0.42, TABLE_CENTER_Y, TABLE_TOP))    # a la derecha del jugador (-X)
SHEET_POS = V((-0.30, -0.50, TABLE_TOP))             # planilla, derecha-delante


def board_pt(file, rank, z=TABLE_TOP):
    """Centro de la casilla (file 0 = columna a, a la izquierda del jugador; rank 0 = fila mas cercana)."""
    x = 0.22 - (file + 0.5) * BOARD_SQ
    y = TABLE_CENTER_Y + 0.22 - (rank + 0.5) * BOARD_SQ
    return V((x, y, z))


def smooth(u):
    u = max(0.0, min(1.0, u))
    return u * u * (3 - 2 * u)


# ----------------------------------------------------------------------------
# Escena y materiales
# ----------------------------------------------------------------------------
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.unit_settings.system = 'METRIC'
    sc.unit_settings.scale_length = 1.0


def make_material(name, rgb, rough=0.85, metal=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    m.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    return m


def new_collection(name, parent=None):
    c = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(c)
    return c


def link_only(obj, coll):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    coll.objects.link(obj)


# ----------------------------------------------------------------------------
# Esqueleto
# ----------------------------------------------------------------------------
class Shape:
    """Escala base->final: x,y por kx (grosor), z por kz (altura)."""

    def __init__(self, kx=1.0, kz=1.0):
        self.kx, self.kz = kx, kz

    def p(self, x, y, z):
        return V((x * self.kx, y * self.kx, z * self.kz))

    def r(self, r):
        return r * self.kx


def build_armature(sh, arm_len=(0.31, 0.28, 0.09, 0.08)):
    """Crea el Armature 'Armature' con la A-pose. Devuelve el objeto."""
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    arm = bpy.context.object
    arm.name = "Armature"
    arm.data.name = "Armature"
    ed = arm.data.edit_bones
    for b in list(ed):
        ed.remove(b)

    fwd = V((0, -1, 0))
    up = V((0, 0, 1))

    def add(name, head, tail, parent=None, connect=False, hint=fwd):
        b = ed.new(name)
        b.head, b.tail = head, tail
        b.align_roll(hint)
        if parent:
            b.parent = ed[parent]
            b.use_connect = connect
        return b

    P = sh.p
    add("Hips", P(0, 0, .88), P(0, 0, .95))
    add("Spine", P(0, 0, .95), P(0, 0, 1.08), "Hips", True)
    add("Chest", P(0, 0, 1.08), P(0, 0, 1.27), "Spine", True)
    add("Neck", P(0, 0, 1.27), P(0, 0, 1.35), "Chest", True)
    add("Head", P(0, 0, 1.35), P(0, 0, 1.64), "Neck", True)

    L1, L2, L3, L4 = arm_len
    for sd, s in (("L", 1), ("R", -1)):
        def sx(x, y, z, s=s):
            return P(s * x, y, z)
        add(f"Shoulder.{sd}", sx(.03, -.01, 1.24), sx(.18, 0, 1.24), "Chest", False)
        sh_pos = sx(.18, 0, 1.24)
        # A-pose: 30 grados respecto a la vertical, codo ligeramente doblado:
        # el antebrazo se inclina hacia delante (-Y), el codo apunta atras.
        d1 = V((s * .5, .03, -.866)).normalized()
        el = sh_pos + d1 * L1
        d2 = (d1 + V((0, -1, 0)) * math.tan(math.radians(14))).normalized()
        wr = el + d2 * L2
        d3 = (d2 + V((0, -1, 0)) * math.tan(math.radians(8))).normalized()
        kn = wr + d3 * L3
        d4 = (d3 + V((0, -1, 0)) * math.tan(math.radians(10))).normalized()
        tp = kn + d4 * L4
        add(f"UpperArm.{sd}", sh_pos, el, f"Shoulder.{sd}", True)
        add(f"Forearm.{sd}", el, wr, f"UpperArm.{sd}", True)
        add(f"Hand.{sd}", wr, kn, f"Forearm.{sd}", True)
        add(f"Fingers.{sd}", kn, tp, f"Hand.{sd}", True)
        th0 = wr + d3 * (L3 * .25) + V((0, -1, 0)) * 0.012 + V((-s, 0, 0)) * .012
        th_d = (d3 * .6 + V((0, -1, 0)) * .7 + V((-s, 0, 0)) * .15).normalized()
        add(f"Thumb.{sd}", th0, th0 + th_d * .06, f"Hand.{sd}", False)

        hip = sx(.085, 0, .88)
        knee = sx(.088, -.028, .45)
        ank = sx(.088, .006, .075)
        toe = sx(.088, -.19, .03)
        add(f"Thigh.{sd}", hip, knee, "Hips", False)
        add(f"Shin.{sd}", knee, ank, f"Thigh.{sd}", True)
        add(f"Foot.{sd}", ank, toe, f"Shin.{sd}", True, hint=up)

    bpy.ops.object.mode_set(mode='OBJECT')
    return arm


# ----------------------------------------------------------------------------
# Malla: tubos (lofts) con pesos
# ----------------------------------------------------------------------------
class Builder:
    """Acumula geometria en un BMesh con grupos de vertices y materiales por cara."""

    def __init__(self, bone_names, materials):
        self.bm = bmesh.new()
        self.dl = self.bm.verts.layers.deform.verify()
        self.bones = list(bone_names)
        self.mats = list(materials)

    def _vert(self, pos, w):
        v = self.bm.verts.new(pos)
        tot = sum(w.values())
        for bn, wt in w.items():
            v[self.dl][self.bones.index(bn)] = wt / tot
        return v

    def loft(self, rings, n=8, mat="Jacket", e1hint=V((1, 0, 0)), caps=(True, True), phase=0.0):
        """rings: lista de dicts (ver ring()). La banda entre el anillo i y el i+1 usa el 'mat' del anillo i."""
        bm = self.bm
        vr = []
        for rg in rings:
            u = rg["u"].normalized()
            h = rg.get("e1", e1hint)
            e1 = h - u * h.dot(u)
            if e1.length < 1e-3:
                alt = V((0, -1, 0))
                e1 = alt - u * alt.dot(u)
            e1.normalize()
            e2 = u.cross(e1)
            rv = []
            for j in range(n):
                a = phase + 2 * math.pi * j / n
                pos = rg["c"] + e1 * (rg["r1"] * math.cos(a)) + e2 * (rg["r2"] * math.sin(a))
                rv.append(self._vert(pos, rg["w"]))
            vr.append(rv)
        mi = self.mats.index
        for i in range(len(rings) - 1):
            m = mi(rings[i].get("mat", mat))
            for j in range(n):
                f = bm.faces.new((vr[i][j], vr[i][(j + 1) % n], vr[i + 1][(j + 1) % n], vr[i + 1][j]))
                f.material_index = m
        if caps[0]:
            f = bm.faces.new(list(reversed(vr[0])))
            f.material_index = mi(rings[0].get("mat", mat))
        if caps[1]:
            f = bm.faces.new(vr[-1])
            f.material_index = mi(rings[-2].get("mat", mat) if len(rings) > 1 else mat)

    def box(self, c, size, w, mat):
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        pts = [V((sx * hx, sy * hy, sz * hz)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        vs = [self._vert(V(c) + p, w) for p in pts]
        m = self.mats.index(mat)
        for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
            f = self.bm.faces.new([vs[i] for i in q])
            f.material_index = m

    def to_object(self, name, collection, arm=None):
        bmesh.ops.recalc_face_normals(self.bm, faces=list(self.bm.faces))
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for p in me.polygons:
            p.use_smooth = False
        for m in self.mats:
            me.materials.append(bpy.data.materials[m])
        ob = bpy.data.objects.new(name, me)
        collection.objects.link(ob)
        for b in self.bones:
            ob.vertex_groups.new(name=b)
        if arm is not None:
            ob.parent = arm
            md = ob.modifiers.new("Armature", 'ARMATURE')
            md.object = arm
        return ob


def ring(c, u, r1, r2=None, w=None, **kw):
    d = dict(c=V(c), u=V(u), r1=r1, r2=r1 if r2 is None else r2, w=w)
    d.update(kw)
    return d


def limb_rings(pts, radii, bones, mats=None, ratio=1.0):
    """Anillos a lo largo de una cadena de articulaciones (centro de cada segmento incluido).
    pts: articulaciones [j0, j1, j2]; radii: radios en [j0, mid01, j1, mid12, j2].
    bones: hueso de cada segmento. En cada articulacion los pesos se reparten 50/50."""
    nodes = []
    for i in range(len(pts) - 1):
        nodes.append((pts[i], i, 0.0))
        nodes.append(((pts[i] + pts[i + 1]) / 2, i, 0.5))
    nodes.append((pts[-1], len(pts) - 2, 1.0))
    out = []
    for k, (pos, seg, t) in enumerate(nodes):
        if k == 0:
            u = pts[1] - pts[0]
        elif k == len(nodes) - 1:
            u = pts[-1] - pts[-2]
        else:
            u = nodes[k + 1][0] - nodes[k - 1][0]
        if t == 0.0 and seg > 0:
            w = {bones[seg - 1]: .5, bones[seg]: .5}
        elif t == 1.0 and seg < len(bones) - 1:
            w = {bones[seg]: .5, bones[seg + 1]: .5}
        else:
            w = {bones[seg]: 1.0}
        rg = ring(pos, u, radii[k] * ratio, radii[k], w)
        if mats:
            rg["mat"] = mats[min(k, len(mats) - 1)]
        out.append(rg)
    return out


# ----------------------------------------------------------------------------
# Rig de poses (FK/IK analitico propio, sin restricciones de Blender)
# ----------------------------------------------------------------------------
def mat_from_axes(x, y, z, pos):
    m = Matrix.Identity(4)
    for i in range(3):
        m[i][0], m[i][1], m[i][2], m[i][3] = x[i], y[i], z[i], pos[i]
    return m


def lerp_any(a, b, u):
    if isinstance(a, dict):
        return {k: (lerp_any(a[k], b[k], u) if k in b else a[k]) for k in a}
    if isinstance(a, Vector):
        return a.lerp(b, u)
    if isinstance(a, (tuple, list)):
        return tuple(lerp_any(x, y, u) for x, y in zip(a, b))
    if isinstance(a, str) or a is None:
        return a
    return a + (b - a) * u


def merge(base, over):
    out = {}
    for k, v in base.items():
        if k in over and isinstance(v, dict) and isinstance(over[k], dict):
            out[k] = merge(v, over[k])
        elif k in over:
            out[k] = over[k]
        else:
            out[k] = v.copy() if isinstance(v, (Vector, dict)) else v
    for k, v in over.items():
        if k not in out:
            out[k] = v
    return out


class Rig:
    def __init__(self, arm):
        self.arm = arm
        self.bones = arm.data.bones
        self.rest = {b.name: b.matrix_local.copy() for b in self.bones}
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in self.bones}
        self.length = {b.name: b.length for b in self.bones}
        self.pm = {}
        self.basis = {}
        self.warn = []
        self._prevq = {}

    def _base(self, n):
        p = self.parent[n]
        if p is None:
            return self.rest[n]
        return self.pm[p] @ self.rest[p].inverted() @ self.rest[n]

    def fk(self, n, euler=(0, 0, 0), loc=None):
        B = self._base(n)
        rot = Euler([math.radians(a) for a in euler], 'XYZ').to_matrix().to_4x4()
        T = Matrix.Translation(loc if loc is not None else (0, 0, 0))
        basis = T @ rot
        self.basis[n] = basis
        self.pm[n] = B @ basis

    def world(self, n, M):
        B = self._base(n)
        self.basis[n] = B.inverted() @ M
        self.pm[n] = M

    def head(self, n):
        return self.pm[n].translation.copy()

    def tail(self, n):
        return self.pm[n] @ V((0, self.length[n], 0))

    def two_bone(self, b1, b2, target, pole, flex_sign):
        """IK analitico de dos huesos. pole = hacia donde apunta el codo/rodilla."""
        B = self._base(b1)
        S = B.translation.copy()
        L1, L2 = self.length[b1], self.length[b2]
        d = target - S
        D = d.length
        lo, hi = abs(L1 - L2) + 1e-3, (L1 + L2) * 0.9995
        if D > hi:
            self.warn.append((b1, round(D - hi, 3)))
        D2 = min(max(D, lo), hi)
        a = d.normalized()
        tgt = S + a * D2
        d1 = (L1 * L1 - L2 * L2 + D2 * D2) / (2 * D2)
        h = math.sqrt(max(L1 * L1 - d1 * d1, 0.0))
        q = pole - a * pole.dot(a)
        if q.length < 1e-4:
            q = V((0, 1, 0)) - a * a.y
        q.normalize()
        E = S + a * d1 + q * h
        Yu = (E - S).normalized()
        Yf = (tgt - E).normalized()
        f = Yf - Yu * Yf.dot(Yu)
        f = (-q if flex_sign > 0 else q) if f.length < 1e-4 else f.normalized()
        Zu = f * flex_sign
        Xu = Yu.cross(Zu).normalized()
        Zu = Xu.cross(Yu)
        self.world(b1, mat_from_axes(Xu, Yu, Zu, S))
        Zf = Xu.cross(Yf)
        self.world(b2, mat_from_axes(Xu, Yf, Zf, E))
        return tgt

    def solve(self, sp):
        self.pm.clear()
        self.basis.clear()
        self.warn = []
        hb = self._base("Hips")
        loc = hb.to_3x3().inverted() @ sp["hips_off"]
        self.fk("Hips", sp["hips_rot"], loc)
        self.fk("Spine", sp["spine"])
        self.fk("Chest", sp["chest"])
        self.fk("Neck", sp["neck"])
        self.fk("Head", sp["head"])
        for sd in "LR":
            self.fk(f"Shoulder.{sd}", sp["sh" + sd])
        for sd in "LR":
            leg = sp.get("legik" + sd)
            if leg is not None:
                self._leg_ik(sd, leg)
            else:
                self.fk(f"Thigh.{sd}", sp["thigh" + sd])
                self.fk(f"Shin.{sd}", sp["shin" + sd])
                self.fk(f"Foot.{sd}", sp["foot" + sd])
        for sd in "LR":
            self._arm(sd, sp["arm" + sd])
        return self.basis

    def _leg_ik(self, sd, leg):
        b1, b2, b3 = f"Thigh.{sd}", f"Shin.{sd}", f"Foot.{sd}"
        ank = self.two_bone(b1, b2, leg["ankle"], leg.get("pole", V((0, -1, 0))), -1)
        rx = Matrix.Rotation(math.radians(leg.get("pitch", 0.0)), 3, 'X')
        r3 = rx @ self.rest[b3].to_3x3()
        self.world(b3, Matrix.Translation(ank) @ r3.to_4x4())

    def _arm(self, sd, a):
        s = 1 if sd == "L" else -1
        U, F, H = f"UpperArm.{sd}", f"Forearm.{sd}", f"Hand.{sd}"
        S = self._base(U).translation
        wa, wr_, wt = a.get("wabs", 0.0), a.get("wrel", 1.0), a.get("watt", 0.0)
        wsum = wa + wr_ + wt
        wr = V((0, 0, 0))
        if wa:
            wr += a["abs"] * wa
        if wr_:
            wr += (S + a["rel"]) * wr_
        if wt:
            bone, off = a["att"]
            wr += (self.pm[bone] @ off) * wt
        wr /= wsum
        tgt = self.two_bone(U, F, wr, a["pole"], +1)
        Yh = a["hdir"].normalized()
        Zh = a["thumb"] - Yh * a["thumb"].dot(Yh)
        Zh.normalize()
        Xh = Yh.cross(Zh)
        self.world(H, mat_from_axes(Xh, Yh, Zh, tgt))
        self.fk(f"Fingers.{sd}", (0, 0, -s * a["curl"]))
        self.fk(f"Thumb.{sd}", (0, 0, -s * a["thumb_curl"]))

    def default_spec(self):
        sp = dict(hips_off=V((0, 0, 0)), hips_rot=(0, 0, 0), spine=(0, 0, 0), chest=(0, 0, 0),
                  neck=(0, 0, 0), head=(0, 0, 0), shL=(0, 0, 0), shR=(0, 0, 0))
        for sd in "LR":
            s = 1 if sd == "L" else -1
            for k in ("thigh", "shin", "foot"):
                sp[k + sd] = (0, 0, 0)
            U, H = f"UpperArm.{sd}", f"Hand.{sd}"
            rest_hand = self.rest[H]
            sp["arm" + sd] = dict(
                abs=V((0, 0, 0)), rel=rest_hand.translation - self.rest[U].translation,
                att=("Head", V((0, 0, 0))), wabs=0.0, wrel=1.0, watt=0.0,
                pole=V((s * .6, 1.0, -.2)),
                hdir=rest_hand.col[1].to_3d(), thumb=rest_hand.col[2].to_3d(),
                curl=12.0, thumb_curl=0.0)
        return sp

    def apply(self, sp, frame, set_keys=True):
        self.solve(sp)
        for pb in self.arm.pose.bones:
            bs = self.basis[pb.name]
            q = bs.to_quaternion()
            if pb.name in self._prevq:
                q.make_compatible(self._prevq[pb.name])
            self._prevq[pb.name] = q
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = q
            if pb.name == "Hips":
                pb.location = bs.to_translation()
            if set_keys:
                pb.keyframe_insert("rotation_quaternion", frame=frame)
                if pb.name == "Hips":
                    pb.keyframe_insert("location", frame=frame)


# ----------------------------------------------------------------------------
# Acciones
# ----------------------------------------------------------------------------
def action_fcurves(act):
    try:
        return list(act.fcurves)
    except Exception:
        out = []
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    out.extend(cb.fcurves)
        return out


def make_action(rig, name, duration, fn, step=0.1, loop=False, times=None):
    """Crea la accion 'name'. fn(t, u) -> spec; se muestrea cada 'step' s o en la lista 'times'."""
    arm = rig.arm
    if arm.animation_data is None:
        arm.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    rig._prevq = {}
    nf = round(duration * FPS)
    if times is None:
        st = max(1, round(step * FPS))
        frames = sorted(set(list(range(0, nf, st)) + [nf]))
    else:
        frames = sorted(set(round(t * FPS) for t in times))
    for f in frames:
        t = f / FPS
        rig.apply(fn(t, t / duration), f)
        for w in rig.warn:
            print(f"   [{name} t={t:.2f}] fuera de alcance: {w}")
    for fc in action_fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'
            kp.handle_left_type = kp.handle_right_type = 'AUTO_CLAMPED'
        if loop:
            fc.modifiers.new('CYCLES')
    act.use_frame_range = True
    act.frame_start, act.frame_end = 0, nf
    act.use_cyclic = bool(loop)
    return act


# ----------------------------------------------------------------------------
# Escena de referencia (mesa, silla, tablero, reloj, planilla)
# ----------------------------------------------------------------------------
def build_reference(coll):
    mats = {
        "wood": make_material("Ref_Wood", (.25, .15, .08)),
        "dark": make_material("Ref_BoardDark", (.15, .09, .05)),
        "light": make_material("Ref_BoardLight", (.7, .6, .45)),
        "paper": make_material("Ref_Paper", (.9, .9, .85)),
        "clock": make_material("Ref_Clock", (.1, .1, .12)),
    }
    out = []

    def cube(name, c, size, m):
        bpy.ops.mesh.primitive_cube_add(location=tuple(c))
        o = bpy.context.object
        o.name = name
        o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        o.data.materials.append(mats[m])
        link_only(o, coll)
        out.append(o)
        return o

    cy = TABLE_CENTER_Y
    cube("Ref_TableTop", (0, cy, TABLE_TOP - .02), (1.3, .9, .04), "wood")
    for ix in (-1, 1):
        for iy in (-1, 1):
            cube("Ref_TableLeg", (ix * .6, cy + iy * .4, (TABLE_TOP - .04) / 2), (.07, .07, TABLE_TOP - .04), "wood")
    cube("Ref_Board", (0, cy, TABLE_TOP + .01), (.44, .44, .02), "dark")
    sq = []
    for i in range(8):
        for j in range(8):
            if (i + j) % 2 == 0:
                sq.append(cube("Ref_Sq", board_pt(i, j, TABLE_TOP + .0205), (BOARD_SQ, BOARD_SQ, .001), "light"))
    cube("Ref_Clock", CLOCK_POS + V((0, 0, .045)), (.2, .09, .09), "clock")
    cube("Ref_Sheet", SHEET_POS + V((0, 0, .0015)), (.21, .30, .003), "paper")
    cube("Ref_ChairSeat", (0, 0, SEAT_Z - .02), (.44, .44, .04), "wood")
    cube("Ref_ChairBack", (0, .21, SEAT_Z + .22), (.44, .03, .44), "wood")
    for ix in (-1, 1):
        for iy in (-1, 1):
            cube("Ref_ChairLeg", (ix * .19, iy * .19, (SEAT_Z - .04) / 2), (.04, .04, SEAT_Z - .04), "wood")
    cube("Ref_Floor", (0, -.5, -.01), (3, 3, .02), "clock")
    return out


# ----------------------------------------------------------------------------
# Verificacion / exportacion
# ----------------------------------------------------------------------------
def count_tris(objs):
    return sum(len(p.vertices) - 2 for o in objs if o.type == 'MESH' for p in o.data.polygons)


def export_glb(path, objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    kw = dict(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
              export_animations=True, export_animation_mode='ACTIONS',
              export_cameras=False, export_lights=False, export_yup=True, export_skins=True,
              export_optimize_animation_size=False, export_force_sampling=True)
    bpy.ops.export_scene.gltf(**kw)


def save_blend(path):
    bpy.ops.wm.save_as_mainfile(filepath=path)


def repo_root():
    return os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


# ----------------------------------------------------------------------------
# Utilidades de animacion por especificaciones
# ----------------------------------------------------------------------------
def clone(sp):
    return copy.deepcopy(sp)


def seq(t, keys):
    """Interpola (con suavizado) entre especificaciones [(t0, spec0), (t1, spec1), ...]."""
    if t <= keys[0][0]:
        return clone(keys[0][1])
    for (t0, s0), (t1, s1) in zip(keys, keys[1:]):
        if t <= t1:
            return lerp_any(s0, s1, smooth((t - t0) / (t1 - t0)))
    return clone(keys[-1][1])


def arm_set(sp, sd, mode, pos, **kw):
    """Fija el objetivo de la muneca. mode: 'abs' (marco del personaje), 'rel' (relativo al hombro),
    'att' (relativo a un hueso: kw bone=...)."""
    a = sp["arm" + sd]
    a["wabs"], a["wrel"], a["watt"] = {"abs": (1.0, 0.0, 0.0), "rel": (0.0, 1.0, 0.0), "att": (0.0, 0.0, 1.0)}[mode]
    if mode == "abs":
        a["abs"] = V(pos)
    elif mode == "rel":
        a["rel"] = V(pos)
    else:
        a["att"] = (kw.pop("bone", "Head"), V(pos))
    for k, v in kw.items():
        a[k] = V(v) if k in ("pole", "hdir", "thumb") else v
    return sp


def tw(sp, key, d):
    """Suma d (tupla) a un campo euler/vector de la especificacion."""
    v = sp[key]
    if isinstance(v, Vector):
        sp[key] = v + V(d)
    else:
        sp[key] = tuple(a + b for a, b in zip(v, d))
    return sp


def gait(sp, t, T, D, ankle_z, lift=0.07, forward=True, xoff=0.088, duty=0.6, yc=0.0):
    """Ciclo de marcha en el sitio con IK de piernas (sin deslizamiento del pie de apoyo).
    D = recorrido del pie de apoyo respecto al cuerpo, T = periodo del ciclo (2 pasos).
    Velocidad del cuerpo = D / (duty * T)."""
    sgn = 1.0 if forward else -1.0
    for sd, off in (("L", 0.0), ("R", 0.5)):
        ph = ((t / T) + off) % 1.0
        if ph < duty:                       # apoyo: el pie retrocede respecto al cuerpo
            u = ph / duty
            y = (-D / 2 + D * u) * sgn
            z = ankle_z
            pitch = -10.0 * smooth((u - 0.7) / 0.3)
        else:                               # vuelo: el pie avanza
            u = (ph - duty) / (1 - duty)
            y = (D / 2 - D * smooth(u)) * sgn
            z = ankle_z + lift * math.sin(math.pi * u)
            pitch = 12.0 * math.sin(math.pi * u) * (1 - u)
        s = 1 if sd == "L" else -1
        sp["legik" + sd] = dict(ankle=V((s * xoff, yc + y, z)), pitch=pitch, pole=V((s * .05, -1, 0)))
    return sp
