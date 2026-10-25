#!/usr/bin/env python3
"""Self-authored PLUGIN wire regression for opt-in UGM HTTP execution."""
import argparse
import http.client
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest
from generate import generate
from verify_bundle import Plugin

ROOT = Path(__file__).resolve().parents[2]
BUILD = Path(os.environ.get('OURIN_UGM_ADAPTER_BUILD', ROOT / 'build/engines/plugins'))


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


class UGMAdapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='ourin-ugm-adapter-')
        cls.work = Path(cls.temp.name).resolve()
        cls.collector = cls.work / 'collector/yaya_plugin_collector'
        subprocess.run([sys.executable, str(ROOT / 'engines/plugins/prepare_collector.py'),
                        '--output-dir', str(cls.collector.parent)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def fixture(self, command, *, mapped=True, on_load=None):
        base = Path(tempfile.mkdtemp(dir=self.work))
        source = base / 'source'
        (source / 'localweb/html').mkdir(parents=True)
        (source / 'localweb/html/index.html').write_text('ourin fixture')
        (source / 'descript.txt').write_text('charset,UTF-8\nname,Ourin UGM fixture\nfilename,yaya.dll\n')
        (source / 'yaya.txt').write_text('charset.dic,UTF-8\ndic,test.dic\n')
        port = free_port()
        (source / 'ugm_config.txt').write_text(f'localhost_number,{port}\n')
        (source / 'test.dic').write_text(('load { _ignored = ' + on_load + ' }\n' if on_load else '') + '''request {
  _ignored = ''' + command + '''
  "PLUGIN/2.0 200 OK%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Script: test%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
}''')
        bundle = base / 'Fixture.plugin'
        args = argparse.Namespace(source=source, output=bundle, engine='yaya',
            adapter=BUILD / 'OurinYayaPlugin.dylib', helper=ROOT / 'yaya_core/build/yaya_core',
            collector=self.collector, source_url='https://example.invalid/self-authored',
            saori_backend=[], engine_library=None,
            ugm_http_helper=BUILD / 'ugm_http_helper' if mapped else None)
        generate(args)
        plugin = Plugin(bundle)
        self.assertEqual(plugin.load(), on_load is None)
        return plugin, bundle, port

    def request(self, plugin):
        return plugin.request('GET PLUGIN/2.0\r\nID: version\r\nCharset: UTF-8\r\n\r\n')

    def test_absolute_mapped_command_serves_and_unload_stops(self):
        plugin, bundle, port = self.fixture("EXECUTE(GETSETTING('coreinfo.path') + 'localweb\\ugm_server.exe')")
        marker = bundle / 'Contents/Resources/payload/localweb/running.signal'
        try:
            self.assertTrue(self.request(plugin).startswith(b'PLUGIN/2.0 200'))
            conn = http.client.HTTPConnection('127.0.0.1', port, timeout=4)
            try:
                conn.request('GET', '/')
                result = conn.getresponse()
                self.assertEqual((result.status, result.read()), (200, b'ourin fixture'))
            finally:
                conn.close()
            self.assertTrue(marker.exists())
        finally:
            plugin.unload()
        self.assertFalse(marker.exists())
        with socket.socket() as s:
            s.settimeout(0.5)
            self.assertNotEqual(s.connect_ex(('127.0.0.1', port)), 0)

    def test_unmapped_shell_arguments_and_wait_are_unavailable(self):
        for command, mapped in [("EXECUTE('localweb\\ugm_server.exe')", False),
                                 ("EXECUTE('/usr/bin/true')", True),
                                 ("EXECUTE('localweb\\ugm_server.exe', '-unexpected')", True),
                                 ("EXECUTE_WAIT('localweb\\ugm_server.exe')", True)]:
            with self.subTest(command=command, mapped=mapped):
                plugin, bundle, port = self.fixture(command, mapped=mapped)
                try:
                    self.assertTrue(self.request(plugin).startswith(b'PLUGIN/2.0 501'))
                    self.assertFalse((bundle / 'Contents/Resources/payload/localweb/running.signal').exists())
                finally:
                    plugin.unload()

    def test_execute_and_wait_never_invoke_shell_in_request_or_load(self):
        sentinel = self.work / 'must-not-exist'
        for builtin in ('EXECUTE', 'EXECUTE_WAIT'):
            command = builtin + "('/usr/bin/touch " + str(sentinel) + "')"
            for on_load in (None, command):
                with self.subTest(builtin=builtin, during_load=on_load is not None):
                    plugin, bundle, port = self.fixture(command, on_load=on_load)
                    try:
                        if on_load is None:
                            self.assertTrue(self.request(plugin).startswith(b'PLUGIN/2.0 501'))
                        self.assertFalse(sentinel.exists())
                    finally:
                        plugin.unload()

    def test_failed_bind_is_unavailable_not_success(self):
        plugin, bundle, port = self.fixture("EXECUTE('localweb\\ugm_server.exe')")
        try:
            with socket.socket() as other:
                other.bind(('127.0.0.1', port))
                other.listen()
                self.assertTrue(self.request(plugin).startswith(b'PLUGIN/2.0 501'))
        finally:
            plugin.unload()


if __name__ == '__main__':
    unittest.main()
