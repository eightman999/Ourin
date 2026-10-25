#!/usr/bin/env python3
"""Opt-in native Bouyomi ABI tests. Synthetic TCP receiver, no speech engine."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import socket
import struct
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


class Receiver:
    def __init__(self, count):
        self.server = socket.socket()
        self.server.bind(('127.0.0.1', 0))
        self.server.listen()
        self.server.settimeout(5)
        self.port = self.server.getsockname()[1]
        self.count = count
        self.packets = []
        self.errors = []
        self.thread = threading.Thread(target=self.receive)

    def receive(self):
        try:
            for _ in range(self.count):
                with self.server.accept()[0] as client:
                    client.settimeout(4)
                    packet = bytearray()
                    while True:
                        data = client.recv(4096)
                        if not data:
                            break
                        packet.extend(data)
                    self.packets.append(bytes(packet))
        except Exception as error:
            self.errors.append(str(error))

    def __enter__(self):
        os.environ['OURIN_BOUYOMI_PORT'] = str(self.port)
        self.thread.start()
        return self

    def __exit__(self, *args):
        self.thread.join(6)
        self.server.close()
        os.environ.pop('OURIN_BOUYOMI_PORT', None)
        if self.thread.is_alive() or self.errors:
            raise AssertionError(self.errors or 'receiver still running')


def packet(text, voice):
    encoded = text.encode()
    return struct.pack('<hhhhhBI', 1, -1, -1, -1, voice, 0, len(encoded)) + encoded


class BouyomiAdapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='ourin-bouyomi-tests-')
        cls.work = Path(cls.temp.name).resolve()
        cls.collector = cls.work / 'collector/yaya_plugin_collector'
        subprocess.run([sys.executable, str(ROOT / 'engines/plugins/prepare_collector.py'), '--output-dir', str(cls.collector.parent)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def fixture(self, body, *, mapped=True, config=None, startup=True):
        base = Path(tempfile.mkdtemp(dir=self.work))
        source = base / 'source'
        source.mkdir()
        (source / 'descript.txt').write_text('charset,UTF-8\nname,Ourin Bouyomi fixture\nfilename,yaya.dll\n')
        (source / 'yaya.txt').write_text('charset.dic,UTF-8\ndic,test.dic\n')
        if config is not None:
            (source / 'config.json').write_text(json.dumps(config))
        (source / 'test.dic').write_text(('load { void FUNCTIONEX("proxy_ex.dll", "/charset", "UTF-8")\n void EXECUTE("core.exe", "-e") }\n' if startup else '') + '''request {
  _value = ''' + body + '''
  "PLUGIN/2.0 200 OK%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Script: %(_value)%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
}''')
        bundle = base / 'Fixture.plugin'
        generate(argparse.Namespace(source=source, output=bundle, engine='yaya', adapter=BUILD / 'OurinYayaPlugin.dylib', helper=ROOT / 'yaya_core/build/yaya_core', collector=self.collector, source_url='https://example.invalid/self-authored', saori_backend=[], engine_library=None, bouyomi_tcp_backend=mapped))
        return Plugin(bundle), bundle

    def request(self, plugin, event='probe', refs=()):
        return plugin.request('GET PLUGIN/2.0\r\nID: ' + event + '\r\nCharset: UTF-8\r\n' + ''.join(f'Reference{i}: {v}\r\n' for i, v in enumerate(refs)) + '\r\n')

    def test_explicit_opt_in_and_no_config_startup(self):
        for mapped, expected in [(False, False), (True, True)]:
            plugin, _ = self.fixture('"ok"', mapped=mapped)
            try:
                self.assertEqual(plugin.load(), expected)
                if expected:
                    self.assertIn(b'Script: ok', self.request(plugin))
            finally:
                plugin.unload()

    def test_windows_launch_and_invalid_config_are_not_success(self):
        for config in [{'BouyomiChanPath': ['C:\\tools\\BouyomiChan.exe']}, {'BouyomiChanPath': '/usr/bin/true'}, {'NoVoiceByDefault': 'false'}, []]:
            with self.subTest(config=config):
                plugin, _ = self.fixture('"ok"', config=config)
                try:
                    self.assertFalse(plugin.load())
                finally:
                    plugin.unload()

    def test_hash_and_standard_voice_list(self):
        plugin, _ = self.fixture('FUNCTIONEX("proxy_ex.dll", "core.exe", "-hash", "桜0")')
        try:
            self.assertTrue(plugin.load())
            self.assertIn(hashlib.md5('桜0'.encode()).hexdigest().encode(), self.request(plugin))
        finally:
            plugin.unload()
        plugin, _ = self.fixture('FUNCTIONEX("proxy_ex.dll", "core.exe", "-l")', config={'NoVoiceByDefault': True, 'BouyomiChanPath': ['']})
        try:
            self.assertTrue(plugin.load())
            result = self.request(plugin).decode()
            self.assertIn('0,読み上げなし\x011,女性1', result)
            self.assertIn('\x018,機械2', result)
            self.assertNotIn('10001', result)
        finally:
            plugin.unload()

    def test_count_requires_host_root_and_confines_symlinks(self):
        ghost = self.work / 'count-ghost'
        (ghost / 'ghost/master').mkdir(parents=True)
        path = ghost / 'ghost/master/descript.txt'
        path.write_bytes('charset,Shift_JIS\nchar2.name,三人目\nkero.name,相方\nsakura.name,桜\n'.encode('cp932'))
        plugin, _ = self.fixture(f'FUNCTIONEX("proxy_ex.dll", "core.exe", "-count", "{ghost}")')
        try:
            self.assertTrue(plugin.load())
            self.assertTrue(self.request(plugin).startswith(b'PLUGIN/2.0 501'))
            result = self.request(plugin, 'OnMenuExec', ['', '', '', '', str(ghost)])
            self.assertIn('桜\x01相方\x01三人目'.encode(), result)
            outside = self.work / 'outside.txt'
            outside.write_text('sakura.name,forbidden')
            path.unlink()
            path.symlink_to(outside)
            self.assertTrue(self.request(plugin, 'OnMenuExec', ['', '', '', '', str(ghost)]).startswith(b'PLUGIN/2.0 501'))
        finally:
            plugin.unload()

    def test_descriptor_bom_default_cp932_and_control_characters(self):
        ghost = self.work / 'charset-ghost'
        (ghost / 'ghost/master').mkdir(parents=True)
        path = ghost / 'ghost/master/descript.txt'
        plugin, _ = self.fixture(f'FUNCTIONEX("proxy_ex.dll", "core.exe", "-count", "{ghost}")')
        try:
            self.assertTrue(plugin.load())
            for data in ['sakura.name,桜\n'.encode('cp932'), '\ufeffcharset, UTF-8 // declaration\nsakura.name,桜\n'.encode(), b'// charset,Shift_JIS\nsakura.name,ASCII\n']:
                path.write_bytes(data)
                self.assertTrue(self.request(plugin, 'OnMenuExec', ['', '', '', '', str(ghost)]).startswith(b'PLUGIN/2.0 200'))
            path.write_bytes(b'sakura.name,unsafe\x01name\n')
            self.assertTrue(self.request(plugin, 'OnMenuExec', ['', '', '', '', str(ghost)]).startswith(b'PLUGIN/2.0 501'))
        finally:
            plugin.unload()

    def test_no_voice_by_default_is_an_intentional_silent_selection(self):
        body = 'EXECUTE("core.exe", "-g "+CHR(34)+"ghost"+CHR(34)+" -v 0 "+CHR(34)+"text"+CHR(34))'
        plugin, _ = self.fixture(body, config={'NoVoiceByDefault': True})
        try:
            self.assertTrue(plugin.load())
            with socket.socket() as reserved:
                reserved.bind(('127.0.0.1', 0))
                os.environ['OURIN_BOUYOMI_PORT'] = str(reserved.getsockname()[1])
                self.assertTrue(self.request(plugin).startswith(b'PLUGIN/2.0 200'))
        finally:
            os.environ.pop('OURIN_BOUYOMI_PORT', None)
            plugin.unload()

    def test_unknown_commands_wait_and_sapi_refused(self):
        for body in ['EXECUTE_WAIT("core.exe", "-e")', 'EXECUTE("/usr/bin/true")', 'EXECUTE("core.exe", "-g "+CHR(34)+"ghost"+CHR(34)+" -v 10001 "+CHR(34)+"text"+CHR(34))', 'FUNCTIONEX("proxy_ex.dll", "../core.exe", "-l")', 'FUNCTIONEX("proxy_ex.dll", "core.exe", "-unknown")']:
            with self.subTest(body=body):
                plugin, _ = self.fixture(body)
                try:
                    self.assertTrue(plugin.load())
                    self.assertTrue(self.request(plugin).startswith(b'PLUGIN/2.0 501'))
                finally:
                    plugin.unload()

    def test_real_tcp_scope_voice_state_and_quicksection(self):
        body = r'''EXECUTE("core.exe", "-g "+CHR(34)+"桜"+CHR(34)+" -v 2 "+CHR(34)+"\0こんにちは\_q隠す\_q。\1相方\p[2]三人目\e"+CHR(34))'''
        plugin, bundle = self.fixture(body)
        state = bundle / 'Contents/Resources/state/yaya-variables.json'
        state.write_text(json.dumps({hashlib.md5(f'桜{i}'.encode()).hexdigest()+'.voice': {'t':'s','v':str(i+2)} for i in range(3)}))
        try:
            self.assertTrue(plugin.load())
            with Receiver(3) as receiver:
                self.assertTrue(self.request(plugin).startswith(b'PLUGIN/2.0 200'))
            self.assertEqual(receiver.packets, [packet('こんにちは。',2),packet('相方',3),packet('三人目',4)])
        finally:
            plugin.unload()

    def test_multiple_scopes_share_one_tcp_deadline(self):
        # Both connections experience real receive backpressure. The first is
        # drained after 1 s; delaying the second past the same 2 s deadline must
        # reject the request, rather than reset a fresh timeout for each scope.
        text = 'x' * 1500000
        body = 'EXECUTE("core.exe", "-g "+CHR(34)+"ghost"+CHR(34)+" -v 0 "+CHR(34)+"\\0' + text + '\\1' + text + '"+CHR(34))'
        plugin, _ = self.fixture(body)
        received, errors = [], []
        with socket.socket() as server:
            server.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
            server.bind(('127.0.0.1', 0))
            server.listen(2)
            server.settimeout(5)
            os.environ['OURIN_BOUYOMI_PORT'] = str(server.getsockname()[1])

            def receive():
                try:
                    for delay in (1.0, 1.4):
                        with server.accept()[0] as client:
                            client.settimeout(4)
                            time.sleep(delay)
                            count = 0
                            while True:
                                data = client.recv(65536)
                                if not data:
                                    break
                                count += len(data)
                            received.append(count)
                except Exception as error:
                    errors.append(str(error))

            thread = threading.Thread(target=receive)
            try:
                self.assertTrue(plugin.load())
                thread.start()
                start = time.monotonic()
                response = self.request(plugin)
                elapsed = time.monotonic() - start
                thread.join(7)
                self.assertFalse(thread.is_alive())
                self.assertEqual(errors, [])
                self.assertEqual(received[0], len(packet(text, 0)))
                self.assertLess(received[1], len(packet(text, 0)))
                self.assertTrue(response.startswith(b'PLUGIN/2.0 501'))
                self.assertLess(elapsed, 3.0)
            finally:
                os.environ.pop('OURIN_BOUYOMI_PORT', None)
                plugin.unload()
                if thread.is_alive():
                    thread.join(7)

    def test_absent_service_is_failure(self):
        body = 'EXECUTE("core.exe", "-g "+CHR(34)+"ghost"+CHR(34)+" -v 0 "+CHR(34)+"\\0first\\1second\\p[2]third"+CHR(34))'
        plugin, _ = self.fixture(body)
        try:
            self.assertTrue(plugin.load())
            with socket.socket() as reserved:
                reserved.bind(('127.0.0.1', 0))
                os.environ['OURIN_BOUYOMI_PORT'] = str(reserved.getsockname()[1])
                self.assertTrue(self.request(plugin).startswith(b'PLUGIN/2.0 501'))
        finally:
            os.environ.pop('OURIN_BOUYOMI_PORT', None)
            plugin.unload()


if __name__ == '__main__':
    unittest.main(verbosity=2)
