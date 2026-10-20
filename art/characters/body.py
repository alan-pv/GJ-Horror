"""Malla low-poly del cuerpo humano (compartida por jugador y arbitro) con pesos al esqueleto."""
import math

from chartools import V, Builder, ring, limb_rings, make_material, hand_frame, FINGER_DEFS, FINGER_NAMES


def build_body(arm, sh, cfg, coll):
    """Devuelve [cuerpo, hair_short, hair_long, hair_bald] (objetos ya enlazados a 'coll').
    cfg: colores (dict nombre->rgb), hem (z base del borde de la chaqueta), mask (bool), gloves (bool),
    tie (bool), nose (bool), eyes (bool), n (lados)."""
    for name, (rgb, rough) in cfg["colors"].items():
        make_material(name, rgb, rough)
    mats = list(cfg["colors"].keys())
    bones = [b.name for b in arm.data.bones]
    bd = Builder(bones, mats)
    P, R = sh.p, sh.r
    bn = arm.data.bones
    N = cfg.get("n", 10)
    jacket = "Jacket"
    hand_mat = "Gloves" if cfg.get("gloves") else "Skin"
    head_mat = "Mask" if cfg.get("mask") else "Skin"

    # ---- torso ----------------------------------------------------------------
    hem = cfg.get("hem", .85)
    T = [  # z, rx, ry, cy, pesos, material de la banda siguiente
        (hem - .05, .125, .095, 0, {"Hips": 1}, "Pants"),
        (hem, cfg.get("hemw", .165), .105, 0, {"Hips": 1}, jacket),
        (.95, .155, .10, 0, {"Hips": .6, "Spine": .4}, jacket),
        (1.04, .148, .095, 0, {"Spine": 1}, jacket),
        (1.12, .155, .10, -.005, {"Spine": .5, "Chest": .5}, jacket),
        (1.20, .18, .108, -.01, {"Chest": 1}, jacket),
        (1.27, .185, .10, -.005, {"Chest": 1}, jacket),
        (1.305, .095, .075, 0, {"Chest": .6, "Neck": .4}, jacket),
    ]
    rings = [ring(P(0, cy, z), (0, 0, 1), R(rx), R(ry), w, mat=m) for z, rx, ry, cy, w, m in T]
    bd.loft(rings, n=N, e1hint=V((1, 0, 0)))

    # panel de camisa (y corbata) en el pecho
    bd.box(P(0, -.1195, 1.17), (R(.075), R(.006), .2 * sh.kz), {"Chest": .7, "Spine": .3}, "Shirt")
    if cfg.get("tie"):
        bd.box(P(0, -.1235, 1.15), (R(.026), R(.006), .16 * sh.kz), {"Chest": .7, "Spine": .3}, "Tie")

    # ---- cuello y cabeza ----------------------------------------------------------
    nk = [
        ring(P(0, 0, 1.28), (0, 0, 1), R(.07), R(.07), {"Chest": .6, "Neck": .4}, mat="Shirt"),
        ring(P(0, 0, 1.325), (0, 0, 1), R(.058), R(.058), {"Neck": 1}, mat="Skin"),
        ring(P(0, 0, 1.36), (0, 0, 1), R(.048), R(.048), {"Neck": .5, "Head": .5}, mat="Skin"),
        ring(P(0, 0, 1.42), (0, 0, 1), R(.046), R(.046), {"Head": 1}, mat="Skin"),
    ]
    bd.loft(nk, n=8, caps=(False, True))

    H = [(1.40, .035, .05, -.025), (1.43, .065, .075, -.015), (1.47, .082, .10, -.005),
         (1.52, .09, .108, 0), (1.57, .092, .108, 0), (1.61, .085, .10, 0),
         (1.65, .065, .082, .005), (1.675, .035, .05, .01)]
    hr = [ring(P(0, cy, z), (0, 0, 1), R(rx), R(ry), {"Head": 1}, mat=head_mat) for z, rx, ry, cy in H]
    bd.loft(hr, n=N, e1hint=V((1, 0, 0)))
    if cfg.get("nose"):
        nr = [ring(P(0, -.097, 1.50), (0, -1, -.25), R(.016), R(.018), {"Head": 1}),
              ring(P(0, -.115, 1.495), (0, -1, -.25), R(.011), R(.012), {"Head": 1}),
              ring(P(0, -.128, 1.49), (0, -1, -.25), R(.005), R(.006), {"Head": 1})]
        bd.loft(nr, n=5, mat="Skin")
    if cfg.get("eyes"):
        for s in (1, -1):
            bd.box(P(s * .036, -.104, 1.548), (R(.024), R(.012), .012 * sh.kz), {"Head": 1}, "Eyes")
    for s in (1, -1):
        bd.box(P(s * .092, .0, 1.525), (R(.012), R(.03), .04 * sh.kz), {"Head": 1}, head_mat)

    # ---- brazos ------------------------------------------------------------------------
    for sd, s in (("L", 1), ("R", -1)):
        sp_, el, wr = bn[f"UpperArm.{sd}"].head_local, bn[f"Forearm.{sd}"].head_local, bn[f"Hand.{sd}"].head_local
        rad = [R(.052), R(.05), R(.043), R(.04), R(.032)]
        rs = limb_rings([sp_, el, wr], rad, [f"UpperArm.{sd}", f"Forearm.{sd}"])
        rs[0]["w"] = {"Chest": .35, f"Shoulder.{sd}": .15, f"UpperArm.{sd}": .5}
        for r_ in rs:
            r_["mat"] = jacket
        # puño de camisa
        cuff = ring(rs[3]["c"].lerp(rs[4]["c"], .78), rs[4]["u"], R(.036), R(.036),
                    {f"Forearm.{sd}": 1}, mat="Shirt")
        rs.insert(4, cuff)
        rs[-1]["r1"] = rs[-1]["r2"] = R(.035)
        rs[-1]["w"] = {f"Forearm.{sd}": .6, f"Hand.{sd}": .4}
        bd.loft(rs, n=N)
        # mano
        _hand(bd, bn, sd, s, R, hand_mat)

    # ---- piernas y zapatos -------------------------------------------------------------
    pr = cfg.get("leg_r", 1.0)
    for sd, s in (("L", 1), ("R", -1)):
        hip, kn, an = bn[f"Thigh.{sd}"].head_local, bn[f"Shin.{sd}"].head_local, bn[f"Shin.{sd}"].tail_local
        rad = [R(.088 * pr), R(.082 * pr), R(.066 * pr), R(.058 * pr), R(.043 * pr)]
        rs = limb_rings([hip, kn, an], rad, [f"Thigh.{sd}", f"Shin.{sd}"], mats=["Pants"])
        rs[0]["w"] = {"Hips": .4, f"Thigh.{sd}": .6}
        rs[-1]["w"] = {f"Shin.{sd}": .5, f"Foot.{sd}": .5}
        bd.loft(rs, n=N)
        fb = bn[f"Foot.{sd}"]
        x = fb.head_local.x
        sr = [
            ring(V((x, .052 * sh.kx, .045 * sh.kz)), (0, -1, 0), R(.044), .043 * sh.kz, {f"Shin.{sd}": .3, f"Foot.{sd}": .7}, mat="Shoes"),
            ring(V((x, -.03 * sh.kx, .042 * sh.kz)), (0, -1, 0), R(.047), .045 * sh.kz, {f"Foot.{sd}": 1}, mat="Shoes"),
            ring(V((x, -.12 * sh.kx, .034 * sh.kz)), (0, -1, 0), R(.051), .036 * sh.kz, {f"Foot.{sd}": 1}, mat="Shoes"),
            ring(V((x, -.2 * sh.kx, .026 * sh.kz)), (0, -1, 0), R(.04), .026 * sh.kz, {f"Foot.{sd}": 1}, mat="Shoes"),
        ]
        bd.loft(sr, n=8, e1hint=V((1, 0, 0)))

    body = bd.to_object("Body", coll, arm)

    # ---- peinados ------------------------------------------------------------------------
    def hair(name, rows, n=9):
        b = Builder(bones, mats)
        rr = [ring(P(0, cy, z), (0, 0, 1), R(rx), R(ry), {"Head": 1}, mat="Hair") for z, rx, ry, cy in rows]
        b.loft(rr, n=n)
        return b.to_object(name, coll, arm)

    short = hair("Hair_Short", [(1.575, .1, .105, .03), (1.61, .1, .112, .022), (1.645, .088, .1, .014),
                                (1.675, .06, .075, .01), (1.692, .022, .036, .01)])
    long_ = hair("Hair_Long", [(1.36, .07, .05, .095), (1.42, .088, .075, .085), (1.48, .1, .1, .06),
                               (1.54, .105, .115, .035), (1.595, .104, .115, .025), (1.645, .09, .102, .014),
                               (1.675, .062, .076, .01), (1.693, .022, .036, .01)])
    bald = hair("Hair_Bald", [(1.585, .096, .114, .014), (1.625, .089, .107, .01), (1.66, .069, .086, .007),
                              (1.682, .036, .052, .008)])
    return [body, short, long_, bald]


def _hand(bd, bn, sd, s, R, mat):
    """Palma (loft de ocho lados) y cinco dedos (lofts de seis lados). Cada anillo de nudillo reparte
    sus pesos entre las dos falanges vecinas; la palma queda rigida (solo Forearm/Hand)."""
    hb = bn[f"Hand.{sd}"]
    hd, w, n = hand_frame(hb.tail_local - hb.head_local, s)
    e1 = V((0, 1, 0))
    H, T = hb.head_local, hb.tail_local
    hr_ = [
        ring(H, hd, R(.030), R(.021), {f"Forearm.{sd}": .4, f"Hand.{sd}": .6}, e1=e1, mat=mat),
        ring(H.lerp(T, .5), hd, R(.042), R(.0165), {f"Hand.{sd}": 1}, e1=e1, mat=mat),
        ring(T, hd, R(.041), R(.0135), {f"Hand.{sd}": 1}, e1=e1, mat=mat),
    ]
    bd.loft(hr_, n=8)

    def finger(names, radii):
        """names: tres huesos; radii: radios [base, mitad1, nudillo1, mitad2, nudillo2, mitad3, punta]."""
        bs = [bn[f"{nm}.{sd}"] for nm in names]
        pts = [bs[0].head_local, bs[1].head_local, bs[2].head_local, bs[2].tail_local]
        dirs = [(b.tail_local - b.head_local).normalized() for b in bs]
        z = (bs[0].matrix_local.to_3x3() @ V((0, 0, 1))).normalized()
        def ax(i):      # eje del anillo en la articulacion i: bisectriz de las falanges vecinas
            if i == 0:
                return dirs[0]
            if i == 3:
                return dirs[2]
            return (dirs[i - 1] + dirs[i]).normalized()
        P_ = f"Hand.{sd}"
        rings = [
            ring(pts[0], ax(0), radii[0], radii[0] * .88, {P_: .5, bs[0].name: .5}, e1=z, mat=mat),
            ring(pts[0].lerp(pts[1], .5), dirs[0], radii[1], radii[1] * .88, {bs[0].name: 1}, e1=z, mat=mat),
            ring(pts[1], ax(1), radii[2], radii[2] * .88, {bs[0].name: .5, bs[1].name: .5}, e1=z, mat=mat),
            ring(pts[1].lerp(pts[2], .5), dirs[1], radii[3], radii[3] * .88, {bs[1].name: 1}, e1=z, mat=mat),
            ring(pts[2], ax(2), radii[4], radii[4] * .88, {bs[1].name: .5, bs[2].name: .5}, e1=z, mat=mat),
            ring(pts[2].lerp(pts[3], .55), dirs[2], radii[5], radii[5] * .88, {bs[2].name: 1}, e1=z, mat=mat),
            ring(pts[3], ax(3), radii[6], radii[6] * .88, {bs[2].name: 1}, e1=z, mat=mat),
        ]
        bd.loft(rings, n=6, caps=(False, True))

    for nm in FINGER_NAMES:
        r = R(FINGER_DEFS[nm][4])
        # nudillos algo mas gruesos que las falanges; la yema se afina
        finger([f"{nm}{i}" for i in (1, 2, 3)],
               [r * .98, r * .92, r * 1.0, r * .88, r * .93, r * .84, r * .55])
    r = R(.0115)
    finger([f"Thumb{i}" for i in (1, 2, 3)],
           [r * 1.35, r * 1.2, r * 1.05, r * .98, r * .98, r * .92, r * .6])
