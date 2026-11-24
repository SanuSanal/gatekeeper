"""Generates the GateKeeper logo concept SVGs from exact geometry (filled paths only, no strokes/text).

Run: python design/logo/build_concepts.py
"""
import math
from pathlib import Path

OUT = Path(__file__).parent / "concepts"
OUT.mkdir(parents=True, exist_ok=True)


def pt(cx, cy, r, deg):
    a = math.radians(deg)
    return cx + r * math.cos(a), cy + r * math.sin(a)  # SVG coords: +deg is clockwise


def f(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def capsule(x0, y0, deg, length, t):
    """Bar with round ends; centreline from (x0,y0) for `length` at angle `deg`."""
    r = t / 2
    x1, y1 = pt(x0, y0, length, deg)
    nx, ny = pt(0, 0, r, deg - 90)  # normal (left side)
    pts = [(x0 + nx, y0 + ny), (x1 + nx, y1 + ny), (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)]
    d = (f"M{f(pts[0][0])} {f(pts[0][1])}L{f(pts[1][0])} {f(pts[1][1])}"
         f"A{f(r)} {f(r)} 0 0 1 {f(pts[2][0])} {f(pts[2][1])}"
         f"L{f(pts[3][0])} {f(pts[3][1])}A{f(r)} {f(r)} 0 0 1 {f(pts[0][0])} {f(pts[0][1])}Z")
    box = [(x0 - r, y0 - r), (x0 + r, y0 + r), (x1 - r, y1 - r), (x1 + r, y1 + r)]
    return d, box


def ring_arc(cx, cy, ri, ro, a0, a1, round_caps=False):
    """Thick arc from angle a0 clockwise to a1 (degrees, a1 > a0)."""
    span = a1 - a0
    large = 1 if span > 180 else 0
    o0, o1 = pt(cx, cy, ro, a0), pt(cx, cy, ro, a1)
    i0, i1 = pt(cx, cy, ri, a0), pt(cx, cy, ri, a1)
    cap = (ro - ri) / 2
    join1 = f"A{f(cap)} {f(cap)} 0 0 1 {f(i1[0])} {f(i1[1])}" if round_caps else f"L{f(i1[0])} {f(i1[1])}"
    join0 = f"A{f(cap)} {f(cap)} 0 0 1 {f(o0[0])} {f(o0[1])}" if round_caps else "Z"
    d = (f"M{f(o0[0])} {f(o0[1])}A{f(ro)} {f(ro)} 0 {large} 1 {f(o1[0])} {f(o1[1])}"
         f"{join1}A{f(ri)} {f(ri)} 0 {large} 0 {f(i0[0])} {f(i0[1])}{join0}")
    if round_caps:
        d += "Z"
    box = []
    for k in range(0, 721):
        a = a0 + span * k / 720
        for r in (ri, ro):
            box.append(pt(cx, cy, r, a))
    if round_caps:
        for a in (a0, a1):
            mx, my = pt(cx, cy, (ri + ro) / 2, a)
            box += [(mx - cap, my - cap), (mx + cap, my + cap)]
    return d, box


def disc(cx, cy, r, hole=None):
    d = f"M{f(cx - r)} {f(cy)}a{f(r)} {f(r)} 0 1 0 {f(2 * r)} 0a{f(r)} {f(r)} 0 1 0 {f(-2 * r)} 0Z"
    if hole:
        d += f"M{f(cx - hole)} {f(cy)}a{f(hole)} {f(hole)} 0 1 0 {f(2 * hole)} 0a{f(hole)} {f(hole)} 0 1 0 {f(-2 * hole)} 0Z"
    return d, [(cx - r, cy - r), (cx + r, cy + r)]


def write(name, shapes, pad=22, optical_lift=3):
    """Fit all shapes into the 256 canvas with `pad`, centred (slightly above centre optically)."""
    pts = [p for _, box in shapes for p in box]
    minx, maxx = min(p[0] for p in pts), max(p[0] for p in pts)
    miny, maxy = min(p[1] for p in pts), max(p[1] for p in pts)
    w, h = maxx - minx, maxy - miny
    s = (256 - 2 * pad) / max(w, h)
    tx = (256 - w * s) / 2 - minx * s
    ty = (256 - h * s) / 2 - miny * s - optical_lift
    body = "".join(f'<path d="{d}"/>' for d, _ in shapes)
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">'
           f'<g fill="#000" fill-rule="evenodd" transform="matrix({f(s)} 0 0 {f(s)} {f(tx)} {f(ty)})">{body}</g></svg>\n')
    (OUT / f"{name}.svg").write_text(svg)
    print(name, f"scale={s:.3f}")


# A - "Sweep": a barrier arm lifting from its pivot; the area it has swept is the geofence wedge.
P = (70, 190)
write("a-sweep", [
    disc(*P, 29, hole=13),
    capsule(*pt(*P, 29, -60), -60, 148, 32),
    ring_arc(*P, 90, 166, -45, 0),
])

# B - "G-gate": a G whose crossbar is the barrier arm, lifted out through the opening.
C = (128, 128)
write("b-ggate", [
    ring_arc(*C, 62, 100, 15, 315),
    capsule(*C, -15, 104, 36),
])

# C - "Lift": the lifting arm drawn as rising signal bars around one pivot (calling + opening).
Q = (60, 206)
write("c-lift", [
    disc(*Q, 25),
    capsule(*pt(*Q, 72, 0), 0, 44, 26),
    capsule(*pt(*Q, 72, -30), -30, 82, 26),
    capsule(*pt(*Q, 72, -60), -60, 120, 26),
])


# ---- Round 2 (no ring-and-stick: A read as a power button) -----------------------------------

def rect(x0, y0, x1, y1):
    return f"M{f(x0)} {f(y0)}H{f(x1)}V{f(y1)}H{f(x0)}Z", [(x0, y0), (x1, y1)]


def capsule_between(x0, y0, x1, y1, t):
    deg = math.degrees(math.atan2(y1 - y0, x1 - x0))
    return capsule(x0, y0, deg, math.hypot(x1 - x0, y1 - y0), t)


def bar_segments(x0, y0, deg, length, t, cuts, gap):
    """A straight bar split by `gap`-wide cuts at the given distances (barrier stripes in mono)."""
    shapes, start = [], 0.0
    stops = [c - gap / 2 for c in cuts] + [length]
    for i, stop in enumerate(stops):
        sx, sy = pt(x0, y0, start, deg)
        ex, ey = pt(x0, y0, stop, deg)
        r = t / 2
        nx, ny = pt(0, 0, r, deg - 90)
        if i == 0 or i == len(stops) - 1:
            # round outer end only
            if i == 0:
                d = (f"M{f(ex + nx)} {f(ey + ny)}L{f(sx + nx)} {f(sy + ny)}"
                     f"A{f(r)} {f(r)} 0 0 0 {f(sx - nx)} {f(sy - ny)}L{f(ex - nx)} {f(ey - ny)}Z")
            else:
                d = (f"M{f(sx + nx)} {f(sy + ny)}L{f(ex + nx)} {f(ey + ny)}"
                     f"A{f(r)} {f(r)} 0 0 1 {f(ex - nx)} {f(ey - ny)}L{f(sx - nx)} {f(sy - ny)}Z")
        else:
            d = (f"M{f(sx + nx)} {f(sy + ny)}L{f(ex + nx)} {f(ey + ny)}"
                 f"L{f(ex - nx)} {f(ey - ny)}L{f(sx - nx)} {f(sy - ny)}Z")
        shapes.append((d, [(sx - r, sy - r), (sx + r, sy + r), (ex - r, ey - r), (ex + r, ey + r)]))
        start = stop + gap
    return shapes


def bar_round_end(x0, y0, deg, length, t):
    """Bar with a butt start (joins another piece) and a round far end."""
    r = t / 2
    x1, y1 = pt(x0, y0, length, deg)
    nx, ny = pt(0, 0, r, deg - 90)
    d = (f"M{f(x0 + nx)} {f(y0 + ny)}L{f(x1 + nx)} {f(y1 + ny)}"
         f"A{f(r)} {f(r)} 0 0 1 {f(x1 - nx)} {f(y1 - ny)}L{f(x0 - nx)} {f(y0 - ny)}Z")
    return d, [(x0 - r, y0 - r), (x0 + r, y0 + r), (x1 - r, y1 - r), (x1 + r, y1 + r)]


# D - "Pass": a tick whose long stroke is the lifted, striped barrier arm.
V = (100, 196)
write("d-pass", [
    capsule(*V, -135, 62, 36),
    *bar_segments(*V, -45, 170, 36, cuts=[82, 128], gap=11),
])

# E - "Enter": a rounded-square zone with a gap; a dot (you) passing through it.
T, R, H = 28, 46, 100  # stroke, corner radius (centreline), half-size
O = 0.8  # overlap between abutting pieces (hides anti-alias seams)
c0, c1 = 128 - H, 128 + H
ri, ro = R - T / 2, R + T / 2
gap_l, gap_r = 128 - 54, 128 + 54
write("e-enter", [
    ring_arc(c0 + R, c0 + R, ri, ro, 180, 270),
    ring_arc(c1 - R, c0 + R, ri, ro, 270, 360),
    ring_arc(c1 - R, c1 - R, ri, ro, 0, 90),
    ring_arc(c0 + R, c1 - R, ri, ro, 90, 180),
    rect(c0 + R - O, c0 - T / 2, c1 - R + O, c0 + T / 2),
    rect(c1 - T / 2, c0 + R - O, c1 + T / 2, c1 - R + O),
    rect(c0 - T / 2, c0 + R - O, c0 + T / 2, c1 - R + O),
    bar_round_end(c0 + R - O, c1, 0, gap_l - (c0 + R - O), T),
    bar_round_end(c1 - R + O, c1, 180, (c1 - R + O) - gap_r, T),
    disc(128, c1, 24),
])

# F - "Lift": the zone's top edge swings up like a barrier arm (reads as a squared G that opens).
hx, hy = pt(c0 + R, c0 + R, R, 240)  # corner turns to 240 deg, where its tangent is exactly -30 deg
write("f-lift", [
    ring_arc(c0 + R, c0 + R, ri, ro, 180, 240),
    ring_arc(c1 - R, c1 - R, ri, ro, 0, 90),
    ring_arc(c0 + R, c1 - R, ri, ro, 90, 180),
    rect(c0 - T / 2, c0 + R - O, c0 + T / 2, c1 - R + O),
    rect(c0 + R - O, c1 - T / 2, c1 - R + O, c1 + T / 2),
    bar_round_end(c1, c1 - R + O, -90, (c1 - R + O) - (c0 + 70), T),
    bar_round_end(hx - O * 0.866, hy + O * 0.5, -30, 170, T),
])


# ---- Round 3: car + gate ------------------------------------------------------------------------

def car_front(cx, base, k=1.0):
    """Front view of a car as one silhouette outline plus holes (windshield, headlights, grille).
    Returned as (outline, holes) path strings so it can be used positive or as negative space."""
    def X(v): return f(cx + v * k)
    def Y(v): return f(base + v * k)
    def R(v): return f(v * k)
    r, tr = 16, 5
    outline = (
        f"M{X(-54)} {Y(-62)}H{X(-50)}L{X(-38)} {Y(-98)}Q{X(-36)} {Y(-104)} {X(-30)} {Y(-104)}"
        f"H{X(30)}Q{X(36)} {Y(-104)} {X(38)} {Y(-98)}L{X(50)} {Y(-62)}H{X(54)}"
        f"A{R(r)} {R(r)} 0 0 1 {X(70)} {Y(-46)}V{Y(-26)}A{R(r)} {R(r)} 0 0 1 {X(54)} {Y(-10)}"
        f"H{X(52)}V{Y(-1)}A{R(tr)} {R(tr)} 0 0 1 {X(47)} {Y(4)}H{X(35)}A{R(tr)} {R(tr)} 0 0 1 {X(30)} {Y(-1)}V{Y(-10)}"
        f"H{X(-30)}V{Y(-1)}A{R(tr)} {R(tr)} 0 0 1 {X(-35)} {Y(4)}H{X(-47)}A{R(tr)} {R(tr)} 0 0 1 {X(-52)} {Y(-1)}V{Y(-10)}"
        f"H{X(-54)}A{R(r)} {R(r)} 0 0 1 {X(-70)} {Y(-26)}V{Y(-46)}A{R(r)} {R(r)} 0 0 1 {X(-54)} {Y(-62)}Z"
    )
    holes = (
        f"M{X(-38)} {Y(-68)}L{X(-29)} {Y(-94)}H{X(29)}L{X(38)} {Y(-68)}Z"   # windshield
        + disc(cx - 46 * k, base - 37 * k, 9.5 * k)[0]                      # headlights
        + disc(cx + 46 * k, base - 37 * k, 9.5 * k)[0]
        + f"M{X(-20)} {Y(-31)}H{X(20)}V{Y(-23)}H{X(-20)}Z"                  # grille slot
    )
    box = [(cx - 70 * k, base - 104 * k), (cx + 70 * k, base + 4 * k)]
    return outline, holes, box


# G - "Raise": a car facing you; the barrier arm lifts over it from a post at the left.
oc, hc, bc = car_front(152, 222, 1.0)
write("g-raise", [
    rect(22, 118, 42, 222),
    disc(32, 118, 17),
    *bar_segments(*pt(32, 118, 12, -45), -45, 140, 24, cuts=[56, 98], gap=10),
    (oc + hc, bc),
])

# H - "Arrive": a car in profile pulls up to the gate; the striped arm is rising.
car_side = (
    "M58 196V176Q58 164 70 163L96 160L118 130Q122 124 130 124H178Q186 124 190 130L212 160"
    "Q232 163 232 177V196H206A22 22 0 0 0 162 196H126A22 22 0 0 0 82 196Z"
    "M121 156L136 134H152V156ZM160 156V134H178L190.7 156Z"
)
write("h-arrive", [
    (car_side, [(58, 124), (232, 196)]),
    disc(104, 196, 16),
    disc(184, 196, 16),
    rect(24, 104, 40, 214),
    disc(32, 104, 13),
    *bar_segments(*pt(32, 104, 13, -60), -60, 92, 18, cuts=[36, 64], gap=8),
])

# I - "Gateway": a solid archway; the car is the opening (negative space), headlights stay solid.
oi, hi, _ = car_front(128, 210, 0.98)
arch = "M30 232V118A98 98 0 0 1 226 118V232Z"
write("i-gateway", [
    (arch + oi + hi, [(30, 20), (226, 232)]),
])
