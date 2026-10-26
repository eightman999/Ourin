#!/usr/bin/env python3
"""Actual Aosora ABI/lifecycle regressions using only Ourin-authored dictionaries."""
from pathlib import Path
import ctypes
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'scripts/corpus_probe'))
from native_shiori_worker import bind_aosora

LIBRARY = Path(sys.argv[1]).resolve()
sys.argv = [sys.argv[0]]


class AosoraNativeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = ctypes.CDLL(str(LIBRARY))
        cls.libc = ctypes.CDLL(None)
        cls.libc.malloc.argtypes = [ctypes.c_size_t]
        cls.libc.malloc.restype = ctypes.c_void_p
        cls.libc.free.argtypes = [ctypes.c_void_p]

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ourin-aosora-test-')
        self.root = Path(self.temp.name)
        self.load, self.request, self.unload = bind_aosora(self.module, self.libc)
        self.root.joinpath('ghost.asproj').write_text('main.as\n')
        self.root.joinpath('main.as').write_text('function OnBoot { return "aosora-test"; }')

    def tearDown(self):
        self.unload()
        self.temp.cleanup()

    def test_lifecycle(self):
        for _ in range(2):
            self.assertTrue(self.load(str(self.root))['ok'])
            self.assertEqual(self.request({'id': 'OnBoot'})['value'], 'aosora-test')
            self.assertTrue(self.unload()['ok'])

    def test_missing_dictionary_rejected(self):
        self.root.joinpath('main.as').unlink()
        self.assertFalse(self.load(str(self.root))['ok'])

    def test_invalid_dictionary_rejected(self):
        self.root.joinpath('main.as').write_text('function Broken { !! invalid }')
        self.assertFalse(self.load(str(self.root))['ok'])

    def test_runtime_error_not_counted_as_dialogue(self):
        self.root.joinpath('main.as').write_text('function OnBoot { return missingFunction(); }')
        self.assertTrue(self.load(str(self.root))['ok'])
        self.assertFalse(self.request({'id': 'OnBoot'})['ok'])

    def test_second_instance_cannot_corrupt_first(self):
        self.assertTrue(self.load(str(self.root))['ok'])
        other_load, _, other_unload = bind_aosora(self.module, self.libc)
        self.assertFalse(other_load(str(self.root))['ok'])
        self.assertTrue(other_unload()['ok'])
        self.assertEqual(self.request({'id': 'OnBoot'})['value'], 'aosora-test')

    def test_existing_save_updated_and_reloaded(self):
        self.root.joinpath('main.as').write_text('''
function OnRecall { return Save.Data.count; }
function OnRemember { Save.Data.count = 37; return "saved"; }
''')
        self.root.joinpath('savedata.asv').write_text('{"count":19}')
        self.assertTrue(self.load(str(self.root))['ok'])
        self.assertEqual(self.request({'id': 'OnRecall'})['value'], '19')
        self.assertEqual(self.request({'id': 'OnRemember'})['value'], 'saved')
        self.assertTrue(self.unload()['ok'])
        self.assertTrue(self.load(str(self.root))['ok'])
        self.assertEqual(self.request({'id': 'OnRecall'})['value'], '37')

    def test_class_declaration_does_not_stop_root_initialization(self):
        self.root.joinpath('ghost.asproj').write_text('main.as\nother.as')
        self.root.joinpath('main.as').write_text('function OnBoot { return AfterClass(); }')
        self.root.joinpath('other.as').write_text('''
class Counter { init { this.count = 2; } function Count { return this.count; } }
local counter = new Counter();
function AfterClass { return counter.Count(); }
''')
        self.assertTrue(self.load(str(self.root))['ok'])
        self.assertEqual(self.request({'id': 'OnBoot'})['value'], '2')


if __name__ == '__main__':
    unittest.main(verbosity=2)
