#!/usr/bin/env python3
"""YAYA 600 foreach semantics through the actual JSON-line helper.

Contract: YAYA-shiori/yaya-shiori Tc600-2, function.cpp CFunction::Foreach.
https://github.com/YAYA-shiori/yaya-shiori/blob/Tc600-2/function.cpp#L449
Fixtures are self-authored; no third-party dictionaries are copied here.
"""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

CORE = Path(__file__).resolve().parents[1] / 'build/yaya_core'


class HashForeachTests(unittest.TestCase):
    def run_core(self, dictionary):
        with tempfile.TemporaryDirectory(prefix='ourin-hash-foreach-') as directory:
            root = Path(directory)
            (root / 'probe.dic').write_text(dictionary, encoding='utf-8')
            requests = [dict(cmd='load', ghost_root=directory, encoding='UTF-8', dic=['probe.dic']),
                        dict(cmd='request', id='Probe'), dict(cmd='unload')]
            run = subprocess.run([str(CORE)], input=''.join(json.dumps(r)+'\n' for r in requests),
                                 capture_output=True, text=True, timeout=10)
            self.assertEqual(run.returncode, 0, run.stderr[-2000:])
            responses = [json.loads(line) for line in run.stdout.splitlines()]
            self.assertEqual(len(responses), 3, run.stderr[-2000:])
            self.assertTrue(all(r.get('ok') for r in responses), responses)
            return responses[1]['value']

    def test_hash_single_variable_yields_values(self):
        self.assertEqual(self.run_core('''Probe {
 _h=IHASH('alpha',4,'beta',7)
 _sum=0
 foreach _h; _value { _sum += _value }
 "%(_sum)"
}'''), '11')

    def test_hash_pair_preserves_nested_value_types(self):
        self.assertEqual(self.run_core('''Probe {
 _h=IHASH('array',(11,22),'hash',IHASH('inner',33),'text','日本語')
 _copy=IHASH()
 foreach _h; _key, _value { _copy[_key]=_value }
 _ok=GETTYPE(_copy['array'])==4 && _copy['array'][1]==22 && GETTYPE(_copy['hash'])==5 && _copy['hash']['inner']==33 && _copy['text']=='日本語'
 "%(_ok)"
}'''), '1')

    def test_pair_array_indices_and_old_single_variable_form(self):
        self.assertEqual(self.run_core('''Probe {
 _array=(10,20,30)
 _weighted=0
 foreach _array; _index, _value { _weighted += (_index + 1) * _value }
 _sum=0
 foreach _array; _value { _sum += _value }
 "%(_weighted)|%(_sum)|%(_index)"
}'''), '140|60|2')

    def test_pair_pseudoarray_respects_variable_delimiter(self):
        self.assertEqual(self.run_core('''Probe {
 _text='red::green::blue'
 SETDELIM(_text,'::')
 _out=''
 foreach _text; _index, _value { _out += "%(_index)=%(_value);" }
 "%(_out)"
}'''), '0=red;1=green;2=blue;')

    def test_hash_source_mutation_does_not_change_snapshot(self):
        self.assertEqual(self.run_core('''Probe {
 _h=IHASH('first',2,'second',3)
 _sum=0
 _count=0
 foreach _h; _key, _value {
  _sum += _value
  _count++
  _h=IHASH('replacement',100)
 }
 "%(_sum)|%(_count)|%(HASH_SIZE(_h))"
}'''), '5|2|1')

    def test_array_snapshot_continue_break_and_same_target_order(self):
        self.assertEqual(self.run_core('''Probe {
 _a=(2,3,4,5)
 _sum=0
 foreach _a; _index, _value {
  _a=(100,200)
  if _index==0 { continue }
  if _index==3 { break }
  _sum+=_value
 }
 foreach (30,40); _same, _same { _last=_same }
 "%(_sum)|%(_last)"
}'''), '7|40')

    def test_empty_and_scalar_sources_do_not_assign_targets(self):
        self.assertEqual(self.run_core('''Probe {
 _key='unchanged'
 _value='unchanged'
 _count=0
 foreach IHASH(); _key, _value { _count++ }
 foreach IARRAY; _key, _value { _count++ }
 foreach ''; _key, _value { _count++ }
 foreach 42; _key, _value { _count++ }
 "%(_count)|%(_key)|%(_value)"
}'''), '0|unchanged|unchanged')

    def test_source_expression_is_evaluated_once(self):
        self.assertEqual(self.run_core('''Make {
 Calls+=1
 IHASH('alpha',1,'beta',2)
}
Probe {
 Calls=0
 _sum=0
 foreach Make(); _key, _value { _sum+=_value }
 "%(_sum)|%(Calls)"
}'''), '3|1')


if __name__ == '__main__':
    unittest.main()
