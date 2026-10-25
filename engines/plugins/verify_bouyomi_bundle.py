#!/usr/bin/env python3
"""Verify an opted-in original Bouyomi bundle on a disposable copy.
Only response metadata and hashes are emitted. The TCP receiver is synthetic;
packet acceptance does not prove external speech synthesis or Windows SAPI.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import sys
import tempfile
from verify_bundle import Plugin
from test_bouyomi_adapter import Receiver, packet


def hashes(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob('*') if p.is_file()}


def verify(original):
    original = original.resolve()
    original_hashes = hashes(original / 'Contents/Resources/payload')
    result = {'schema': 1, 'plugin': 'bouyomi', 'cycles': [], 'external_speech_verified': False,
              'limitations': ['Windows engine auto-launch', 'Windows SAPI voices 10001+',
                              'existing upstream text voice-state migration',
                              'external speech synthesis', 'full Sakura Script coverage',
                              'Ourin GUI and Intel execution']}
    with tempfile.TemporaryDirectory(prefix='ourin-bouyomi-probe-') as temporary:
        work = Path(temporary).resolve()
        bundle = work / 'Bouyomi.plugin'
        shutil.copytree(original, bundle)
        ghost = work / 'ghost-fixture'
        (ghost / 'ghost/master').mkdir(parents=True)
        (ghost / 'ghost/master/descript.txt').write_text('charset,UTF-8\nsakura.name,桜\nkero.name,相方\n')
        plugin = Plugin(bundle)
        saved = bundle / 'Contents/Resources/state/yaya-variables.json'
        if saved.exists():
            saved.unlink()  # Disposable copy only: make the initial-state check reproducible.
        ghostname = 'Ourin検証'
        keys = [hashlib.md5(f'{ghostname}{scope}'.encode()).hexdigest()+'.voice' for scope in range(2)]

        def request(event, refs=(), *, expected=None):
            if expected is None:
                expected = 204 if event == 'OnOtherGhostTalk' else 200
            wire = 'GET PLUGIN/2.0\r\nID: ' + event + '\r\nCharset: UTF-8\r\n'
            wire += ''.join(f'Reference{i}: {value}\r\n' for i, value in enumerate(refs)) + '\r\n'
            response = plugin.request(wire)
            assert response.startswith(f'PLUGIN/2.0 {expected}'.encode()), (event, response.split(b'\r\n')[0])
            return response

        for index in range(2):
            cycle = {'cycle': index+1, 'loaded': plugin.load(), 'events': []}
            assert cycle['loaded']
            try:
                for event, refs in [('version', []), ('OnMenuExec', ['dummy', ghostname, 'dummy', 'dummy', str(ghost)]),
                                    ('OnMenuShow', [ghostname, '0', str(ghost)])]:
                    response = request(event, refs)
                    cycle['events'].append({'id': event, 'status': 200, 'bytes': len(response), 'sha256': hashlib.sha256(response).hexdigest()})
                    if event == 'OnMenuExec':
                        assert '桜'.encode() in response and '相方'.encode() in response
                        if index:
                            assert '女性2'.encode() in response and '男性1'.encode() in response
                    if event == 'OnMenuShow':
                        assert '機械2'.encode() in response
                        assert response.count(b'OnVoiceSelected,') == 9
                if index == 0:
                    # -v is validated by upstream, but the actual packet voice is read
                    # from the scope map. Unconfigured scope falls back to 0.
                    with Receiver(1) as receiver:
                        request('OnOtherGhostTalk', [ghostname, '', '', '', r'\0初回\e'])
                    assert receiver.packets == [packet('初回', 0)]
                    cycle['default_packet_verified'] = True
                for scope, voice in [(0, 2), (1, 3)]:
                    request('OnVoiceSelected', [ghostname, str(scope), str(voice), str(ghost)])
                state = json.loads(saved.read_text())
                assert [str(state[key]['v']) for key in keys] == ['2', '3']
                cycle['saved_scope_voices'] = [2, 3]
                with Receiver(2) as receiver:
                    request('OnOtherGhostTalk', [ghostname, '', '', '', r'\0こんにちは\_q隠す\_q。\1相方です\e'])
                assert receiver.packets == [packet('こんにちは。', 2), packet('相方です', 3)]
                cycle['tcp_packets'] = [{'bytes': len(value), 'sha256': hashlib.sha256(value).hexdigest()}
                                        for value in receiver.packets]
                cycle['scope_voice_and_quicksection_verified'] = True
                cycle['talk_status'] = 204
                request('OnVoiceSelected', [ghostname, '0', '10001', str(ghost)])
                request('OnOtherGhostTalk', [ghostname, '', '', '', r'\0unsupported\e'], expected=501)
                request('OnVoiceSelected', [ghostname, '0', '2', str(ghost)])
                cycle['unsupported_sapi_rejected'] = True
                with socket.socket() as reserved:
                    reserved.bind(('127.0.0.1', 0))
                    os.environ['OURIN_BOUYOMI_PORT'] = str(reserved.getsockname()[1])
                    try:
                        request('OnOtherGhostTalk', [ghostname, '', '', '', r'\0unavailable\e'], expected=501)
                    finally:
                        os.environ.pop('OURIN_BOUYOMI_PORT', None)
                cycle['absent_service_rejected'] = True
            finally:
                plugin.unload()
            result['cycles'].append(cycle)
        result['payload_hashes_unchanged'] = hashes(bundle / 'Contents/Resources/payload') == original_hashes
        assert result['payload_hashes_unchanged']
        result['dictionary_sha256'] = {path: value for path, value in original_hashes.items() if path.endswith('.dic')}
        result['source_payload_unchanged'] = hashes(original / 'Contents/Resources/payload') == original_hashes
        assert result['source_payload_unchanged']
    result['temporary_copy_deleted'] = not work.exists()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = verify(args.bundle)
    text = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output:
        args.output.write_text(text)
    print(text)


if __name__ == '__main__':
    main()
