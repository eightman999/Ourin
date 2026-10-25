#!/usr/bin/env python3
"""User-call argument expansion and reference feedback through the real helper.

Contract: upstream YAYA 3ccd7c26, function.cpp ExecFunctionWithArgs.
Self-authored dictionaries only; builtins keep their individual Value arguments.
"""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

CORE = Path(__file__).resolve().parents[1] / 'build/yaya_core'


class UserArgumentTests(unittest.TestCase):
    def run_core(self, dictionary):
        with tempfile.TemporaryDirectory(prefix='ourin-user-arguments-') as directory:
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
            files = {p.name: p.read_bytes() for p in root.glob('*.json')}
            return responses[1]['value'], files

    def test_mixed_array_arguments_expand_in_original_order(self):
        actual, _ = self.run_core('''Join {
 "%(_argc)|%(DUMPJSON(_argv))"
}
Probe {
 Join('before',(1,2),IARRAY,('x','y'),'after')
}''')
        self.assertEqual(actual, '6|["before",1,2,"x","y","after"]')

    def test_single_array_expansion_is_one_level_and_hash_stays_one_value(self):
        actual, _ = self.run_core('''Join { "%(_argc)|%(DUMPJSON(_argv))" }
Probe {
 _nested=PARSEJSON('[[1,2],{"nested":[3,4]},5]')
 Join(_nested)
}''')
        self.assertEqual(actual, '3|[[1,2],{"nested":[3,4]},5]')

    def test_plugin_style_response_builder_keeps_all_lines(self):
        actual, _ = self.run_core('''MakeResponse {
 _result='PLUGIN/2.0 ' + _argv[0] + CHR(13) + CHR(10)
 for _i=1; _i<_argc; _i++ {
  _result+=_argv[_i]+CHR(13)+CHR(10)
 }
 _result+CHR(13)+CHR(10)
}
Probe {
 _lines=('Charset: UTF-8','Script: menu','Event: OnMenuExec')
 MakeResponse('200 OK',_lines)
}''')
        self.assertEqual(actual, 'PLUGIN/2.0 200 OK\r\nCharset: UTF-8\r\nScript: menu\r\nEvent: OnMenuExec\r\n\r\n')

    def test_reference_array_and_scalar_use_expanded_offsets(self):
        actual, _ = self.run_core('''Mutate {
 _argv[2]=20
 _argv[3]=30
 _argv[4]='changed'
}
Probe {
 _prefix=(7,8)
 _array=(2,3)
 _scalar='original'
 void Mutate(_prefix,&_array,&_scalar)
 "%(DUMPJSON(_prefix))|%(DUMPJSON(_array))|%(_scalar)"
}''')
        self.assertEqual(actual, '[7,8]|[20,30]|changed')

    def test_reference_array_reassembles_only_original_width(self):
        actual, _ = self.run_core('''Grow {
 _argv[0]=10
 _argv[1]=20
 _argv ,= 99
}
Probe {
 _array=(1,2)
 void Grow(&_array)
 DUMPJSON(_array)
}''')
        self.assertEqual(actual, '[10,20]')

    def test_shortened_argv_truncates_array_and_does_not_change_missing_scalar(self):
        actual, _ = self.run_core('''Shrink { _argv=(9,8) }
Probe {
 _array=(1,2,3)
 _after='keep'
 void Shrink('prefix',&_array,&_after)
 "%(DUMPJSON(_array))|%(_after)"
}''')
        self.assertEqual(actual, '[8]|keep')

    def test_empty_reference_array_has_zero_width(self):
        actual, _ = self.run_core('''Mutate { _argv[0]='after' }
Probe {
 _empty=IARRAY
 _scalar='before'
 void Mutate(&_empty,&_scalar)
 "%(GETTYPE(_empty))|%(ARRAYSIZE(_empty))|%(_scalar)"
}''')
        self.assertEqual(actual, '4|0|after')

    def test_nested_reference_array_element_is_written_back_to_caller_scope(self):
        actual, _ = self.run_core('''Mutate {
 _argv[0]=30
 _argv[1]=40
}
Forward { void Mutate(&_argv) }
Probe {
 _matrix=PARSEJSON('[[1,2],[3,4]]')
 void Forward(&_matrix[1])
 DUMPJSON(_matrix)
}''')
        self.assertEqual(actual, '[[1,2],[30,40]]')

    def test_scalar_reference_and_builtin_swap_still_work(self):
        actual, _ = self.run_core('''Mutate { _argv[0]+='!' }
Forward { void Mutate(&_argv[0]) }
Probe {
 _first='a'
 _second='b'
 void E.Swap(&_first,&_second)
 void Forward(&_first)
 "%(_first)|%(_second)"
}''')
        self.assertEqual(actual, 'b!|a')

    def test_builtin_json_and_arraysize_keep_top_level_nested_array(self):
        actual, files = self.run_core('''Probe {
 _value=PARSEJSON('[[1,2],{"nested":[3,4]},5]')
 _ok=FWRITEJSON('array.json',_value,'UTF-8',0)
 _read=FREADJSON('array.json')
 "%(_ok)|%(ARRAYSIZE(_value))|%(DUMPJSON(_read))"
}''')
        self.assertEqual(actual, '1|3|[[1,2],{"nested":[3,4]},5]')
        self.assertEqual(json.loads(files['array.json']), [[1,2], {'nested':[3,4]}, 5])


if __name__ == '__main__':
    unittest.main()
