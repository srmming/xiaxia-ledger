#!/usr/bin/env python3
"""把 skills/fin 下的说明打包进 fin（Sources/FinanceCore/SkillBundle.generated.swift）。
改了 skills/fin 里的文件后跑一次：python3 scripts/gen-skill-bundle.py
（测试 testSkillBundleMatchesRepo 会检查两边是不是一样。）"""
import os, sys
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = os.path.join(root, "skills", "fin")
files = ["SKILL.md", "references/commands.md", "PROMPT.md"]
out = ["// 自动生成，别手改。改 skills/fin 里的文件，再跑 python3 scripts/gen-skill-bundle.py", "",
       "/// fin 自带的 skill 文件（给别人的电脑装 skill 用，那里没有这个仓库）。", "enum SkillBundle {",
       "    static let files: [(path: String, text: String)] = ["]
for f in files:
    text = open(os.path.join(src, f), encoding="utf-8").read()
    if '"""#' in text or "\\#" in text:
        sys.exit(f"{f} 里有 \"\"\"# 或 \\#，没法放进 Swift 原样字符串")
    out.append(f'        ("{f}", #"""')
    out.append(text.rstrip("\n"))
    out.append('"""#),')
out += ["    ]", "}", ""]
open(os.path.join(root, "Sources", "FinanceCore", "SkillBundle.generated.swift"), "w", encoding="utf-8").write("\n".join(out))
print("已生成 Sources/FinanceCore/SkillBundle.generated.swift")
