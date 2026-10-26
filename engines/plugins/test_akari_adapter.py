#!/usr/bin/env python3
"""Native Akari PLUGIN ABI regression using self-authored dictionaries only."""
import argparse
import hashlib
import json
import os
import signal
import sys
import time
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from generate import generate
from verify_bundle import Plugin

REPO = Path(__file__).resolve().parents[2]

class AkariAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ourin-akari-test-')
        self.root = Path(self.temp.name)
        self.sequence = 0
        self.source = self.root / 'source'
        self.source.mkdir()
        (self.source/'descript.txt').write_text('charset,UTF-8\nname,Ourin fixture\nid,akari-fixture\nfilename,akari.dll\n')
    def tearDown(self):
        self.temp.cleanup()
    def package(self, code):
        (self.source/'main.azr').write_text(code)
        self.before = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in self.source.iterdir()}
        self.sequence += 1
        self.bundle = self.root/f'Fixture{self.sequence}.plugin'
        generate(argparse.Namespace(source=self.source, output=self.bundle, engine='akari',
            adapter=REPO/'build/engines/plugins/OurinAkariPlugin.dylib',
            engine_library=REPO/'build/engines/additional/libakari.dylib',
            helper=None, collector=None, source_url='https://example.invalid/fixture', saori_backend=[]))
        return Plugin(self.bundle)
    def wire(self, event='OnExample', method='GET'):
        return f'{method} PLUGIN/2.0M\r\nCharset: UTF-8\r\nID: {event}\r\nReference12: 日本語\r\n\r\n'
    def test_raw_plugin_headers_and_normalized_protocol(self):
        plugin = self.package('''array _customrequest(dict ref) {
 array ar;
 ar += "PLUGIN/2.0 200 OK";
 ar += "Charset: UTF-8";
 ar += "Reference12: " + ref["Reference12"];
 ar += "Script: こんにちは";
 ar += "Target: fixture";
 ar += "Reference0: " + ref["head"];
 ar += "";
 return ar;
}''')
        self.assertTrue(plugin.load())
        try:
            response = plugin.request(self.wire()).decode()
            for expected in ['PLUGIN/2.0 200 OK', 'Script: こんにちは', 'Reference12: 日本語',
                             'Reference0: GET PLUGIN/2.0', 'Target: fixture']:
                self.assertIn(expected, response)
            with self.assertRaises(RuntimeError):
                plugin.request('GET SHIORI/3.0\r\n\r\n')
        finally: plugin.unload()
        self.assertEqual(self.before, {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in self.source.iterdir()})
    def test_missing_request_handler_keeps_plugin_protocol(self):
        plugin = self.package('string version() { return "fixture"; }')
        self.assertTrue(plugin.load())
        try: self.assertTrue(plugin.request(self.wire()).startswith(b'PLUGIN/2.0 204'))
        finally: plugin.unload()
    def test_unload_executes_dictionary_save_and_reload(self):
        plugin = self.package('''load() { }
unload() { _vsave("lifecycle", "saved-by-unload"); }
array _customrequest(dict ref) { return {"PLUGIN/2.0 204 No Content", "Charset: UTF-8", ""}; }
''')
        self.assertTrue(plugin.load())
        plugin.request(self.wire())
        plugin.unload()
        saved = self.bundle/'Contents/Resources/payload/files/variables/lifecycle.json'
        self.assertTrue(saved.is_file())
        self.assertIn('saved-by-unload', saved.read_text())
        self.assertTrue(plugin.load())
        plugin.unload()
    def test_two_live_plugins_keep_independent_engine_state(self):
        def code(marker):
            return 'array _customrequest(dict ref) { return {"PLUGIN/2.0 200 OK", "Charset: UTF-8", "Script: ' + marker + '", ""}; }'
        first = self.package(code('first'))
        second = self.package(code('second'))
        self.assertTrue(first.load()); self.assertTrue(second.load())
        try:
            for _ in range(3):
                self.assertIn(b'Script: first', first.request(self.wire()))
                self.assertIn(b'Script: second', second.request(self.wire()))
            first.unload()
            self.assertIn(b'Script: second', second.request(self.wire()))
        finally:
            first.unload(); second.unload()

    def test_unload_reaps_helper_and_spawned_descendant(self):
        plugin = self.package('load() {}')
        pid_file = self.root/'descendant.json'
        helper = self.bundle/'Contents/Resources/akari_helper'
        # A self-authored helper exercises the adapter's real process boundary.
        # Keep the helper alive after its unload response: stop() must terminate
        # both it and its long-running child, rather than only the helper PID.
        helper.write_text('#!' + sys.executable + '\n' +
            'import json, os, subprocess, sys, time\n' +
            'from pathlib import Path\n' +
            'for line in sys.stdin:\n' +
            ' message = json.loads(line)\n' +
            " if message['cmd'] == 'load':\n" +
            "  child = subprocess.Popen(['/bin/sleep', '30'])\n" +
            f'  Path({str(pid_file)!r}).write_text(json.dumps([os.getpid(), child.pid]))\n' +
            " print(json.dumps({'ok': True}), flush=True)\n" +
            " if message['cmd'] == 'unload': time.sleep(30); break\n")
        helper.chmod(0o755)
        pids = []
        def exists(pid):
            try:
                os.kill(pid, 0)
                return True
            except ProcessLookupError:
                return False
        # This test covers standalone ownership. The corpus runner owns cleanup
        # of the entire outer group when its explicit environment flag is set.
        with patch.dict(os.environ):
            os.environ.pop('OURIN_CORPUS_PARENT_OWNS_GROUP', None)
            try:
                self.assertTrue(plugin.load())
                pids = json.loads(pid_file.read_text())
                self.assertEqual(len(pids), 2)
                self.assertTrue(all(exists(pid) for pid in pids))
                plugin.unload()
                deadline = time.monotonic() + 5
                while any(exists(pid) for pid in pids) and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertFalse(any(exists(pid) for pid in pids),
                                 'adapter unload left its helper or descendant alive')
            finally:
                plugin.unload()
                # Clean up even on a pre-fix adapter or a failed assertion.
                if not pids and pid_file.exists():
                    pids = json.loads(pid_file.read_text())
                for pid in pids:
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_resource_escape_fails_load(self):
        plugin = self.package('load() {}')
        path = self.bundle/'Contents/Resources/adapter.json'
        config = json.loads(path.read_text()); config['payload'] = '../../../../source'
        path.write_text(json.dumps(config))
        self.assertFalse(plugin.load())

if __name__ == '__main__': unittest.main()
