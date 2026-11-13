#!/usr/bin/env python3
"""EXECUTE / EXECUTE_WAIT は yaya_core 内でシェルを起動せず、必ずホストへ委ねる。
YAYA: http://usada.sakura.vg/contents/shiori.html (EXECUTE / EXECUTE_WAIT)
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

CORE=Path(__file__).resolve().parents[1]/'build/yaya_core'


class ExecuteHostGateTests(unittest.TestCase):
    def run_core(self, dictionary, host_replies, load_extra=None):
        with tempfile.TemporaryDirectory(prefix='ourin-exec-gate-') as directory:
            marker=Path(directory)/'ourin_exec_test'
            (Path(directory)/'probe.dic').write_text(dictionary.replace('MARKER',str(marker)))
            load=dict(cmd='load',ghost_root=directory,encoding='UTF-8',dic=['probe.dic'])
            load.update(load_extra or {})
            commands=[load,dict(cmd='request',id='Probe'),*host_replies,dict(cmd='unload')]
            result=subprocess.run([str(CORE)],input=''.join(json.dumps(x)+'\n' for x in commands),
                                  capture_output=True,text=True,timeout=15)
            self.assertEqual(result.returncode,0,result.stderr[-2000:])
            output=[json.loads(x) for x in result.stdout.splitlines()]
            callbacks=[x for x in output if 'host_op' in x]
            responses=[x for x in output if 'host_op' not in x]
            return callbacks,responses,marker.exists()

    def test_execute_without_host_execute_is_delegated_and_never_shelled(self):
        dictionary='''Probe {
 _a=EXECUTE('touch MARKER; echo')
 _b=EXECUTE_WAIT('touch MARKER', '-x')
 "%(_a)|%(_b)"
}'''
        denied={'ok':False,'status':403,'error':'denied'}
        callbacks,responses,created=self.run_core(dictionary,[denied,denied])
        self.assertFalse(created,'yaya_core must not run the command itself')
        self.assertEqual([c['host_op'] for c in callbacks],['execute','execute'])
        self.assertEqual(callbacks[0]['params'],{'command':callbacks[0]['params']['command'],'wait':False,'arguments':''})
        self.assertTrue(callbacks[0]['params']['command'].startswith('touch '))
        self.assertEqual(callbacks[1]['params']['wait'],True)
        self.assertEqual(callbacks[1]['params']['arguments'],'-x')
        self.assertEqual(responses[1]['value'],'0|-1')

    def test_host_result_is_returned(self):
        dictionary='''Probe {
 _a=EXECUTE('/usr/bin/true')
 _b=EXECUTE_WAIT('/usr/bin/false')
 "%(_a)|%(_b)"
}'''
        replies=[{'ok':True,'status':200},{'ok':True,'status':200,'exit_code':1}]
        callbacks,responses,_=self.run_core(dictionary,replies,{'host_execute':True})
        self.assertEqual(len(callbacks),2)
        self.assertEqual(responses[1]['value'],'1|1')


if __name__=='__main__':
    unittest.main()
