#!/usr/bin/env python3
"""SAORI 204 must not become an empty-string YAYA output candidate.
UKADOC: https://ssp.shillest.net/ukadoc/manual/spec_saori_ex.html
Self-authored fixtures exercise the actual helper and host callback protocol.
"""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

CORE=Path(__file__).resolve().parents[1]/'build/yaya_core'


class SAORINoContentTests(unittest.TestCase):
    def run_core(self, dictionary, wires, count=1):
        with tempfile.TemporaryDirectory(prefix='ourin-saori-empty-') as directory:
            (Path(directory)/'probe.dic').write_text(dictionary)
            commands=[dict(cmd='load',ghost_root=directory,encoding='UTF-8',dic=['probe.dic'])]
            for _ in range(count):
                commands.append(dict(cmd='request',id='Probe'))
                commands.extend(dict(ok=True,status=200,response=wire) for wire in wires)
            commands.append(dict(cmd='unload'))
            result=subprocess.run([str(CORE)],input=''.join(json.dumps(x)+'\n' for x in commands),capture_output=True,text=True,timeout=15)
            self.assertEqual(result.returncode,0,result.stderr[-2000:])
            output=[json.loads(x) for x in result.stdout.splitlines()]
            callbacks=[x for x in output if 'host_op' in x]
            responses=[x for x in output if 'host_op' not in x]
            self.assertEqual(len(callbacks),len(wires)*count,output)
            self.assertTrue(all(x.get('ok') for x in responses),responses)
            return responses[1:-1]

    def test_no_content_is_void_but_200_empty_is_string(self):
        actual=self.run_core('''Probe {
 _none=FUNCTIONEX('fixture.dll','no-content')
 _empty=FUNCTIONEX('fixture.dll','empty-result')
 _text=FUNCTIONEX('fixture.dll','text-result')
 _missing=FUNCTIONEX('fixture.dll','missing-result')
 "%(GETTYPE(_none))|%(GETTYPE(_empty))|%(GETTYPE(_text))|%(_text)|%(GETTYPE(_missing))"
}''',[
            'SAORI/1.0 204 No Content\r\nCharset: UTF-8\r\n\r\n',
            'SAORI/1.0 200 OK\r\nResult: \r\n\r\n',
            'SAORI/1.0 200 OK\r\nResult: 日本語\r\n\r\n',
            'SAORI/1.0 200 OK\r\n\r\n'])
        self.assertEqual(actual[0]['value'],'0|3|3|日本語|3')

    def test_standalone_204_cannot_hide_menu_randomly(self):
        actual=self.run_core('''Probe {
 FUNCTIONEX('fixture.dll','/charset','UTF-8')
 if 1 {
  FUNCTIONEX('fixture.dll','/charset','sjis')
  "voice-menu"
 }
}''',['SAORI/1.0 204 No Content\r\n\r\n']*2,count=64)
        self.assertEqual([x['value'] for x in actual],['voice-menu']*64)

    def test_204_does_not_retain_previous_valueex(self):
        actual=self.run_core('''Probe {
 _first=FUNCTIONEX('fixture.dll','values')
 _before=ARRAYSIZE(valueex())
 _none=FUNCTIONEX('fixture.dll','no-content')
 "%(_before)|%(ARRAYSIZE(valueex()))|%(GETTYPE(_none))"
}''',['SAORI/1.0 200 OK\r\nResult: yes\r\nValue0: alpha\r\nValue2: beta\r\n\r\n',
      'SAORI/1.0 204 No Content\r\n\r\n'])
        self.assertEqual(actual[0]['value'],'2|0|0')


if __name__=='__main__':
    unittest.main()
