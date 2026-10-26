"""Independent post-Cursor audit cases; fixtures are created only in temporary roots."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import signal
import select
from unittest.mock import patch
import sys
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / 'scripts'))
from corpus_probe.engine import resolve_engine
from corpus_probe.ghost import BoundedSession, _summarize_event, _yaya_config_path, probe_ghost
from corpus_probe.io_util import bounded_tree_digest, MAX_FILE_DIGEST_BYTES

class AuditRegressions(unittest.TestCase):
    def test_aosora_200_runtime_error_is_not_success(self):
        from corpus_probe.native_shiori_worker import parse_aosora_response
        for levels in (b'error', b'warning\x01error'):
            response = b'SHIORI/3.0 200 OK\r\nErrorLevel: ' + levels + b'\r\nValue: diagnostic\r\n\r\n'
            result = parse_aosora_response(response)
            self.assertFalse(result['ok'])
            self.assertEqual(result['value'], '')
            self.assertEqual(result['error'], 'aosora_runtime_error')

    def test_aosora_warning_does_not_discard_response(self):
        from corpus_probe.native_shiori_worker import parse_aosora_response
        response = b'SHIORI/3.0 200 OK\r\nErrorLevel: warning\r\nValue: authored-marker\r\n\r\n'
        result = parse_aosora_response(response)
        self.assertTrue(result['ok'])
        self.assertEqual(result['value'], 'authored-marker')

    def test_downloaded_native_with_claimed_abi_is_never_executed(self):
        import plistlib
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'custom.dylib').write_bytes(b'\xcf\xfa\xed\xfe')
            (root / 'custom.plist').write_bytes(plistlib.dumps({'OurinShioriABI':'ukagaka-long'}))
            (root / 'descript.txt').write_text('name,Untrusted\nshiori.macos,custom.dylib\n')
            with patch('corpus_probe.ghost.BoundedSession') as session:
                result = probe_ghost(root, REPO, 'untrusted', None, root, [])
            session.assert_not_called()
            self.assertEqual(result['status'], 'unsupported')
            self.assertEqual(result['reason'], 'downloaded_native_module_not_trusted')
            self.assertIsNone(result['checks']['engine']['native_artifact'])

    def test_second_session_load_or_unload_failure_prevents_pass(self):
        script = r'''
import json,sys
from pathlib import Path
marker=Path('session-marker')
second=marker.exists()
for line in sys.stdin:
    message=json.loads(line)
    label=message.get('cmd')
    if label=='load': marker.write_text('loaded')
    fail=second and label==sys.argv[1]
    print(json.dumps({'ok':not fail,'status':500 if fail else 200,'value':'self-authored response'}),flush=True)
'''
        for failure in ('load', 'unload'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp)
                (root/'descript.txt').write_text('name,Reopen test\nshiori,satori.dll\n')
                engine={'supported':True,'helper':'satori_core'}
                with patch('corpus_probe.ghost.resolve_engine',return_value=engine), patch('corpus_probe.ghost._helper_command',return_value=[sys.executable,'-c',script,failure]):
                    result=probe_ghost(root,REPO,'reopen',None,root,[])
                self.assertEqual(result['status'],'partial')
                self.assertEqual(result['reason'],'reopen_failed')
                self.assertTrue(result['checks']['conversation']['ok'])
                self.assertTrue(all(x['ok'] for x in result['checks']['lifecycle']))
                self.assertFalse(result['checks']['persistence']['cycle2_complete'])

    def test_tree_budget_accepts_large_package_but_stays_bounded(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            asset = root / 'self-authored-sparse-asset.bin'
            self.assertEqual(MAX_FILE_DIGEST_BYTES, 8 * 1024 * 1024)
            for size in (79_373_671, 128 * 1024 * 1024):
                with asset.open('wb') as output:
                    output.truncate(size)
                digest, error = bounded_tree_digest(root)
                self.assertIsNone(error)
                self.assertEqual(digest['file_count'], 1)
                self.assertEqual(digest['truncated_file_count'], 1)
                self.assertFalse(digest['digest_complete'])
            with asset.open('ab') as output:
                output.write(b'x')
            digest, error = bounded_tree_digest(root)
            self.assertIsNone(digest)
            self.assertEqual(error, 'tree_too_large')

    def test_omitted_shiori_uses_shiori_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            config = root / 'shiori.txt'
            config.write_text('dic,probe.dic\n')
            (root / 'yaya.txt').write_text('dic,other.dic\n')
            result = resolve_engine(root, root, {}, REPO, None, [])
            self.assertEqual(result['module_stem'], 'shiori')
            self.assertEqual(result['runtime_kind'], 'yaya_core')
            self.assertEqual(_yaya_config_path(root, {}), config)

    def test_omitted_shiori_unknown_dll_is_not_assumed_yaya(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'shiori.dll').write_bytes(b'MZ test only')
            result = resolve_engine(root, root, {}, REPO, 'yaya', [])
            self.assertEqual(result['module_stem'], 'shiori')
            self.assertFalse(result['supported'])
            self.assertEqual(result['unsupported_reason'], 'windows_shiori_not_executable')

    def test_known_yaya_windows_dll_does_not_disable_native_helper(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'yaya.dll').write_bytes(b'MZ test only')
            result = resolve_engine(root, root, {'shiori': 'yaya.dll'}, REPO, None, [])
            self.assertTrue(result['supported'])
            self.assertEqual(result['helper'], 'yaya_core')
            self.assertFalse(result['windows_only_metadata'])

    def test_unknown_windows_dll_never_executes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'unknown.dll').write_bytes(b'MZ test only')
            result = resolve_engine(root, root, {'shiori': 'unknown.dll'}, REPO, 'yaya', [])
            self.assertFalse(result['supported'])
            self.assertIsNone(result['native_artifact'])

    def test_unload_without_success_is_not_success(self):
        self.assertFalse(_summarize_event('unload', {'error_category': 'timeout'})['ok'])

    def test_small_response_does_not_wait_for_pipe_eof(self):
        code = 'import sys,json,time; sys.stdin.readline(); print(json.dumps({"ok":True,"status":200,"value":"short"}),flush=True); time.sleep(10)'
        with tempfile.TemporaryDirectory() as tmp:
            session = BoundedSession([sys.executable, '-c', code], Path(tmp))
            try:
                result = session.exchange({'cmd': 'request'}, 2)
                self.assertTrue(result['ok'])
                self.assertEqual(result['value_length'], 5)
            finally:
                session.close()
            self.assertIsNotNone(session.proc.poll())

    def test_unterminated_output_flood_is_bounded_and_reaped(self):
        code = 'import os,time; os.write(1,b"x"*1048576); time.sleep(10)'
        with tempfile.TemporaryDirectory() as tmp:
            session = BoundedSession([sys.executable, '-c', code], Path(tmp))
            started = time.monotonic()
            try:
                result = session.exchange({'cmd': 'load'}, 2)
                self.assertFalse(result['ok'])
            finally:
                session.close()
            self.assertLess(time.monotonic()-started, 5)
            self.assertIsNotNone(session.proc.poll())

class ProcessGroupRegressions(unittest.TestCase):
    def test_parent_owned_close_only_terminates_helper(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {"OURIN_CORPUS_PARENT_OWNS_GROUP": "1"}):
            session = BoundedSession([sys.executable, '-c', 'import time; time.sleep(30)'], Path(tmp))
            try:
                self.assertEqual(os.getpgid(session.proc.pid), os.getpgrp())
            finally:
                session.close()
            self.assertIsNotNone(session.proc.poll())

    def test_standalone_owns_separate_process_group(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {"OURIN_CORPUS_PARENT_OWNS_GROUP": "0"}):
            session = BoundedSession([sys.executable, '-c', 'import time; time.sleep(30)'], Path(tmp))
            try:
                self.assertEqual(os.getpgid(session.proc.pid), session.proc.pid)
                self.assertNotEqual(os.getpgid(session.proc.pid), os.getpgrp())
            finally:
                session.close()
            self.assertIsNotNone(session.proc.poll())

    def test_outer_timeout_group_signal_reaches_and_reaps_helper(self):
        code = r"""
import json,os,signal,sys,time
from pathlib import Path
sys.path.insert(0,sys.argv[1])
from corpus_probe.ghost import BoundedSession
session=BoundedSession([sys.executable,'-c','import time; time.sleep(30)'],Path.cwd())
def stopped(signum, frame):
    try:
        session.proc.wait(timeout=2)
    except Exception:
        session.proc.kill(); session.proc.wait(); sys.exit(3)
    sys.exit(0)
signal.signal(signal.SIGTERM,stopped)
print(json.dumps({'pid':session.proc.pid,'group':os.getpgid(session.proc.pid)}),flush=True)
time.sleep(30)
"""
        env = {**os.environ, "OURIN_CORPUS_PARENT_OWNS_GROUP": "1", "PYTHONDONTWRITEBYTECODE": "1"}
        supervisor = subprocess.Popen([sys.executable, '-c', code, str(REPO/'scripts')],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env, start_new_session=True)
        try:
            self.assertTrue(select.select([supervisor.stdout], [], [], 5)[0])
            ready = json.loads(supervisor.stdout.readline())
            self.assertEqual(ready['group'], supervisor.pid)
            os.killpg(supervisor.pid, signal.SIGTERM)
            supervisor.communicate(timeout=5)
            self.assertEqual(supervisor.returncode, 0)
            with self.assertRaises(ProcessLookupError):
                os.kill(ready['pid'], 0)
        finally:
            if supervisor.poll() is None:
                os.killpg(supervisor.pid, signal.SIGKILL)
                supervisor.communicate(timeout=5)


class NativeStdoutRegressions(unittest.TestCase):
    def test_native_print_does_not_corrupt_json_and_load_failure_stays_failure(self):
        import shutil
        compiler = shutil.which('clang')
        if sys.platform != 'darwin' or not compiler:
            self.skipTest('macOS clang unavailable')
        with tempfile.TemporaryDirectory(prefix='ourin-native-stdout-') as tmp:
            root = Path(tmp)
            source = root/'fixture.c'
            source.write_text(r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
__attribute__((constructor)) static void init(void) { puts("native init diagnostic"); fflush(stdout); }
int kagari_load(char *path, long len) {
    int failure = strstr(path, "/fail/") != NULL;
    free(path);
    puts("{\"ok\":true,\"status\":200,\"value\":\"engine log is not protocol\"}"); fflush(stdout);
    return failure ? -1 : 0;
}
char *kagari_request(int id, char *request, long *len) {
    free(request); puts("native request diagnostic"); fflush(stdout);
    char *result = strdup("SHIORI/3.0 200 OK\r\nValue: self-authored test\r\n\r\n");
    *len = strlen(result); return result;
}
int kagari_unload(int id) { puts("native unload diagnostic"); fflush(stdout); return 1; }
''')
            library = root/'fixture.dylib'
            subprocess.run([compiler, '-dynamiclib', str(source), '-o', str(library)], check=True, capture_output=True, timeout=30)
            worker = REPO/'scripts/corpus_probe/native_shiori_worker.py'
            for failed in (False, True):
                messages = [{'cmd':'load','ghost_root':str(root/('fail' if failed else 'success'))}]
                if not failed:
                    messages.append({'cmd':'request','id':'OnBoot'})
                messages.append({'cmd':'unload'})
                result = subprocess.run([sys.executable,str(worker),'--abi','kagari','--library',str(library)], input=''.join(json.dumps(x)+'\n' for x in messages),capture_output=True,text=True,cwd=root,timeout=10)
                self.assertEqual(result.returncode,0)
                answers = [json.loads(x) for x in result.stdout.splitlines()]
                self.assertEqual(len(answers),len(messages))
                self.assertEqual(answers[0]['ok'],not failed)
                self.assertIn('native init diagnostic',result.stderr)
                self.assertNotIn('engine log is not protocol',result.stdout)


if __name__ == '__main__':
    unittest.main()
