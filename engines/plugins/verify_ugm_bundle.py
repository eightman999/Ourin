#!/usr/bin/env python3
"""Probe a locally generated UGM bundle in a disposable macOS sandbox copy.

Requires the author's original payload; never downloads or modifies that input.
Only fixture settings/save data are added to the copy. Prints metadata, not scripts.
"""
import argparse
import hashlib
import http.client
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile


def verify(bundle):
    from verify_bundle import Plugin
    root = bundle / 'Contents/Resources/payload'
    before = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in root.rglob('*.dic')}
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    (root / 'ugm_config.txt').write_text(f'localhost_number,{port}\ncheck_interval,1\n')
    seed = {'SaveData_Reserved': {}, 'SaveData_Waiting': [], 'SaveData_Received': {},
            'oyasumi_flag': 2, 'bugfix_record': {'ourin_fixture': 1}}
    (root / 'savedata.json').write_text(json.dumps(seed))
    plugin = Plugin(bundle)
    result = {'cycles': [], 'sandbox': 'network limited to loopback; writes limited to disposable copy',
              'fixture': 'synthetic savedata/config; original dictionaries unchanged', 'gui_verified': False}
    previous_save = None
    for cycle in range(2):
        row = {'loaded': plugin.load(), 'events': []}
        result['cycles'].append(row)
        try:
            if not row['loaded']:
                raise RuntimeError('bundle load refused')
            for event in ['version', 'OnMenuExec']:
                raw = plugin.request(f'GET PLUGIN/2.0\r\nID: {event}\r\nCharset: UTF-8\r\nSender: Ourin\r\nSecurityLevel: local\r\n\r\n')
                lines = raw.split(b'\r\n')
                headers = {line.split(b':', 1)[0]: line.split(b':', 1)[1].strip() for line in lines[1:] if b':' in line}
                metadata = {'id': event, 'status_line': lines[0].decode('ascii', errors='replace'),
                    'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(),
                    'header_names': [k.decode('ascii', errors='replace') for k in headers]}
                if event == 'OnMenuExec':
                    metadata['script_has_configured_port'] = f'http://localhost:{port}/'.encode() in headers.get(b'Script', b'')
                    metadata['event_header_correct'] = headers.get(b'Event') == b'OnPluginExec'
                row['events'].append(metadata)
            row['http'] = []
            for path in ['/', '/res/data.json']:
                connection = http.client.HTTPConnection('127.0.0.1', port, timeout=3)
                try:
                    connection.request('GET', path)
                    response = connection.getresponse()
                    body = response.read()
                    record = {'path': path, 'status': response.status, 'bytes': len(body),
                              'sha256': hashlib.sha256(body).hexdigest()}
                    if path.endswith('.json'):
                        web_data = json.loads(body)
                        record['saved_flag_visible'] = isinstance(web_data, list) and bool(web_data) and web_data[0].get('oyasumi_flag') == 2
                    row['http'].append(record)
                finally:
                    connection.close()
        except Exception as error:
            row['error'] = type(error).__name__
        finally:
            plugin.unload()
        saved = json.loads((root / 'savedata.json').read_text())
        # UGM legitimately adds its own migration bookkeeping on first start.
        row['fixture_state_preserved'] = saved.get('oyasumi_flag') == 2 and saved.get('bugfix_record', {}).get('ourin_fixture') == 1
        row['saved_state_stable_after_reload'] = saved == previous_save if cycle else None
        previous_save = saved
        row['running_marker_removed'] = not (root / 'localweb/running.signal').exists()
        with socket.socket() as sock:
            row['port_closed'] = sock.connect_ex(('127.0.0.1', port)) != 0
    after = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*.dic')}
    result['dictionary_count'] = len(before)
    result['dictionary_hashes_unchanged'] = before == after
    result['passed'] = len(before) == 11 and before == after and all(
        row['loaded'] and not row.get('error') and len(row['events']) == 2
        and all(e['status_line'] == 'PLUGIN/2.0 200 OK' for e in row['events'])
        and row['events'][1]['script_has_configured_port'] and row['events'][1]['event_header_correct']
        and all(h['status'] == 200 for h in row['http']) and row['http'][1]['saved_flag_visible']
        and row['fixture_state_preserved'] and row['running_marker_removed'] and row['port_closed']
        for row in result['cycles']) and result['cycles'][1]['saved_state_stable_after_reload']
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--isolated-child', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.isolated_child:
        result = verify(args.bundle)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result['passed'] else 1
    sandbox = shutil.which('sandbox-exec')
    if not sandbox:
        parser.error('macOS sandbox-exec is required for original payload execution')
    with tempfile.TemporaryDirectory(prefix='ourin-ugm-real-') as temporary:
        work = Path(temporary).resolve()
        bundle = work / 'UGM.plugin'
        shutil.copytree(args.bundle.resolve(), bundle)
        profile = '(version 1)(allow default)(deny network*)' \
            '(allow network-outbound (remote ip "localhost:*"))' \
            '(allow network-inbound (local ip "localhost:*"))' \
            '(allow network-bind (local ip "localhost:*"))' \
            '(deny file-write* (require-not (subpath ' + json.dumps(str(work)) + ')))' \
            '(allow file-write* (literal "/dev/null"))'
        run = subprocess.run([sandbox, '-p', profile, sys.executable, str(Path(__file__).resolve()),
                              str(bundle), '--isolated-child'], cwd=work, capture_output=True, text=True,
                             timeout=120, env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})
        if not run.stdout:
            raise RuntimeError('isolated probe failed without a result: ' + run.stderr[-1000:])
        result = json.loads(run.stdout)
    result['temporary_copy_deleted'] = not work.exists()
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return run.returncode


if __name__ == '__main__':
    sys.exit(main())
