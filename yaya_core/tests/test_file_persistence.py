#!/usr/bin/env python3
"""Actual JSON-line helper regression tests; no third-party ghost assets needed."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

CORE = Path(__file__).resolve().parents[1] / 'build/yaya_core'


class FilePersistenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ourin-yaya-files-')
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def run_core(self, dictionary, events, save_file=None, extra=None):
        (self.root / 'probe.dic').write_text(dictionary)
        load = dict(cmd='load', ghost_root=str(self.root), encoding='UTF-8', dic=['probe.dic'])
        if save_file is not None:
            load['save_file'] = str(save_file)
        requests = [load] + [dict(cmd='request', id=e) for e in events]
        requests += extra if extra is not None else [dict(cmd='unload')]
        run = subprocess.run([str(CORE)], input=''.join(json.dumps(r)+'\n' for r in requests),
                             capture_output=True, text=True, timeout=10)
        self.assertEqual(run.returncode, 0, run.stderr[-2000:])
        responses = [json.loads(line) for line in run.stdout.splitlines()]
        self.assertEqual(len(responses), len(requests), run.stderr[-2000:])
        self.assertTrue(all(r.get('ok') for r in responses), responses)
        return [r['value'] for r in responses if 'value' in r]

    def test_missing_read_does_not_create_or_loop(self):
        values = self.run_core('''Probe {
 _opened = FOPEN('missing.txt', 'r')
 _read = FREAD('missing.txt')
 "open=%(_opened),read=%(_read)"
}''', ['Probe'])
        self.assertEqual(values, ['open=0,read=-1'])
        self.assertFalse((self.root/'missing.txt').exists())

    def test_filename_registry_eof_blank_lines_and_duplicate_open(self):
        (self.root/'lines.txt').write_bytes(b'first\r\n\r\nlast')
        values = self.run_core('''Probe {
 _a=FOPEN('lines.txt','r')
 _b=FOPEN('./lines.txt','w')
 _c=FREAD('lines.txt')
 _d=FREAD('lines.txt')
 _e=FREAD('lines.txt')
 _f=FREAD('lines.txt')
 FCLOSE('lines.txt')
 _g=FREAD('lines.txt')
 "%(_a)|%(_b)|%(_c)|%(_d)|%(_e)|%(_f)|%(_g)"
}''', ['Probe'])
        self.assertEqual(values, ['1|2|first||last|-1|-1'])
        self.assertEqual((self.root/'lines.txt').read_bytes(), b'first\r\n\r\nlast')

    def test_writes_add_newline_and_binary_encoding_shares_registry(self):
        values = self.run_core('''Probe {
 FOPEN('written.txt','w')
 FWRITE('written.txt','one')
 FWRITE('written.txt','two')
 FCLOSE('written.txt')
 FOPEN('raw.bin','w')
 FWRITEDECODE('raw.bin','AEE=')
 FCLOSE('raw.bin')
 FOPEN('raw.bin','r')
 _a=FREADENCODE('raw.bin',1)
 _b=FREADENCODE('raw.bin',1)
 FCLOSE('raw.bin')
 "%(_a)|%(_b)"
}''', ['Probe'])
        self.assertEqual(values, ['AA==|QQ=='])
        self.assertEqual((self.root/'written.txt').read_bytes(), b'one\ntwo\n')
        self.assertEqual((self.root/'raw.bin').read_bytes(), b'\x00A')

    def test_foreach_and_saved_delimiter_survive_new_process(self):
        dictionary = '''Seed {
 Items='a|b|c'
 SETDELIM(Items,'|')
 _local='x::y'
 SETDELIM(_local,'::')
 _n=0
 foreach _local; _item { _n++ }
 SAVEVAR()
 "%(_n)"
}
Probe {
 _n=0
 foreach Items; _item { _n++ }
 "%(_n):%(Items[1])"
}'''
        self.assertEqual(self.run_core(dictionary, ['Seed', 'Probe']), ['2','3:b'])
        saved = json.loads((self.root/'yaya_variable.cfg').read_text())
        self.assertEqual(saved['Items']['delimiter'], '|')
        self.assertEqual(self.run_core(dictionary, ['Probe']), ['3:b'])

    def test_legacy_json_uses_default_delimiter(self):
        (self.root/'legacy.json').write_text(json.dumps({'Items': {'t':'s','v':'a,b,c'}}))
        self.assertEqual(self.run_core('''Probe {
 Items='x|y'
 SETDELIM(Items,'|')
 RESTOREVAR('legacy.json')
 _n=0
 foreach Items; _item { _n++ }
 "%(_n):%(Items[1])"
}''', ['Probe']), ['3:b'])

    def test_foreign_save_is_not_overwritten(self):
        path=self.root/'yaya_variable.cfg'
        original=b'// YAYA upstream save\r\nCounter,42\r\n'
        path.write_bytes(original)
        self.assertEqual(self.run_core('''Probe { "saved=%(SAVEVAR())" }''', ['Probe']), ['saved=0'])
        self.assertEqual(path.read_bytes(), original)

    def test_host_save_path_is_separate_from_basepath_and_auto_saves(self):
        save=self.root/'shiori/aya_variable.cfg'
        save.parent.mkdir()
        dictionary='''Seed { Counter=71\n "seeded" }
Probe { "%(Counter)|%(GETSETTING('coreinfo.savefile'))" }'''
        self.run_core(dictionary,['Seed'],save_file=save)
        self.assertEqual(self.run_core(dictionary,['Probe'],save_file=save), [f'71|{save}'])
        self.assertFalse((self.root/'yaya_variable.cfg').exists())

    def test_prefix_cleanup_preserves_persistent_variables(self):
        dictionary = """Seed {
 Counter=42
 Temp.value=3
 _names=GETVARLIST('Temp.')
 foreach _names; _name { ERASEVAR(_name) }
 "%(Counter)|%(ISVAR('Temp.value'))"
}
Probe { "%(Counter)" }"""
        self.assertEqual(self.run_core(dictionary,['Seed']),['42|0'])
        self.assertEqual(self.run_core(dictionary,['Probe']),['42'])

    def test_unload_closes_filename_registry(self):
        (self.root/'lines.txt').write_text('first\nsecond\n')
        dictionary='''Probe {
 _opened=FOPEN('lines.txt','r')
 _line=FREAD('lines.txt')
 "%(_opened)|%(_line)"
}'''
        extra=[dict(cmd='unload'),dict(cmd='load',ghost_root=str(self.root),dic=['probe.dic'],encoding='UTF-8'),dict(cmd='request',id='Probe'),dict(cmd='unload')]
        self.assertEqual(self.run_core(dictionary,['Probe'],extra=extra),['1|first','1|first'])


if __name__ == '__main__':
    unittest.main()
