"""颜色：(浅色, 深色, 浅色透明度, 深色透明度)。Swift 里同一份。"""
TINTS = {   # 有语义的色（跟 Theme.swift 对齐，图标用亮一点的版本）
    'brand': (0xE8643A, 0xFF8157), 'ai': (0x5856D6, 0x8C89FF), 'income': (0x1E9E5A, 0x36C77F),
    'warn': (0xE8A000, 0xFFB72B), 'alert': (0xD33F35, 0xFF6A5F), 'fg2': (0x5A5A62, 0xB0B0B7), 'fg3': (0x8C8C93, 0x8C8C93),
}
SOFT_ALPHA = (0.34, 0.42)
TILE_ALPHA = (0.14, 0.20)
NAMED = {
    'sun': (0xFFCF4D, 0xFFC93C, 1, 1), 'sunShade': (0xFFAE2B, 0xFFA21F, .45, .5), 'ray': (0xFFAD38, 0xFFA62B, 1, 1),
    'leaf': (0x4CB963, 0x5CCB72, 1, 1), 'leafStem': (0x3E9E52, 0x4CB963, 1, 1), 'leafVein': (0x2F8A45, 0x2F8A45, .55, .55),
    'shine': (0xFFFFFF, 0xFFFFFF, .85, .8), 'cheek': (0xFF7F93, 0xFF7F93, .6, .6), 'ink': (0x4A3326, 0x4A3326, 1, 1),
    'white': (0xFFFFFF, 0xFFFFFF, 1, 1), 'glass': (0xFFFFFF, 0xFFFFFF, .4, .4), 'tongue': (0xFF6F7D, 0xFF6F7D, 1, 1),
    'sweat': (0x6CC3F5, 0x7FCBF7, 1, 1), 'bubble': (0x8C89FF, 0x8C89FF, .55, .6), 'zz': (0x5856D6, 0x8C89FF, 1, 1),
    'spark': (0xFF8A4C, 0xFFB052, 1, 1), 'confA': (0xFF7FA8, 0xFF7FA8, 1, 1), 'confB': (0x4C8DF6, 0x5AA0FF, 1, 1),
    'confC': (0x2DB884, 0x36C77F, 1, 1), 'ground': (0x000000, 0xFFFFFF, .07, .08),
}
def tint_hex(t, dark=False):
    if t is None: return None
    if t in TINTS: return TINTS[t][1 if dark else 0]
    return int(t, 16)
