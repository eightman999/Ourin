#!/usr/bin/env python3
"""Run original CeVIO/AIVOICE dictionaries through the live Irodori bridge.

Works on disposable copies, emits hashes/status/timing rather than dictionaries.
The service must already be running. Audio playback is controlled by the service.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'engines/plugins'))
from verify_bundle import Plugin


def status(port):
    with socket.create_connection(('127.0.0.1', port), timeout=3) as sock:
        sock.sendall(b'{"product":"cevio","session":"probe","action":"status"}\n')
        return json.loads(sock.makefile('rb').readline(65537))


def hashes(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob('*') if p.is_file()}


def request(plugin, event, refs=()):
    if any('\r' in value or '\n' in value for value in refs):
        raise ValueError('line breaks not allowed in protocol references')
    raw = plugin.request('GET PLUGIN/2.0\r\nID: '+event+'\r\nCharset: UTF-8\r\n'+
                         ''.join(f'Reference{i}: {value}\r\n' for i, value in enumerate(refs))+'\r\n')
    if not raw.startswith((b'PLUGIN/2.0 200', b'PLUGIN/2.0 204')):
        raise RuntimeError(f'{event}: '+raw.split(b'\r\n')[0].decode(errors='replace'))
    return raw


def await_completion(port, previous, timeout=120):
    deadline = time.monotonic()+timeout
    while time.monotonic()<deadline:
        report = status(port)
        fresh = [e for e in report['history'] if int(e['id'])>previous]
        failed = [e for e in fresh if e['state'] in ('failed', 'cancelled', 'cancelled-before-generation')]
        if failed:
            raise RuntimeError('speech failed: '+json.dumps(failed, ensure_ascii=False))
        complete = [e for e in fresh if e['state']=='completed']
        if complete:
            if not complete[-1]['files']:
                raise RuntimeError('empty audio output')
            return fresh
        time.sleep(.1)
    raise TimeoutError('no completed speech from original plugin')


def prepare_bundle(source, target, product):
    shutil.copytree(source, target)
    resources = target/'Contents/Resources'
    (resources/'state/yaya-variables.json').unlink(missing_ok=True)
    config = json.loads((resources/'adapter.json').read_text())
    config['local_tts_backend'] = product
    (resources/'adapter.json').write_text(json.dumps(config, ensure_ascii=False, indent=2)+'\n')
    shutil.copy2(ROOT/'build/engines/plugins/OurinYayaPlugin.dylib', target/'Contents/MacOS/OurinPluginAdapter')
    shutil.copy2(ROOT/'yaya_core/build/yaya_core', resources/'yaya_core')
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(target)], check=True, capture_output=True)


def verify(source_root, port):
    before = status(port)
    if not before['ready']:
        raise RuntimeError('Irodori service not ready')
    os.environ['OURIN_LOCAL_TTS_PORT'] = str(port)
    result = dict(schema=1, backend='irodori-mlx', commercial_voices_verified=False, plugins=[])
    with tempfile.TemporaryDirectory(prefix='ourin-tts-original-') as directory:
        work = Path(directory)
        for product, name in [('cevio','ukagakaplugin-cevio-talker'), ('aivoice','ssp-aivoice')]:
            source = source_root/f'{name}.plugin'
            original_hashes = hashes(source/'Contents/Resources/payload')
            target = work/f'{name}.plugin'
            prepare_bundle(source, target, product)
            plugin = Plugin(target)
            prefix = 'CeVIO' if product=='cevio' else 'AIVOICE'
            voice = 'IrodoriAkari' if product=='cevio' else 'IrodoriAoi'
            item = dict(product=product, voice=voice, cycles=[])
            for cycle in range(2):
                assert plugin.load(), 'original plugin load failed'
                try:
                    menu = request(plugin, 'OnMenuExec')
                    assert voice.encode() in menu, 'voice list missing from original menu'
                    detail = request(plugin, 'On'+prefix+'.CharConfigMenu', [voice])
                    assert b'Volume' in detail
                    if cycle == 0:
                        request(plugin, 'On'+prefix+'.WhoTalker', [voice])
                        request(plugin, 'On'+prefix+'.SetWhoTalker', ['OurinTTS検証'])
                        for key, value in [('Volume','35' if product=='cevio' else '0.7'),
                                           ('Speed','60' if product=='cevio' else '1.3'),
                                           ('喜び' if product=='cevio' else 'StyleJ','60' if product=='cevio' else '0.6')]:
                            request(plugin, 'On'+prefix+'.CharOption', [voice,key])
                            request(plugin, 'On'+prefix+'.SetOption', [value])
                    previous = max([int(e['id']) for e in status(port)['history']] or [0])
                    request(plugin, 'OnOtherGhostTalk', ['OurinTTS検証','','','', r'\0こんにちは。桜鈴から声を届けます。\e'])
                    events = await_completion(port, previous)
                    item['cycles'].append(dict(cycle=cycle+1, loaded=True, menu=True, events=events))
                finally:
                    plugin.unload()
            # Actual replacement/cancellation through the unchanged dictionary,
            # not just a direct worker or synthetic service test.
            assert plugin.load()
            try:
                previous = max([int(e['id']) for e in status(port)['history']] or [0])
                request(plugin, 'OnOtherGhostTalk', ['OurinTTS検証','','','',
                        r'\0これは途中で置き換える長い発話です。' + '古い発話を続けてはいけません。'*8 + r'\e'])
                time.sleep(.05)
                request(plugin, 'OnOtherGhostTalk', ['OurinTTS検証','','','', r'\0新しい発話に切り替えました。\e'])
                fresh = await_completion(port, previous+1)
                records = [e for e in status(port)['history'] if int(e['id'])>previous]
                assert any(e['state'].startswith('cancelled') and int(e['id'])==previous+1 for e in records)
                item['replacement_verified'] = True
                item['replacement_events'] = records
                # Reuse the completed audio to enter playback, then unload.
                request(plugin, 'OnOtherGhostTalk', ['OurinTTS検証','','','', r'\0新しい発話に切り替えました。\e'])
                deadline = time.monotonic()+15
                while not status(port)['playing'] and time.monotonic()<deadline:
                    time.sleep(.02)
                if not status(port)['playing']:
                    raise RuntimeError('playback did not start; run service without --no-play for this check')
                started = time.monotonic()
                plugin.unload()
                report = status(port)
                assert not report['playing'], 'unload left audio player running'
                item['unload_stop_seconds'] = time.monotonic()-started
                deadline = time.monotonic()+3
                while status(port)['active'] and time.monotonic()<deadline:
                    time.sleep(.02)
                assert not status(port)['active'], 'stale generation after unload'
                item['unload_stops_playback'] = True
            finally:
                plugin.unload()
            assert hashes(target/'Contents/Resources/payload')==original_hashes
            assert hashes(source/'Contents/Resources/payload')==original_hashes
            item['payload_hashes_unchanged'] = True
            item['dictionary_sha256'] = {p:h for p,h in original_hashes.items() if p.endswith(('.uka','.dic'))}
            result['plugins'].append(item)
    result['temporary_copies_deleted'] = not work.exists()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, default=ROOT/'build/plugin-ports')
    parser.add_argument('--port', type=int, default=50731)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = verify(args.source_root, args.port)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    print(args.output)


if __name__ == '__main__': main()
