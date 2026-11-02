#!/usr/bin/env python3
"""Build a single-file HTML wiki from docs/deepwiki/*.md.

usage:
  python3 build_site.py [--repo ROOT] [--out FILE] [--artifact-out FILE] [--no-mermaid]

The Markdown pages stay the source of truth. This script renders them into one
self-contained HTML file (hash routing, sidebar, page outline, search, prev/next,
light/dark themes). Mermaid diagrams are rendered ahead of time into inline SVG
(light and dark variants) by render_mermaid.js. Source references
(`../../path#Lx-Ly`) become GitHub links pinned to the commit in site.json.

Requirements: Python 3.9+, markdown-it-py, Pygments; Node.js with the packages in
package.json (mermaid, playwright) for diagrams. With --no-mermaid (or without Node)
diagrams are shown as their Mermaid source.
"""
import argparse
import hashlib
import html
import json
import os
import re
import subprocess
import sys
import tempfile
import unicodedata
from datetime import date
from pathlib import Path

from markdown_it import MarkdownIt
from pygments import highlight
from pygments.formatters import HtmlFormatter
from pygments.lexers import get_lexer_by_name
from pygments.util import ClassNotFound

TOOLS = Path(__file__).resolve().parent
WIKI = TOOLS.parent

# --------------------------------------------------------------------------- utilities


def git(repo, *args):
    return subprocess.run(['git', '-C', str(repo), *args], capture_output=True, text=True, check=True).stdout.strip()


def gh_slug(text):
    """GitHub-style heading slug (approximate): lower-case, drop punctuation, spaces to '-'."""
    t = re.sub(r'<[^>]+>', '', text)
    t = t.replace('`', '').replace('*', '')
    t = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', t)
    t = t.strip().lower()
    t = re.sub(r'[^\w\- ]', '', t)
    return t.replace(' ', '-')


def strip_tags(s):
    s = re.sub(r'<(script|style|svg)\b.*?</\1>', ' ', s, flags=re.S)
    s = re.sub(r'<[^>]+>', ' ', s)
    s = html.unescape(s)
    return re.sub(r'\s+', ' ', s).strip()


def esc(s):
    return html.escape(s, quote=True)


def json_for_script(obj):
    return json.dumps(obj, ensure_ascii=False, separators=(',', ':')).replace('</', '<\\/')


# --------------------------------------------------------------------------- page model

DETAILS_RE = re.compile(r'<details>\s*<summary>(.*?)</summary>(.*?)</details>\s*', re.S)
LINK_MD_RE = re.compile(r'\[([^\]]+)\]\(([^)\s]+)\)')
NUM_RE = re.compile(r'^(\d+(?:\.\d+)?)\s+(.*)$')


class Page:
    def __init__(self, path):
        self.path = path
        self.file = path.name
        self.id = 'home' if path.stem == 'README' else path.stem
        raw = path.read_text(encoding='utf-8')
        m = re.match(r'#\s+(.+)\n', raw)
        self.title = m.group(1).strip() if m else path.stem
        body = raw[m.end():] if m else raw
        self.related = []
        dm = DETAILS_RE.search(body)
        if dm and '関連ソースファイル' in dm.group(1):
            for lm in LINK_MD_RE.finditer(dm.group(2)):
                self.related.append(lm.group(2))
            body = body[:dm.start()] + body[dm.end():]
        self.body = body
        nm = NUM_RE.match(self.title)
        self.num, self.short = (nm.group(1), nm.group(2)) if nm else ('', self.title)
        self.group = ''
        self.desc = ''
        self.headings = []  # (level, text_html, id, slug)
        self.html = ''
        self.sections = []
        self.stats = {}


def parse_nav(readme_text, pages_by_file):
    """Groups and order come from the README tables: '### group' then '| [title](./file.md) | desc |'."""
    groups = []
    cur = None
    for line in readme_text.split('\n'):
        hm = re.match(r'^###\s+(.+)$', line)
        if hm:
            cur = {'name': hm.group(1).strip(), 'pages': []}
            groups.append(cur)
            continue
        rm = re.match(r'^\|\s*\[([^\]]+)\]\(\./([^)#]+\.md)\)\s*\|\s*(.*?)\s*\|\s*$', line)
        if rm and cur is not None and rm.group(2) in pages_by_file:
            p = pages_by_file[rm.group(2)]
            p.group = cur['name']
            p.desc = rm.group(3)
            cur['pages'].append(p)
    listed = {p.file for g in groups for p in g['pages']}
    rest = [p for f, p in sorted(pages_by_file.items()) if f not in listed and p.id != 'home']
    if rest:
        groups.append({'name': 'その他', 'pages': rest})
        for p in rest:
            p.group = 'その他'
    return groups


# --------------------------------------------------------------------------- markdown rendering


class Renderer:
    def __init__(self, cfg, repo, sha, pages):
        self.cfg = cfg
        self.repo = repo
        self.sha = sha
        self.pages = {p.id: p for p in pages}
        self.diagrams = {}  # key -> code
        self.md = MarkdownIt('commonmark', {'html': True, 'linkify': False, 'typographer': False}).enable('table').enable('strikethrough')
        self.cur = None
        self.formatter = HtmlFormatter(nowrap=True)
        r = self.md.renderer.rules
        self._default_link_open = r.get('link_open')
        r['link_open'] = self.r_link_open
        r['fence'] = self.r_fence
        r['code_block'] = self.r_code_block
        r['heading_open'] = self.r_heading_open
        r['heading_close'] = self.r_heading_close
        r['table_open'] = lambda t, i, o, e, s=None: '<div class="table-wrap"><table>\n'
        r['table_close'] = lambda t, i, o, e, s=None: '</table></div>\n'
        r['paragraph_open'] = self.r_paragraph_open

    # ---- headings (pass 1 collects them so that anchors across pages resolve)
    def collect_headings(self, page):
        tokens = self.md.parse(page.body)
        n = 0
        page.headings = []
        for i, t in enumerate(tokens):
            if t.type == 'heading_open' and t.tag in ('h2', 'h3'):
                n += 1
                inline = tokens[i + 1]
                hid = f'{page.id}--s{n}'
                page.headings.append((int(t.tag[1]), inline.content, hid, gh_slug(inline.content)))

    def anchor_for(self, pid, frag):
        page = self.pages.get(pid)
        if not page or not frag:
            return pid
        want = frag.lower()
        for lvl, text, hid, slug in page.headings:
            if slug == want or gh_slug(frag) == slug:
                return hid
        return pid

    # ---- links
    def rewrite(self, href):
        if re.match(r'^[a-z][a-z0-9+.-]*:', href, re.I):
            return href, 'ext'
        if href.startswith('#'):
            return '#' + self.anchor_for(self.cur.id, href[1:]), 'wiki'
        path, _, frag = href.partition('#')
        target = os.path.normpath(os.path.join('docs/deepwiki', path)).replace(os.sep, '/')
        if target.startswith('docs/deepwiki/') and target.endswith('.md') and '/' not in target[len('docs/deepwiki/'):]:
            stem = target[len('docs/deepwiki/'):-3]
            pid = 'home' if stem == 'README' else stem
            if pid in self.pages:
                return '#' + self.anchor_for(pid, frag), 'wiki'
        if target.startswith('..'):
            return href, 'ext'
        absolute = self.repo / target
        base = f'https://github.com/{self.cfg["github"]}'
        if absolute.is_dir():
            return f'{base}/tree/{self.sha}/{target}', 'src'
        url = f'{base}/blob/{self.sha}/{target}'
        if frag:
            if target.lower().endswith(('.md', '.markdown')) and frag.startswith('L'):
                url += '?plain=1'
            url += '#' + frag
        return url, 'src'

    def r_link_open(self, tokens, idx, options, env):
        t = tokens[idx]
        href = t.attrGet('href') or ''
        new, kind = self.rewrite(href)
        t.attrSet('href', new)
        if kind in ('ext', 'src'):
            t.attrSet('target', '_blank')
            t.attrSet('rel', 'noopener')
        if kind == 'src':
            t.attrSet('class', 'src')
        return self.md.renderer.renderToken(tokens, idx, options, env)

    # ---- headings
    def r_heading_open(self, tokens, idx, options, env):
        t = tokens[idx]
        if t.tag in ('h2', 'h3'):
            env['hn'] = env.get('hn', 0) + 1
            hid = f'{self.cur.id}--s{env["hn"]}'
            t.attrSet('id', hid)
            env['open_hid'] = hid
        return self.md.renderer.renderToken(tokens, idx, options, env)

    def r_heading_close(self, tokens, idx, options, env):
        t = tokens[idx]
        extra = ''
        if t.tag in ('h2', 'h3') and env.get('open_hid'):
            extra = f'<a class="h-anchor" href="#{env["open_hid"]}" aria-label="この節へのリンク">#</a>'
            env['open_hid'] = None
        return extra + f'</{t.tag}>\n'

    # ---- paragraphs: 出典 / 注意
    def r_paragraph_open(self, tokens, idx, options, env):
        inline = tokens[idx + 1] if idx + 1 < len(tokens) else None
        content = inline.content.lstrip() if inline is not None and inline.type == 'inline' else ''
        cls = None
        if re.match(r'^\*\*出典[:：]?\*\*|^出典[:：]', content):
            cls = 'sources'
            if inline is not None and inline.children:
                # drop the "、" separators between source links
                for ch in inline.children:
                    if ch.type == 'text' and ch.content.strip() in ('、', ',', '，', '・'):
                        ch.content = ' '
        elif re.match(r'^(\*\*)?注意', content):
            cls = 'note'
        elif re.match(r'^(\*\*)?(推測|未確認)', content):
            cls = 'note note-guess'
        if cls and not tokens[idx].hidden:
            return f'<p class="{cls}">'
        return self.md.renderer.renderToken(tokens, idx, options, env)

    # ---- code
    def code_html(self, code, lang):
        lang = (lang or '').strip().split()[0] if lang else ''
        alias = {'sh': 'bash', 'shell': 'bash', 'console': 'bash', 'zsh': 'bash', 'objc': 'objective-c', 'objcpp': 'objective-c++',
                 'cl': 'c', 'opencl': 'c', 'glsl': 'glsl', 'plist': 'xml', 'txt': 'text', 'jsonl': 'json', 'dic': 'text', 'kis': 'text'}
        name = alias.get(lang.lower(), lang.lower()) if lang else 'text'
        try:
            lexer = get_lexer_by_name(name)
            body = highlight(code, lexer, self.formatter)
        except ClassNotFound:
            body = esc(code)
            name = 'text'
        label = esc(lang) if lang else ''
        return (f'<div class="code"><div class="code-bar"><span class="code-lang">{label}</span>'
                f'<button type="button" class="copy" aria-label="コードをコピー">コピー</button></div>'
                f'<pre class="hl"><code>{body}</code></pre></div>\n')

    def r_fence(self, tokens, idx, options, env):
        t = tokens[idx]
        info = (t.info or '').strip()
        if info.split()[:1] == ['mermaid']:
            code = t.content.rstrip('\n')
            key = hashlib.sha1(code.encode('utf-8')).hexdigest()[:12]
            self.diagrams[key] = code
            env['diagrams'] = env.get('diagrams', 0) + 1
            return f'<!--MERMAID:{key}-->\n'
        return self.code_html(t.content, info)

    def r_code_block(self, tokens, idx, options, env):
        return self.code_html(tokens[idx].content, '')

    def render_body(self, page, text):
        self.cur = page
        env = {}
        out = self.md.render(text, env)
        return out, env


# --------------------------------------------------------------------------- mermaid


def render_mermaid(diagrams, cfg, skip):
    if skip or not diagrams:
        return {}
    payload = {
        'fontFamily': cfg['diagram_font'],
        'themes': cfg['mermaid'],
        'diagrams': [{'key': k, 'code': c} for k, c in diagrams.items()],
    }
    with tempfile.TemporaryDirectory() as td:
        inp = Path(td) / 'in.json'
        out = Path(td) / 'out.json'
        inp.write_text(json.dumps(payload, ensure_ascii=False), encoding='utf-8')
        try:
            subprocess.run(['node', str(TOOLS / 'render_mermaid.js'), str(inp), str(out)], check=True, cwd=str(TOOLS))
        except (OSError, subprocess.CalledProcessError) as e:
            print(f'warning: mermaid rendering failed ({e}); diagrams fall back to source', file=sys.stderr)
            return {}
        return json.loads(out.read_text(encoding='utf-8'))


def clean_svg(svg):
    # Keep Mermaid's natural width as the upper bound, and never shrink a diagram below 72 % of it:
    # a wider diagram scrolls inside its figure (and can be opened full size) instead of becoming unreadable.
    def repl(m):
        w = float(m.group(1))
        return f' style="max-width:{w:.0f}px;min-width:min({w * 0.72:.0f}px,{w:.0f}px)"'
    return re.sub(r'\sstyle="max-width:\s*([\d.]+)px;?"', repl, svg, count=1)


def diagram_html(key, code, rendered):
    r = rendered.get(key) or {}
    if r.get('light') and r.get('dark'):
        return (f'<figure class="diagram" data-key="{key}">'
                f'<div class="mm mm-l">{clean_svg(r["light"])}</div>'
                f'<div class="mm mm-d">{clean_svg(r["dark"])}</div>'
                f'<button type="button" class="zoom" aria-label="図を拡大">拡大</button></figure>')
    note = '図の描画に失敗したため Mermaid のソースを表示している。' if r.get('error') else '図は Mermaid のソースで表示している（描画なしでビルド）。'
    return f'<figure class="diagram diagram-src"><figcaption>{note}</figcaption><pre class="hl"><code>{esc(code)}</code></pre></figure>'


# --------------------------------------------------------------------------- site assembly


def build(args):
    repo = Path(args.repo).resolve() if args.repo else WIKI.parent.parent
    cfg = json.loads((TOOLS / 'site.json').read_text(encoding='utf-8'))
    sha = git(repo, 'rev-parse', cfg['commit'])
    short = sha[:7]
    files = sorted(WIKI.glob('*.md'))
    pages = [Page(p) for p in files]
    by_file = {p.file: p for p in pages}
    home = next(p for p in pages if p.id == 'home')
    groups = parse_nav(home.body, by_file)
    order = [p for g in groups for p in g['pages']]

    rd = Renderer(cfg, repo, sha, pages)
    for p in pages:
        rd.collect_headings(p)

    # home: split README body into intro / reading guide / toc (replaced by cards) / rest
    home_parts = re.split(r'(?m)^(?=## )', home.body)
    for p in pages:
        if p.id == 'home':
            continue
        out, env = rd.render_body(p, p.body)
        p.html = out
        n_src = len(re.findall(r'class="src"', out))
        p.stats = {'sources': n_src, 'diagrams': env.get('diagrams', 0), 'sections': sum(1 for h in p.headings if h[0] == 2),
                   'lines': p.path.read_text(encoding='utf-8').count('\n')}

    home_pre = prerender_home(home, home_parts, rd)
    rendered = render_mermaid(rd.diagrams, cfg, args.no_mermaid)
    failed = [k for k, v in rendered.items() if v.get('error')]

    def inject(htmltext):
        return re.sub(r'<!--MERMAID:([0-9a-f]{12})-->', lambda m: diagram_html(m.group(1), rd.diagrams[m.group(1)], rendered), htmltext)

    # search index (per h2/h3 section)
    search = []
    for p in order:
        parts = re.split(r'(?=<h[23] id=")', p.html)
        secs = []
        intro = strip_tags(parts[0])
        if intro:
            secs.append({'i': p.id, 'h': '', 'x': intro})
        for part in parts[1:]:
            hm = re.match(r'<h[23] id="([^"]+)">(.*?)<a class="h-anchor"[^>]*>#</a></h[23]>', part, re.S)
            if not hm:
                continue
            secs.append({'i': hm.group(1), 'h': strip_tags(hm.group(2)), 'x': strip_tags(part[hm.end():])})
        search.append({'p': p.id, 't': p.title, 'g': p.group, 's': secs})

    # page templates
    tpl = []
    for idx, p in enumerate(order):
        prev_p = order[idx - 1] if idx > 0 else home
        next_p = order[idx + 1] if idx + 1 < len(order) else None
        tpl.append(page_template(p, prev_p, next_p, cfg, sha, inject, rd))
    total = {
        'pages': len(order),
        'sections': sum(p.stats['sections'] for p in order),
        'diagrams': sum(p.stats['diagrams'] for p in order),
        'sources': sum(p.stats['sources'] for p in order),
        'lines': sum(p.stats['lines'] for p in order),
    }
    home_html = home_template(home_pre, groups, inject, cfg, sha, total, order[0] if order else None)
    nav_html = sidebar_html(groups, home)

    meta = {
        'site': cfg['name'],
        'pages': [{'id': p.id, 'title': p.title, 'short': p.short, 'num': p.num, 'group': p.group} for p in [home] + order],
        'search': search,
    }

    head = head_html(cfg, artifact=False)
    body = body_html(cfg, short, sha, nav_html, home_html, tpl, meta, artifact=False)
    full = ('<!doctype html>\n<html lang="ja">\n<head>\n<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
            f'{head}</head>\n<body>\n{body}</body>\n</html>\n')
    out = Path(args.out) if args.out else WIKI / 'site' / 'index.html'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(full, encoding='utf-8')
    print(f'wrote {out} ({out.stat().st_size / 1e6:.2f} MB): {total}, diagrams rendered={len(rendered) - len(failed)} failed={len(failed)}')
    if args.artifact_out:
        a_head = head_html(cfg, artifact=True)
        a_body = body_html(cfg, short, sha, nav_html, home_html, tpl, meta, artifact=True)
        ap = Path(args.artifact_out)
        ap.parent.mkdir(parents=True, exist_ok=True)
        ap.write_text(f'{a_head}{a_body}', encoding='utf-8')
        print(f'wrote {ap} ({ap.stat().st_size / 1e6:.2f} MB)')
    return 1 if failed else 0


def related_html(p, cfg, sha, rd):
    if not p.related:
        return ''
    items = []
    rd.cur = p
    for href in p.related:
        url, kind = rd.rewrite(href)
        label = os.path.normpath(os.path.join('docs/deepwiki', href.split('#')[0])).replace(os.sep, '/')
        items.append(f'<li><a class="src" href="{esc(url)}" target="_blank" rel="noopener">{esc(label)}</a></li>')
    return (f'<details class="related"><summary><span>関連ソースファイル</span><span class="count">{len(items)}</span></summary>'
            f'<p class="related-note">このページは次のファイルをもとに作成した（commit <code>{sha[:7]}</code>）。</p>'
            f'<ul>{"".join(items)}</ul></details>')


def pager(prev_p, next_p):
    def card(p, rel):
        if not p:
            return '<span></span>'
        label = '前のページ' if rel == 'prev' else '次のページ'
        return (f'<a class="pager-{rel}" href="#{p.id}"><span class="pager-label">{label}</span>'
                f'<span class="pager-title">{esc(p.title)}</span></a>')
    return f'<nav class="pager" aria-label="ページ送り">{card(prev_p, "prev")}{card(next_p, "next")}</nav>'


def page_template(p, prev_p, next_p, cfg, sha, inject, rd):
    crumbs = f'<div class="crumbs"><a href="#home">{esc(cfg["name"])}</a><span aria-hidden="true">/</span><span>{esc(p.group)}</span></div>'
    st = p.stats
    meta = (f'<div class="page-meta"><span>{st["sections"]} 節</span><span>図 {st["diagrams"]}</span>'
            f'<span>出典リンク {st["sources"]}</span><span>commit <code>{sha[:7]}</code></span></div>')
    num = f'<span class="h1-num">{esc(p.num)}</span>' if p.num else ''
    head = f'<header class="page-head">{crumbs}<h1>{num}<span>{esc(p.short)}</span></h1>{meta}</header>'
    foot = (f'<footer class="page-foot">Markdown 原本: <code>docs/deepwiki/{esc(p.file)}</code>'
            f' · 出典の行番号は commit <code>{sha[:7]}</code> 時点のもの</footer>')
    body = inject(p.html)
    rel = related_html(p, cfg, sha, rd)
    return (f'<template id="tpl-{p.id}" data-title="{esc(p.title)}"><article class="page">{head}{rel}'
            f'<div class="prose">{body}</div>{pager(prev_p, next_p)}{foot}</article></template>')



def prerender_home(home, parts, rd):
    """Render the README parts (before Mermaid runs, so that its diagrams are collected)."""
    rd.cur = home
    intro_html, _ = rd.render_body(home, parts[0] if parts else '')
    blocks = []
    for part in parts[1:]:
        title = part.split('\n', 1)[0][3:].strip()
        if title == '目次':
            blocks.append(None)  # replaced by the page cards
        else:
            blocks.append(rd.render_body(home, part)[0])
    return intro_html, blocks


def home_template(pre, groups, inject, cfg, sha, total, first):
    intro_html, raw_blocks = pre
    blocks = [cards_html(groups) if b is None else inject(b) for b in raw_blocks]
    stats = (f'<dl class="stats"><div><dt>ページ</dt><dd>{total["pages"]}</dd></div>'
             f'<div><dt>節</dt><dd>{total["sections"]}</dd></div>'
             f'<div><dt>図</dt><dd>{total["diagrams"]}</dd></div>'
             f'<div><dt>出典リンク</dt><dd>{total["sources"]:,}</dd></div>'
             f'<div><dt>対象 commit</dt><dd><a href="https://github.com/{cfg["github"]}/tree/{sha}" target="_blank" rel="noopener"><code>{sha[:7]}</code></a></dd></div></dl>')
    start = f'<a class="btn" href="#{first.id}">{esc(first.title)} から読む</a>' if first else ''
    hero = (f'<header class="hero"><p class="eyebrow">DeepWiki · {esc(cfg["github"])}</p>'
            f'<h1 class="wordmark">{esc(cfg["wordmark"])}</h1><p class="tagline">{esc(cfg["tagline"])}</p>'
            f'{stats}<div class="hero-actions">{start}'
            f'<a class="btn btn-quiet" href="https://github.com/{cfg["github"]}" target="_blank" rel="noopener">GitHub のリポジトリ</a></div></header>')
    return f'<article class="page home">{hero}<div class="prose">{inject(intro_html)}{"".join(blocks)}</div></article>'


def cards_html(groups):
    out = ['<h2 id="home--toc">目次<a class="h-anchor" href="#home--toc" aria-label="この節へのリンク">#</a></h2>']
    for g in groups:
        out.append(f'<section class="group"><h3 class="group-name">{esc(g["name"])}</h3><div class="cards">')
        for p in g['pages']:
            st = p.stats
            out.append(f'<a class="card" href="#{p.id}"><span class="card-num">{esc(p.num)}</span>'
                       f'<span class="card-title">{esc(p.short)}</span><span class="card-desc">{esc(p.desc)}</span>'
                       f'<span class="card-meta">{st["sections"]} 節 · 図 {st["diagrams"]} · 出典 {st["sources"]}</span></a>')
        out.append('</div></section>')
    return ''.join(out)


def sidebar_html(groups, home):
    out = [f'<a class="nav-home" href="#home" data-page="home">トップ</a>']
    for g in groups:
        out.append(f'<div class="nav-group"><p class="nav-group-name">{esc(g["name"])}</p><ul>')
        for p in g['pages']:
            sub = ' nav-sub' if '.' in p.num else ''
            out.append(f'<li class="nav-item{sub}"><a href="#{p.id}" data-page="{p.id}"><span class="nav-num">{esc(p.num)}</span>'
                       f'<span class="nav-title">{esc(p.short)}</span></a></li>')
        out.append('</ul></div>')
    return ''.join(out)


def head_html(cfg, artifact):
    css = (TOOLS / 'site.css').read_text(encoding='utf-8')
    tokens = cfg['tokens']

    def block(d):
        return ';'.join(f'--{k}:{v}' for k, v in d.items())
    theme_css = (f':root{{{block(cfg["consts"])}}}\n'
                 f':root{{{block(tokens["light"])};--mm-l:block;--mm-d:none}}\n'
                 f'@media (prefers-color-scheme: dark){{:root:not([data-theme="light"]){{{block(tokens["dark"])};--mm-l:none;--mm-d:block;color-scheme:dark}}}}\n'
                 f':root[data-theme="dark"]{{{block(tokens["dark"])};--mm-l:none;--mm-d:block;color-scheme:dark}}\n'
                 f':root[data-theme="light"]{{color-scheme:light}}\n')
    fonts = cfg['fonts_url']
    side = '<meta name="claude:viewport-fit-sides" content="cover">\n' if artifact else ''
    return (f'<title>{esc(cfg["title"])}</title>\n{side}'
            f'<meta name="description" content="{esc(cfg["tagline"])}">\n'
            f'<link rel="preconnect" href="https://fonts.googleapis.com">\n<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n'
            f'<link rel="stylesheet" href="{esc(fonts)}">\n'
            f'<style>\n/* layout: sticky top bar, left page tree, reading column, right outline rail; drawer under 900px */\n{theme_css}{css}</style>\n')


def body_html(cfg, short, sha, nav_html, home_html, tpl, meta, artifact):
    js = (TOOLS / 'site.js').read_text(encoding='utf-8')
    toggle = '' if artifact else ('<button type="button" class="icon-btn theme-btn" id="theme-btn" aria-label="配色を切り替える" title="配色: システム">'
                                  '<span class="theme-ico" aria-hidden="true"></span></button>')
    return f'''<div class="topbar"><div class="topbar-in">
<button type="button" class="icon-btn menu-btn" id="menu-btn" aria-label="ページ一覧を開く" aria-expanded="false" aria-controls="sidebar"><span class="menu-ico" aria-hidden="true"></span></button>
<a class="brand" href="#home"><span class="brand-mark" aria-hidden="true"></span><span class="brand-name">{esc(cfg["name"])}</span><span class="brand-sub">DeepWiki</span></a>
<div class="search" role="search"><label class="sr-only" for="q">wiki 内を検索</label><input id="q" type="search" placeholder="検索（/ で移動）" autocomplete="off" spellcheck="false"><div class="results" id="results" hidden></div></div>
<a class="commit-chip" href="https://github.com/{esc(cfg["github"])}/tree/{sha}" target="_blank" rel="noopener" title="この wiki が対象とするコミット">commit <code>{short}</code></a>
{toggle}</div></div>
<div class="scrim" id="scrim" hidden></div>
<div class="layout">
<aside class="sidebar" id="sidebar" aria-label="ページ一覧"><nav>{nav_html}</nav></aside>
<main class="main" id="content" tabindex="-1">{home_html}</main>
<aside class="rail" id="rail" aria-label="このページの内容"><p class="rail-title">このページの内容</p><nav id="rail-nav"></nav></aside>
</div>
<div class="zoom-layer" id="zoom-layer" hidden role="dialog" aria-modal="true" aria-label="拡大した図"><div class="zoom-bar"><span>図の拡大表示</span><button type="button" class="icon-btn" id="zoom-close" aria-label="閉じる">×</button></div><div class="zoom-body" id="zoom-body"></div></div>
<template id="tpl-home" data-title="{esc(cfg["title"])}">{home_html}</template>
{"".join(tpl)}
<script type="application/json" id="wiki-data">{json_for_script(meta)}</script>
<script>{js}</script>
'''


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo', help='repository root (default: two levels above docs/deepwiki)')
    ap.add_argument('--out', help='output HTML (default: docs/deepwiki/site/index.html)')
    ap.add_argument('--artifact-out', help='also write a variant without the document skeleton (for claude.ai artifacts)')
    ap.add_argument('--no-mermaid', action='store_true', help='do not pre-render diagrams')
    args = ap.parse_args()
    return build(args)


if __name__ == '__main__':
    sys.exit(main())
