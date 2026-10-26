#!/usr/bin/env python3
"""YAYA JSON and hash persistence tests through the actual helper process.

Contract: YAYA-shiori/yaya-shiori 3ccd7c26, sysfunc.cpp and jsonxml.cpp.
All fixtures are self-authored. Third-party saved data is never opened.
"""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

CORE = Path(__file__).resolve().parents[1] / 'build/yaya_core'


class JsonFileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ourin-json-files-')
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def run_core(self, code, events=('Probe',)):
        (self.root/'probe.dic').write_text(code)
        requests = [dict(cmd='load', ghost_root=str(self.root), encoding='UTF-8', dic=['probe.dic'])]
        requests += [dict(cmd='request', id=e) for e in events] + [dict(cmd='unload')]
        run = subprocess.run([str(CORE)], input=''.join(json.dumps(r)+'\n' for r in requests),
                             capture_output=True, text=True, timeout=10)
        self.assertEqual(run.returncode, 0, run.stderr[-2000:])
        responses = [json.loads(line) for line in run.stdout.splitlines()]
        self.assertEqual(len(responses), len(requests), run.stderr[-2000:])
        self.assertTrue(all(r.get('ok') for r in responses), responses)
        return [r['value'] for r in responses if 'value' in r]

    def test_bom_comments_types_and_exact_int64(self):
        (self.root/'in.json').write_text('\ufeff{/*comment*/"a":[true,false,null,1.5,1e2],// comment\n"n":9223372036854775807,"jp":"桜鈴"}')
        values = self.run_core('''Probe {
 _v=FREADJSON('in.json')
 _a=_v['a']
 _ok=GETTYPE(_v)==5 && _a[0]==1 && _a[1]==0 && GETTYPE(_a[2])==0 && _a[3]==1.5 && GETTYPE(_a[4])==1 && _v['n']==9223372036854775807 && _v['jp']=='桜鈴'
 "%(_ok)"
}''')
        self.assertEqual(values, ['1'])

    def test_nested_json_roundtrip_and_default_format(self):
        values = self.run_core('''Probe {
 _v=IHASH('name','桜鈴','items',(1,2,3),'nested',IHASH('n',9223372036854775807))
 _ok=FWRITEJSON('out.json',_v)
 _r=FREADJSON('out.json')
 _compact=DUMPJSON(_r)
 _parsed=PARSEJSON(_compact)
 "%(_ok)|%(_parsed['nested']['n'])|%(_parsed['items'][2])"
}''')
        self.assertEqual(values, ['1|9223372036854775807|3'])
        raw=(self.root/'out.json').read_text()
        self.assertTrue(raw.endswith('\n'))
        self.assertIn('桜鈴', raw)
        self.assertEqual(json.loads(raw)['items'], [1,2,3])

    def test_charset_is_independent_of_fcharset_and_escapes_unrepresentable(self):
        (self.root/'sjis.json').write_bytes('{"name":"日本語"}'.encode('cp932'))
        values=self.run_core('''Probe {
 FCHARSET(0)
 _r=FREADJSON('sjis.json','Shift_JIS')
 _ok=FWRITEJSON('legacy.json',IHASH('text','日本語😀'),'Shift_JIS',0)
 _back=FREADJSON('legacy.json',0)
 _utf=FWRITEJSON('utf.json',IHASH('text','日本語😀'))
 "%(_r['name'])|%(_ok)|%(_back['text'])|%(_utf)"
}''')
        self.assertEqual(values,['日本語|1|日本語😀|1'])
        self.assertFalse((self.root/'legacy.json').read_bytes().endswith(b'\n'))
        self.assertEqual(json.loads((self.root/'utf.json').read_text())['text'],'日本語😀')

    def test_failures_return_error_codes_without_creating_files(self):
        (self.root/'bad.json').write_text('{broken')
        (self.root/'keep.json').write_text('original')
        values=self.run_core('''Probe {
 _a=FREADJSON('missing.json')
 _ea=GETLASTERROR()
 _b=FREADJSON('bad.json')
 _eb=GETLASTERROR()
 _c=FWRITEJSON('keep.json',1,'not-a-charset')
 _ec=GETLASTERROR()
 _d=PARSEJSON(4)
 _ed=GETLASTERROR()
 _e=PARSEJSON()
 _ee=GETLASTERROR()
 "%(_ea)|%(_eb)|%(_c)|%(_ec)|%(_ed)|%(_ee)|%(GETTYPE(_a))|%(GETTYPE(_b))"
}''')
        self.assertEqual(values,['25|26|0|12|9|8|0|0'])
        self.assertFalse((self.root/'missing.json').exists())
        self.assertEqual((self.root/'keep.json').read_text(),'original')

    def test_path_escape_and_symlink_refused(self):
        with tempfile.TemporaryDirectory(prefix='ourin-json-outside-') as outside:
            target=Path(outside)/'keep.json'; target.write_text('{"private":1}')
            (self.root/'linked').symlink_to(outside, target_is_directory=True)
            values=self.run_core('''Probe {
 _r=FREADJSON('linked/keep.json')
 _re=GETLASTERROR()
 _w=FWRITEJSON('linked/keep.json',0)
 _we=GETLASTERROR()
 _up=FWRITEJSON('../escape.json',0)
 "%(_re)|%(_w)|%(_we)|%(_up)|%(GETTYPE(_r))"
}''')
            self.assertEqual(values,['25|0|25|0|0'])
            self.assertEqual(target.read_text(),'{"private":1}')

    def test_deep_or_invalid_utf8_json_fails(self):
        (self.root/'deep.json').write_text('['*200+'0'+']'*200)
        (self.root/'invalid.json').write_bytes(b'{"v":"\xff"}')
        self.assertEqual(self.run_core('''Probe {
 _a=FREADJSON('deep.json')
 _ea=GETLASTERROR()
 _b=FREADJSON('invalid.json')
 "%(_ea)|%(GETLASTERROR())|%(GETTYPE(_a))|%(GETTYPE(_b))"
}'''),['26|26|0|0'])

    def test_hash_savevar_survives_second_process_with_types(self):
        code='''Seed {
 Saved=IHASH('nested',IHASH('empty',IARRAY,'nil',PARSEJSON('null')),'values',(1,'2',3.5))
 SAVEVAR()
 "seed"
}
Probe {
 _ok=GETTYPE(Saved)==5 && GETTYPE(Saved['nested']['empty'])==4 && GETTYPE(Saved['nested']['nil'])==0 && Saved['values'][2]==3.5
 "%(_ok)"
}'''
        self.assertEqual(self.run_core(code,('Seed',)),['seed'])
        self.assertEqual(self.run_core(code),['1'])
        self.assertEqual(json.loads((self.root/'yaya_variable.cfg').read_text())['Saved']['t'],'d')

    def test_numeric_options_and_nonfinite_values_match_yaya(self):
        values=self.run_core('''Probe {
 _v=IHASH('n',SQRT(-1),'values',(1,2))
 _write=FWRITEJSON('finite.json',_v,1.0,0.5)
 _round=FREADJSON('finite.json',1.0)
 _compact=DUMPJSON(_v,'0')
 _bad=FREADJSON('finite.json',IARRAY)
 "%(_write)|%(GETTYPE(_round['n']))|%(GETLASTERROR())|%(_compact)"
}''')
        self.assertEqual(values,['1|0|9|{"n":null,"values":[1,2]}'])
        self.assertEqual((self.root/'finite.json').read_text(),'{"n":null,"values":[1,2]}')


if __name__ == '__main__': unittest.main()
