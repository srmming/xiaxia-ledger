"""夏夏：一颗圆滚滚的小太阳，头顶一片小嫩叶（夏天）。64 网格。
四种性格各一张脸，另外几种心情给空状态、出错、加载、庆祝用。"""
from geom import *
from icons import ICONS

FACE = (32, 35, 19.5)   # 脸的圆心和半径


def L(paint, p, w=0):
    return (paint, p, w)


def body(rays=True):
    cx, cy, r = FACE
    out = []
    if rays:
        for i in range(1, 8):          # 正上方那根留给嫩叶
            out.append(L('ray', ellipse(cx, cy - r - 4.6, 3.6, 5.2).rot(i * 45, cx, cy)))
    # 嫩叶 + 小茎
    out.append(L('leafStem', path(f"M{cx} {cy - r + 1} C{cx} {cy - r - 3} {cx + 1} {cy - r - 6} {cx + 3} {cy - r - 7.6}"), 2))
    out.append(L('leaf', path(f"M{cx + 2} {cy - r - 7} C{cx + 4} {cy - r - 13} {cx + 10} {cy - r - 13.4} {cx + 13} {cy - r - 11.6} C{cx + 11} {cy - r - 6.4} {cx + 6} {cy - r - 4.6} {cx + 2} {cy - r - 7} Z")))
    out.append(L('leafVein', path(f"M{cx + 4.4} {cy - r - 7.6} C{cx + 7} {cy - r - 9.6} {cx + 9} {cy - r - 10.6} {cx + 11} {cy - r - 11}"), 1))
    out.append(L('leaf', path(f"M{cx - 1} {cy - r - 4.2} C{cx - 3.6} {cy - r - 8.4} {cx - 8} {cy - r - 8.4} {cx - 9.6} {cy - r - 6.8} C{cx - 7.6} {cy - r - 3.6} {cx - 4} {cy - r - 2.6} {cx - 1} {cy - r - 4.2} Z")))
    out.append(L('sun', circle(cx, cy, r)))
    # 下半边一点暖色阴影，显得圆鼓鼓
    a0, a1 = 25, 155
    sh = arc(cx, cy, r, a0, a1)
    import math
    p1 = (cx + r * math.cos(math.radians(a1)), cy + r * math.sin(math.radians(a1)))
    p0 = (cx + r * math.cos(math.radians(a0)), cy + r * math.sin(math.radians(a0)))
    sh.cmds.append(('C', (p1[0] + 6, cy + r * 0.95), (p0[0] - 6, cy + r * 0.95), p0))
    sh.cmds.append(('Z',))
    out.append(L('sunShade', sh))
    out.append(L('shine', ellipse(cx - 9.6, cy - 10.4, 4.2, 2.4, rot=-38)))
    out.append(L('shine', circle(cx - 4.4, cy - 14.2, 1.2)))
    return out


def cheeks(alpha_paint='cheek'):
    cx, cy, _ = FACE
    return [L(alpha_paint, ellipse(cx - 10.6, cy + 6.2, 3.4, 2.2)), L(alpha_paint, ellipse(cx + 10.6, cy + 6.2, 3.4, 2.2))]


def dot_eyes(dx=0, dy=0, ry=2.9):
    cx, cy, _ = FACE
    out = []
    for ex in (cx - 7, cx + 7):
        out.append(L('ink', ellipse(ex + dx, cy - 0.6 + dy, 2.25, ry)))
        out.append(L('white', circle(ex + dx + 0.8, cy - 1.8 + dy, 0.85)))
    return out


def drop(x, y, s=1):
    return L('sweat', path(f"M{x} {y - 4.4 * s} C{x + 2.6 * s} {y - 0.8 * s} {x + 3 * s} {y + 0.6 * s} {x + 3 * s} {y + 1.6 * s} C{x + 3 * s} {y + 3.4 * s} {x + 1.6 * s} {y + 4.6 * s} {x} {y + 4.6 * s} C{x - 1.6 * s} {y + 4.6 * s} {x - 3 * s} {y + 3.4 * s} {x - 3 * s} {y + 1.6 * s} C{x - 3 * s} {y + 0.6 * s} {x - 2.6 * s} {y - 0.8 * s} {x} {y - 4.4 * s} Z"))


def face(kind):
    cx, cy, _ = FACE
    ink = lambda p, w=2: L('ink', p, w)
    if kind == 'gentle':      # 温和直说：眯眯笑
        return cheeks() + dot_eyes() + [ink(path(f"M{cx - 3.8} {cy + 6} C{cx - 1.6} {cy + 8.8} {cx + 1.6} {cy + 8.8} {cx + 3.8} {cy + 6}"), 2.1)]
    if kind == 'sharp':       # 毒舌：半睁眼、挑一边眉、歪嘴笑
        out = cheeks()
        for ex in (cx - 7, cx + 7):
            out.append(L('ink', path(f"M{ex - 2.6} {cy - 1} H{ex + 2.6} C{ex + 2.6} {cy + 1.4} {ex + 1.4} {cy + 2.8} {ex} {cy + 2.8} C{ex - 1.4} {cy + 2.8} {ex - 2.6} {cy + 1.4} {ex - 2.6} {cy - 1} Z")))
            out.append(L('white', circle(ex + 0.9, cy + 0.4, 0.7)))
        out.append(ink(line((cx - 10.4, cy - 5.6), (cx - 4.2, cy - 4.4)), 2))
        out.append(ink(path(f"M{cx + 4} {cy - 5} C{cx + 6} {cy - 7.6} {cx + 8.6} {cy - 8} {cx + 10.6} {cy - 7}"), 2))
        out.append(ink(path(f"M{cx - 3.6} {cy + 7.4} C{cx - 0.6} {cy + 8.6} {cx + 2.6} {cy + 7.8} {cx + 4.8} {cy + 4.8}"), 2.1))
        return out
    if kind == 'calm':        # 文静：圆眼镜、闭着眼微笑
        out = cheeks()
        for ex in (cx - 7, cx + 7):
            out.append(L('glass', circle(ex, cy - 0.4, 4.9)))
            out.append(ink(circle(ex, cy - 0.4, 4.9), 1.5))
            out.append(ink(path(f"M{ex - 2.4} {cy} C{ex - 1.2} {cy - 1.6} {ex + 1.2} {cy - 1.6} {ex + 2.4} {cy}"), 1.9))
        out.append(ink(path(f"M{cx - 2.1} {cy - 1.4} C{cx - 0.8} {cy - 2.4} {cx + 0.8} {cy - 2.4} {cx + 2.1} {cy - 1.4}"), 1.5))
        out.append(ink(path(f"M{cx - 2} {cy + 7} C{cx - 0.8} {cy + 7.9} {cx + 0.8} {cy + 7.9} {cx + 2} {cy + 7}"), 1.9))
        return out
    if kind == 'cheer':       # 打气：^ ^ 眼、张嘴大笑、亮晶晶
        out = cheeks()
        for ex in (cx - 7, cx + 7):
            out.append(ink(line((ex - 2.8, cy + 0.8), (ex, cy - 2.4), (ex + 2.8, cy + 0.8)), 2.3))
        out.append(L('ink', path(f"M{cx - 4.6} {cy + 4.4} H{cx + 4.6} C{cx + 4.6} {cy + 8.4} {cx + 2.4} {cy + 10.6} {cx} {cy + 10.6} C{cx - 2.4} {cy + 10.6} {cx - 4.6} {cy + 8.4} {cx - 4.6} {cy + 4.4} Z")))
        out.append(L('tongue', ellipse(cx, cy + 8.9, 2.6, 1.5)))
        out.append(L('spark', star4(55, 13, 4.4)))
        out.append(L('spark', star4(9, 18, 3)))
        out.append(L('spark', star4(57, 30, 2.2)))
        return out
    if kind == 'worried':     # 担心：八字眉、波浪嘴、冒汗
        out = cheeks() + dot_eyes(dy=0.6)
        out.append(ink(line((cx - 10.4, cy - 4.6), (cx - 4.6, cy - 6.4)), 1.9))
        out.append(ink(line((cx + 4.6, cy - 6.4), (cx + 10.4, cy - 4.6)), 1.9))
        out.append(ink(path(f"M{cx - 4.6} {cy + 7.8} C{cx - 3.2} {cy + 6} {cx - 1.6} {cy + 6} {cx} {cy + 7.8} C{cx + 1.6} {cy + 9.6} {cx + 3.2} {cy + 9.6} {cx + 4.6} {cy + 7.8}"), 1.9))
        out.append(drop(cx + 17.4, cy - 11, 1))
        return out
    if kind == 'thinking':    # 想事情：眼睛往右上看、小嘴、想法泡泡
        out = cheeks() + dot_eyes(dx=1.2, dy=-1.2)
        out.append(L('ink', ellipse(cx + 2.4, cy + 7.4, 1.7, 1.5)))
        out.append(L('bubble', circle(48.6, 12.4, 1.9)))
        out.append(L('bubble', circle(53.6, 7.4, 2.7)))
        out.append(L('bubble', circle(45.4, 16.8, 1.2)))
        return out
    if kind == 'sleeping':    # 睡着：闭眼、小嘴、Zz
        out = cheeks()
        for ex in (cx - 7, cx + 7):
            out.append(ink(path(f"M{ex - 2.8} {cy - 0.6} C{ex - 1.4} {cy + 1.6} {ex + 1.4} {cy + 1.6} {ex + 2.8} {cy - 0.6}"), 2.1))
        out.append(L('ink', ellipse(cx, cy + 7.6, 1.6, 1.3)))
        out.append(L('zz', line((47, 9), (53, 9), (47, 15.4), (53, 15.4)), 2.2))
        out.append(L('zz', line((55.4, 2.4), (59.4, 2.4), (55.4, 6.6), (59.4, 6.6)), 1.7))
        return out
    if kind == 'oops':        # 出错：> < 眼、小圆嘴、冒汗
        out = cheeks()
        out.append(ink(line((cx - 9.6, cy - 3.6), (cx - 5, cy - 0.8), (cx - 9.6, cy + 2)), 2.2))
        out.append(ink(line((cx + 9.6, cy - 3.6), (cx + 5, cy - 0.8), (cx + 9.6, cy + 2)), 2.2))
        out.append(L('ink', ellipse(cx, cy + 7.6, 2.4, 2.2)))
        out.append(drop(cx + 17.4, cy - 11, 1))
        return out
    if kind == 'celebrate':   # 庆祝：打气的脸 + 彩纸
        out = face('cheer')[:-3]
        conf = [('confA', rrect(4, 10, 3.2, 6, 1.2, rot=-30)), ('confB', rrect(56, 20, 3.2, 6, 1.2, rot=25)),
                ('confC', circle(10, 4, 2)), ('confA', circle(58, 6, 1.8)), ('confB', rrect(2, 30, 3, 5.4, 1.2, rot=40)),
                ('confC', rrect(54, 36, 3, 5.4, 1.2, rot=-35)), ('spark', star4(52, 12, 3.6)), ('spark', star4(12, 22, 2.6))]
        return out + [L(c, p) for c, p in conf]
    raise KeyError(kind)


MASCOTS = {}
for kind, label, group in [
    ('gentle', '温和直说', 'persona'), ('sharp', '毒舌', 'persona'), ('calm', '文静', 'persona'), ('cheer', '打气', 'persona'),
    ('worried', '担心', 'mood'), ('thinking', '想一想', 'mood'), ('sleeping', '睡着了', 'mood'),
    ('oops', '出错了', 'mood'), ('celebrate', '庆祝', 'mood'),
]:
    MASCOTS['xiaxia.' + kind] = dict(name='xiaxia.' + kind, label=label, group=group, size=64, layers=body() + face(kind))


# ===================== 空状态插画（160 x 120） =====================

def place(layers, s, dx, dy, tint=None):
    out = []
    for paint, p, w in layers:
        if tint and paint in ('soft', 'solid', 'hi', 'cut'):
            paint = f"{paint}:{tint}"
        out.append((paint, p.scale(s).move(dx, dy), w * s))
    return out


def ground():
    return [L('ground', ellipse(80, 109, 58, 6.4))]


def mascot_at(kind, s=1.05, dx=82, dy=36):
    return place(body() + face(kind), s, dx, dy)


ILLOS = {}

def illo(name, label, prop, tint, kind, ps=2.3, px=8, py=52, extra=None, ms=1.36, mx=70, my=20):
    layers = ground()
    if prop:
        layers += place(ICONS[prop]['layers'], ps, px, py, tint)
    layers += mascot_at(kind, ms, mx, my)
    if extra:
        layers += extra
    ILLOS['illo.' + name] = dict(name='illo.' + name, label=label, group='illustration', size=(160, 120), layers=layers)

illo('ledger', '账本还是空的', 'education', 'brand', 'sleeping')
illo('month', '这个月还没有流水', 'act.calendar', 'brand', 'sleeping')
illo('spending', '还没花钱', 'nav.spending', 'brand', 'gentle')
illo('trends', '流水还不够看趋势', 'nav.trends', 'ai', 'thinking')
illo('accounts', '还没有账户', 'savings', 'F98DB0', 'thinking')
illo('plans', '还没有计划', 'nav.plans', 'income', 'cheer')
illo('search', '没找到', 'act.search', 'fg3', 'thinking')
illo('connect', '还没连上 AI', 'act.link', 'ai', 'worried')
illo('error', '出了点问题', 'badge.warn', 'warn', 'oops')
illo('done', '都处理好了', 'badge.done', 'income', 'celebrate')
illo('loading', '夏夏在想', None, None, 'thinking', ms=1.5, mx=32, my=14)
