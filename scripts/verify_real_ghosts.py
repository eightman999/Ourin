#!/usr/bin/env python3
"""Run real dictionaries through existing helpers, always in a disposable copy.

This checks helper protocol/dictionary/save behavior, not the GUI or complete SAORI
integration. YAYA configuration is resolved by compiling the production Swift
collector from ShioriLoader.swift; no second config parser is maintained here.
"""
import argparse
import ctypes
import sys
import hashlib
import json
from pathlib import Path
import queue
import shutil
import subprocess
import threading
import time


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for data in iter(lambda: f.read(1024 * 1024), b''):
            h.update(data)
    return h.hexdigest()


def snapshot(root):
    result = {}
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise ValueError(f'Symlink is not accepted in verification input: {path}')
        if path.is_file():
            result[str(path.relative_to(root))] = digest(path)
    return result


def tree_digest(files):
    return hashlib.sha256(json.dumps(files, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def compile_collector(repo, out):
    source = (repo / 'Ourin/USL/ShioriLoader.swift').read_text()
    start = source.index('// MARK: - YAYA Config Parsing Helpers')
    end = source.index('// MARK: - YayaBackend Helpers')
    runner = r'''
let config = URL(fileURLWithPath: CommandLine.arguments[1])
let limit = URL(fileURLWithPath: CommandLine.arguments[2])
let content = try (try? String(contentsOf: config, encoding: .utf8)) ?? String(contentsOf: config, encoding: .shiftJIS)
var collector = DicCollector()
collectDicEntries(content: content, baseURL: config.deletingLastPathComponent(), sourceName: config.lastPathComponent, collector: &collector, visited: [])
let resolved = applyYayaBasePath(collector, root: config.deletingLastPathComponent(), within: limit)
var result: [String: Any] = ["cmd": "load", "ghost_root": resolved.root.path, "encoding": collector.globalCharset ?? "auto", "dic_entries": resolved.entries.map { entry -> [String:String] in
    var value = ["path": entry.path]
    if let encoding = entry.encoding { value["encoding"] = encoding }
    return value
}]
result["save_file"] = config.deletingPathExtension().path + "_variable.cfg"
if let depth = collector.functionDepth { result["fncdepth"] = depth }
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
'''
    swift = out / 'collector.swift'
    swift.write_text('import Foundation\n' + source[start:end] + runner)
    binary = out / 'collector'
    subprocess.run(['/usr/bin/swiftc', str(swift), '-o', str(binary)], check=True, timeout=60)
    return binary


class Session:
    def __init__(self, binary, cwd, log):
        self.stderr = log.open('wb')
        self.proc = subprocess.Popen(binary if isinstance(binary, list) else [str(binary)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=self.stderr, cwd=cwd)
        self.lines = queue.Queue()
        self.operations = []
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.proc.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def send(self, message):
        self.proc.stdin.write((json.dumps(message, ensure_ascii=False) + '\n').encode())
        self.proc.stdin.flush()

    def exchange(self, message, timeout):
        started = time.monotonic()
        self.send(message)
        while True:
            try:
                line = self.lines.get(timeout=max(0.001, timeout - (time.monotonic() - started)))
            except queue.Empty:
                raise TimeoutError(f'{message.get("id", message["cmd"])} exceeded {timeout}s')
            if line is None:
                raise RuntimeError(f'helper exited ({self.proc.poll()})')
            response = json.loads(line)
            if 'host_op' in response:
                # Match an empty desktop for FMO. External capabilities are not
                # faked as successes: they remain explicitly outside this harness.
                self.operations.append(response)
                if response['host_op'] == 'fmo':
                    self.send({'ok': True, 'snapshot': ''})
                else:
                    self.send({'ok': False, 'error': 'not provided by real-ghost helper harness'})
                continue
            value = response.get('value') or ''
            return {'ok': response.get('ok'), 'status': response.get('status'),
                    'seconds': round(time.monotonic() - started, 3),
                    'value_length': len(value), 'value_sha256': hashlib.sha256(value.encode()).hexdigest(),
                    'contains_delimiter': '\x01' in value,
                    'error': response.get('error'),
                    'loaded_dictionary_count': len(response.get('loaded_dics', []))}

    def close(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.proc.kill(); self.proc.wait()
        self.proc.stdin.close(); self.proc.stdout.close(); self.stderr.close()


def expected_status_rules(case):
    """Exceptions must name one event/method and cite why its status is expected."""
    rules = {}
    for rule in case.get('expected_statuses', []):
        event, method = rule.get('event'), rule.get('method')
        status, reason = rule.get('status'), rule.get('reason')
        if (not isinstance(event, str) or not event or '*' in event
                or method not in ('GET', 'NOTIFY')
                or type(status) is not int or not 100 <= status <= 599
                or not isinstance(reason, str) or not reason.strip()):
            raise ValueError('Expected status requires an exact event, GET/NOTIFY, integer status and reason')
        key = (event, method)
        if key in rules:
            raise ValueError(f'Duplicate expected status for {event} {method}')
        rules[key] = rule
    return rules


def status_verdict(request, response, rules):
    rule = rules.get((request.get('id'), request.get('method', 'GET'))) if request.get('cmd') == 'request' else None
    status = response.get('status')
    matches = (status == rule['status']) if rule else (type(status) is int and 200 <= status < 400)
    result = {'status_matches': matches}
    if rule:
        result.update(expected_status=rule['status'], expected_status_reason=rule['reason'])
    return result


def run_case(case, repo, out, collector, event_timeout):
    rules = expected_status_rules(case)
    source = Path(case['root']).resolve()
    before = snapshot(source)
    caseout = out / case['name']
    caseout.mkdir()
    copied = caseout / 'copy'
    shutil.copytree(source, copied, symlinks=False)
    # Explicitly disable network updates and external host capabilities by not
    # implementing them. No user-owned files or savedata are rewritten.
    binary = Path(case['library']).resolve() if case['engine'] == 'kawari' else repo / case['engine'] / 'build' / case['engine']
    command = [sys.executable, str(Path(__file__).resolve()), '--native-worker', str(binary)] if case['engine'] == 'kawari' else binary
    report = {'name': case['name'], 'engine': case['engine'], 'source': str(source),
              'source_url': case.get('source_url'), 'source_tree_sha256': tree_digest(before),
              'source_files': len(before), 'helper_sha256': digest(binary), 'events': [],
              'verification_layer': 'helper process, not GUI', 'host_operations': []}
    if case['engine'] == 'yaya_core':
        config = copied / case.get('config', 'ghost/master/yaya.txt')
        compiled = subprocess.run([str(collector), str(config), str(copied)],
                                  capture_output=True, text=True, check=True, timeout=30)
        (caseout / 'collector.log').write_text(compiled.stderr)
        load = json.loads(compiled.stdout)
        # GhostManager creates profile before runtime startup; do so only in copy.
        (Path(load['ghost_root']) / 'profile').mkdir(exist_ok=True)
    else:
        load = {'cmd': 'load', 'ghost_root': str(copied / case.get('master', 'ghost/master'))}
        (Path(load['ghost_root']) / 'profile').mkdir(exist_ok=True)
    events = case.get('events', [
        {'id': 'OnNotifyUserInfo', 'method': 'NOTIFY', 'ref': ['User']},
        {'id': 'OnBoot', 'ref': ['0']},
        {'id': 'OnMouseDoubleClick', 'ref': ['100', '100', '0', '0', 'head']},
        {'id': 'OnCommunicate', 'ref': ['User', 'こんにちは']},
        {'id': 'OnClose', 'ref': ['user']},
    ])
    try:
        for cycle in [1, 2]:
            session = Session(command, copied, caseout / f'helper-{cycle}.stderr.log')
            try:
                plan = [('load', load, 60)] + [(event['id'], {'cmd': 'request', 'method': 'GET',
                    'headers': {'Sender': 'Ourin', 'Charset': 'UTF-8', 'SecurityLevel': 'local'}, **event}, event_timeout)
                    for event in (events if cycle == 1 else [{'id': 'OnBoot', 'ref': ['0']}, {'id': 'OnClose', 'ref': ['user']}])]
                plan.append(('OnDestroy', {'cmd': 'request', 'method': 'NOTIFY', 'id': 'OnDestroy', 'headers': {'Charset': 'UTF-8', 'Sender': 'Ourin'}}, event_timeout))
                plan.append(('unload', {'cmd': 'unload'}, event_timeout))
                for label, request, timeout in plan:
                    try:
                        response = session.exchange(request, timeout)
                        report['events'].append({'cycle': cycle, 'event': label, 'method': request.get('method'),
                                                 **response, **status_verdict(request, response, rules)})
                        if response['ok'] is False:
                            raise RuntimeError(f'{label} returned failure')
                    except Exception as error:
                        report['events'].append({'cycle': cycle, 'event': label, 'failure': str(error)})
                        # Timeout makes this session unusable. Attempting a fresh
                        # cycle still checks whether saved state can be reopened.
                        break
            finally:
                report['host_operations'] += session.operations
                session.close()
            current = snapshot(copied)
            changed = [name for name in sorted(set(before) | set(current)) if before.get(name) != current.get(name)]
            report[f'changed_files_after_cycle_{cycle}'] = changed
            report[f'changed_file_hashes_after_cycle_{cycle}'] = {name: current.get(name) for name in changed}
    finally:
        after = snapshot(source)
        report['source_unchanged'] = before == after
        report['passed'] = report['source_unchanged'] and not any('failure' in row or not row.get('status_matches', False) for row in report['events'])
        (caseout / 'result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    return report


def native_worker(library):
    """KAWARI's upstream shiori.h POSIX long ABI, in a killable subprocess."""
    module = ctypes.CDLL(library)
    libc = ctypes.CDLL(None)
    libc.malloc.argtypes = [ctypes.c_size_t]; libc.malloc.restype = ctypes.c_void_p
    libc.free.argtypes = [ctypes.c_void_p]
    module.loadu.argtypes = [ctypes.c_void_p, ctypes.c_long]; module.loadu.restype = ctypes.c_int
    module.request.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_long)]; module.request.restype = ctypes.c_void_p
    module.unload.argtypes = []; module.unload.restype = ctypes.c_int
    loaded = False

    def owned(data):
        pointer = libc.malloc(len(data) + 1)
        if not pointer: raise MemoryError()
        ctypes.memmove(pointer, data + b'\0', len(data) + 1)
        return pointer

    for line in sys.stdin:
        command = json.loads(line)
        if command['cmd'] == 'load':
            data = (command['ghost_root'].rstrip('/') + '/').encode()
            loaded = bool(module.loadu(owned(data), len(data)))
            response = {'ok': loaded, 'status': 200 if loaded else 500}
        elif command['cmd'] == 'unload':
            ok = bool(module.unload()) if loaded else True
            loaded = False
            response = {'ok': ok, 'status': 200 if ok else 500}
        else:
            headers = {'Sender': 'Ourin', 'Charset': 'UTF-8', 'ID': command['id'], **command.get('headers', {})}
            headers.update({f'Reference{i}': value for i, value in enumerate(command.get('ref', []))})
            wire = command.get('method', 'GET') + ' SHIORI/3.0\r\n' + ''.join(f'{key}: {value}\r\n' for key, value in headers.items()) + '\r\n'
            data = wire.encode(); length = ctypes.c_long(len(data))
            pointer = module.request(owned(data), ctypes.byref(length))
            if not pointer: response = {'ok': False, 'error': 'null native response'}
            else:
                try:
                    if not 0 <= length.value <= 64 * 1024 * 1024: raise ValueError('Invalid response length')
                    raw = ctypes.string_at(pointer, length.value)
                finally: libc.free(pointer)
                raw_header = raw.decode('latin1')
                charset = next((part.split(':', 1)[1].strip() for part in raw_header.split('\r\n') if part.lower().startswith('charset:')), 'UTF-8')
                text = raw.decode(charset, errors='replace')
                status = int(text.split(' ', 2)[1])
                value = next((part.split(':', 1)[1].strip() for part in text.split('\r\n') if part.lower().startswith('value:')), '')
                response = {'ok': 200 <= status < 300, 'status': status, 'value': value}
        print(json.dumps(response, ensure_ascii=False), flush=True)
    if loaded: module.unload()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cases', required=True, type=Path, help='JSON list of name/engine/root/config/events/source_url objects')
    parser.add_argument('--output', type=Path, required=True, help='New output directory; existing directories are refused')
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--event-timeout', type=float, default=20)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    cases = json.loads(args.cases.read_text())
    collector = compile_collector(args.repo, args.output) if any(c['engine'] == 'yaya_core' for c in cases) else None
    results = []
    for case in cases:
        result = run_case(case, args.repo, args.output, collector, args.event_timeout)
        results.append(result)
        print(json.dumps({'name': result['name'], 'passed': result['passed'], 'events': result['events']}, ensure_ascii=False), flush=True)
    (args.output / 'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n')
    return 0 if all(result['passed'] for result in results) else 1


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--native-worker':
        native_worker(sys.argv[2])
    else:
        raise SystemExit(main())
