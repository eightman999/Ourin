#!/usr/bin/env python3
"""Exercise real nashi in isolated SHIOLINK children; no user ghosts are touched."""
import argparse
import json
import os
from pathlib import Path
import selectors
import subprocess
import tempfile
import time
import uuid

HERE = Path(__file__).resolve().parent


class Wire:
    def __init__(self, executable, directory, architecture=None):
        self.errors = tempfile.TemporaryFile()
        command = [str(executable)]
        if architecture:
            command = ['/usr/bin/arch', '-' + architecture, '/usr/bin/env', 'DYLD_PRINT_LIBRARIES=1', str(executable)]
        self.child = subprocess.Popen(command, cwd=directory, stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=self.errors,
            env={'PATH': '/usr/bin:/bin', 'LANG': 'en_US.UTF-8', 'DYLD_PRINT_LIBRARIES': '1'})
        self.pending = b''
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.child.stdout, selectors.EVENT_READ)
        self.write('*L:' + str(directory) + '/\r\n')
        assert self.request('version')['Value'] == '1.0.0'  # Preserve the actual upstream constant.

    def write(self, text, charset='utf-8'):
        self.child.stdin.write(text.encode(charset)); self.child.stdin.flush()

    def line(self):
        deadline = time.monotonic() + 5
        while b'\n' not in self.pending:
            if not self.selector.select(max(0, deadline - time.monotonic())):
                raise AssertionError('nashi response timed out')
            chunk = os.read(self.child.stdout.fileno(), 8192)
            if not chunk:
                self.errors.seek(0)
                raise AssertionError('nashi EOF: ' + self.errors.read().decode('utf-8', errors='replace')[-3000:])
            self.pending += chunk
        result, self.pending = self.pending.split(b'\n', 1)
        return result.rstrip(b'\r').decode('utf-8')

    def request(self, event, reference=None, method='GET', charset='UTF-8'):
        serial = uuid.uuid4().hex
        self.write('*S:' + serial + '\r\n')
        assert self.line() == '*S:' + serial
        request = method + ' SHIORI/3.0\r\nCharset: ' + charset + '\r\nID: ' + event + '\r\nSender: Ourin\r\n'
        if reference is not None: request += 'Reference0: ' + reference + '\r\n'
        self.write(request + '\r\n', 'cp932' if charset == 'CP932' else 'utf-8')
        result = {'Status': int(self.line().split(' ')[1])}
        while True:
            line = self.line()
            if not line: break
            key, value = line.split(':', 1); result[key] = value.strip()
        return result

    def close(self, incomplete=False):
        if incomplete:
            self.write('*S:incomplete\r\n')
            assert self.line() == '*S:incomplete'
            self.write('GET SHIORI/3.0\r\n')
            self.child.stdin.close()
        else:
            self.write('*U:\r\n')
        self.child.wait(timeout=6)
        assert self.child.returncode == 0
        self.errors.seek(0); diagnostics = self.errors.read().decode('utf-8', errors='replace')
        assert 'nashi-shiolink' in diagnostics, 'No positive dyld load evidence'
        assert '/opt/homebrew/' not in diagnostics, diagnostics
        self.selector.close(); self.errors.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('executable', type=Path)
    parser.add_argument('--arch', choices=['arm64', 'x86_64'])
    args = parser.parse_args(); executable = args.executable.resolve()
    fixture = json.loads((HERE / 'fixture.json').read_text())
    with tempfile.TemporaryDirectory(prefix='ourin-nashi-probe-') as temp:
        roots = [Path(temp) / name for name in ('日本語 辞書A', '日本語 辞書B')]
        originals = []
        for index, directory in enumerate(roots):
            directory.mkdir()
            fixture['variables'][0]['value'] = index * 100
            text = json.dumps(fixture, ensure_ascii=False, indent=2)
            (directory / 'ghost.json').write_text(text); originals.append(text)
        first, second = Wire(executable, roots[0], args.arch), Wire(executable, roots[1], args.arch)
        try:
            assert first.child.pid != second.child.pid
            assert first.request('OnBoot')['Value'] == '桜鈴 🌸 1\\e'
            assert second.request('OnBoot')['Value'] == '桜鈴 🌸 101\\e'
            assert first.request('OnEcho', '表・ソ・日本語🌸')['Value'] == '表・ソ・日本語🌸\\e'
            assert first.request('OnEcho', '表ソ・日本語ｶﾅ', charset='CP932')['Value'] == '表ソ・日本語ｶﾅ\\e'
            assert first.request('OnIncrement', method='NOTIFY')['Status'] == 204
            assert first.request('OnClose')['Value'] == '桜鈴・なし栞終了\\-'
            first.close()
            assert second.request('OnRead')['Value'] == '保存 101\\e'
            assert second.request('OnBoot')['Value'] == '桜鈴 🌸 102\\e'
            second.close(incomplete=True)
            for index, value in enumerate((11, 102)):
                saved = json.loads((roots[index] / 'nashi_save.json').read_text())
                assert saved['vars']['回数'] == value
                resumed = Wire(executable, roots[index], args.arch)
                try: assert resumed.request('OnRead')['Value'] == '保存 ' + str(value) + '\\e'
                finally: resumed.close()
                assert (roots[index] / 'ghost.json').read_text() == originals[index]
        finally:
            for wire in (first, second):
                if wire.child.poll() is None: wire.child.kill(); wire.child.wait()
    print(json.dumps({'engine': 'nashi licensed main 1.0.4-alpha', 'result': 'PASS',
                      'parallel_ghosts': 2, 'unload_isolation': True, 'unicode': True,
                      'cp932_wire': True, 'notify_side_effect': True, 'saved_reload': True,
                      'incomplete_eof_save': True, 'source_unchanged': True,
                      'external_runtime_or_dylib': False, 'requested_architecture': args.arch}, ensure_ascii=False, indent=2))


if __name__ == '__main__': main()
