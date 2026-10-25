#!/usr/bin/env python3
"""Native local TTS helper ABI regressions; synthesis is a synthetic loopback service.
Original bundle tests use private payloads when available, preserving all hashes.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from generate import generate
from verify_bundle import Plugin

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / 'build/engines/plugins'
VOICE = 'IrodoriAkari'


class Service:
    def __init__(self, response=None):
        self.requests = []
        self.response = response
        owner = self
        class Handler(socketserver.StreamRequestHandler):
            def handle(self):
                self.connection.settimeout(3)
                try:
                    request = json.loads(self.rfile.readline(65537))
                    owner.requests.append(request)
                    if owner.response:
                        response = owner.response(request)
                    else:
                        arg = request['argument']
                        result = {'start':'ready','stop':'stopped','check':'True'}.get(request['action'])
                        if result is None:
                            if arg == 'GetCharList':
                                result = (',' if request['product'] == 'cevio' else '') + VOICE + ',IrodoriAoi'
                            elif arg.startswith('GetCharOptions_'):
                                result = ',喜び,怒り,悲しみ'
                            elif arg == 'end':
                                result = 'endClient'
                            else:
                                result = 'Server read OK.'
                        response = {'ok':True,'result':result}
                    if isinstance(response, bytes):
                        self.wfile.write(response)
                    else:
                        self.wfile.write((json.dumps(response,ensure_ascii=False)+'\n').encode())
                except (BrokenPipeError,ConnectionResetError):
                    pass
        class Server(socketserver.ThreadingTCPServer):
            daemon_threads = True
        self.server = Server(('127.0.0.1',0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever,daemon=True)

    def __enter__(self):
        self.old = os.environ.get('OURIN_LOCAL_TTS_PORT')
        os.environ['OURIN_LOCAL_TTS_PORT'] = str(self.server.server_address[1])
        self.thread.start()
        return self

    def __exit__(self,*args):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        if self.old is None:
            os.environ.pop('OURIN_LOCAL_TTS_PORT',None)
        else:
            os.environ['OURIN_LOCAL_TTS_PORT'] = self.old

    def speeches(self):
        return [r for r in self.requests if r['action']=='client' and ',' in r['argument']]


def request(plugin,event='probe',refs=()):
    return plugin.request('GET PLUGIN/2.0\r\nID: '+event+'\r\nCharset: UTF-8\r\n'+''.join(f'Reference{i}: {value}\r\n' for i,value in enumerate(refs))+'\r\n')


def hashes(root):
    return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file()}


class LocalTTSAdapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='ourin-local-tts-tests-')
        cls.work = Path(cls.temp.name).resolve()
        cls.collector = cls.work / 'collector/yaya_plugin_collector'
        subprocess.run([sys.executable,str(ROOT / 'engines/plugins/prepare_collector.py'),'--output-dir',str(cls.collector.parent)],check=True,capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def fixture(self,body='"ok"',product='cevio',mapped=True,startup=True):
        base = Path(tempfile.mkdtemp(dir=self.work))
        source = base / 'source'
        source.mkdir()
        (source / 'descript.txt').write_text('charset,UTF-8\nname,Ourin Local TTS fixture\nfilename,yaya.dll\n')
        (source / 'yaya.txt').write_text('charset.dic,UTF-8\ndic,test.dic\n')
        exe = 'myserver.exe' if product=='cevio' else 'server.exe'
        (source / 'test.dic').write_text(('load { void EXECUTE("dll/'+exe+'") }\n' if startup else '') + '''request {
  _value = ''' + body + '''
  "PLUGIN/2.0 200 OK%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Script: %(_value)%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
}''')
        bundle = base / 'Fixture.plugin'
        generate(argparse.Namespace(source=source,output=bundle,engine='yaya',adapter=BUILD / 'OurinYayaPlugin.dylib',helper=ROOT / 'yaya_core/build/yaya_core',collector=self.collector,source_url='https://example.invalid/self-authored',saori_backend=[],engine_library=None,local_tts_backend=product if mapped else None))
        return Plugin(bundle),bundle

    def test_explicit_opt_in_and_live_start(self):
        for product in ('cevio','aivoice'):
            for mapped in (False,True):
                with self.subTest(product=product,mapped=mapped),Service() as service:
                    plugin,_ = self.fixture(product=product,mapped=mapped)
                    try:
                        self.assertEqual(plugin.load(),mapped)
                    finally:
                        plugin.unload()
                    self.assertEqual([r['action'] for r in service.requests],['start','stop'] if mapped else [])

    def test_generator_rejects_mixed_backends(self):
        for extra in ({'bouyomi_tcp_backend':True},{'ugm_http_helper':Path('/unused')},{'saori_backend':['proxy_ex.dll=/unused']}):
            values=dict(local_tts_backend='cevio',engine='yaya',saori_backend=[])
            values.update(extra)
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                generate(argparse.Namespace(**values))

    def test_invalid_ports_are_rejected(self):
        plugin,_=self.fixture()
        try:
            for value in ('', '0', '65536', '50731x', '-1'):
                os.environ['OURIN_LOCAL_TTS_PORT']=value
                self.assertFalse(plugin.load())
        finally:
            plugin.unload()
            os.environ.pop('OURIN_LOCAL_TTS_PORT',None)

    def test_missing_service_rejects_load(self):
        plugin,_ = self.fixture()
        with socket.socket() as reserved:
            reserved.bind(('127.0.0.1',0))
            os.environ['OURIN_LOCAL_TTS_PORT'] = str(reserved.getsockname()[1])
            try:
                self.assertFalse(plugin.load())
            finally:
                plugin.unload()
                os.environ.pop('OURIN_LOCAL_TTS_PORT',None)

    def test_charset_is_utf8_and_sjis_is_process_compatibility_flag(self):
        for charset in ('UTF-8','sjis'):
            plugin,_ = self.fixture('FUNCTIONEX("./dll/proxy_ex.dll","/charset","'+charset+'")')
            with Service():
                try:
                    self.assertTrue(plugin.load())
                    self.assertIn(b'Script: \r\n',request(plugin))
                finally:
                    plugin.unload()
        plugin,_ = self.fixture('FUNCTIONEX("./dll/proxy_ex.dll","./client.exe","GetCharOptions_IrodoriAkari")')
        with Service():
            try:
                self.assertTrue(plugin.load())
                self.assertIn('喜び,怒り,悲しみ'.encode(),request(plugin))
            finally:
                plugin.unload()

    def test_unknown_commands_and_wrong_product_rejected(self):
        bodies = ['EXECUTE("/usr/bin/true")','EXECUTE("dll/server.exe")','EXECUTE_WAIT("dll/myserver.exe")','EXECUTE("dll/myserver.exe","--extra")',
                  'FUNCTIONEX("./dll/proxy_ex.dll","../client.exe","GetCharList")',
                  'FUNCTIONEX("./dll/proxy_ex.dll","./check.exe")',
                  'FUNCTIONEX("./dll/proxy_ex.dll","./client.exe","x","extra")',
                  'FUNCTIONEX("./dll/proxy_ex.dll","/charset","utf-16")']
        for body in bodies:
            with self.subTest(body=body),Service() as service:
                plugin,_ = self.fixture(body)
                try:
                    self.assertTrue(plugin.load())
                    self.assertTrue(request(plugin).startswith(b'PLUGIN/2.0 501'))
                    self.assertEqual(len(service.requests),1)
                finally:
                    plugin.unload()

    def test_malformed_and_oversize_service_reply_rejected(self):
        invalid = [b'{}\n',b'{"ok":false,"result":"no"}\n',b'{"ok":true,"result":"unsafe\\r\\nHeader: bad"}\n',b'{"ok":true,"result":42}\n',b'not-json\n', b'x'*65537+b'\n']
        for response in invalid:
            with self.subTest(response=response[:60]):
                plugin,_ = self.fixture()
                with Service(lambda r: response):
                    try:
                        self.assertFalse(plugin.load())
                    finally:
                        plugin.unload()

    def test_request_deadline_and_new_session_on_reload(self):
        plugin,_ = self.fixture('FUNCTIONEX("./dll/proxy_ex.dll","./client.exe","GetCharList")')
        def respond(r):
            if r['action']=='client':
                time.sleep(2.3)
            return {'ok':True,'result':'ready'}
        with Service(respond) as service:
            try:
                self.assertTrue(plugin.load())
                start=time.monotonic()
                self.assertTrue(request(plugin).startswith(b'PLUGIN/2.0 501'))
                self.assertLess(time.monotonic()-start,2.9)
                plugin.unload()
                self.assertTrue(plugin.load())
            finally:
                plugin.unload()
            sessions=[r['session'] for r in service.requests if r['action']=='start']
            self.assertEqual(len(set(sessions)),2)

    def test_original_bundles_menu_save_restore_and_unmodified_payload(self):
        names={'cevio':'ukagakaplugin-cevio-talker','aivoice':'ssp-aivoice'}
        if any(not (ROOT/'build/plugin-ports'/f'{name}.plugin').exists() for name in names.values()):
            self.skipTest('private original plugin payloads not installed')
        for product,name in names.items():
            with self.subTest(product=product):
                source=ROOT/'build/plugin-ports'/f'{name}.plugin'
                original=hashes(source/'Contents/Resources/payload')
                bundle=self.work/f'{name}.plugin'
                shutil.copytree(source,bundle)
                resources=bundle/'Contents/Resources'
                state=resources/'state/yaya-variables.json'
                if state.exists(): state.unlink()  # Disposable copy only.
                config=json.loads((resources/'adapter.json').read_text())
                config['local_tts_backend']=product
                (resources/'adapter.json').write_text(json.dumps(config))
                shutil.copy2(BUILD/'OurinYayaPlugin.dylib',bundle/'Contents/MacOS/OurinPluginAdapter')
                shutil.copy2(ROOT/'yaya_core/build/yaya_core', resources/'yaya_core')
                subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(bundle)],check=True,capture_output=True)
                plugin=Plugin(bundle)
                prefix='CeVIO' if product=='cevio' else 'AIVOICE'
                with Service() as service:
                    for cycle in range(2):
                        try:
                            self.assertTrue(plugin.load())
                            menu=request(plugin,'OnMenuExec')
                            self.assertIn(VOICE.encode(),menu, (cycle, service.requests, menu))
                            self.assertIn(b'On'+prefix.encode()+b'.CharConfigMenu',menu)
                            detail=request(plugin,'On'+prefix+'.CharConfigMenu',[VOICE])
                            self.assertIn(b'Volume',detail)
                            if product=='cevio':self.assertIn('喜び'.encode(),detail)
                            if cycle==0:
                                before=len(service.speeches())
                                request(plugin,'OnOtherGhostTalk',['probe-ghost','','','',r'\0既定では無音\e'])
                                self.assertEqual(len(service.speeches()),before)
                                request(plugin,'On'+prefix+'.WhoTalker',[VOICE])
                                request(plugin,'On'+prefix+'.SetWhoTalker',['probe-ghost'])
                                request(plugin,'On'+prefix+'.CharOption',[VOICE,'Volume'])
                                request(plugin,'On'+prefix+'.SetOption',['75' if product=='cevio' else '1.5'])
                                request(plugin,'On'+prefix+'.CharOption',[VOICE,'喜び' if product=='cevio' else 'StyleJ'])
                                request(plugin,'On'+prefix+'.SetOption',['60' if product=='cevio' else '0.6'])
                            before=len(service.speeches())
                            talk=request(plugin,'OnOtherGhostTalk',['probe-ghost','','','',r'\0こんにちは,桜です。\e'])
                            self.assertTrue(talk.startswith(b'PLUGIN/2.0 204'),talk[:120])
                            self.assertEqual(len(service.speeches()),before+1)
                            fields=service.speeches()[-1]['argument'].split(',')
                            self.assertEqual(fields[0],VOICE)
                            self.assertEqual(float(fields[1]),75 if product=='cevio' else 1.5)
                            self.assertIn('こんにちは,桜です',service.speeches()[-1]['argument'])
                            if product=='cevio':self.assertIn('喜びMySep60',service.speeches()[-1]['argument'])
                            else:self.assertAlmostEqual(float(fields[7]),0.6)
                            before=len(service.speeches())
                            request(plugin,'OnOtherGhostTalk',['different-ghost','','','',r'\0対象外\e'])
                            self.assertEqual(len(service.speeches()),before)
                        finally:
                            plugin.unload()
                        self.assertTrue(state.exists())
                    self.assertEqual(len([r for r in service.requests if r['action']=='stop']),2)
                    self.assertEqual(len(set(r['session'] for r in service.requests if r['action']=='start')),2)
                self.assertEqual(hashes(resources/'payload'),original)
                self.assertEqual(hashes(source/'Contents/Resources/payload'),original)


if __name__=='__main__':
    unittest.main()
