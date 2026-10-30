#!/usr/bin/env python3
"""Exercise the staged real script engines with a system-only PATH."""
import argparse
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


class Wire:
    def __init__(self, executable, arguments, directory):
        self.fragmented = executable.parent.parent.name == 'miyojs'
        self.initialization_deadline = time.monotonic() + (60 if executable.parent.parent.name == 'phiori' else 5)
        self.errors = tempfile.TemporaryFile()
        self.process = subprocess.Popen([str(executable), *arguments], cwd=directory,
            env={'PATH': '/usr/bin:/bin', 'LANG': 'en_US.UTF-8', 'OURIN_VERIFY_DYLD': '1'},
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.errors)
        self.pending = b''
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.write('*L:' + str(directory) + '/\r\n')

    def write(self, value, fragmented=False):
        data = value.encode('utf-8')
        size = 3 if fragmented else max(1, len(data))
        for offset in range(0, len(data), size):
            self.process.stdin.write(data[offset:offset + size])
            self.process.stdin.flush()
            if fragmented:
                time.sleep(0.001)

    def line(self):
        deadline = max(time.monotonic() + 5, self.initialization_deadline or 0)
        while b'\n' not in self.pending:
            if not self.selector.select(max(0, deadline - time.monotonic())):
                self.errors.seek(0)
                raise AssertionError('SHIOLINK output timed out: ' + self.errors.read().decode('utf-8', errors='replace')[-4000:])
            chunk = os.read(self.process.stdout.fileno(), 8192)
            if not chunk:
                self.errors.seek(0)
                raise AssertionError('SHIOLINK EOF: ' + self.errors.read().decode('utf-8', errors='replace')[-4000:])
            self.pending += chunk
        result, self.pending = self.pending.split(b'\n', 1)
        return result.rstrip(b'\r').decode('utf-8')

    def request(self, event, reference=None, method='GET'):
        serial = uuid.uuid4().hex
        self.write('*S:' + serial + '\r\n')
        assert self.line() == '*S:' + serial
        headers = 'Charset: UTF-8\r\nSender: Ourin\r\nID: ' + event + '\r\n'
        if reference is not None:
            headers += 'Reference0: ' + reference + '\r\n'
        self.write(method + ' SHIORI/3.0\r\n' + headers + '\r\n',
                   fragmented=self.fragmented and event == 'OnMouseDoubleClick')
        lines = []
        while (line := self.line()):
            lines.append(line)
        self.initialization_deadline = None
        return '\n'.join(lines)

    def close(self):
        self.write('*U:\r\n')
        self.process.wait(timeout=1)
        assert self.process.returncode == 0
        self.errors.seek(0)
        libraries = self.errors.read().decode('utf-8', errors='replace')
        assert '/runtime/' in libraries, 'No positive dyld evidence; shell may have stripped diagnostics'
        assert '/opt/homebrew/' not in libraries, libraries
        self.selector.close()
        self.errors.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('plugins', type=Path)
    args = parser.parse_args()
    products = args.plugins.resolve()
    results = []
    with tempfile.TemporaryDirectory(prefix='ourin-script-plugins-probe-') as temp:
        for name in ('miyojs', 'sanajk', 'sana', 'phiori'):
            print('Verifying ' + name, file=sys.stderr, flush=True)
            directory = Path(temp) / ('日本語 エンジン-' + name)
            directory.mkdir()
            arguments = []
            if name == 'miyojs':
                (directory / 'dictionaries').mkdir()
                shutil.copyfile(HERE / 'fixtures/miyo.yaml', directory / 'dictionaries/miyo.yaml')
                shutil.copyfile(HERE / 'fixtures/probe.js', directory / 'probe.js')
                (directory / 'SHIOLINK.INI').write_text('commandline=C:\\runtime\\node.exe ".\\node_modules\\miyojs\\bin\\miyo-shiolink.js" ".\\dictionaries"\n')
                arguments = []
            elif name == 'sanajk':
                shutil.copyfile(HERE / 'fixtures/sanajk/main.js', directory / '日本語 entry.js')
                (directory / 'SHIOLINK.INI').write_text('commandline=C:\\runtime\\node.exe ".\\日本語 entry.js"\n')
                arguments = []
            elif name == 'sana':
                shutil.copyfile(HERE / 'fixtures/sana/main.rb', directory / '日本語 entry.rb')
                (directory / 'SHIOLINK.INI').write_text('commandline=C:\\runtime\\ruby.exe ".\\日本語 entry.rb"\n')
                arguments = []
            else:
                sample = ROOT / 'build/engines/phiori/upstream-sample'
                shutil.copytree(sample / 'phiori', directory / 'phiori')
                for filename in ('config.txt', 'resource.txt', 'words.dic', 'example.py'):
                    shutil.copyfile(sample / filename, directory / filename)
                shutil.copyfile(HERE / 'fixtures/phiori/probe.py', directory / 'probe.py')
            for count in (1, 2):
                wire = Wire(products / name / 'bin' / name, arguments, directory)
                try:
                    version = wire.request('version')
                    assert '200' in version or (name == 'phiori' and '204' in version), (name, version)
                    if name == 'phiori':
                        wire.request('ownerghostname', 'probe', method='NOTIFY')
                        response = wire.request('OnOurinCounter', '桜鈴 🌸')
                    else:
                        response = wire.request('OnBoot')
                    assert 'Value: 桜鈴 🌸 ' + str(count) in response, (name, response)
                    if name != 'phiori':
                        assert 'Value: 表・ソ・日本語 🌸' in wire.request('OnMouseDoubleClick', '表・ソ・日本語 🌸')
                    notify = wire.request('OnTest', '通知', method='NOTIFY')
                    assert '204' in notify, (name, notify)
                    wire.close()
                finally:
                    if wire.process.poll() is None:
                        wire.process.kill()
                        wire.process.wait()
            results.append({'engine': name, 'cycles': 2, 'unicode': True, 'saved_reload': True,
                            'external_dylibs_loaded': False, 'path': '/usr/bin:/bin',
                            'windows_entry_selection': name != 'phiori',
                            'fragmented_unicode_request': name == 'miyojs', 'result': 'PASS'})
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
