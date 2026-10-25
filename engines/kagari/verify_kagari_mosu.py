#!/usr/bin/env python3
"""Verify KAGARI and the unmodified mosu NAR in timeout-bounded child processes.

Native extensions are built from pinned upstream sources into a temporary copy.
No DLL replacement, script stubbing, or successful-empty-response shortcut is used.
Exit 0 = all checks passed; 1 = failed; 2 = real-ghost compatibility incomplete.
"""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

TIMEOUT_SEC = 120
NAR_DEFAULT = Path('/tmp/ourin-real-ghosts-20261025/mosu.nar')
SOURCES = {
    'luasocket': ('https://github.com/lunarmodules/luasocket.git', '95b7efa9da506ef968c1347edf3fc56370f0deed'),
    'luautf8': ('https://github.com/starwing/luautf8.git', 'a47b1433473a2509d77ad28f59a976716d187927'),
    'luachild': ('https://github.com/Tatakinov/luachild.git', 'efcb09bd6059f5852313bfd431106a75344f4038'),
    'lua-iconv': ('https://github.com/ittner/lua-iconv.git', 'a94fdb1f6d50c22bb59330df607bb0848d0ba673'),
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(argv: list[str], cwd: Path | None = None) -> str:
    result = subprocess.run(argv, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=TIMEOUT_SEC)
    if result.returncode:
        raise RuntimeError(f'{argv[0]} exited {result.returncode}:\n{result.stdout[-8000:]}')
    return result.stdout


def stage_dependencies(work: Path, master: Path, lua_inc: Path) -> dict:
    """Build legitimate libraries only; missing SAORI/fh remain explicit failures."""
    if not (lua_inc / 'lua.h').is_file():
        raise RuntimeError(f'Lua 5.4 headers missing: {lua_inc}')
    manifest = {}
    sources = work / 'sources'
    sources.mkdir()
    for name, (url, revision) in SOURCES.items():
        src = sources / name
        command(['git', 'clone', '--quiet', '--no-checkout', url, str(src)])
        command(['git', 'checkout', '--quiet', revision], cwd=src)
        manifest[name] = {'url': url, 'revision': command(['git', 'rev-parse', 'HEAD'], cwd=src).strip()}
    core = master / 'corelib'
    socket = sources / 'luasocket'
    command(['make', 'macosx', 'LUAV=5.4', f'LUAINC_macosx={lua_inc}'], cwd=socket)
    for module in ('socket', 'mime'):
        candidates = sorted((socket / 'src').glob(f'{module}-*.so'))
        if not candidates:
            raise RuntimeError(f'luasocket missing {module} binary')
        (core / module).mkdir(exist_ok=True)
        shutil.copy2(candidates[-1], core / module / 'core.so')
    common = ['clang', '-bundle', '-undefined', 'dynamic_lookup', '-I', str(lua_inc)]
    command(common + [str(sources / 'luautf8/lutf8lib.c'), '-o', str(core / 'lua-utf8.so')])
    # POSIX upstream needs signal.h explicitly on current Apple Clang.
    command(common + ['-DUSE_POSIX', '-include', 'signal.h'] +
            [str(sources / 'luachild' / name) for name in
             ('luachild_common.c', 'luachild_posix.c', 'luachild_lua_5_3.c')] +
            ['-o', str(core / 'luachild.so')])
    command(common + [str(sources / 'lua-iconv/luaiconv.c'), '-liconv', '-o', str(core / 'iconv.so')])
    manifest['outputs'] = {str(p.relative_to(master)): digest(p) for p in core.rglob('*.so')}
    return manifest


class Kagari:
    def __init__(self, library: Path):
        self.libc = ctypes.CDLL(None)
        self.libc.malloc.argtypes = [ctypes.c_size_t]
        self.libc.malloc.restype = ctypes.c_void_p
        self.libc.free.argtypes = [ctypes.c_void_p]
        # Lua native modules built with dynamic_lookup must resolve this same Lua ABI.
        self.lib = ctypes.CDLL(str(library), mode=ctypes.RTLD_GLOBAL)
        self.lib.kagari_load.argtypes = [ctypes.c_void_p, ctypes.c_long]
        self.lib.kagari_load.restype = ctypes.c_int
        self.lib.kagari_request.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.POINTER(ctypes.c_long)]
        self.lib.kagari_request.restype = ctypes.c_void_p
        self.lib.kagari_unload.argtypes = [ctypes.c_int]
        self.lib.kagari_unload.restype = ctypes.c_int

    def owned_buffer(self, raw: bytes):
        ptr = self.libc.malloc(len(raw) + 1)
        if not ptr:
            raise MemoryError('malloc')
        ctypes.memmove(ptr, raw + b'\0', len(raw) + 1)
        return ptr

    def load(self, directory: Path) -> int:
        raw = (str(directory) + os.sep).encode()
        # KAGARI owns and frees the supplied path and request buffers.
        return self.lib.kagari_load(self.owned_buffer(raw), len(raw))

    def request(self, instance: int, event: str, refs: dict[int, str] | None = None) -> str:
        lines = ['GET SHIORI/3.0', 'Charset: UTF-8', 'Sender: OurinCompatibilityProbe',
                 'SecurityLevel: Local', f'ID: {event}']
        lines.extend(f'Reference{k}: {v}' for k, v in (refs or {}).items())
        raw = ('\r\n'.join(lines) + '\r\n\r\n').encode()
        length = ctypes.c_long(len(raw))
        ptr = self.lib.kagari_request(instance, self.owned_buffer(raw), ctypes.byref(length))
        if not ptr:
            return ''
        try:
            if not 0 <= length.value <= 16 * 1024 * 1024:
                raise ValueError(f'invalid response length: {length.value}')
            return ctypes.string_at(ptr, length.value).decode('utf-8', errors='strict')
        finally:
            self.libc.free(ptr)


def response_check(raw: str) -> tuple[bool, str]:
    headers = raw.split('\r\n\r\n', 1)[0].split('\r\n')
    status = headers[0] if headers else ''
    value = next((line[6:].strip() for line in headers[1:] if line.startswith('Value:')), '')
    return bool(re.fullmatch(r'SHIORI/3\.0 200(?: .*)?', status) and value), value


def child_probe(args) -> int:
    result = {'phase': args.phase, 'events': [], 'ok': False}
    try:
        api = Kagari(args.library)
        if args.phase == 'invalid':
            instance = api.load(args.ghost)
            result.update(load=instance, ok=instance < 0)
            if instance >= 0:
                api.lib.kagari_unload(instance)
        else:
            instance = api.load(args.ghost)
            result['load'] = instance
            if instance < 0:
                result['error'] = 'KAGARI load failed; see child log for missing dependency'
            else:
                try:
                    events = [('OnBoot', {}), ('OnMouseDoubleClick', {0: '0', 1: '0', 2: '0', 3: '0', 4: ''})]
                    if args.phase == 'ghost-first':
                        events.append(('OnMenu', {0: '1'}))
                    elif args.phase == 'ghost-reload':
                        events.append(('OnMenu', {}))
                    events.append(('OnClose', {}))
                    for event, refs in events:
                        raw = api.request(instance, event, refs)
                        ok, value = response_check(raw)
                        if event == 'OnMenu':
                            ok = ok and '1分' in value  # 30 -> 60 seconds; retained after reload.
                        result['events'].append({'event': event, 'ok': ok, 'response': raw})
                    result['ok'] = all(event['ok'] for event in result['events'])
                finally:
                    result['unload'] = api.lib.kagari_unload(instance)
                    result['ok'] = result['ok'] and result['unload'] == 1
    except Exception as exc:
        result['error'] = f'{type(exc).__name__}: {exc}'
    args.result.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    return 0 if result['ok'] else 2


def run_probe(library: Path, ghost: Path, phase: str, work: Path) -> dict:
    result_file = work / f'{phase}.json'
    argv = [sys.executable, str(Path(__file__).resolve()), str(library), '--child', '--ghost',
            str(ghost), '--phase', phase, '--result', str(result_file)]
    try:
        proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              timeout=TIMEOUT_SEC, text=True)
        (work / f'{phase}.log').write_text(proc.stdout)
        result = json.loads(result_file.read_text()) if result_file.is_file() else {'ok': False}
        result['exit_code'] = proc.returncode
        result['ok'] = result.get('ok', False) and proc.returncode == 0
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout or b''
        (work / f'{phase}.log').write_bytes(output if isinstance(output, bytes) else output.encode())
        result = {'ok': False, 'timeout_seconds': TIMEOUT_SEC}
    print(f'{phase}: {"PASS" if result["ok"] else "FAIL"}', flush=True)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('library', type=lambda s: Path(s).resolve())
    parser.add_argument('nar', nargs='?', type=Path, default=NAR_DEFAULT)
    parser.add_argument('--workdir', type=Path)
    parser.add_argument('--lua-include', type=Path)
    parser.add_argument('--child', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--ghost', type=Path, help=argparse.SUPPRESS)
    parser.add_argument('--phase', help=argparse.SUPPRESS)
    parser.add_argument('--result', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.child:
        return child_probe(args)
    work = args.workdir.resolve() if args.workdir else Path(tempfile.mkdtemp(prefix='ourin-mosu-check-'))
    if args.workdir:
        work.mkdir(parents=True, exist_ok=False)
    print(f'Evidence: {work}', flush=True)
    summary = {'library': str(args.library), 'library_sha256': digest(args.library),
               'nar': str(args.nar.resolve()), 'nar_sha256_before': digest(args.nar), 'checks': {}}
    try:
        minimal = work / 'minimal'
        minimal.mkdir()
        (minimal / 'index.lua').write_text("return {load=function() return true end, unload=function() return true end, request=function() return 'SHIORI/3.0 200 OK\\r\\nCharset: UTF-8\\r\\nValue: kagari-minimal\\r\\n\\r\\n' end}\n")
        summary['checks']['minimal'] = run_probe(args.library, minimal, 'minimal', work)
        summary['checks']['minimal_reload'] = run_probe(args.library, minimal, 'minimal-reload', work)
        summary['checks']['load_failure'] = run_probe(args.library, work / 'absent', 'invalid', work)
        if not all(c['ok'] for c in summary['checks'].values()):
            return 1
        master = work / 'nar/ghost/master'
        with zipfile.ZipFile(args.nar) as archive:
            base = (work / 'nar').resolve()
            for item in archive.infolist():
                if not (base / item.filename).resolve().is_relative_to(base):
                    raise ValueError('unsafe NAR path')
            archive.extractall(base)
        lua_inc = args.lua_include or args.library.parents[2] / 'deps/kagari/lua-5.4.4/src'
        summary['dependencies'] = stage_dependencies(work, master, lua_inc.resolve())
        summary['checks']['mosu'] = run_probe(args.library, master, 'ghost-first', work)
        save = master / 'kagari_save.lua'
        summary['checks']['save'] = {'ok': save.is_file() and save.stat().st_size > 0}
        if save.is_file():
            summary['checks']['save']['sha256'] = digest(save)
        if summary['checks']['mosu']['ok'] and summary['checks']['save']['ok']:
            summary['checks']['reload'] = run_probe(args.library, master, 'ghost-reload', work)
        return 0 if all(c['ok'] for c in summary['checks'].values()) else 2
    except Exception as exc:
        summary['error'] = f'{type(exc).__name__}: {exc}'
        print(summary['error'], flush=True)
        return 2
    finally:
        summary['nar_sha256_after'] = digest(args.nar)
        summary['nar_unchanged'] = summary['nar_sha256_after'] == summary['nar_sha256_before']
        (work / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
        print(f'Results: {work / "summary.json"}', flush=True)


if __name__ == '__main__':
    raise SystemExit(main())
