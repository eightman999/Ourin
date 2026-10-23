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
SRCS = [ROOT / "scripts/data/default_dialogue.json", ROOT / "scripts/data/default_dialogue_events.json"]
DST = ROOT / "DefaultGhost/sakura/ghost/master/dialogue.dic"
SCOPE = {0: r"\0", 1: r"\1", 2: r"\p[2]"}
FACES = {0: {0, 1, 3, 4, 5, 6, 7, 8}, 1: {100, 101, 103, 104, 105, 106, 107, 108}, 2: {10, 11, 12, 13}}
FORBIDDEN = re.compile(r'[\\%"{}\n\r<>]')
PLACEHOLDER = re.compile(r"<<(R[0-7]|HOUR)>>")

# 埋め込み記号を使ってよいカテゴリ（前方一致）と、使える記号。
ALLOWED_PLACEHOLDERS = [
    ("chime_noon", set()), ("chime_midnight", set()),
    ("chime_", {"HOUR"}),
    ("vanished", {"R0"}), ("install_complete_all", set()), ("install_complete", {"R1"}),
    ("ghost_changing", {"R0"}), ("ghost_changed", {"R0"}), ("ghost_calling", {"R0"}),
    ("battery_", {"R0"}), ("shell_changed", {"R1"}),
]


def allowed_placeholders(category):
    for prefix, allowed in ALLOWED_PLACEHOLDERS:
        if category.startswith(prefix):
            return allowed
    return set()


def yaya_expr(token):
    """埋め込み記号を YAYA の式へ。参照値は台本の注入を避けるため Esc() を通す。"""
    if token == "HOUR":
        return "TOSTR(GETTIME[3])"
    return f"Esc(reference[{token[1]}])"


def script(lines, category):
    allowed = allowed_placeholders(category)
    parts, prev = [], None  # parts: ("lit", str) / ("expr", str)

    def lit(text):
        if parts and parts[-1][0] == "lit":
            parts[-1] = ("lit", parts[-1][1] + text)
        else:
            parts.append(("lit", text))

    for i, line in enumerate(lines):
        who, face, text = line["who"], line["face"], line["text"].strip()
        if who not in FACES or face not in FACES[who]:
            raise ValueError(f"invalid who/face: {line}")
        used = set(PLACEHOLDER.findall(text))
        if not used <= allowed:
            raise ValueError(f"placeholder not allowed in {category}: {text}")
        plain = PLACEHOLDER.sub("", text)
        if FORBIDDEN.search(plain):
            raise ValueError(f"forbidden character: {text}")
        if who != prev:
            lit(SCOPE[who])
            prev = who
        lit(rf"\s[{face}]")
        pos = 0
        for m in PLACEHOLDER.finditer(text):
            lit(text[pos:m.start()])
            parts.append(("expr", yaya_expr(m.group(1))))
            pos = m.end()
        lit(text[pos:])
        if i < len(lines) - 1:
            lit(r"\n")
    lit(r"\e")
    return " + ".join(f'"{v}"' if kind == "lit" else v for kind, v in parts)


def main():
    groups = OrderedDict()
    seen = set()
    for src in SRCS:
        data = json.loads(src.read_text(encoding="utf-8"))
        for talk in data["talks"]:
            if talk["id"] in seen:
                raise ValueError(f"duplicate id: {talk['id']}")
            seen.add(talk["id"])
            groups.setdefault(talk["category"], []).append(script(talk["lines"], talk["category"]))
    parts = [
        "// 自動生成: scripts/gen_default_dialogue.py（元データ: scripts/data/default_dialogue*.json）",
        "// 手で編集せず、元データを直して再生成する。",
        "",
    ]
    for category, scripts in groups.items():
        parts.append(f"Talk_{category}")
        parts.append("{")
        parts.extend(f"\t{s}" for s in scripts)
        parts.append("}")
        parts.append("")
    DST.write_text("\n".join(parts), encoding="utf-8")
    print(f"generated {DST} ({len(groups)} functions, {sum(len(v) for v in groups.values())} talks)")


if __name__ == "__main__":
    sys.exit(main())
