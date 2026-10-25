#!/usr/bin/env python3
"""Meaningful real C ABI regression tests, using only self-authored dictionaries."""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate import generate
from verify_bundle import Plugin
REPO = Path(__file__).resolve().parents[2]
BASE = Path('/tmp/ourin-corpus-20261025')

class PluginAdapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        BASE.mkdir(exist_ok=True)
        cls.work = Path(tempfile.mkdtemp(prefix='plugin-adapter-tests-', dir=BASE))
        cls.collector = cls.work / 'build/yaya_plugin_collector'
        subprocess.run([sys.executable, str(REPO/'engines/plugins/prepare_collector.py'), '--output-dir', str(cls.collector.parent)], check=True, capture_output=True)
    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.work)
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(dir=self.work))
        self.source = self.root / 'source'
        self.source.mkdir()
        (self.source/'descript.txt').write_text('charset,UTF-8\nname,Self-authored fixture\nid,ourin-fixture\nfilename,yaya.dll\n')
        (self.source/'yaya.txt').write_text('charset.dic,UTF-8\ndic,plugin.dic\n')
    def tearDown(self):
        shutil.rmtree(self.root)
    def package(self, code):
        (self.source/'plugin.dic').write_text(code)
        self.before = {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in self.source.iterdir()}
        bundle = self.root / 'Fixture.plugin'
        args = argparse.Namespace(source=self.source, output=bundle, engine='yaya', adapter=REPO/'build/engines/plugins/OurinYayaPlugin.dylib', helper=REPO/'yaya_core/build/yaya_core', collector=self.collector, source_url='https://example.invalid/self-authored', saori_backend=[], engine_library=None)
        generate(args)
        return bundle
    def test_exact_plugin_wire_headers_unicode_and_204(self):
        bundle = self.package('''request {
  if STRSTR(_argv[0], "NOTIFY ") == 0 {
    REPLACE(_argv[0], "NOTIFY PLUGIN/2.0", "PLUGIN/2.0 204 No Content")
  } else {
    REPLACE(_argv[0], "GET PLUGIN/2.0M", "PLUGIN/2.0M 200 OK")
  }
}
''')
        plugin = Plugin(bundle)
        self.assertTrue(plugin.load())
        try:
            wire = 'GET PLUGIN/2.0M\r\nID: OnExample\r\nCharset: UTF-8\r\nSender: テスト\r\nReference12: 高位参照\r\nScript: 日本語\r\nTarget: original\r\n\r\n'
            self.assertEqual(wire.replace('GET PLUGIN/2.0M', 'PLUGIN/2.0M 200 OK').encode(), plugin.request(wire))
            notify = 'NOTIFY PLUGIN/2.0\r\nID: OnExample\r\nCharset: UTF-8\r\nReference0: value\r\n\r\n'
            self.assertEqual(notify.replace('NOTIFY PLUGIN/2.0', 'PLUGIN/2.0 204 No Content').encode(), plugin.request(notify))
        finally: plugin.unload()
        self.assertEqual(self.before, {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in self.source.iterdir()})
    def test_state_persists_across_unload_reload_without_touching_payload(self):
        bundle=self.package('''load { counter += 1 }
request { "PLUGIN/2.0 200 OK%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Reference0: %(counter)%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))" }
''')
        plugin=Plugin(bundle);self.assertTrue(plugin.load())
        wire='GET PLUGIN/2.0\r\nID: counter\r\n\r\n'
        try:self.assertIn(b'Reference0: 1\r\n',plugin.request(wire))
        finally:plugin.unload()
        self.assertTrue((bundle/'Contents/Resources/state/yaya-variables.json').is_file())
        self.assertFalse((bundle/'Contents/Resources/payload/yaya_variable.cfg').exists())
        self.assertTrue(plugin.load())
        try:self.assertIn(b'Reference0: 2\r\n',plugin.request(wire))
        finally:plugin.unload()

    def test_shift_jis_wire_roundtrip(self):
        bundle=self.package('request { REPLACE(_argv[0], "GET PLUGIN/2.0", "PLUGIN/2.0 200 OK") }')
        plugin=Plugin(bundle);self.assertTrue(plugin.load())
        wire='GET PLUGIN/2.0\r\nID: test\r\nCharset: Shift_JIS\r\nReference0: 日本語\r\n\r\n'
        try:self.assertEqual(wire.replace('GET PLUGIN/2.0','PLUGIN/2.0 200 OK').encode('cp932'),plugin.request(wire.encode('cp932')))
        finally:plugin.unload()

    def test_parseheader_preserves_duplicates_body_and_converts_only_canonical_numbers(self):
        bundle=self.package('''request {
  _p = PARSEHEADER(_argv[0], 1)
  _h = _p['header']
  _keys = _p['key']
  _raw = _p['rawvalue']
  _vals = _p['value']
  _ok = _p['start'] == "GET PLUGIN/2.0" && _h['X'] == 2 && _keys[1] == "X" && _keys[2] == "X" && _raw[1] == "1" && GETTYPE(_vals[1]) == 1 && GETTYPE(_h['Padded']) == 3 && _h['Space'] == " value" && _p['body'] == "body: untouched"
  "PLUGIN/2.0 200 OK%(CHR(13))%(CHR(10))Script: %(_ok)%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
}
''')
        plugin=Plugin(bundle); self.assertTrue(plugin.load())
        wire='GET PLUGIN/2.0\r\nID: test\r\nX: 1\r\nX: 2\r\nPadded: 001\r\nSpace:  value\r\ninvalid header\r\n\r\nbody: untouched'
        try:self.assertIn(b'Script: 1\r\n',plugin.request(wire))
        finally:plugin.unload()

    def test_hash_nested_assignment_and_numeric_array_regression(self):
        bundle=self.package('''request {
  _h = IHASH("a", 1, "a", 9, "nested", IHASH("x", 3))
  _h['nested']['x'] += 2
  _h['new'] = "value"
  _a = (10, 20, 30)
  _a[1] += 5
  _a[3] = 40
  _bad = PARSEHEADER(123)
  _error = GETLASTERROR()
  _lf = PARSEHEADER("First%(CHR(10))N: 9%(CHR(10))%(CHR(10))Body")
  _ok = _h['a'] == 1 && _h['nested']['x'] == 5 && _h['new'] == "value" && HASH_EXIST("new", _h) == 1 && HASH_SIZE(_h) == 3 && _a[1] == 25 && _a[3] == 40 && GETTYPE(_bad) == 0 && _error == 9 && _lf['body'] == "Body" && GETTYPE(_lf['header']['N']) == 3
  "PLUGIN/2.0 200 OK%(CHR(13))%(CHR(10))Script: %(_ok)%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
}
''')
        plugin=Plugin(bundle); self.assertTrue(plugin.load())
        try:self.assertIn(b'Script: 1\r\n',plugin.request('GET PLUGIN/2.0\r\nID: test\r\n\r\n'))
        finally:plugin.unload()

    def test_invalid_protocol_is_not_synthetic_success(self):
        bundle=self.package('request { "PLUGIN/2.0 200 OK%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))" }')
        plugin=Plugin(bundle); self.assertTrue(plugin.load())
        try:self.assertTrue(plugin.request('GET SHIORI/3.0\r\n\r\n').startswith(b'PLUGIN/2.0 400'))
        finally:plugin.unload()
    def test_no_framework_is_not_direct_event_fallback(self):
        bundle=self.package('OnMenuExec { "hello" }')
        plugin=Plugin(bundle);self.assertTrue(plugin.load())
        try:self.assertTrue(plugin.request('GET PLUGIN/2.0\r\nID: OnMenuExec\r\n\r\n').startswith(b'PLUGIN/2.0 501'))
        finally:plugin.unload()
    def test_malformed_framework_reply_is_error(self):
        bundle=self.package('request { "success-looking invalid text" }')
        plugin=Plugin(bundle);self.assertTrue(plugin.load())
        try:self.assertTrue(plugin.request('GET PLUGIN/2.0\r\nID: OnMenuExec\r\n\r\n').startswith(b'PLUGIN/2.0 502'))
        finally:plugin.unload()
    def test_unavailable_external_saori_is_error(self):
        bundle=self.package('''request {
  _ignored = LOADLIB("not-a-native-backend.dll")
  "PLUGIN/2.0 200 OK%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
}
''')
        plugin=Plugin(bundle);self.assertTrue(plugin.load())
        try:self.assertTrue(plugin.request('GET PLUGIN/2.0\r\nID: OnMenuExec\r\n\r\n').startswith(b'PLUGIN/2.0 501'))
        finally:plugin.unload()
    def test_partially_parsed_dictionary_set_rejects_load(self):
        (self.source/'broken.dic').write_text('Broken { foreach x ; key, value { "" } }')
        (self.source/'yaya.txt').write_text('charset.dic,UTF-8\ndic,plugin.dic\ndic,broken.dic\n')
        bundle=self.package('request { "PLUGIN/2.0 200 OK%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))" }')
        plugin=Plugin(bundle)
        try:self.assertFalse(plugin.load())
        finally:plugin.unload()

    def test_generator_rejects_source_symlink(self):
        (self.source/'linked').symlink_to('/etc/passwd')
        with self.assertRaises(ValueError):self.package('request { "" }')

if __name__=='__main__': unittest.main()
