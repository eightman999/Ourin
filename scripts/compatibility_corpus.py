#!/usr/bin/env python3
"""Bounded public NAR/ZIP corpus checks; never installs into a user's data.

Download/import-structure/runtime rates describe different layers. A probe is run
only inside macOS sandbox-exec; there is no unsandboxed fallback. --resume reuses
matching results; --retry-failed retries error/unverified/unsupported/partial
records. Change --probe-revision after changing engine dependencies not present
in the argv. Third-party payloads are always removed from runner-owned item dirs.
"""
from __future__ import annotations
import argparse
import datetime as dt
import fcntl
import hashlib
import html
import json
import os
from pathlib import Path, PurePosixPath
import re
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zipfile

BASE = Path('/tmp/ourin-corpus-20261025').resolve()
SANDBOX_EXEC = '/usr/bin/sandbox-exec' if Path('/usr/bin/sandbox-exec').is_file() else None
KINDS = {'ghost', 'balloon', 'plugin'}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix='.' + path.name + '.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as output:
            json.dump(value, output, ensure_ascii=False, indent=2)
            output.write('\n')
            output.flush()
            os.fsync(output.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def public_reason(value):
    # Engine errors may contain local paths. Published reports contain metadata,
    # not local account names, probe conversation text, or arbitrary stderr.
    value = str(value).replace(str(BASE), '<corpus>').replace('/tmp/ourin-corpus-20261025', '<corpus>')
    value = re.sub(r'/Users/[^\s"\'<>]+', '<local-path>', value)
    value = re.sub(r'/(?:private/)?(?:tmp|var/folders)/[^\s"\'<>]+', '<temporary-path>', value)
    return value[:1500]


def public_value(value, depth=0):
    if depth > 8:
        return '<depth-limit>'
    if isinstance(value, str):
        return public_reason(value)
    if isinstance(value, dict):
        return {str(k)[:128]: public_value(v, depth + 1) for k, v in list(value.items())[:128]}
    if isinstance(value, list):
        return [public_value(v, depth + 1) for v in value[:128]]
    if value is None or isinstance(value, (bool, int, float)):
        return value
    return str(type(value).__name__)


def valid_url(value):
    if not isinstance(value, str):
        raise ValueError('URL must be a string')
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme not in {'http', 'https'} or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError('only public HTTP(S) URLs without credentials are accepted')
    if any(ord(c) < 32 for c in value):
        raise ValueError('URL contains control characters')
    return value


def load_catalog(path):
    raw = path.read_bytes()
    data = json.loads(raw)
    if not isinstance(data, dict) or data.get('schema') != 1 or not isinstance(data.get('items'), list):
        raise ValueError('catalog must have schema=1 and items array')
    items, ids = [], set()
    for item in data['items']:
        if not isinstance(item, dict) or not isinstance(item.get('id'), str) or not item['id'].strip():
            raise ValueError('every item requires a nonempty string id')
        if item['id'] in ids:
            raise ValueError('duplicate item id')
        ids.add(item['id'])
        if item.get('kind') not in KINDS or not isinstance(item.get('name'), str):
            raise ValueError('invalid item kind/name')
        if item.get('engine_hint') is not None and not isinstance(item['engine_hint'], str):
            raise ValueError('engine_hint must be a string')
        items.append({key: item.get(key) for key in ('id', 'name', 'kind', 'engine_hint')} | {
            'source_url': valid_url(item.get('source_url')), 'download_url': valid_url(item.get('download_url'))})
        if 'github_release_asset' in item:
            asset = item['github_release_asset']
            if not isinstance(asset, str) or not asset or '/' in asset or '\\' in asset or any(ord(c) < 32 for c in asset):
                raise ValueError('github_release_asset must be a filename')
            if items[-1]['download_url'] != items[-1]['source_url']:
                raise ValueError('release asset entries must publish only the source release page')
            github_release_api(items[-1]['source_url'])
            items[-1]['github_release_asset'] = asset
    return items, sha(raw)


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        valid_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def download(url, target, limits):
    result = {'status': 'error', 'http_status': None, 'final_url': url,
              'sha256': None, 'bytes': 0, 'error': None}
    digest = hashlib.sha256()
    deadline = time.monotonic() + limits['timeout']
    try:
        request = urllib.request.Request(url, headers={'User-Agent': 'Ourin-Compatibility-Corpus/1.0'})
        opener = urllib.request.build_opener(SafeRedirect())
        with opener.open(request, timeout=limits['timeout']) as response, target.open('xb') as output:
            result.update(http_status=response.status, final_url=valid_url(response.geturl()))
            length = response.headers.get('Content-Length')
            if length and int(length) > limits['max_download_bytes']:
                raise ValueError('download_size_limit: Content-Length exceeds limit')
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError('download_timeout')
                socket = getattr(getattr(getattr(response, 'fp', None), 'raw', None), '_sock', None)
                if socket is not None:
                    socket.settimeout(remaining)
                chunk = response.read1(min(65536, limits['max_download_bytes'] - result['bytes'] + 1))
                if not chunk:
                    break
                digest.update(chunk)
                result['bytes'] += len(chunk)
                if result['bytes'] > limits['max_download_bytes']:
                    raise ValueError('download_size_limit')
                output.write(chunk)
            if not result['bytes']:
                raise ValueError('empty_download')
            result['status'] = 'success'
    except urllib.error.HTTPError as error:
        result.update(http_status=error.code, final_url=error.geturl(), error=f'HTTP {error.code}')
    except Exception as error:
        result['error'] = public_reason(error)
    if result['bytes']:
        result['sha256'] = digest.hexdigest()
    final = urllib.parse.urlsplit(result['final_url'])
    result['signed_query_redacted'] = bool(final.query or final.fragment)
    result['final_url'] = urllib.parse.urlunsplit((final.scheme, final.netloc, final.path, '', ''))
    return result


def github_release_api(source_url):
    parsed = urllib.parse.urlsplit(source_url)
    match = re.fullmatch(r'/([^/]+)/([^/]+)/releases/(?:tag/(.+)|(latest))/?', parsed.path)
    if parsed.scheme != 'https' or parsed.netloc != 'github.com' or not match or parsed.query or parsed.fragment:
        raise ValueError('github_release_asset requires a GitHub release tag/latest page')
    owner, repo, tag, latest = match.groups()
    suffix = 'latest' if latest else 'tags/' + urllib.parse.quote(urllib.parse.unquote(tag), safe='')
    return f'https://api.github.com/repos/{owner}/{repo}/releases/{suffix}'


def download_item(item, target, limits):
    if not item.get('github_release_asset'):
        return download(item['download_url'], target, limits)
    public_url = item['source_url']
    result = {'status': 'error', 'http_status': None, 'final_url': public_url,
              'sha256': None, 'bytes': 0, 'error': None, 'source_page_only': True}
    try:
        request = urllib.request.Request(github_release_api(public_url), headers={
            'User-Agent': 'Ourin-Compatibility-Corpus/1.0', 'Accept': 'application/vnd.github+json'})
        opener = urllib.request.build_opener(SafeRedirect())
        with opener.open(request, timeout=limits['timeout']) as response:
            metadata = response.read(2 * 1024 * 1024 + 1)
        if len(metadata) > 2 * 1024 * 1024:
            raise ValueError('metadata size limit')
        release = json.loads(metadata)
        assets = [a for a in release.get('assets', []) if a.get('name') == item['github_release_asset']]
        if len(assets) != 1:
            result['error'] = 'release_asset_missing_or_ambiguous'
            return result
        url = valid_url(assets[0]['browser_download_url'])
        asset_url = urllib.parse.urlsplit(url)
        owner_repo = '/'.join(urllib.parse.urlsplit(public_url).path.split('/')[:3])
        if asset_url.scheme != 'https' or asset_url.netloc != 'github.com' or not asset_url.path.startswith(owner_repo + '/releases/download/'):
            raise ValueError('unexpected asset origin')
        fetched = download(url, target, limits)
        # Author disallows published direct links. Neither redirected URLs nor
        # exceptions from this private resolution may enter logs/reports.
        result.update(fetched)
        result['final_url'] = public_url
        result['source_page_only'] = True
        if result['error']:
            result['error'] = 'release_asset_download_failed'
    except urllib.error.HTTPError as error:
        result.update(http_status=error.code, error=f'release_resolution_HTTP_{error.code}')
    except Exception:
        result['error'] = 'release_asset_resolution_failed'
    return result


def entry_path(info):
    name = info.orig_filename
    if '\0' in name:
        raise ValueError('archive_path_nul')
    if not info.flag_bits & 0x800:
        try:
            name = name.encode('cp437').decode('cp932')
        except (UnicodeError, LookupError):
            pass
    name = name.replace('\\', '/')
    if name.startswith('/') or re.match(r'^[A-Za-z]:', name):
        raise ValueError('archive_absolute_path')
    parts = name.rstrip('/').split('/')
    if not parts or any(p in {'', '.', '..'} or ':' in p or any(ord(c) < 32 for c in p) for p in parts):
        raise ValueError('archive_unsafe_path')
    return PurePosixPath(*parts)


def extract_archive(archive, destination, limits):
    result = {'status': 'error', 'entries': 0, 'expanded_bytes': 0, 'reason': None}
    try:
        with zipfile.ZipFile(archive) as source:
            infos = source.infolist()
            result['entries'] = len(infos)
            if len(infos) > limits['max_entries']:
                raise ValueError('archive_entry_limit')
            plan, seen, implicit_dirs = [], set(), set()
            total = 0
            for info in infos:
                path = entry_path(info)
                key = unicodedata.normalize('NFC', str(path)).casefold()
                mode = info.external_attr >> 16
                kind = stat.S_IFMT(mode)
                if kind not in {0, stat.S_IFREG, stat.S_IFDIR}:
                    raise ValueError('archive_symlink_or_special_file')
                if info.flag_bits & 1:
                    raise ValueError('archive_encrypted_entry')
                # Windows NARs commonly use backslash suffixes and DOS directory bits.
                directory = info.orig_filename.endswith(('/', '\\')) or kind == stat.S_IFDIR or bool(info.external_attr & 0x10)
                if directory and info.file_size:
                    raise ValueError('archive_directory_has_payload')
                if key in seen or (key in implicit_dirs and not directory):
                    raise ValueError('archive_duplicate_or_conflicting_path')
                for parent in path.parents:
                    if str(parent) == '.':
                        continue
                    parent_key = unicodedata.normalize('NFC', str(parent)).casefold()
                    if parent_key in seen and parent_key not in implicit_dirs:
                        raise ValueError('archive_file_directory_conflict')
                    implicit_dirs.add(parent_key)
                if directory:
                    implicit_dirs.add(key)
                seen.add(key)
                total += info.file_size
                if total > limits['max_expanded_bytes']:
                    raise ValueError('archive_expanded_size_limit')
                if info.file_size and info.file_size / max(info.compress_size, 1) > limits['max_compression_ratio']:
                    raise ValueError('archive_compression_ratio_limit')
                plan.append((info, path, directory))
            destination.mkdir()
            actual = 0
            for info, path, directory in plan:
                target = destination.joinpath(*path.parts)
                if directory:
                    target.mkdir(parents=True, exist_ok=True)
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                with source.open(info) as stream, target.open('xb') as output:
                    while chunk := stream.read(65536):
                        actual += len(chunk)
                        if actual > limits['max_expanded_bytes']:
                            raise ValueError('archive_expanded_size_limit')
                        output.write(chunk)
            result.update(status='pass', expanded_bytes=actual)
    except Exception as error:
        result['reason'] = public_reason(error)
    return result


def inventory(root, kind):
    files = [p for p in root.rglob('*') if p.is_file()]
    descriptions = [p for p in files if p.name.casefold() == 'descript.txt']
    checks = {'files': len(files), 'descript': bool(descriptions)}
    if kind == 'ghost':
        masters = [p for p in descriptions if p.parent.name.casefold() == 'master'
                   and p.parent.parent.name.casefold() == 'ghost']
        checks['ghost_master'] = bool(masters)
        checks['shell'] = any((p.parent.parent.parent / 'shell').is_dir() for p in masters)
        ok = bool(masters)
    elif kind == 'balloon':
        checks['balloon_images'] = any(p.name.casefold().startswith('balloon') and p.suffix.casefold() == '.png' for p in files)
        ok = bool(descriptions) and checks['balloon_images']
    else:
        checks['module'] = any(p.suffix.casefold() in {'.dll', '.dylib', '.so', '.bundle'} for p in files)
        ok = bool(descriptions) and checks['module']
    return {'status': 'pass' if ok else 'partial', 'layer': 'static_structure', 'checks': checks,
            'reason': 'Static entry structure recognized; application installation and GUI are not tested.' if ok else 'Expected entry structure is incomplete.'}


def bounded_process(argv, payload, cwd, environment, timeout, max_output):
    process = subprocess.Popen(argv, cwd=cwd, env=environment, stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    deadline = time.monotonic() + timeout
    selector = selectors.DefaultSelector()
    collected = {process.stdout: bytearray(), process.stderr: bytearray()}
    failure = None
    try:
        process.stdin.write(payload)
        process.stdin.close()
        for stream in collected:
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, selectors.EVENT_READ)
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                failure = 'probe_timeout'
                break
            for key, _ in selector.select(min(remaining, 0.1)):
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                else:
                    collected[key.fileobj].extend(chunk)
                    if sum(len(data) for data in collected.values()) > max_output:
                        failure = 'probe_output_limit'
                        break
            if failure:
                break
        if not failure:
            try:
                process.wait(timeout=max(0.01, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                failure = 'probe_timeout'
    finally:
        selector.close()
        # Kill residual children in the same group too, even if the direct child exited.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        process.stdout.close()
        process.stderr.close()
    return process.returncode, bytes(collected[process.stdout]), bytes(collected[process.stderr]), failure


def run_probe(command, item, root, work, settings):
    result = {'status': 'unverified', 'executed': False, 'attempted': False, 'checks': {}, 'reason': 'No probe configured (static_only).'}
    if not command:
        return result
    if not SANDBOX_EXEC or not Path(SANDBOX_EXEC).is_file():
        result['reason'] = 'sandbox_unavailable: probe was not run'
        return result
    executable = shutil.which(command[0])
    if not executable:
        result['reason'] = 'probe_executable_unavailable'
        return result
    command = [executable] + command[1:]
    profile = '(version 1)(allow default)(deny network*)(deny file-write* (require-not (subpath ' + json.dumps(str(work.resolve()), ensure_ascii=False) + ')))(allow file-write* (literal "/dev/null"))'
    home, temp = work / 'home', work / 'tmp'
    home.mkdir()
    temp.mkdir()
    environment = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin',
                   'HOME': str(home), 'TMPDIR': str(temp), 'LANG': 'en_US.UTF-8',
                   'PYTHONDONTWRITEBYTECODE': '1', 'OURIN_CORPUS_PARENT_OWNS_GROUP': '1'}
    payload = canonical({**{k: item.get(k) for k in ('id', 'kind', 'engine_hint')}, 'root': str(root)})
    try:
        code, stdout, stderr, failure = bounded_process([SANDBOX_EXEC, '-p', profile] + command, payload,
            work, environment, settings['probe_timeout'], settings['max_probe_output_bytes'])
        result['attempted'] = True
        if failure:
            raise ValueError(failure)
        if code != 0:
            if b'sandbox-exec:' in stderr or b'sandbox_apply:' in stderr:
                result['reason'] = 'sandbox_unavailable: sandbox initialization failed'
                return result
            raise ValueError(f'probe_exit_status_{code}')
        answer = json.loads(stdout)
        if not isinstance(answer, dict) or answer.get('status') not in {'pass', 'partial', 'unsupported', 'error'} or not isinstance(answer.get('checks'), dict):
            raise ValueError('invalid_probe_schema')
        executed = answer['checks'].get('runtime_executed') is True
        status = answer['status']
        reason = answer.get('reason', '')
        if not isinstance(reason, str):
            raise ValueError('invalid_probe_reason')
        if status == 'pass' and not executed:
            status = 'partial'
            reason = 'Probe claimed pass without explicit runtime_executed evidence. ' + reason
        result.update(status=status, executed=executed, checks=public_value(answer['checks']), reason=public_reason(reason))
    except Exception as error:
        result.update(status='error', reason=public_reason(error))
    return result


def cleanup_owned(work_root, record):
    name, token = record.get('artifact'), record.get('token')
    failure = {'status': 'error', 'removed': False, 'reason': 'Owned artifact marker mismatch; no deletion attempted.'}
    if not isinstance(name, str) or '/' in name or not name.startswith('item-') or not isinstance(token, str):
        return failure
    directory = work_root / name
    if not directory.exists() and not directory.is_symlink():
        return {'status': 'pass', 'removed': True, 'reason': 'Artifact directory absent.'}
    if directory.is_symlink():
        return failure
    try:
        if directory.resolve().parent != work_root.resolve():
            return failure
        marker = json.loads((directory / '.ourin-owned.json').read_text())
        if marker.get('token') != token:
            return failure
        shutil.rmtree(directory)
        return {'status': 'pass', 'removed': True, 'reason': 'Downloaded and extracted artifacts removed.'}
    except Exception as error:
        return {'status': 'error', 'removed': False, 'reason': public_reason(error)}


def ratio(numerator, denominator, definition):
    return {'numerator': numerator, 'denominator': denominator,
            'percent': round(100 * numerator / denominator, 2) if denominator else None, 'definition': definition}


def rates(items, selected_count=None):
    selected_count = len(items) if selected_count is None else selected_count
    downloaded = sum(i['download']['status'] == 'success' for i in items)
    imported = sum(i['import']['status'] == 'pass' for i in items)
    tested = sum(i['runtime'].get('executed') is True for i in items)
    passed = sum(i['runtime']['status'] == 'pass' and i['runtime'].get('executed') is True for i in items)
    return {'download': ratio(downloaded, selected_count, 'Downloaded successfully / selected catalog items'),
            'import': ratio(imported, downloaded, 'Recognized static entry structure / successful downloads (not app install)'),
            'runtime_tested': ratio(tested, imported, 'Explicit runtime_executed evidence / recognized static structures'),
            'runtime_pass': ratio(passed, tested, 'Probe runtime pass / items with runtime_executed evidence'),
            'runtime_pass_of_selected': ratio(passed, selected_count, 'Probe runtime pass / all selected catalog items')}


def markdown(report):
    lines = ['# 配布物の互換性検証結果', '', '静的な構成確認は、アプリへのインストール成功や実画面の互換性を保証しません。', '',
             '| 検証層 | 件数 | 率 | 分母の定義 |', '| --- | ---: | ---: | --- |']
    for name, rate in report['rates'].items():
        percent = 'n/a' if rate['percent'] is None else str(rate['percent']) + '%'
        lines.append(f"| {name} | {rate['numerator']}/{rate['denominator']} | {percent} | {rate['definition']} |")
    lines += ['', f"選択件数: {report['selected_count']}。再取得せず結果を再利用: {report['skipped_count']} 件。", '',
              '| 配布物 | 種類 | 取得 | 静的構成 | 実行 | 削除 | 配布元 | ダウンロード |',
              '| --- | --- | --- | --- | --- | --- | --- | --- |']
    def cell(value):
        return html.escape(str(value)).replace('|', '&#124;').replace('\n', ' ').replace('\r', ' ').replace('`', '&#96;').replace('[', '&#91;').replace(']', '&#93;')
    def link(url):
        return '[link](<' + urllib.parse.quote(url, safe=':/?&=%#@+;,-._~') + '>)'
    notes = []
    for item in report['items']:
        lines.append('| ' + ' | '.join([cell(item['name']), item['kind'], item['download']['status'],
            item['import']['status'], item['runtime']['status'], item['cleanup']['status'],
            link(item['source_url']), link(item['download_url'])]) + ' |')
        if item['status'] in {'error', 'partial', 'unsupported', 'unverified'}:
            reason = item['download'].get('error') or item['archive'].get('reason') or item['runtime'].get('reason') or item['import'].get('reason')
            notes.append(f"- {cell(item['name'])}: {cell(reason)}")
    if notes:
        lines += ['', '## 確認事項', ''] + notes
    if report.get('cleanup_pending'):
        lines += ['', '削除が完了していない検証用一時領域: ' + ', '.join(map(cell, report['cleanup_pending']))]
    return '\n'.join(lines) + '\n'


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--markdown', type=Path)
    parser.add_argument('--work-root', type=Path, default=BASE / 'work')
    parser.add_argument('--max-items', type=int, default=100)
    parser.add_argument('--max-download-bytes', type=int, default=128 * 1024 * 1024)
    parser.add_argument('--max-expanded-bytes', type=int, default=512 * 1024 * 1024)
    parser.add_argument('--max-entries', type=int, default=20000)
    parser.add_argument('--max-compression-ratio', type=float, default=1000)
    parser.add_argument('--timeout', type=float, default=30)
    parser.add_argument('--probe-timeout', type=float, default=30)
    parser.add_argument('--max-probe-output-bytes', type=int, default=1024 * 1024)
    parser.add_argument('--probe-command-json', default='[]')
    parser.add_argument('--probe-revision', default='')
    parser.add_argument('--resume', action='store_true')
    parser.add_argument('--retry-failed', action='store_true')
    args = parser.parse_args(argv)
    try:
        work_root = args.work_root.resolve()
        if work_root != BASE and BASE not in work_root.parents:
            raise ValueError('work-root must be within /tmp/ourin-corpus-20261025')
        if args.output.resolve() == args.catalog.resolve() or (args.markdown and args.markdown.resolve() in {args.catalog.resolve(), args.output.resolve()}):
            raise ValueError('catalog/output/markdown must be separate files')
        settings = {key: getattr(args, key) for key in ('max_download_bytes', 'max_expanded_bytes', 'max_entries',
            'max_compression_ratio', 'timeout', 'probe_timeout', 'max_probe_output_bytes', 'probe_revision')}
        if args.max_items < 1 or any(value <= 0 for key, value in settings.items() if key != 'probe_revision'):
            raise ValueError('all limits must be positive')
        command = json.loads(args.probe_command_json)
        if not isinstance(command, list) or not all(isinstance(s, str) and s and '\0' not in s for s in command):
            raise ValueError('probe-command-json must be an argv array')
        settings['probe_command'] = command
        settings['probe_files'] = {str(Path(arg).resolve()): sha(Path(arg).read_bytes()) for arg in command
                                   if Path(arg).is_file() and Path(arg).stat().st_size <= 256 * 1024 * 1024}
        settings['runner_sha256'] = sha(Path(__file__).read_bytes())
        catalog, catalog_sha = load_catalog(args.catalog)
        selected = catalog[:args.max_items]
        work_root.mkdir(parents=True, exist_ok=True)
        report_key = sha(str(args.output.resolve()).encode())[:20]
        lock = (work_root / ('.lock-' + report_key)).open('a')
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        state_path = work_root / ('.state-' + report_key + '.json')
        state = json.loads(state_path.read_text()) if state_path.exists() else {'active': []}
        pending = []
        for record in state.get('active', []):
            result = cleanup_owned(work_root, record)
            if not result['removed']:
                pending.append(record)
        state = {'active': pending}
        atomic_json(state_path, state)
        previous = {}
        if args.resume and args.output.exists():
            saved = json.loads(args.output.read_text())
            if saved.get('schema') == 1:
                previous = {i['id']: i for i in saved.get('items', []) if isinstance(i, dict) and 'id' in i}
        report = {'schema': 1, 'generated_at': '', 'catalog_sha256': catalog_sha,
                  'settings': public_value({k: v for k, v in settings.items() if k not in {'probe_command', 'probe_files'}}),
                  'probe_fingerprint': sha(canonical(settings)), 'selected_count': len(selected),
                  'catalog_count': len(catalog), 'skipped_count': 0, 'items': [],
                  'cleanup_pending': [r.get('artifact', 'invalid marker') for r in pending]}
        def persist():
            report['generated_at'] = dt.datetime.now(dt.timezone.utc).isoformat()
            report['rates'] = rates(report['items'], report['selected_count'])
            report['completed_count'] = sum(i['cleanup'].get('removed') is True for i in report['items'])
            atomic_json(args.output, report)
            if args.markdown:
                args.markdown.parent.mkdir(parents=True, exist_ok=True)
                fd, temp = tempfile.mkstemp(prefix='.' + args.markdown.name + '.', dir=args.markdown.parent)
                try:
                    with os.fdopen(fd, 'w', encoding='utf-8') as output:
                        output.write(markdown(report))
                    os.replace(temp, args.markdown)
                finally:
                    if os.path.exists(temp):
                        os.unlink(temp)
        persist()
        for item in selected:
            fingerprint = sha(canonical({'item': item, 'settings': settings}))
            old = previous.get(item['id'])
            if old and old.get('fingerprint') == fingerprint and old.get('cleanup', {}).get('removed') is True and not (
                    args.retry_failed and old.get('status') not in {'pass', 'static_only'}):
                old['resumed'] = True
                report['items'].append(old)
                report['skipped_count'] += 1
                persist()
                continue
            record = {**item, 'fingerprint': fingerprint, 'resumed': False,
                'download': {'status': 'error', 'http_status': None, 'final_url': item['download_url'], 'sha256': None, 'bytes': 0, 'error': 'Not attempted yet.'},
                'archive': {'status': 'not_checked', 'entries': 0, 'expanded_bytes': 0, 'reason': None},
                'import': {'status': 'not_checked', 'layer': 'static_structure', 'checks': {}, 'reason': None},
                'runtime': {'status': 'unverified', 'executed': False, 'checks': {}, 'reason': 'Not attempted yet.'},
                'cleanup': {'status': 'pending', 'removed': False, 'reason': 'Item in progress.'}, 'status': 'error'}
            report['items'].append(record)
            work = Path(tempfile.mkdtemp(prefix='item-', dir=work_root))
            owned = {'artifact': work.name, 'token': uuid.uuid4().hex}
            atomic_json(work / '.ourin-owned.json', owned)
            state['active'].append(owned)
            atomic_json(state_path, state)
            persist()
            try:
                record['download'] = download_item(item, work / 'download.nar', settings)
                persist()
                if record['download']['status'] == 'success':
                    root = work / 'extracted'
                    record['archive'] = extract_archive(work / 'download.nar', root, settings)
                    persist()
                    if record['archive']['status'] == 'pass':
                        record['import'] = inventory(root, item['kind'])
                        persist()
                        if record['import']['status'] == 'pass':
                            record['runtime'] = run_probe(command, item, root, work, settings)
                            record['status'] = record['runtime']['status'] if command else 'static_only'
                        else:
                            record['status'] = 'partial'
                            record['runtime']['reason'] = 'Incomplete static structure; runtime was not attempted.'
            except Exception as error:
                record['status'] = 'error'
                record['runtime']['reason'] = public_reason(error)
            finally:
                record['cleanup'] = cleanup_owned(work_root, owned)
                if record['cleanup']['removed']:
                    state['active'].remove(owned)
                else:
                    record['status'] = 'error'
                atomic_json(state_path, state)
                report['cleanup_pending'] = [r['artifact'] for r in state['active']]
                persist()
            print(f"{item['id']}: {record['status']} (cleanup={record['cleanup']['status']})", flush=True)
        lock.close()
        return 0
    except (ValueError, OSError, json.JSONDecodeError) as error:
        print(public_reason(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
