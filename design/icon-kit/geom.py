"""夏夏图标的小画图库：所有形状最后都变成只含 M / L / C / Z（绝对坐标）的路径，
这样 SVG 预览和 SwiftUI 里的 Path 用的是同一份数据。"""
import math

K = 0.5522847498  # 用三次贝塞尔近似四分之一圆


class P:
    """一条路径：命令列表 [('M',(x,y)), ('L',(x,y)), ('C',(x1,y1),(x2,y2),(x,y)), ('Z',)]"""

    def __init__(self, cmds=None):
        self.cmds = list(cmds or [])

    def __add__(self, other):
        return P(self.cmds + other.cmds)

    def map(self, f):
        out = []
        for c in self.cmds:
            out.append((c[0],) + tuple(f(*pt) for pt in c[1:]))
        return P(out)

    def move(self, dx, dy):
        return self.map(lambda x, y: (x + dx, y + dy))

    def scale(self, s, sy=None, cx=0, cy=0):
        sy = s if sy is None else sy
        return self.map(lambda x, y: (cx + (x - cx) * s, cy + (y - cy) * sy))

    def rot(self, deg, cx, cy):
        a = math.radians(deg)
        ca, sa = math.cos(a), math.sin(a)
        return self.map(lambda x, y: (cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca))

    def flipx(self, cx):
        return self.map(lambda x, y: (2 * cx - x, y))

    def d(self):
        parts = []
        for c in self.cmds:
            parts.append(c[0])
            for (x, y) in c[1:]:
                parts.append(f"{fmt(x)} {fmt(y)}")
        return " ".join(parts)


def fmt(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


# ---------- 基本形状 ----------

def ellipse(cx, cy, rx, ry=None, rot=0):
    ry = rx if ry is None else ry
    kx, ky = rx * K, ry * K
    p = P([
        ('M', (cx + rx, cy)),
        ('C', (cx + rx, cy + ky), (cx + kx, cy + ry), (cx, cy + ry)),
        ('C', (cx - kx, cy + ry), (cx - rx, cy + ky), (cx - rx, cy)),
        ('C', (cx - rx, cy - ky), (cx - kx, cy - ry), (cx, cy - ry)),
        ('C', (cx + kx, cy - ry), (cx + rx, cy - ky), (cx + rx, cy)),
        ('Z',),
    ])
    return p.rot(rot, cx, cy) if rot else p


def circle(cx, cy, r):
    return ellipse(cx, cy, r)


def rrect(x, y, w, h, r=0, rot=0, corners=None):
    """圆角矩形；corners=(左上,右上,右下,左下) 可分别给半径。"""
    tl, tr, br, bl = corners if corners else (r, r, r, r)
    m = min(w, h) / 2
    tl, tr, br, bl = (min(v, m) for v in (tl, tr, br, bl))
    c = []
    c.append(('M', (x + tl, y)))
    c.append(('L', (x + w - tr, y)))
    if tr: c.append(('C', (x + w - tr + tr * K, y), (x + w, y + tr - tr * K), (x + w, y + tr)))
    c.append(('L', (x + w, y + h - br)))
    if br: c.append(('C', (x + w, y + h - br + br * K), (x + w - br + br * K, y + h), (x + w - br, y + h)))
    c.append(('L', (x + bl, y + h)))
    if bl: c.append(('C', (x + bl - bl * K, y + h), (x, y + h - bl + bl * K), (x, y + h - bl)))
    c.append(('L', (x, y + tl)))
    if tl: c.append(('C', (x, y + tl - tl * K), (x + tl - tl * K, y), (x + tl, y)))
    c.append(('Z',))
    p = P(c)
    return p.rot(rot, x + w / 2, y + h / 2) if rot else p


def poly(pts, r=0):
    """多边形，r>0 时每个角都磨圆（可爱的关键）。"""
    n = len(pts)
    if not r:
        c = [('M', pts[0])] + [('L', p) for p in pts[1:]] + [('Z',)]
        return P(c)
    c = []
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        d1 = math.dist(p0, p1); d2 = math.dist(p1, p2)
        rr = min(r, d1 / 2.05, d2 / 2.05)
        a = (p1[0] + (p0[0] - p1[0]) * rr / d1, p1[1] + (p0[1] - p1[1]) * rr / d1)
        b = (p1[0] + (p2[0] - p1[0]) * rr / d2, p1[1] + (p2[1] - p1[1]) * rr / d2)
        ca = (a[0] + (p1[0] - a[0]) * 0.62, a[1] + (p1[1] - a[1]) * 0.62)
        cb = (b[0] + (p1[0] - b[0]) * 0.62, b[1] + (p1[1] - b[1]) * 0.62)
        c.append(('L' if c else 'M', a))
        c.append(('C', ca, cb, b))
    c.append(('Z',))
    return P(c)


def path(s):
    """读一小段 SVG 路径（M L H V C Q Z，大写绝对坐标），转成本库格式。"""
    import re
    toks = re.findall(r"[MLHVCQZ]|-?\d*\.?\d+", s)
    i = 0; cmd = None; cur = (0, 0); start = (0, 0); out = []
    def num():
        nonlocal i
        v = float(toks[i]); i += 1; return v
    while i < len(toks):
        t = toks[i]
        if t.isalpha():
            cmd = t; i += 1
            if cmd == 'Z':
                out.append(('Z',)); cur = start; continue
        if cmd == 'M':
            cur = (num(), num()); start = cur; out.append(('M', cur)); cmd = 'L'
        elif cmd == 'L':
            cur = (num(), num()); out.append(('L', cur))
        elif cmd == 'H':
            cur = (num(), cur[1]); out.append(('L', cur))
        elif cmd == 'V':
            cur = (cur[0], num()); out.append(('L', cur))
        elif cmd == 'C':
            a = (num(), num()); b = (num(), num()); cur = (num(), num()); out.append(('C', a, b, cur))
        elif cmd == 'Q':
            q = (num(), num()); e = (num(), num())
            a = (cur[0] + 2 / 3 * (q[0] - cur[0]), cur[1] + 2 / 3 * (q[1] - cur[1]))
            b = (e[0] + 2 / 3 * (q[0] - e[0]), e[1] + 2 / 3 * (q[1] - e[1]))
            out.append(('C', a, b, e)); cur = e
        else:
            raise ValueError(s)
    return P(out)


def arc(cx, cy, r, a0, a1, ry=None):
    """开口弧线（给描边用），角度用度，0 度在右边，顺时针为正（屏幕坐标）。"""
    ry = r if ry is None else ry
    segs = max(1, int(math.ceil(abs(a1 - a0) / 90)))
    da = (a1 - a0) / segs
    out = []
    for s in range(segs):
        t0 = math.radians(a0 + da * s); t1 = math.radians(a0 + da * (s + 1))
        k = 4 / 3 * math.tan((t1 - t0) / 4)
        p0 = (cx + r * math.cos(t0), cy + ry * math.sin(t0))
        p3 = (cx + r * math.cos(t1), cy + ry * math.sin(t1))
        p1 = (p0[0] - k * r * math.sin(t0), p0[1] + k * ry * math.cos(t0))
        p2 = (p3[0] + k * r * math.sin(t1), p3[1] - k * ry * math.cos(t1))
        if s == 0: out.append(('M', p0))
        out.append(('C', p1, p2, p3))
    return P(out)


def line(*pts):
    return P([('M', pts[0])] + [('L', p) for p in pts[1:]])


def star4(cx, cy, r, w=0.38):
    """四角星（亮晶晶）：四个尖用曲线收进去。"""
    c = [('M', (cx, cy - r))]
    pts = [(cx + r, cy), (cx, cy + r), (cx - r, cy), (cx, cy - r)]
    prev = (cx, cy - r)
    for p in pts:
        mid = ((prev[0] + p[0]) / 2, (prev[1] + p[1]) / 2)
        ctrl = (cx + (mid[0] - cx) * w, cy + (mid[1] - cy) * w)
        c.append(('C', ctrl, ctrl, p))
        prev = p
    c.append(('Z',))
    return P(c)


def star5(cx, cy, r, inner=0.5, rr=0.9, rot=0):
    pts = []
    for i in range(10):
        a = math.radians(-90 + rot + i * 36)
        rad = r if i % 2 == 0 else r * inner
        pts.append((cx + rad * math.cos(a), cy + rad * math.sin(a)))
    return poly(pts, rr)


def heart(cx, cy, s):
    """小爱心，s≈宽度的一半。"""
    return path(
        f"M{cx} {cy + s * 0.95} "
        f"C{cx - s * 0.35} {cy + s * 0.65} {cx - s} {cy + s * 0.2} {cx - s} {cy - s * 0.3} "
        f"C{cx - s} {cy - s * 0.85} {cx - s * 0.3} {cy - s * 1.05} {cx} {cy - s * 0.5} "
        f"C{cx + s * 0.3} {cy - s * 1.05} {cx + s} {cy - s * 0.85} {cx + s} {cy - s * 0.3} "
        f"C{cx + s} {cy + s * 0.2} {cx + s * 0.35} {cy + s * 0.65} {cx} {cy + s * 0.95} Z")


def gear(cx, cy, r_out, r_in, teeth, tooth_w=0.5, rr=0.8):
    pts = []
    step = 360 / teeth
    for i in range(teeth):
        a = -90 + i * step
        hw = step * tooth_w / 2
        for ang, rad in ((a - step / 2 + 2, r_in), (a - hw, r_out), (a + hw, r_out)):
            t = math.radians(ang)
            pts.append((cx + rad * math.cos(t), cy + rad * math.sin(t)))
        t = math.radians(a + step / 2 - 2)
        pts.append((cx + r_in * math.cos(t), cy + r_in * math.sin(t)))
    return poly(pts, rr)
