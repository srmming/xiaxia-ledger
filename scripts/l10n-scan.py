#!/usr/bin/env python3
"""多语言进度：数一数界面代码里还有多少中文没包 tr(…)，以及包了但两张表里没有的。

用法：python3 scripts/l10n-scan.py [--list]
  --list  把还没进表的键一行一行列出来（翻译时用）
只读，不改任何文件。
"""
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
han = re.compile(r'[一-鿿]')
tr_call = re.compile(r'\btr\("((?:[^"\\]|\\.)*)"\)')
literal = re.compile(r'"((?:[^"\\]|\\.)*)"')
entry = re.compile(r'^\s*"((?:[^"\\]|\\.)*)":\s*"', re.M)

def table(name):
    return set(entry.findall((root / f"Sources/FinanceCore/L10n/L10n+{name}.swift").read_text()))

def key_of(src):
    # tr("够花 \(n) 个月") 的键是「够花 %@ 个月」
    out, i, depth = "", 0, 0
    while i < len(src):
        if src.startswith("\\(", i):
            depth, i = 1, i + 2
            while i < len(src) and depth:
                depth += src[i] == "("; depth -= src[i] == ")"; i += 1
            out += "%@"
        else:
            out += src[i]; i += 1
    return out

en, es = table("en"), table("es")
wrapped, missing, bare = 0, set(), 0
for f in sorted((root / "Sources").rglob("*.swift")):
    if "L10n" in f.parts or f.name.endswith(".generated.swift") or f.name.endswith("Data.swift"):
        continue
    for line in f.read_text().splitlines():
        code = line.split("//")[0]
        keys = [key_of(k) for k in tr_call.findall(code)]
        wrapped += len(keys)
        missing |= {k for k in keys if k not in en or k not in es}
        rest = tr_call.sub("", code)
        bare += sum(1 for s in literal.findall(rest) if han.search(s))

print(f"已包 tr 的：{wrapped} 处；其中表里还没有的键：{len(missing)} 个")
print(f"还没包 tr 的中文：{bare} 处（含给 AI 的提示词、示例数据等不用翻的）")
print(f"表：英文 {len(en)} 条，西班牙语 {len(es)} 条")
if "--list" in sys.argv:
    for k in sorted(missing): print(k)
sys.exit(1 if missing else 0)
