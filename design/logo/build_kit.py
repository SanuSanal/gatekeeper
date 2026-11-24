"""GateKeeper logo kit: final "Lift" mark (a pivot with three rising bars), colour versions,
app-icon tile, custom wordmark, lockups and Android vector drawables.

Run: python design/logo/build_kit.py
Everything is generated from the geometry below; edit here, never by hand in the outputs.
"""
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
KIT = Path(__file__).parent / "kit"
KIT.mkdir(parents=True, exist_ok=True)

GREEN = "#1F6B5C"
CREAM = "#F3EFE4"
AMBER = "#E8A33D"
INK = "#17231F"


def f(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def pt(cx, cy, r, deg):
    a = math.radians(deg)
    return cx + r * math.cos(a), cy + r * math.sin(a)


def capsule_path(x0, y0, x1, y1, t):
    r = t / 2
    deg = math.degrees(math.atan2(y1 - y0, x1 - x0))
    nx, ny = pt(0, 0, r, deg - 90)
    return (f"M{f(x0 + nx)} {f(y0 + ny)}L{f(x1 + nx)} {f(y1 + ny)}"
            f"A{f(r)} {f(r)} 0 0 1 {f(x1 - nx)} {f(y1 - ny)}L{f(x0 - nx)} {f(y0 - ny)}"
            f"A{f(r)} {f(r)} 0 0 1 {f(x0 + nx)} {f(y0 + ny)}Z")


def disc_path(cx, cy, r):
    return f"M{f(cx - r)} {f(cy)}a{f(r)} {f(r)} 0 1 0 {f(2 * r)} 0a{f(r)} {f(r)} 0 1 0 {f(-2 * r)} 0Z"


# ---- the mark ------------------------------------------------------------------------------------
# Construction (in mark units): pivot dot radius HUB at the origin; three bars of width T start at
# radius RS and point at 0, -30 and -60 degrees (-y is up); their round-cap centres end at RS+L.
# Gap between neighbouring bars at their start = 2*RS*sin(15deg) - T.
MARKS = {
    "regular": dict(HUB=26, T=28, RS=76, ANGLES=(0, -30, -60), LENGTHS=(44, 82, 120)),
    # Small-size cut (<= 32 px): heavier bars and dot, shorter bars, same angles.
    "small": dict(HUB=32, T=36, RS=90, ANGLES=(0, -30, -60), LENGTHS=(24, 54, 84)),
}


def mark_geometry(kind="regular"):
    g = MARKS[kind]
    bars = []
    for a, L in zip(g["ANGLES"], g["LENGTHS"]):
        x0, y0 = pt(0, 0, g["RS"], a)
        x1, y1 = pt(0, 0, g["RS"] + L, a)
        bars.append((x0, y0, x1, y1))
    pts = [(-g["HUB"], -g["HUB"]), (g["HUB"], g["HUB"])]
    for x0, y0, x1, y1 in bars:
        r = g["T"] / 2
        pts += [(x0 - r, y0 - r), (x0 + r, y0 + r), (x1 - r, y1 - r), (x1 + r, y1 + r)]
    minx, maxx = min(p[0] for p in pts), max(p[0] for p in pts)
    miny, maxy = min(p[1] for p in pts), max(p[1] for p in pts)
    return g, bars, (minx, miny, maxx, maxy)


def mark_fit(kind, box, optical_lift=0.0):
    """Scale and origin (pivot centre) that fit the mark into box=(x, y, size), optically centred."""
    g, bars, (minx, miny, maxx, maxy) = mark_geometry(kind)
    bx, by, size = box
    w, h = maxx - minx, maxy - miny
    s = size / max(w, h)
    ox = bx + (size - w * s) / 2 - minx * s
    oy = by + (size - h * s) / 2 - miny * s - optical_lift * size
    return s, ox, oy


def mark_paths(kind, box, optical_lift=0.0):
    """Returns (hub_path, bars_path) fitted into box=(x, y, size) square, optically centred."""
    g, bars, _ = mark_geometry(kind)
    s, ox, oy = mark_fit(kind, box, optical_lift)
    hub = disc_path(ox, oy, g["HUB"] * s)
    bar_d = "".join(capsule_path(ox + x0 * s, oy + y0 * s, ox + x1 * s, oy + y1 * s, g["T"] * s)
                    for x0, y0, x1, y1 in bars)
    return hub, bar_d


def svg(view_w, view_h, body, title="GateKeeper"):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {f(view_w)} {f(view_h)}">'
            f"<title>{title}</title>{body}</svg>\n")


def write(name, content):
    (KIT / name).write_text(content)
    print("wrote", name)


def symbol_files():
    for kind, suffix in (("regular", ""), ("small", "-small")):
        hub, bars = mark_paths(kind, (24, 24, 208), optical_lift=0.012)
        write(f"symbol{suffix}-black.svg", svg(256, 256, f'<path fill="#000" d="{hub}{bars}"/>'))
        write(f"symbol{suffix}-color.svg", svg(256, 256, f'<path fill="{GREEN}" d="{bars}"/><path fill="{AMBER}" d="{hub}"/>'))
        write(f"symbol{suffix}-reversed.svg", svg(256, 256, f'<path fill="{CREAM}" d="{bars}"/><path fill="{AMBER}" d="{hub}"/>'))


# ---- wordmark: custom lowercase monoline "gatekeeper" ------------------------------------------------
# Units: baseline y=0, x-height 100, stroke 20, round caps (matching the bars), bowls r=40 on centreline.
# Every piece winds clockwise so overlaps stay filled under the nonzero rule.
WT, XH, RB = 20, 100, 40


def ring(cx, cy, r, t):
    ro, ri = r + t / 2, r - t / 2
    return (f"M{f(cx - ro)} {f(cy)}A{f(ro)} {f(ro)} 0 1 1 {f(cx + ro)} {f(cy)}A{f(ro)} {f(ro)} 0 1 1 {f(cx - ro)} {f(cy)}Z"
            f"M{f(cx - ri)} {f(cy)}A{f(ri)} {f(ri)} 0 1 0 {f(cx + ri)} {f(cy)}A{f(ri)} {f(ri)} 0 1 0 {f(cx - ri)} {f(cy)}Z")


def arc_stroke(cx, cy, r, t, a0, a1):
    """Clockwise arc a0->a1 (deg) with round caps, as a filled outline (clockwise winding)."""
    ro, ri, cap = r + t / 2, r - t / 2, t / 2
    large = 1 if (a1 - a0) > 180 else 0
    o0, o1 = pt(cx, cy, ro, a0), pt(cx, cy, ro, a1)
    i0, i1 = pt(cx, cy, ri, a0), pt(cx, cy, ri, a1)
    return (f"M{f(o0[0])} {f(o0[1])}A{f(ro)} {f(ro)} 0 {large} 1 {f(o1[0])} {f(o1[1])}"
            f"A{f(cap)} {f(cap)} 0 0 1 {f(i1[0])} {f(i1[1])}A{f(ri)} {f(ri)} 0 {large} 0 {f(i0[0])} {f(i0[1])}"
            f"A{f(cap)} {f(cap)} 0 0 1 {f(o0[0])} {f(o0[1])}Z")


def bar(x0, y0, x1, y1):
    return capsule_path(x0, y0, x1, y1, WT)


C = -XH / 2  # bowl centre y
GLYPHS = {
    # char: (advance width, builder taking the x offset)
    "g": (100, lambda x: ring(x + 50, C, RB, WT) + bar(x + 90, -90, x + 90, 26) + arc_stroke(x + 52, 26, 38, WT, 0, 172)),
    "a": (100, lambda x: ring(x + 50, C, RB, WT) + bar(x + 90, -90, x + 90, 0)),
    "t": (62, lambda x: bar(x + 24, -128, x + 24, 0) + bar(x + 0, -92, x + 56, -92)),
    "e": (100, lambda x: arc_stroke(x + 50, C, RB, WT, 28, 360) + bar(x + 14, C, x + 88, C)),
    "k": (86, lambda x: bar(x + 10, -140, x + 10, 0) + bar(x + 14, -34, x + 76, -96) + bar(x + 40, -58, x + 80, 0)),
    "p": (100, lambda x: ring(x + 50, C, RB, WT) + bar(x + 10, -90, x + 10, 62)),
    "r": (74, lambda x: bar(x + 10, -90, x + 10, 0) + arc_stroke(x + 50, C, RB, WT, 180, 290)),
}
KERN = 18  # space between glyph advance boxes
W_TOP, W_BOTTOM = -140, 76  # wordmark vertical extent in glyph units


def wordmark_path(text="gatekeeper"):
    x, d = 0.0, ""
    for ch in text:
        w, build = GLYPHS[ch]
        d += build(x)
        x += w + KERN
    return d, x - KERN


def lockups():
    word, ww = wordmark_path()
    # Horizontal: symbol 208 tall; wordmark x-height = 0.34 of the symbol; baseline on the dot's bottom.
    s, ox, oy = mark_fit("regular", (24, 24, 208))
    baseline = oy + MARKS["regular"]["HUB"] * s
    k = 0.34 * 208 / XH
    hub, bars_ = mark_paths("regular", (24, 24, 208))
    tx = 24 + 208 + 0.20 * 208
    total_w = tx + ww * k + 24
    word_g = f'<path transform="matrix({f(k)} 0 0 {f(k)} {f(tx)} {f(baseline)})" d="{word}"/>'
    for name, wc, bc, hc, bg in (
        ("lockup-horizontal-color.svg", INK, GREEN, AMBER, None),
        ("lockup-horizontal-reversed.svg", CREAM, CREAM, AMBER, GREEN),
        ("lockup-horizontal-black.svg", "#000", "#000", "#000", None),
    ):
        body = f'<rect width="{f(total_w)}" height="256" fill="{bg}"/>' if bg else ""
        body += f'<path fill="{bc}" d="{bars_}"/><path fill="{hc}" d="{hub}"/><g fill="{wc}">{word_g}</g>'
        write(name, svg(total_w, 256, body))
    # Stacked: symbol above a centred wordmark.
    k2 = 0.30 * 208 / XH
    sw = ww * k2
    width = max(208, sw) + 48
    sx = (width - 208) / 2
    hub2, bars2 = mark_paths("regular", (sx, 24, 208))
    base = 24 + 208 + 40 - W_TOP * k2
    height = base + W_BOTTOM * k2 + 24
    word2 = f'<path transform="matrix({f(k2)} 0 0 {f(k2)} {f((width - sw) / 2)} {f(base)})" d="{word}"/>'
    write("lockup-stacked-color.svg", svg(width, height,
          f'<path fill="{GREEN}" d="{bars2}"/><path fill="{AMBER}" d="{hub2}"/><g fill="{INK}">{word2}</g>'))
    write("wordmark-black.svg", svg(ww + 40, W_BOTTOM - W_TOP + 40,
          f'<path transform="translate(20 {f(20 - W_TOP)})" d="{word}"/>'))


def app_icon():
    tile = f'<rect width="256" height="256" rx="58" fill="{GREEN}"/>'
    hub, bars_ = mark_paths("regular", (60, 60, 136), optical_lift=0.015)
    write("app-icon.svg", svg(256, 256, tile + f'<path fill="{CREAM}" d="{bars_}"/><path fill="{AMBER}" d="{hub}"/>'))
    hs, bs = mark_paths("small", (56, 56, 144), optical_lift=0.015)
    write("app-icon-small.svg", svg(256, 256, tile + f'<path fill="{CREAM}" d="{bs}"/><path fill="{AMBER}" d="{hs}"/>'))
    # Full-bleed square (iOS/Apple touch applies its own mask) and PWA maskable (mark inside the 80% safe circle).
    square = f'<rect width="256" height="256" fill="{GREEN}"/>'
    write("app-icon-square.svg", svg(256, 256, square + f'<path fill="{CREAM}" d="{bars_}"/><path fill="{AMBER}" d="{hub}"/>'))
    hm, bm = mark_paths("regular", (70, 70, 116), optical_lift=0.015)
    write("app-icon-maskable.svg", svg(256, 256, square + f'<path fill="{CREAM}" d="{bm}"/><path fill="{AMBER}" d="{hm}"/>'))


def vector_drawable(size_dp, viewport, paths):
    body = "".join(f'\n    <path android:fillColor="{c}" android:pathData="{d}" />' for c, d in paths)
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<!-- Generated by design/logo/build_kit.py. Do not edit by hand. -->\n'
            '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            f'    android:width="{size_dp}dp" android:height="{size_dp}dp"\n'
            f'    android:viewportWidth="{viewport}" android:viewportHeight="{viewport}">{body}\n</vector>\n')


def android():
    res = ROOT / "android/app/src/main/res"
    # Adaptive icon: 108dp canvas; the mark stays inside the 66dp safe zone (52dp box, centred).
    hub, bars_ = mark_paths("regular", (28, 28, 52), optical_lift=0.015)
    (res / "drawable/ic_launcher_foreground.xml").write_text(vector_drawable(108, 108, [(CREAM, bars_), (AMBER, hub)]))
    (res / "drawable/ic_launcher_monochrome.xml").write_text(vector_drawable(108, 108, [("#FFFFFFFF", bars_ + hub)]))
    # Notification icon: white, small-size cut, 24dp.
    hs, bs = mark_paths("small", (2, 2, 20))
    (res / "drawable/ic_stat_gate.xml").write_text(vector_drawable(24, 24, [("#FFFFFFFF", bs + hs)]))
    (res / "values/ic_launcher_colors.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">{GREEN}</color>\n</resources>\n')
    (res / "mipmap-anydpi-v26").mkdir(exist_ok=True)
    (res / "mipmap-anydpi-v26/ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />\n'
        '</adaptive-icon>\n')
    # Preview: foreground under a circular launcher mask (72dp visible circle, 66dp safe zone dashed).
    write("android-adaptive-preview.svg", svg(108, 108,
          f'<rect width="108" height="108" fill="#ddd"/><circle cx="54" cy="54" r="36" fill="{GREEN}"/>'
          f'<circle cx="54" cy="54" r="33" fill="none" stroke="#fff" stroke-width=".4" stroke-dasharray="1 1"/>'
          f'<path fill="{CREAM}" d="{bars_}"/><path fill="{AMBER}" d="{hub}"/>'))
    print("wrote Android launcher, monochrome and notification drawables")


if __name__ == "__main__":
    symbol_files()
    lockups()
    app_icon()
    android()
