#!/usr/bin/env python3
"""把一批译文加进两张翻译表。

  python3 scripts/l10n-add.py 文件

文件一行一条：中文原文||英文||西班牙语（原文照代码里的写法抄，\\n、\\" 这些转义原样留着）。
# 开头的行和空行不算。已经在表里的键会被新译文替换。会检查 %@ 的个数对不对得上。
"""
import re, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = {1: "Sources/FinanceCore/L10n/L10n+en.swift", 2: "Sources/FinanceCore/L10n/L10n+es.swift"}
ENTRY = re.compile(r'^        "((?:[^"\\]|\\.)*)": "((?:[^"\\]|\\.)*)",\n', re.M)


def holes(s):
    return len(re.findall(r"%@", s)) + len(set(re.findall(r"%(\d)\$[@MN]", s)))


def main(path):
    rows, bad = [], 0
    for n, line in enumerate(open(path, encoding="utf-8").read().split("\n"), 1):
        if not line or line.startswith("#"): continue
        parts = line.split("||")
        if len(parts) != 3:
            print(f"✗ 第 {n} 行不是三段：{line[:60]}"); bad += 1; continue
        zh, en, es = parts
        for lang, t in (("en", en), ("es", es)):
            if holes(t) != holes(zh):
                print(f"✗ 第 {n} 行 {lang} 的 %@ 个数不对：{zh[:50]}"); bad += 1
            if not t.strip():
                print(f"✗ 第 {n} 行 {lang} 是空的：{zh[:50]}"); bad += 1
        rows.append(parts)
    if bad: sys.exit(1)
    for col, rel in FILES.items():
        p = os.path.join(ROOT, rel)
        src = open(p, encoding="utf-8").read()
        table = dict(ENTRY.findall(src))
        head = src[:src.index("[\n") + 2]
        order = [k for k, _ in ENTRY.findall(src)]
        for r in rows:
            v = r[col].replace('"', '\\"') if '"' in r[col] and '\\"' not in r[col] else r[col]
            if r[0] not in table: order.append(r[0])
            table[r[0]] = v
        body = "".join(f'        "{k}": "{table[k]}",\n' for k in order)
        open(p, "w", encoding="utf-8").write(head + body + "    ]\n}\n")
    print(f"加了 {len(rows)} 条")


if __name__ == "__main__":
    main(sys.argv[1])
