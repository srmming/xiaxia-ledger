"""生成夏夏图标的全部产物（改了 icons.py / mascot.py 后跑一次：python3 design/icon-kit/build.py）：
- design/icon-kit/svg/**.svg            每个图标一张浅色 SVG（给设计看、给别处用）
- design/icon-kit/glyphs.json           全部图标数据
- design/icon-kit/index.html            展示页（template.html + 图标数据）
- Sources/LedgerUI/XiaGlyphData.swift   app 里画图标用的路径数据（自动生成，别手改）
"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from icons import ICONS
from mascot import MASCOTS, ILLOS
from palette import TINTS, NAMED, SOFT_ALPHA, tint_hex
from geom import fmt

ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
ALL = {}
for d in (ICONS, MASCOTS, ILLOS):
    ALL.update(d)


def size_of(g):
    s = g.get('size', 24)
    return s if isinstance(s, tuple) else (s, s)


def color(paint, tint, dark=False):
    """返回 (hex, alpha)；None 表示跟着文字颜色（template）。"""
    if ':' in paint:
        paint, tint = paint.split(':')
    if paint in NAMED:
        c = NAMED[paint]
        return (c[1] if dark else c[0]), (c[3] if dark else c[2])
    base = tint_hex(tint, dark)
    if paint == 'hi':
        return 0xFFFFFF, 0.9
    a = 1.0 if paint == 'solid' else SOFT_ALPHA[1 if dark else 0]
    return base, a


def svg(g, dark=False, template_color=None):
    w, h = size_of(g)
    tint = g.get('tint')
    body = []; defs = []; mid = 0
    for paint, p, sw in g['layers']:
        if paint.split(':')[0] == 'cut':
            mid += 1
            shape = (f'<path d="{p.d()}" fill="none" stroke="black" stroke-width="{fmt(sw)}" stroke-linecap="round" stroke-linejoin="round"/>'
                     if sw else f'<path d="{p.d()}" fill="black"/>')
            defs.append(f'<mask id="m{mid}" maskUnits="userSpaceOnUse" x="0" y="0" width="{w}" height="{h}"><rect width="{w}" height="{h}" fill="white"/>{shape}</mask>')
            body = [f'<g mask="url(#m{mid})">' + ''.join(body) + '</g>']
            continue
        hexv, a = color(paint, tint, dark)
        col = template_color if hexv is None else f"#{hexv:06X}"
        if hexv is None and template_color is None:
            col = '#FFFFFF' if dark else '#1C1C1E'
        op = f' opacity="{fmt(a)}"' if a < 1 else ''
        if sw:
            body.append(f'<path d="{p.d()}" fill="none" stroke="{col}" stroke-width="{fmt(sw)}" stroke-linecap="round" stroke-linejoin="round"{op}/>')
        else:
            body.append(f'<path d="{p.d()}" fill="{col}"{op}/>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">'
            + (f"<defs>{''.join(defs)}</defs>" if defs else '') + ''.join(body) + '</svg>')


def write_svgs():
    out = os.path.join(HERE, 'svg')
    for name, g in ALL.items():
        folder = os.path.join(out, g['group'])
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, name.split('.')[-1] + '.svg'), 'w') as f:
            f.write(svg(g) + '\n')


def write_json():
    data = []
    for name, g in ALL.items():
        w, h = size_of(g)
        data.append(dict(name=name, label=g['label'], group=g['group'], tint=g.get('tint'), w=w, h=h,
                         light=svg(g), dark=svg(g, dark=True)))
    with open(os.path.join(HERE, 'glyphs.json'), 'w') as f:
        json.dump(data, f, ensure_ascii=False)
    return data


def write_page(data):
    """展示页：把全部图标塞进 template.html，生成能直接打开的 index.html。"""
    with open(os.path.join(HERE, 'template.html')) as f:
        page = f.read()
    blob = json.dumps(data, ensure_ascii=False, separators=(',', ':')).replace('</', '<\\/')
    with open(os.path.join(HERE, 'index.html'), 'w') as f:
        f.write(page.replace('__GLYPHS__', blob))


def swift_case(name):
    parts = name.replace('-', '.').split('.')
    s = parts[0] + ''.join(p[:1].upper() + p[1:] for p in parts[1:])
    return s


def write_swift():
    lines = [
        '// 自动生成：design/icon-kit/build.py。别手改，改 design/icon-kit/icons.py 或 mascot.py 再跑一次。',
        '// 夏夏账本自己画的图标（原创）：每个图标是几层路径，层的颜料见 XiaIcons.swift 里的 XiaRenderer。',
        'import CoreGraphics',
        '',
        'enum XiaGlyph: String, CaseIterable, Sendable {',
    ]
    for name in ALL:
        lines.append(f'    case {swift_case(name)} = "{name}"')
    lines += ['}', '', 'extension XiaGlyph {',
              '    /// 画布大小（图标 24×24，夏夏 64×64，插画 160×120）。',
              '    var canvas: CGSize {', '        switch self {']
    sizes = {}
    for name, g in ALL.items():
        sizes.setdefault(size_of(g), []).append(name)
    for (w, h), names in sizes.items():
        cases = ', '.join('.' + swift_case(n) for n in names)
        lines.append(f'        case {cases}: CGSize(width: {w}, height: {h})')
    lines += ['        }', '    }', '',
              '    /// 自带的颜色（分类、账户、徽章）；nil = 跟着文字颜色。',
              '    var tint: String? {', '        switch self {']
    by_tint = {}
    for name, g in ALL.items():
        if g.get('tint'):
            by_tint.setdefault(g['tint'], []).append(name)
    for t, names in by_tint.items():
        lines.append(f'        case {", ".join("." + swift_case(n) for n in names)}: "{t}"')
    lines += ['        default: nil', '        }', '    }', '',
              '    /// 给人看的名字（无障碍朗读也用）。',
              '    var label: String {', '        switch self {']
    for name, g in ALL.items():
        lines.append(f'        case .{swift_case(name)}: "{g["label"]}"')
    lines += ['        }', '    }', '',
              '    /// (颜料, 路径, 描边宽度；0 = 填充)',
              '    var layers: [(String, String, Double)] {', '        switch self {']
    for name, g in ALL.items():
        lines.append(f'        case .{swift_case(name)}: [')
        for paint, p, sw in g['layers']:
            lines.append(f'            ("{paint}", "{p.d()}", {fmt(sw)}),')
        lines.append('        ]')
    lines += ['        }', '    }', '}', '']
    path = os.path.join(ROOT, 'Sources', 'LedgerUI', 'XiaGlyphData.swift')
    with open(path, 'w') as f:
        f.write('\n'.join(lines))
    return path


def write_palette_swift():
    """颜色表也生成一份，Swift 和展示页永远一致。"""
    L = ['// 自动生成：design/icon-kit/build.py（palette.py）。别手改。', '',
         'enum XiaPalette {',
         f'    static let softAlpha: (Double, Double) = ({SOFT_ALPHA[0]}, {SOFT_ALPHA[1]})',
         '    /// 有语义的色：(浅色, 深色)', '    static let tints: [String: (UInt32, UInt32)] = [']
    for k, (a, b) in TINTS.items():
        L.append(f'        "{k}": (0x{a:06X}, 0x{b:06X}),')
    L += ['    ]', '    /// 夏夏和插画用的固定颜色：(浅色, 深色, 浅色透明度, 深色透明度)',
          '    static let named: [String: (UInt32, UInt32, Double, Double)] = [']
    for k, (a, b, x, y) in NAMED.items():
        L.append(f'        "{k}": (0x{a:06X}, 0x{b:06X}, {x}, {y}),')
    L += ['    ]', '}', '']
    with open(os.path.join(ROOT, 'Sources', 'LedgerUI', 'XiaPaletteData.swift'), 'w') as f:
        f.write('\n'.join(L))


if __name__ == '__main__':
    write_svgs()
    data = write_json()
    write_page(data)
    p = write_swift()
    write_palette_swift()
    print(f'{len(data)} 个图标 → {p}')
