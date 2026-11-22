"""空状态插画（160 x 120）：一块地面阴影 + 放大的道具图标 + 几颗小星星。
夏夏本人的形象由「用 ChatGPT 生成夏夏动态形象」线程另做，这里不画她。"""
from geom import *
from icons import ICONS


def place(layers, s, dx, dy, tint=None):
    out = []
    for paint, p, w in layers:
        if tint and paint in ('soft', 'solid', 'hi', 'cut'):
            paint = f"{paint}:{tint}"
        out.append((paint, p.scale(s).move(dx, dy), w * s))
    return out


ILLOS = {}

def illo(name, label, prop, tint):
    t = tint or ICONS[prop]['tint']
    layers = [('ground', ellipse(80, 106, 46, 6), 0)]
    layers += place(ICONS[prop]['layers'], 3.6, 80 - 12 * 3.6, 58 - 12 * 3.6, t)
    layers += [(f'solid:{t}', star4(126, 26, 6), 0), (f'soft:{t}', star4(36, 40, 4.4), 0), (f'soft:{t}', star4(122, 80, 3.4), 0)]
    ILLOS['illo.' + name] = dict(name='illo.' + name, label=label, group='illustration', size=(160, 120), layers=layers)

illo('ledger', '账本还是空的', 'education', 'brand')
illo('month', '这个月还没有流水', 'act.calendar', 'brand')
illo('spending', '还没花钱', 'nav.spending', 'brand')
illo('trends', '流水还不够看趋势', 'nav.trends', 'ai')
illo('accounts', '还没有账户', 'savings', None)
illo('plans', '还没有计划', 'nav.plans', 'income')
illo('search', '没找到', 'act.search', 'fg3')
illo('connect', '还没连上 AI', 'act.link', 'ai')
illo('error', '出了点问题', 'badge.warn', 'warn')
illo('done', '都处理好了', 'badge.done', 'income')
illo('loading', '正在读', 'act.sync', 'ai')
