#!/usr/bin/env python3
"""把界面代码里的中文字符串包上 tr(…)。一次性的搬运工具：给还没包过的文件用，包完看一眼 diff 再提交。

  python3 scripts/l10n-wrap.py [--dry] 文件…

不包的：三引号的大段文字（多半是给 AI 的提示词）、拿来比较或当键用的（== "…"、case "…":、字典键、
accessibilityIdentifier、page:/prompt: 这些给 AI 的参数）、枚举的原始值。跳过的会列出来，自己看要不要手动处理。
"""
import re, sys

HAN = re.compile(r"[一-鿿]")
# 字符串前面是这些，就不是给人看的字，不包。
SKIP_BEFORE = re.compile(
    r"(?:\btr\(|\btrKey\(|==\s*|!=\s*|accessibilityIdentifier\(|AppStorage\(|\bforKey:\s*|\bpage:\s*|\bprompt:\s*|\bquestion:\s*|"
    r"\bauthor:\s*|\bsystemImage:\s*|\bsystemName:\s*|\bnamed:\s*|\bImage\(|\brawValue:\s*|\bcontains\(|\bhasPrefix\(|\bhasSuffix\(|"
    r"\bof:\s*|\bwith:\s*|\bseparatedBy:\s*|\bseparator:\s*|\bcategory:\s*|\bbookID:\s*|\bid:\s*|\bkey:\s*|\bidentifier:\s*|"
    r"\bdateFormat\s*=\s*|\bfatalError\(|\bprint\(|\bassert\w*\([^\n]*|\bcase\s+\w+\s*=\s*|,\s*\w+\s*=\s*)$")


def scan_literal(s, i):
    """s[i] 是开头的引号。返回 (结束位置, 改过的文字, 自己这层有没有中文, 有没有插值)。里面嵌的字符串递归处理。"""
    out, j, han, interp = ['"'], i + 1, False, False
    while j < len(s):
        c = s[j]
        if c == "\\":
            if s[j + 1] == "(":
                interp = True
                depth, k, buf = 1, j + 2, ["\\("]
                while k < len(s) and depth:
                    ch = s[k]
                    if ch == '"':
                        end, text, h, _ = scan_literal(s, k)
                        before = "".join(buf)
                        buf.append(f"tr({text})" if h and not SKIP_BEFORE.search(before) else text)
                        k = end
                        continue
                    depth += ch == "("
                    depth -= ch == ")"
                    buf.append(ch)
                    k += 1
                out.append("".join(buf))
                j = k
                continue
            out.append(s[j:j + 2]); j += 2
            continue
        if c == '"':
            out.append('"')
            return j + 1, "".join(out), han, interp
        if c == "\n": raise ValueError("字符串没合上")
        han = han or bool(HAN.match(c))
        out.append(c); j += 1
    raise ValueError("字符串没合上")


def wrap(src):
    out, i, n, skipped, count = [], 0, len(src), [], 0
    while i < n:
        c = src[i]
        if src.startswith("//", i):
            e = src.find("\n", i); e = n if e < 0 else e
            out.append(src[i:e]); i = e; continue
        if src.startswith("/*", i):
            e = src.find("*/", i) + 2
            out.append(src[i:e]); i = e; continue
        if src.startswith('"""', i):
            e = src.find('"""', i + 3) + 3
            out.append(src[i:e]); i = e; continue
        if src.startswith('#"', i):
            e = src.find('"#', i + 2) + 2
            out.append(src[i:e]); i = e; continue
        if c == '"':
            end, text, han, _ = scan_literal(src, i)
            done = "".join(out)
            line = done[done.rfind("\n") + 1:]
            rest = src[end:end + 4]
            why = None
            if han or "tr(" in text:
                if SKIP_BEFORE.search(line): why = "前面的写法说明不是给人看的"
                elif rest.startswith(":") or re.match(r"\s*(==|!=)", rest): why = "当键或拿来比较"
                elif line.rstrip().endswith("[") and rest.startswith("]"): why = "下标"
                elif line.lstrip().startswith("case ") and ":" not in strip_strings(line): why = "case 的匹配值或枚举原始值"
                elif line.lstrip().startswith("@"): why = "属性"
            if han and why is None:
                out.append(f"tr({text})"); count += 1
            else:
                # 不包外面这层；里面嵌的也按原样留着，免得半包
                out.append(src[i:end] if why else text)
                if han and why: skipped.append((done.count("\n") + 1, why, src[i:end][:70]))
            i = end; continue
        out.append(c); i += 1
    return "".join(out), count, skipped


def strip_strings(line):
    return re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)


if __name__ == "__main__":
    dry = "--dry" in sys.argv
    total = 0
    for path in [a for a in sys.argv[1:] if not a.startswith("--")]:
        src = open(path, encoding="utf-8").read()
        new, count, skipped = wrap(src)
        total += count
        print(f"{path}: 包了 {count} 处，跳过 {len(skipped)} 处")
        for ln, why, text in skipped: print(f"    {ln}: {why}: {text}")
        if not dry and new != src: open(path, "w", encoding="utf-8").write(new)
    print(f"一共包了 {total} 处")
