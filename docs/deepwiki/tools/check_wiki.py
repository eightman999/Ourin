#!/usr/bin/env python3
"""DeepWiki の機械検証: 出典リンクの実在・行範囲・ラベル整合、wiki 内リンク、出典のない節、mermaid 抽出。

usage: check_wiki.py <repo_root> [--mermaid-out FILE] [--quiet]
"""
import json
import re
import subprocess
import sys
from pathlib import Path

LINK_RE = re.compile(r'(?<!!)\[([^\]\n]*)\]\(([^)\s]+)\)')
ANCHOR_RE = re.compile(r'^L(\d+)(?:-L(\d+))?$')
LABEL_RE = re.compile(r'^`?([^`:\s]+?):(\d+)(?:-(\d+))?`?$')
HEADING_RE = re.compile(r'^(#{2,3})\s+(.*)$')


def main():
    repo = Path(sys.argv[1]).resolve()
    mermaid_out = None
    if '--mermaid-out' in sys.argv:
        mermaid_out = sys.argv[sys.argv.index('--mermaid-out') + 1]
    quiet = '--quiet' in sys.argv
    wiki = repo / 'docs' / 'deepwiki'
    tracked = set(subprocess.run(['git', '-C', str(repo), 'ls-files'], capture_output=True, text=True).stdout.split('\n'))
    tracked_dirs = set()
    for t in tracked:
        p = Path(t)
        for parent in p.parents:
            tracked_dirs.add(str(parent))
    line_cache = {}

    def nlines(p: Path):
        if p not in line_cache:
            with open(p, 'rb') as f:
                data = f.read()
            n = data.count(b'\n')
            if data and not data.endswith(b'\n'):
                n += 1
            line_cache[p] = n
        return line_cache[p]

    errors = []
    warnings = []
    stats = {'pages': 0, 'code_links': 0, 'line_links': 0, 'wiki_links': 0, 'mermaid': 0}
    mermaids = []
    for md in sorted(wiki.glob('*.md')):
        stats['pages'] += 1
        text = md.read_text(encoding='utf-8')
        lines = text.split('\n')
        in_code = False
        fence = None
        cur_mermaid = None
        section = None
        section_has_src = True
        section_line = 0
        for i, line in enumerate(lines, 1):
            stripped = line.strip()
            if stripped.startswith('```') or stripped.startswith('~~~'):
                if not in_code:
                    in_code = True
                    fence = stripped[:3]
                    lang = stripped[3:].strip()
                    if lang == 'mermaid':
                        cur_mermaid = {'file': md.name, 'line': i, 'code': []}
                    continue
                elif stripped.startswith(fence):
                    in_code = False
                    if cur_mermaid is not None:
                        cur_mermaid['code'] = '\n'.join(cur_mermaid['code'])
                        mermaids.append(cur_mermaid)
                        stats['mermaid'] += 1
                        cur_mermaid = None
                    continue
            if in_code:
                if cur_mermaid is not None:
                    cur_mermaid['code'].append(line)
                continue
            h = HEADING_RE.match(line)
            if h and h.group(1) == '##':
                if section is not None and not section_has_src and md.name != 'README.md':
                    warnings.append(f'{md.name}:{section_line}: 節「{section}」に出典がない')
                section = h.group(2).strip()
                section_line = i
                section_has_src = section in ('関連ページ',) or section.startswith('関連ページ')
            if '**出典' in line or '出典:' in line:
                section_has_src = True
            scan = re.sub(r'`[^`]*`', lambda mm: mm.group(0) if '](' not in mm.group(0) else '', line)
            for m in LINK_RE.finditer(scan):
                label, target = m.group(1), m.group(2)
                if re.match(r'^[a-z]+://', target) or target.startswith('mailto:'):
                    continue
                if target.startswith('#'):
                    continue
                path_part, _, anchor = target.partition('#')
                resolved = (md.parent / path_part).resolve()
                try:
                    rel = str(resolved.relative_to(repo))
                except ValueError:
                    errors.append(f'{md.name}:{i}: リポジトリ外へのリンク {target}')
                    continue
                if resolved.parent == wiki and path_part.endswith('.md') and '/' not in path_part.lstrip('./'):
                    stats['wiki_links'] += 1
                    if not resolved.exists():
                        errors.append(f'{md.name}:{i}: wiki ページが存在しない {target}')
                    continue
                stats['code_links'] += 1
                if not resolved.exists():
                    errors.append(f'{md.name}:{i}: ファイルが存在しない {target}')
                    continue
                if resolved.is_file() and rel not in tracked:
                    warnings.append(f'{md.name}:{i}: git 管理外のファイル {rel}')
                if resolved.is_dir() and rel not in tracked_dirs:
                    warnings.append(f'{md.name}:{i}: git 管理外のディレクトリ {rel}')
                lm = LABEL_RE.match(label.strip())
                if anchor:
                    am = ANCHOR_RE.match(anchor)
                    if not am:
                        if resolved.is_file():
                            warnings.append(f'{md.name}:{i}: 行アンカーでないアンカー {target}')
                        continue
                    if resolved.is_dir():
                        errors.append(f'{md.name}:{i}: ディレクトリに行アンカー {target}')
                        continue
                    stats['line_links'] += 1
                    a, b = int(am.group(1)), int(am.group(2) or am.group(1))
                    n = nlines(resolved)
                    if a < 1 or b < a or b > n:
                        errors.append(f'{md.name}:{i}: 行範囲が不正 {rel}#L{a}-L{b}（ファイルは {n} 行）')
                    if lm:
                        lp, la, lb = lm.group(1), int(lm.group(2)), int(lm.group(3) or lm.group(2))
                        if lp != rel:
                            errors.append(f'{md.name}:{i}: ラベルのパス {lp} とリンク先 {rel} が不一致')
                        if (la, lb) != (a, b):
                            errors.append(f'{md.name}:{i}: ラベルの行 {la}-{lb} とアンカー L{a}-L{b} が不一致')
                    elif ':' in label and re.search(r':\d', label):
                        warnings.append(f'{md.name}:{i}: ラベル書式が想定外 [{label}]')
                else:
                    if lm:
                        errors.append(f'{md.name}:{i}: ラベルに行番号があるのにアンカーがない [{label}]({target})')
        if section is not None and not section_has_src and md.name != 'README.md':
            warnings.append(f'{md.name}:{section_line}: 節「{section}」に出典がない')
        if in_code:
            errors.append(f'{md.name}: コードブロックが閉じていない')
    if mermaid_out:
        Path(mermaid_out).write_text(json.dumps(mermaids, ensure_ascii=False), encoding='utf-8')
    print(json.dumps(stats, ensure_ascii=False))
    print(f'errors={len(errors)} warnings={len(warnings)}')
    for e in errors:
        print('ERROR', e)
    if not quiet:
        for w in warnings:
            print('WARN ', w)
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
