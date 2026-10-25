#!/usr/bin/env python3
"""Exercise compiled SHIORI libraries in separate processes on disposable dictionaries.

No user ghost is read or modified. Fixtures are Ourin-authored; this is an engine/ABI
check, not a real-ghost or GUI compatibility certification.
"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'OurinTests/Fixtures/additional-shiori'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def phase(library, master, product, reload):
    c = ctypes.CDLL(None)
    c.malloc.argtypes = [ctypes.c_size_t]
    c.malloc.restype = ctypes.c_void_p
    c.free.argtypes = [ctypes.c_void_p]
    engine = ctypes.CDLL(str(library))
    engine.loadu.argtypes = [ctypes.c_void_p, ctypes.c_int32]
    engine.loadu.restype = ctypes.c_int32
    engine.request.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int32)]
    engine.request.restype = ctypes.c_void_p
    engine.unload.argtypes = []
    engine.unload.restype = ctypes.c_int32

    def owned(data):
        pointer = c.malloc(len(data) + 1)
        if not pointer:
            raise MemoryError()
        ctypes.memmove(pointer, data + b'\0', len(data) + 1)
        return pointer

    data = (str(master) + '/').encode()
    assert engine.loadu(owned(data), len(data)) == 1, 'loadu failed'
    exchanges = []

    def request(event, expected, method='GET'):
        wire = f'{method} SHIORI/3.0\r\nCharset: UTF-8\r\nSender: OurinTests\r\nID: {event}\r\n\r\n'.encode()
        length = ctypes.c_int32(len(wire))
        answer = engine.request(owned(wire), ctypes.byref(length))
        assert answer and 0 < length.value <= 8 * 1024 * 1024, f'{event}: empty response'
        try:
            response = ctypes.string_at(answer, length.value).decode()
        finally:
            c.free(answer)
        exchanges.append({'method': method, 'event': event, 'response': response})
        assert expected in response, f'{event}: expected {expected!r}, got {response!r}'

    try:
        if reload:
            # Read before OnBoot/OnRemember: this cannot succeed by reassigning the value.
            request('OnRecall', 'Value: 37\r\n')
        request('OnBoot', f'boot:{product}')
        request('OnAITalk', f'talk:{product}')
        request('OnRemember', 'Value: remember')
        assert engine.loadu(owned(data), len(data)) == 0, 'duplicate singleton load was accepted'
        request('OnRecall', 'Value: 37\r\n')
        request('OnUndefinedOurinFixture', 'SHIORI/3.0 204', 'NOTIFY')
        request('OnClose', f'close:{product}')
    finally:
        assert engine.unload() == 1, 'unload failed'
    return exchanges


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--libraries', type=Path, default=ROOT / 'build/engines/additional')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--product')
    parser.add_argument('--master', type=Path)
    parser.add_argument('--reload', action='store_true')
    args = parser.parse_args()
    if args.master:
        print(json.dumps(phase(args.libraries / f'lib{args.product}.dylib', args.master,
                               args.product, args.reload)))
        return
    cases = json.loads((FIXTURES / 'cases.json').read_text())
    if args.product:
        cases = [case for case in cases if case['product'] == args.product]
    assert cases, 'no matching fixture'
    report = []
    environment = {key: value for key, value in os.environ.items()
                   if key not in {'UTATANE_GHOST_STATE_DIR', 'AKARI_VARIABLE_STORE_PATH',
                                  'ESE_SHIORI_STATE_PATH', 'NISESHIORI_STATE_PATH',
                                  'SHINO_STATE_PATH', 'HISUI_STATE_PATH', 'YUHNA_STATE_PATH'}}
    for case in cases:
        product = case['product']
        with tempfile.TemporaryDirectory(prefix=f'ourin-{product}-') as temporary:
            master = Path(temporary) / 'nested/日本語辞書'
            shutil.copytree(FIXTURES / product, master)
            dictionary_hashes = {str(p.relative_to(master)): digest(p)
                                 for p in master.rglob('*') if p.is_file()}
            commands = [sys.executable, __file__, '--libraries', str(args.libraries.resolve()),
                        '--product', product, '--master', str(master)]
            runs = []
            for flags in [[], ['--reload']]:
                result = subprocess.run(commands + flags, env=environment, capture_output=True,
                                        text=True, timeout=40)
                if result.returncode != 0:
                    raise RuntimeError(f"{product} {flags}: {result.stderr}")
                runs.append(json.loads(result.stdout))
            assert all(digest(master / path) == sha for path, sha in dictionary_hashes.items()), 'dictionary modified'
            state = master / case['state_file']
            assert state.exists() and state.stat().st_size > 0, 'state not saved'
            report.append({'product': product, 'result': 'PASS', 'separate_process_reload': True,
                           'dictionary_unchanged': True, 'state': json.loads(state.read_text()),
                           'library_sha256': digest(args.libraries / f'lib{product}.dylib'),
                           'exchanges': runs})
            print(f'PASS {product}: load, GET/NOTIFY, close, save, separate-process reload')
    if args.output:
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
