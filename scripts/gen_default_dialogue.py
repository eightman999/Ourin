#!/usr/bin/env python3
"""scripts/data/default_dialogue.json から、標準ゴーストの会話辞書 dialogue.dic を生成する。

JSON は { "talks": [ { "category", "id", "lines": [ {"who", "face", "text"} ] } ] } 形式。
who: 0=さくら(\\0) 1=りんね(\\1) 2=ベル(\\p[2])。生成物は手で編集しない。"""
import json
import re
import sys
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "scripts/data/default_dialogue.json"
DST = ROOT / "DefaultGhost/sakura/ghost/master/dialogue.dic"
SCOPE = {0: r"\0", 1: r"\1", 2: r"\p[2]"}
FACES = {0: {0, 1, 3, 4, 5, 6, 7, 8}, 1: {100, 101, 103, 104, 105, 106, 107, 108}, 2: {10, 11, 12, 13}}
FORBIDDEN = re.compile(r'[\\%"{}\n\r]')


def script(lines):
    out, prev = [], None
    for i, line in enumerate(lines):
        who, face, text = line["who"], line["face"], line["text"].strip()
        if who not in FACES or face not in FACES[who]:
            raise ValueError(f"invalid who/face: {line}")
        if FORBIDDEN.search(text):
            raise ValueError(f"forbidden character: {text}")
        if who != prev:
            out.append(SCOPE[who])
            prev = who
        out.append(rf"\s[{face}]{text}")
        if i < len(lines) - 1:
            out.append(r"\n")
    out.append(r"\e")
    return "".join(out)


def main():
    data = json.loads(SRC.read_text(encoding="utf-8"))
    groups = OrderedDict()
    for talk in data["talks"]:
        groups.setdefault(talk["category"], []).append(script(talk["lines"]))
    parts = [
        "// 自動生成: scripts/gen_default_dialogue.py（元データ: scripts/data/default_dialogue.json）",
        "// 手で編集せず、元データを直して再生成する。",
        "",
    ]
    for category, scripts in groups.items():
        parts.append(f"Talk_{category}")
        parts.append("{")
        parts.extend(f'\t"{s}"' for s in scripts)
        parts.append("}")
        parts.append("")
    DST.write_text("\n".join(parts), encoding="utf-8")
    print(f"generated {DST} ({len(groups)} functions, {sum(len(v) for v in groups.values())} talks)")


if __name__ == "__main__":
    sys.exit(main())
