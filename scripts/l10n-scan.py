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

def parse_string(code, i):
    """code[i] 是开头的引号。返回 (键, 结束位置, 里面嵌套的 tr 键)。插值里可以再有字符串和 tr。"""
    out, nested, i = "", [], i + 1
    while i < len(code) and code[i] != '"':
        if code.startswith("\\(", i):
            depth, i = 1, i + 2
            while i < len(code) and depth:
                if code[i] == '"':
                    is_tr = code[max(0, i - 3):i] == "tr(" and not (i >= 4 and (code[i - 4].isalnum() or code[i - 4] == "_"))
                    k, i, inner = parse_string(code, i)
                    nested += inner + ([k] if is_tr else [])
                    continue
                depth += code[i] == "("; depth -= code[i] == ")"; i += 1
            out += "%@"
        elif code[i] == "\\":
            out += code[i:i + 2]; i += 2
        else:
            out += code[i]; i += 1
    return out, i + 1, nested

def tr_keys(code):
    """一行里所有 tr("…") 的键，含插值里嵌套的。"""
    keys, i = [], 0
    for m in re.finditer(r'\btr\("', code):
        if m.start() < i: continue
        k, i, inner = parse_string(code, m.end() - 1)
        keys += inner + [k]
    return keys

en, es = table("en"), table("es")
wrapped, missing, bare = 0, set(), 0
for f in sorted((root / "Sources").rglob("*.swift")):
    if "L10n" in f.parts or f.name.endswith(".generated.swift") or f.name.endswith("Data.swift"):
        continue
    for line in f.read_text().splitlines():
        code = line.split("//")[0]
        keys = tr_keys(code)
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
