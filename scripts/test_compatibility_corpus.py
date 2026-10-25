#!/usr/bin/env python3
"""Black-box tests for scripts/compatibility_corpus.py.

These tests invoke the runner as a CLI subprocess (``sys.executable
scripts/compatibility_corpus.py ...``) against a local ThreadingHTTPServer
that serves ZIP/NAR payloads generated in memory. No external network is
contacted; every download URL points at 127.0.0.1.

All fixture artifacts (catalogs, reports, work roots, probe scripts, canary
files) are created inside a per-test temporary directory under the allowed
base ``/tmp/ourin-corpus-20261025``; tearDown removes only that directory.
The runner contract requires every artifact working directory to resolve
beneath that base, so ``--work-root`` is always a subdirectory of it.

Probe coverage notes
--------------------
* Probe subprocess behaviour (stdin JSON, stdout JSON, timeout, bounded
  output, sandboxed execution) is exercised with REAL probe scripts via
  ``--probe-command-json`` - nothing is mocked.
* On macOS, probe tests expect execution through /usr/bin/sandbox-exec:
  network is denied and writes are allowed only inside the item work root.
* When the sandbox is unavailable (non-macOS, or sandbox-exec missing),
  the same tests assert ``runtime.status == 'unverified'`` instead of a
  probe outcome. This is contract behaviour: an unsandboxed probe may
  never report pass/partial/unsupported/error.
* The optional in-process test at the bottom imports the module and
  patches ``module.SANDBOX_EXEC`` to simulate an unavailable sandbox.
  It exists only as a portability aid for non-macOS runners and is
  skipped if the module layout differs; it asserts nothing about real
  sandbox coverage.

Run:  python3 scripts/test_compatibility_corpus.py -v
"""
from __future__ import annotations

import collections
import signal
import hashlib
import importlib.util
import io
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import unittest.mock
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = pathlib.Path(__file__).resolve().parent
RUNNER = HERE / 'compatibility_corpus.py'
ALLOWED_BASE = pathlib.Path('/tmp/ourin-corpus-20261025')
SANDBOX_EXEC = '/usr/bin/sandbox-exec'
TEST_SECRET = 'CORPUS_TEST_SECRET'  # must be stripped from probe env


def sandbox_available() -> bool:
    return os.path.exists(SANDBOX_EXEC)


def build_zip(entries: dict) -> bytes:
    """entries: name -> bytes, or (bytes, zipfile.ZipInfo) is not supported;
    use raw_zip for exotic metadata."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, data in entries.items():
            z.writestr(name, data)
    return buf.getvalue()


def ghost_zip(name: bytes = b'TestGhost') -> bytes:
    return build_zip({
        'ghost/master/descript.txt': b'name,' + name + b'\nshiori,yaya.dll\ncraftmanw,tester\n',
        'ghost/master/yaya.txt': b'request,GET\n',
        'shell/master/descript.txt': b'name,TestShell\ntype,shell\n',
        'shell/master/surface0.png': b'\x89PNG\r\n\x1a\n' + b'\x00' * 32,
    })


def balloon_zip() -> bytes:
    return build_zip({
        'descript.txt': b'name,TestBalloon\ntype,balloon\n',
        'balloon0.png': b'\x89PNG\r\n\x1a\n' + b'\x00' * 16,
        'balloons0.png': b'\x89PNG\r\n\x1a\n' + b'\x00' * 16,
    })


def symlink_zip() -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w') as z:
        info = zipfile.ZipInfo('ghost/master/evil-link.txt')
        info.external_attr = (0o120777 << 16) | 0o777  # S_IFLNK symlink mode
        z.writestr(info, b'../../etc/passwd')
        z.writestr('ghost/master/descript.txt', b'name,G\nshiori,yaya.dll\n')
    return buf.getvalue()


def duplicate_zip() -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w') as z:
        z.writestr('ghost/master/descript.txt', b'name,A\n')
        z.writestr('ghost/master/descript.txt', b'name,B\n')
    return buf.getvalue()


def bomb_zip(expanded: int = 4 * 1024 * 1024) -> bytes:
    """Highly compressible payload: tiny compressed, large expanded."""
    return build_zip({'ghost/master/descript.txt': b'name,G\nshiori,yaya.dll\n',
                      'ghost/master/pad.bin': b'\x00' * expanded})


class _Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.server.hits[self.path] += 1
        entry = self.server.routes.get(self.path)
        if entry is None:
            self.send_response(404)
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        status, body, *extras = entry
        self.send_response(status)
        for key, value in (extras[0] if extras else {}).items():
            self.send_header(key, value)
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # runner aborted an oversize download mid-stream

    def log_message(self, *args):
        pass


class CorpusCase(unittest.TestCase):
    """Per-test sandboxed fixture: HTTP server + temp tree under ALLOWED_BASE."""

    cli_timeout = 120

    @classmethod
    def setUpClass(cls):
        ALLOWED_BASE.mkdir(parents=True, exist_ok=True)

    def setUp(self):
        self.tmp = pathlib.Path(
            tempfile.mkdtemp(prefix='corpus-test-', dir=str(ALLOWED_BASE)))
        self.work = self.tmp / 'work'
        self.probe_dir = self.tmp / 'probes'
        self.probe_dir.mkdir()
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), _Handler)
        self.server.routes = {}
        self.server.hits = collections.Counter()
        self.thread = threading.Thread(target=self.server.serve_forever,
                                       daemon=True)
        self.thread.start()
        self.base = f'http://127.0.0.1:{self.server.server_address[1]}'

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=10)
        shutil.rmtree(self.tmp, ignore_errors=False)

    # ---------- fixture helpers ----------

    def serve(self, path: str, body: bytes, status: int = 200):
        self.server.routes[path] = (status, body)

    def hits(self, path: str) -> int:
        return self.server.hits.get(path, 0)

    def item(self, item_id='g1', name='Test Ghost', kind='ghost',
             path='/ghost.nar', engine_hint='yaya'):
        entry = {'id': item_id, 'name': name, 'kind': kind,
                 'source_url': f'{self.base}/page/{item_id}',
                 'download_url': f'{self.base}{path}'}
        if engine_hint:
            entry['engine_hint'] = engine_hint
        return entry

    def write_catalog(self, items, name='catalog.json'):
        path = self.tmp / name
        path.write_text(json.dumps({'schema': 1, 'items': items},
                                   ensure_ascii=False))
        return path

    def write_probe(self, name: str, source: str) -> str:
        path = self.probe_dir / name
        path.write_text(source)
        return str(path)

    def run_cli(self, catalog, args=(), report='report.json', env=None,
                expect=0, timeout=None):
        report_path = self.tmp / report
        cmd = [sys.executable, str(RUNNER),
               '--catalog', str(catalog),
               '--output', str(report_path),
               '--work-root', str(self.work), *args]
        proc = subprocess.run(
            cmd, capture_output=True, text=True,
            timeout=timeout or self.cli_timeout,
            env={**os.environ, **(env or {})})
        output = f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
        if expect is not None:
            self.assertEqual(proc.returncode, expect, output)
        data = None
        if report_path.is_file():
            data = json.loads(report_path.read_text())
        return proc, data, report_path, output

    def only_item(self, report):
        self.assertIsNotNone(report)
        self.assertEqual(1, len(report['items']), json.dumps(report)[:2000])
        return report['items'][0]

    def assert_no_artifact_leaks(self):
        """No downloaded archive bytes or extracted payload may remain."""
        if not self.work.is_dir():
            return
        leftovers = [p for p in self.work.rglob('*')]
        names = {p.name for p in leftovers}
        self.assertFalse(names & {'surface0.png', 'pad.bin', 'evil-link.txt',
                                  'yaya.txt', 'balloon0.png', 'descript.txt',
                                  'probe-write.tmp'},
                         f'extracted payload left behind: {names}')
        for p in leftovers:
            self.assertFalse(p.is_symlink(), f'symlink left behind: {p}')
            self.assertNotIn(p.suffix, {'.nar', '.zip'},
                             f'archive left behind: {p}')

    def assert_percent(self, rate):
        n, d = rate['numerator'], rate['denominator']
        self.assertIsInstance(rate['definition'], str)
        self.assertTrue(rate['definition'].strip())
        self.assertLessEqual(n, d)
        if d:
            self.assertAlmostEqual(rate['percent'], 100.0 * n / d, delta=0.5)
        else:
            self.assertIn(rate.get('percent'), (0, None))

    def expect_probe_outcome(self, item, expected_status):
        """Assert probe outcome when sandboxed; unverified otherwise."""
        runtime = item['runtime']
        if not sandbox_available():
            self.assertEqual('unverified', runtime['status'],
                             json.dumps(item, ensure_ascii=False))
            self.assertFalse(runtime.get('executed'))
            self.assertIn(item['status'], ('unverified', 'static_only'))
            self.assertNotEqual('unsupported', runtime['status'])
            return None
        self.assertEqual(expected_status, runtime['status'],
                         json.dumps(item, ensure_ascii=False))
        return runtime


# ---------------------------------------------------------------------------
# Happy path: download -> preflight -> extract -> static inventory -> cleanup
# ---------------------------------------------------------------------------

class HappyPathTests(CorpusCase):

    def test_valid_ghost_static_only(self):
        payload = ghost_zip()
        self.serve('/ghost.nar', payload)
        catalog = self.write_catalog([self.item()])
        _, report, report_path, out = self.run_cli(catalog)

        item = self.only_item(report)
        self.assertEqual('g1', item['id'])
        self.assertEqual('ghost', item['kind'])
        self.assertEqual(f'{self.base}/page/g1', item['source_url'])
        self.assertEqual(f'{self.base}/ghost.nar', item['download_url'])
        self.assertEqual('yaya', item['engine_hint'])
        self.assertTrue(item['fingerprint'])

        dl = item['download']
        self.assertEqual('success', dl['status'], out)
        self.assertEqual(200, dl['http_status'])
        self.assertEqual(len(payload), dl['bytes'])
        self.assertEqual(hashlib.sha256(payload).hexdigest(), dl['sha256'])
        self.assertTrue(dl['final_url'].endswith('/ghost.nar'))

        arc = item['archive']
        self.assertEqual('pass', arc['status'], json.dumps(item)[:2000])
        self.assertEqual(4, arc['entries'])

        imp = item['import']
        self.assertEqual('pass', imp['status'], json.dumps(item)[:2000])
        self.assertEqual('static_structure', imp['layer'])

        # No probe: static extraction is never a runtime pass.
        self.assertEqual('unverified', item['runtime']['status'])
        self.assertFalse(item['runtime'].get('executed'))
        self.assertEqual('static_only', item['status'])

        self.assertEqual('pass', item['cleanup']['status'],
                         json.dumps(item)[:2000])

        # Report envelope
        self.assertEqual(1, report['schema'])
        self.assertEqual(hashlib.sha256(catalog.read_bytes()).hexdigest(),
                         report['catalog_sha256'])
        self.assertIsInstance(report['settings'], dict)
        self.assertEqual(1, report['selected_count'])
        self.assertEqual(0, report['skipped_count'])

        rates = report['rates']
        for key in ('download', 'import', 'runtime_tested', 'runtime_pass',
                    'runtime_pass_of_selected'):
            self.assertIn(key, rates)
            self.assert_percent(rates[key])
        self.assertEqual((1, 1), (rates['download']['numerator'],
                                  rates['download']['denominator']))
        self.assertEqual(1, rates['import']['numerator'])
        self.assertEqual(0, rates['runtime_tested']['numerator'])
        self.assertEqual(0, rates['runtime_pass']['numerator'])
        self.assertEqual(0, rates['runtime_pass_of_selected']['numerator'])
        self.assertEqual(1,
                         rates['runtime_pass_of_selected']['denominator'])

        self.assert_no_artifact_leaks()

    def test_valid_balloon_static_only(self):
        self.serve('/balloon.nar', balloon_zip())
        catalog = self.write_catalog([self.item(
            item_id='b1', name='Test Balloon', kind='balloon',
            path='/balloon.nar', engine_hint=None)])
        _, report, _, out = self.run_cli(catalog)
        item = self.only_item(report)
        self.assertEqual('success', item['download']['status'], out)
        self.assertEqual('pass', item['archive']['status'],
                         json.dumps(item)[:2000])
        self.assertEqual('static_structure', item['import']['layer'])
        self.assertIn(item['import']['status'], ('pass', 'partial'),
                      json.dumps(item)[:2000])
        self.assertNotEqual('pass', item['runtime']['status'])
        self.assert_no_artifact_leaks()

    def test_markdown_report_escapes_injection(self):
        self.serve('/ghost.nar', ghost_zip())
        evil = 'Bad](https://evil.example/x)Name'
        catalog = self.write_catalog([self.item(name=evil)])
        md_path = self.tmp / 'report.md'
        _, report, _, out = self.run_cli(
            catalog, args=('--markdown', str(md_path)))
        self.assertTrue(md_path.is_file(), out)
        text = md_path.read_text()
        # Source/download links must be present.
        self.assertIn('/page/g1', text)
        self.assertIn('/ghost.nar', text)
        # The raw markdown-injection sequence must not survive unescaped.
        self.assertNotIn('](https://evil.example/x)', text)
        self.assertEqual(evil, self.only_item(report)['name'])

    def test_files_outside_work_root_untouched(self):
        outside = self.tmp / 'outside'
        outside.mkdir()
        canary = outside / 'keep.txt'
        canary.write_text('do not touch')
        self.serve('/ghost.nar', ghost_zip())
        catalog = self.write_catalog([self.item()])
        self.run_cli(catalog)
        self.assertEqual('do not touch', canary.read_text())
        self.assertFalse((outside / 'pwn.txt').exists())


# ---------------------------------------------------------------------------
# Download failures and size limits
# ---------------------------------------------------------------------------

class DownloadTests(CorpusCase):

    def test_http_404_is_download_error(self):
        catalog = self.write_catalog([self.item(path='/missing.nar')])
        _, report, _, out = self.run_cli(catalog)
        item = self.only_item(report)
        dl = item['download']
        self.assertEqual('error', dl['status'], out)
        self.assertEqual(404, dl['http_status'])
        self.assertIn('not_checked', (item['archive']['status'],))
        self.assertEqual('error', item['status'])
        self.assertEqual('pass', item['cleanup']['status'])
        # source_url metadata is retained even on failure.
        self.assertEqual(f'{self.base}/page/g1', item['source_url'])
        self.assert_no_artifact_leaks()

    def test_download_size_limit(self):
        self.serve('/big.nar', ghost_zip() + b'\x00' * 4096)
        catalog = self.write_catalog([self.item(path='/big.nar')])
        _, report, _, out = self.run_cli(
            catalog, args=('--max-download-bytes', '256'))
        item = self.only_item(report)
        self.assertEqual('error', item['download']['status'], out)
        self.assertEqual('error', item['status'])
        self.assert_no_artifact_leaks()


# ---------------------------------------------------------------------------
# ZIP/NAR preflight safety
# ---------------------------------------------------------------------------

class ArchiveSafetyTests(CorpusCase):

    def _run_payload(self, path, payload, args=()):
        self.serve(path, payload)
        catalog = self.write_catalog([self.item(path=path)])
        _, report, _, out = self.run_cli(catalog, args=args)
        return self.only_item(report), out

    def test_malicious_members_rejected(self):
        abs_name = str(self.tmp / 'pwn_abs.txt')
        cases = {
            'traversal': build_zip({'../pwn_trav.txt': b'x',
                                    'ghost/master/descript.txt': b'name,G\n'}),
            'deep_traversal': build_zip({
                'ghost/../../pwn_deep.txt': b'x',
                'ghost/master/descript.txt': b'name,G\n'}),
            'absolute': build_zip({abs_name: b'x',
                                   'ghost/master/descript.txt': b'name,G\n'}),
            'backslash': build_zip({'..\\pwn_bs.txt': b'x',
                                    'ghost/master/descript.txt': b'name,G\n'}),
            'symlink': symlink_zip(),
            'duplicate': duplicate_zip(),
        }
        for label, payload in cases.items():
            with self.subTest(label=label):
                item, out = self._run_payload(f'/{label}.nar', payload)
                self.assertEqual('success', item['download']['status'], out)
                self.assertEqual('error', item['archive']['status'],
                                 json.dumps(item)[:2000])
                self.assertTrue(item['archive'].get('reason'),
                                'rejection must carry a reason')
                self.assertEqual('error', item['status'])
                self.assertEqual('pass', item['cleanup']['status'],
                                 'cleanup must be recorded for failures')
                # Nothing may have escaped into the test tree.
                escaped = [p for p in self.tmp.rglob('pwn*')]
                self.assertEqual([], escaped)
                linked = [p for p in self.tmp.rglob('*') if p.is_symlink()]
                self.assertEqual([], linked)
                self.assert_no_artifact_leaks()

    def test_expanded_size_limit(self):
        item, out = self._run_payload('/bomb.nar', bomb_zip(),
                                      args=('--max-expanded-bytes', '65536'))
        self.assertEqual('error', item['archive']['status'], out)
        self.assertEqual('error', item['status'])
        self.assert_no_artifact_leaks()

    def test_entry_count_limit(self):
        item, out = self._run_payload('/ghost.nar', ghost_zip(),
                                      args=('--max-entries', '2'))
        self.assertEqual('error', item['archive']['status'], out)
        self.assert_no_artifact_leaks()

    def test_compression_ratio_limit(self):
        item, out = self._run_payload(
            '/bomb.nar', bomb_zip(),
            args=('--max-compression-ratio', '5'))
        self.assertEqual('error', item['archive']['status'], out)
        self.assert_no_artifact_leaks()

    def test_non_zip_payload_rejected(self):
        item, out = self._run_payload('/notazip.nar', b'this is not a zip')
        self.assertEqual('success', item['download']['status'], out)
        self.assertTrue(item['download'].get('sha256'))
        self.assertEqual('error', item['archive']['status'])
        self.assert_no_artifact_leaks()


# ---------------------------------------------------------------------------
# Resume / retry semantics
# ---------------------------------------------------------------------------

class ResumeTests(CorpusCase):

    def test_resume_skips_unchanged(self):
        self.serve('/ghost.nar', ghost_zip())
        catalog = self.write_catalog([self.item()])
        _, r1, _, _ = self.run_cli(catalog)
        self.assertEqual(1, self.hits('/ghost.nar'))
        fp1 = self.only_item(r1)['fingerprint']

        _, r2, _, out = self.run_cli(catalog, args=('--resume',))
        item = self.only_item(r2)
        self.assertEqual(1, self.hits('/ghost.nar'),
                         'resume must not redownload an unchanged entry\n' + out)
        self.assertTrue(item['resumed'])
        self.assertEqual(fp1, item['fingerprint'])
        self.assertGreaterEqual(r2['skipped_count'], 1)

    def test_resume_reruns_changed_entry(self):
        self.serve('/ghost.nar', ghost_zip())
        catalog = self.write_catalog([self.item()])
        _, r1, _, _ = self.run_cli(catalog)
        fp1 = self.only_item(r1)['fingerprint']

        # Change the catalog entry -> fingerprint changes -> must rerun.
        catalog2 = self.write_catalog(
            [self.item(name='Renamed Ghost')], name='catalog.json')
        _, r2, _, out = self.run_cli(catalog2, args=('--resume',))
        item = self.only_item(r2)
        self.assertEqual(2, self.hits('/ghost.nar'),
                         'changed entry must be redownloaded\n' + out)
        self.assertNotEqual(fp1, item['fingerprint'])
        self.assertFalse(item.get('resumed'))

    def test_retry_failed(self):
        self.serve('/missing.nar', b'', status=404)
        catalog = self.write_catalog([self.item(path='/missing.nar')])
        _, r1, _, _ = self.run_cli(catalog)
        self.assertEqual('error', self.only_item(r1)['download']['status'])
        self.assertEqual(1, self.hits('/missing.nar'))

        # Plain --resume does not silently retry a failed record.
        _, r2, _, out = self.run_cli(catalog, args=('--resume',))
        self.assertEqual(1, self.hits('/missing.nar'),
                         '--resume alone must not rerun failures\n' + out)
        self.assertGreaterEqual(r2['skipped_count'], 1)

        _, r3, _, out = self.run_cli(catalog,
                                   args=('--resume', '--retry-failed'))
        self.assertEqual(2, self.hits('/missing.nar'),
                         '--retry-failed must rerun the failed item\n' + out)
        self.assertEqual('error', self.only_item(r3)['download']['status'])

    def test_max_items_does_not_skew_denominators(self):
        self.serve('/a.nar', ghost_zip())
        self.serve('/b.nar', ghost_zip(b'B'))
        items = [self.item('a', 'A', path='/a.nar'),
                 self.item('b', 'B', path='/b.nar')]
        catalog = self.write_catalog(items)
        _, report, _, out = self.run_cli(catalog,
                                       args=('--max-items', '1'))
        self.assertEqual(1, report['selected_count'], out)
        self.assertLessEqual(len(report['items']), 2)
        self.assertEqual(1, report['rates']['download']['denominator'])
        self.assertLessEqual(report['rates']['download']['numerator'], 1)


# ---------------------------------------------------------------------------
# Probe behaviour (real subprocesses, sandboxed on macOS)
# ---------------------------------------------------------------------------

PASS_PROBE = '''
import json, sys
req = json.load(sys.stdin)
print(json.dumps({
    "status": "pass",
    "checks": {"runtime_executed": True,
               "saw_id": req.get("id"),
               "saw_kind": req.get("kind"),
               "saw_hint": req.get("engine_hint")},
    "reason": "probe ok"}))
'''

FALSE_EVIDENCE_PROBE = '''
import json, sys
req = json.load(sys.stdin)
# Claims pass but never actually executed anything -> runner must not
# count this as a runtime pass.
print(json.dumps({"status": "pass",
                  "checks": {"runtime_executed": False},
                  "reason": "lies"}))
'''

BAD_JSON_PROBE = 'import sys; sys.stdout.write("this is not json\\n")'

SLEEP_PROBE = 'import time; time.sleep(120)'

FLOOD_PROBE = ('import sys\n'
               'sys.stdout.write("x" * (1024 * 1024))\n'
               'sys.stdout.flush()\n')

SANDBOX_PROBE = '''
import json, os, pathlib, socket, sys
req = json.load(sys.stdin)
checks = {"runtime_executed": True}
try:
    s = socket.create_connection(("127.0.0.1", PORT), timeout=2)
    s.close()
    checks["loopback_allowed"] = True
except Exception:
    checks["loopback_allowed"] = False
try:
    pathlib.Path(CANARY).write_text("escaped")
    checks["outside_write_allowed"] = True
except Exception:
    checks["outside_write_allowed"] = False
try:
    inside = pathlib.Path(req["root"]) / "probe-write.tmp"
    inside.write_text("x")
    checks["root_write_allowed"] = inside.read_text() == "x"
except Exception:
    checks["root_write_allowed"] = False
# HOME/TMPDIR must be scoped to the item work root: the probe root itself
# or its direct parent (the work dir that contains the extraction root).
root = pathlib.Path(req["root"])
allowed = (str(root), str(root.parent))
for var in ("TMPDIR", "HOME"):
    value = os.environ.get(var) or ""
    checks[var.lower() + "_scoped"] = value.startswith(allowed)
checks["secret_leaked"] = "SECRET_NAME" in os.environ
print(json.dumps({"status": "pass", "checks": checks,
                  "reason": "sandbox probe"}))
'''


class ProbeTests(CorpusCase):

    def _probe_args(self, probe_source, name='probe.py', extra=()):
        path = self.write_probe(name, probe_source)
        return ('--probe-command-json',
                json.dumps([sys.executable, path]), *extra)

    def _run_ghost_with_probe(self, args, secret=False):
        self.serve('/ghost.nar', ghost_zip())
        catalog = self.write_catalog([self.item()])
        env = {TEST_SECRET: 'hunter2'} if secret else None
        _, report, _, out = self.run_cli(catalog, args=args, env=env)
        return self.only_item(report), out, report

    def test_probe_pass_counts_as_runtime_pass(self):
        item, out, report = self._run_ghost_with_probe(
            self._probe_args(PASS_PROBE))
        rt = self.expect_probe_outcome(item, 'pass')
        if rt is None:
            return
        self.assertTrue(rt['executed'])
        self.assertEqual('pass', item['status'], out)
        checks = rt.get('checks') or {}
        self.assertEqual('g1', checks.get('saw_id'))
        self.assertEqual('ghost', checks.get('saw_kind'))
        self.assertEqual('yaya', checks.get('saw_hint'))
        rates = report['rates']
        self.assertEqual(1, rates['runtime_tested']['numerator'])
        self.assertEqual(1, rates['runtime_pass']['numerator'])
        self.assertEqual(1, rates['runtime_pass_of_selected']['numerator'])

    def test_probe_invalid_json_is_error(self):
        item, out, _ = self._run_ghost_with_probe(
            self._probe_args(BAD_JSON_PROBE, 'bad.py'))
        rt = self.expect_probe_outcome(item, 'error')
        if rt is None:
            return
        self.assertNotEqual('pass', item['status'])
        self.assertTrue(rt.get('reason'))

    def test_probe_timeout_kills_process_group(self):
        started = time.monotonic()
        item, out, _ = self._run_ghost_with_probe(
            self._probe_args(SLEEP_PROBE, 'slow.py',
                             extra=('--probe-timeout', '2')),
        )
        elapsed = time.monotonic() - started
        rt = self.expect_probe_outcome(item, 'error')
        if rt is None:
            return
        self.assertLess(elapsed, 60,
                        'probe timeout did not terminate the child')
        reason = (rt.get('reason') or '').lower()
        self.assertTrue(reason, 'probe timeout must record a reason')
        self.assertTrue(any(word in reason
                            for word in ('timeout', 'timed out', 'killed')),
                        f'unexpected timeout reason: {reason}')

    def test_probe_stdout_is_bounded(self):
        item, out, _ = self._run_ghost_with_probe(
            self._probe_args(FLOOD_PROBE, 'flood.py',
                             extra=('--max-probe-output-bytes', '4096')))
        rt = self.expect_probe_outcome(item, 'error')
        if rt is not None:
            self.assertNotEqual('pass', item['status'])

    def test_probe_pass_without_runtime_evidence_is_not_pass(self):
        item, out, report = self._run_ghost_with_probe(
            self._probe_args(FALSE_EVIDENCE_PROBE, 'liar.py'))
        if not sandbox_available():
            self.assertEqual('unverified', item['runtime']['status'])
            return
        self.assertNotEqual('pass', item['runtime']['status'], out)
        self.assertNotEqual('pass', item['status'], out)
        self.assertEqual(0, report['rates']['runtime_pass']['numerator'])

    def test_sandbox_denies_network_and_outside_writes(self):
        """Real sandbox check: only runs meaningfully when sandbox-exec
        exists (macOS). Elsewhere this verifies the 'unverified' path."""
        canary = self.tmp / 'canary' / 'escaped.txt'
        canary.parent.mkdir()
        port = self.server.server_address[1]
        probe = (SANDBOX_PROBE
                 .replace('PORT', str(port))
                 .replace('CANARY', json.dumps(str(canary)))
                 .replace('SECRET_NAME', TEST_SECRET))
        item, out, _ = self._run_ghost_with_probe(
            self._probe_args(probe, 'sandbox.py'), secret=True)
        rt = self.expect_probe_outcome(item, 'pass')
        if rt is None:
            self.assertFalse(canary.exists())
            return
        checks = rt['checks']
        self.assertFalse(checks['loopback_allowed'],
                         'sandbox permitted loopback network access')
        self.assertFalse(checks['outside_write_allowed'],
                         'sandbox permitted write outside item root')
        self.assertTrue(checks['root_write_allowed'],
                        'sandbox denied legitimate write inside item root')
        self.assertTrue(checks['tmpdir_scoped'],
                        'TMPDIR not scoped to the item work root')
        self.assertTrue(checks['home_scoped'],
                        'HOME not scoped to the item work root')
        self.assertFalse(checks['secret_leaked'],
                         'probe env leaked parent credentials')
        self.assertFalse(canary.exists(),
                         'probe wrote outside its item root')
        self.assertEqual('pass', item['cleanup']['status'])
        self.assert_no_artifact_leaks()

    def test_probe_env_is_scrubbed(self):
        """Run the whole runner with a planted secret; the sandboxed probe
        must never see it (asserted via the sandbox probe checks)."""
        canary = self.tmp / 'c2' / 'escaped.txt'
        canary.parent.mkdir()
        port = self.server.server_address[1]
        probe = (SANDBOX_PROBE
                 .replace('PORT', str(port))
                 .replace('CANARY', json.dumps(str(canary)))
                 .replace('SECRET_NAME', TEST_SECRET))
        self.serve('/ghost.nar', ghost_zip())
        catalog = self.write_catalog([self.item()])
        args = self._probe_args(probe, 'env.py')
        report_path = self.tmp / 'env-report.json'
        cmd = [sys.executable, str(RUNNER), '--catalog', str(catalog),
               '--output', str(report_path), '--work-root', str(self.work),
               *args]
        proc = subprocess.run(cmd, capture_output=True, text=True,
                              timeout=self.cli_timeout,
                              env={**os.environ, TEST_SECRET: 'hunter2'})
        self.assertEqual(0, proc.returncode,
                         proc.stdout + proc.stderr)
        item = self.only_item(json.loads(report_path.read_text()))
        rt = self.expect_probe_outcome(item, 'pass')
        if rt is not None:
            self.assertFalse(rt['checks']['secret_leaked'])


# ---------------------------------------------------------------------------
# CLI / catalog validation
# ---------------------------------------------------------------------------

class ConfigTests(CorpusCase):

    def test_malformed_catalog_exits_nonzero(self):
        bad = self.tmp / 'bad.json'
        bad.write_text('{not json')
        proc, report, report_path, out = self.run_cli(bad, expect=None)
        self.assertNotEqual(0, proc.returncode)
        self.assertFalse(report_path.exists())

    def test_bad_probe_command_json_exits_nonzero(self):
        self.serve('/ghost.nar', ghost_zip())
        catalog = self.write_catalog([self.item()])
        for value in ('not json', '"just-a-string"', '42', '{}'):
            with self.subTest(value=value):
                proc, _, _, out = self.run_cli(
                    catalog,
                    args=('--probe-command-json', value),
                    report=f'cfg-{abs(hash(value))}.json',
                    expect=None)
                self.assertNotEqual(0, proc.returncode,
                                    f'accepted {value!r}\n{out}')

    def test_hostile_catalog_id_cannot_escape(self):
        """Catalog ids must never control filesystem paths."""
        self.serve('/ghost.nar', ghost_zip())
        entry = self.item()
        entry['id'] = '../esc7f3a9'
        catalog = self.write_catalog([entry])
        self.run_cli(catalog, expect=None)
        # Whatever the runner does with the item, nothing may appear at a
        # path derived from the hostile id.
        self.assertEqual([], [p for p in self.tmp.rglob('esc7f3a9')])
        self.assertEqual([], [p for p in ALLOWED_BASE.glob('esc7f3a9*')])
        self.assert_no_artifact_leaks()

    def test_work_root_outside_allowed_base_rejected(self):
        self.serve('/ghost.nar', ghost_zip())
        catalog = self.write_catalog([self.item()])
        report_path = self.tmp / 'r.json'
        cmd = [sys.executable, str(RUNNER), '--catalog', str(catalog),
               '--output', str(report_path),
               '--work-root', str(self.tmp.parent.parent / 'evil-work')]
        proc = subprocess.run(cmd, capture_output=True, text=True,
                              timeout=self.cli_timeout)
        self.assertNotEqual(0, proc.returncode,
                            proc.stdout + proc.stderr)


# ---------------------------------------------------------------------------
# Optional in-process check: sandbox unavailable -> unverified
# (portability aid; real coverage is the black-box path above)
# ---------------------------------------------------------------------------

class SandboxUnavailableUnitTests(CorpusCase):

    def test_missing_sandbox_marks_runtime_unverified(self):
        try:
            spec = importlib.util.spec_from_file_location(
                'compatibility_corpus', RUNNER)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
        except Exception as exc:
            self.skipTest(f'runner module not importable: {exc}')
        if not hasattr(module, 'SANDBOX_EXEC'):
            self.skipTest('runner exposes no SANDBOX_EXEC constant')
        if not hasattr(module, 'main'):
            self.skipTest('runner exposes no main() entry point')

        probe = self.write_probe('p.py', PASS_PROBE)
        self.serve('/ghost.nar', ghost_zip())
        catalog = self.write_catalog([self.item()])
        report_path = self.tmp / 'unit-report.json'
        argv = [str(RUNNER), '--catalog', str(catalog),
                '--output', str(report_path),
                '--work-root', str(self.work),
                '--probe-command-json', json.dumps([sys.executable, probe])]
        with unittest.mock.patch.object(module, 'SANDBOX_EXEC', None):
            try:
                try:
                    rc = module.main(argv[1:])
                except TypeError:
                    with unittest.mock.patch.object(sys, 'argv', argv):
                        rc = module.main()
            except SystemExit as exc:
                rc = exc.code if isinstance(exc.code, int) else 0
        self.assertEqual(0, rc)
        item = self.only_item(json.loads(report_path.read_text()))
        self.assertEqual('unverified', item['runtime']['status'])
        self.assertNotIn(item['runtime']['status'],
                         ('pass', 'partial', 'unsupported'))
        self.assertNotEqual('pass', item['status'])
        self.assert_no_artifact_leaks()



# Supervisor regressions added after reviewing Devin's initial 27 tests.
class ReviewedBoundaryTests(CorpusCase):
    def test_windows_directory_metadata_and_late_explicit_parents(self):
        for late in (False, True):
            with self.subTest(late=late):
                buf = io.BytesIO()
                with zipfile.ZipFile(buf, 'w') as archive:
                    def directories():
                        for name in ('ghost\\', 'ghost\\master\\'):
                            info = zipfile.ZipInfo(name)
                            info.create_system = 0
                            info.external_attr = 0x10
                            archive.writestr(info, b'')
                    if not late:
                        directories()
                    archive.writestr('ghost\\master\\descript.txt', b'name,Fixture\n')
                    if late:
                        directories()
                self.serve('/windows.nar', buf.getvalue())
                _, report, _, _ = self.run_cli(self.write_catalog([self.item(path='/windows.nar')]))
                self.assertEqual('pass', self.only_item(report)['archive']['status'])
                self.assertEqual('pass', self.only_item(report)['import']['status'])
                self.assert_no_artifact_leaks()

    def test_sandbox_allows_devnull_for_child_process(self):
        self.serve('/ghost.nar', ghost_zip())
        probe = self.write_probe('devnull.py',
            'import json,sys,subprocess\njson.load(sys.stdin)\n'
            'p=subprocess.run([sys.executable,"-c","print(123)"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)\n'
            'print(json.dumps({"status":"pass","checks":{"runtime_executed":True,"devnull":p.returncode==0}}))\n')
        _, report, _, _ = self.run_cli(self.write_catalog([self.item()]),
            args=('--probe-command-json', json.dumps([sys.executable, probe])))
        runtime = self.expect_probe_outcome(self.only_item(report), 'pass')
        if runtime is not None:
            self.assertTrue(runtime['checks']['devnull'])
        self.assert_no_artifact_leaks()

    def test_release_asset_resolver_keeps_direct_url_private(self):
        spec = importlib.util.spec_from_file_location('release_runner', RUNNER)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        page = 'https://github.com/author/project/releases/tag/v1.0'
        asset = 'https://github.com/author/project/releases/download/v1.0/private.nar'
        item = self.item()
        item.update(source_url=page, download_url=page, github_release_asset='private.nar')
        catalog = self.write_catalog([item])
        loaded, _ = module.load_catalog(catalog)
        self.assertEqual('private.nar', loaded[0]['github_release_asset'])
        metadata = json.dumps({'assets': [{'name': 'private.nar', 'browser_download_url': asset}]}).encode()
        opener = unittest.mock.Mock()
        opener.open.return_value = io.BytesIO(metadata)
        fetched = {'status': 'success', 'http_status': 200, 'final_url': asset + '?secret=private',
                   'sha256': 'a' * 64, 'bytes': 10, 'error': None}
        with unittest.mock.patch.object(module.urllib.request, 'build_opener', return_value=opener), \
             unittest.mock.patch.object(module, 'download', return_value=fetched) as fetch:
            result = module.download_item(loaded[0], self.tmp / 'asset.nar', {'timeout': 2})
        fetch.assert_called_once_with(asset, self.tmp / 'asset.nar', {'timeout': 2})
        self.assertEqual('success', result['status'])
        self.assertEqual(page, result['final_url'])
        self.assertTrue(result['source_page_only'])
        self.assertNotIn('/releases/download/', json.dumps(result))
        self.assertNotIn('secret', json.dumps(result))

    def test_release_asset_missing_and_resolution_errors_are_public_safe(self):
        spec = importlib.util.spec_from_file_location('release_runner_fail', RUNNER)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        item = {'source_url': 'https://github.com/author/project/releases/latest',
                'download_url': 'https://github.com/author/project/releases/latest',
                'github_release_asset': 'missing.nar'}
        opener = unittest.mock.Mock()
        opener.open.return_value = io.BytesIO(b'{"assets":[]}')
        with unittest.mock.patch.object(module.urllib.request, 'build_opener', return_value=opener):
            result = module.download_item(item, self.tmp / 'asset.nar', {'timeout': 2})
        self.assertEqual('release_asset_missing_or_ambiguous', result['error'])
        opener.open.side_effect = OSError('private direct URL secret')
        with unittest.mock.patch.object(module.urllib.request, 'build_opener', return_value=opener):
            result = module.download_item(item, self.tmp / 'asset.nar', {'timeout': 2})
        self.assertEqual('release_asset_resolution_failed', result['error'])
        self.assertNotIn('secret', json.dumps(result))

    def test_release_asset_rejects_public_direct_link_and_invalid_source(self):
        for source, download in (
                ('https://github.com/author/project/releases/tag/v1', 'https://github.com/author/project/releases/download/v1/file.nar'),
                ('https://example.com/releases/latest', 'https://example.com/releases/latest')):
            with self.subTest(source=source):
                item = self.item()
                item.update(source_url=source, download_url=download, github_release_asset='file.nar')
                completed, _, _, _ = self.run_cli(self.write_catalog([item]), expect=2)
                self.assertEqual(2, completed.returncode)

    def test_redirect_signed_query_is_not_published(self):
        self.serve('/signed.nar?sig=fixture-secret&jwt=fixture-token', ghost_zip())
        self.server.routes['/redirect'] = (302, b'', {
            'Location': '/signed.nar?sig=fixture-secret&jwt=fixture-token#fragment'})
        catalog = self.write_catalog([self.item(path='/redirect')])
        _, report, report_path, _ = self.run_cli(catalog)
        download = self.only_item(report)['download']
        self.assertEqual('success', download['status'])
        self.assertEqual(self.base + '/signed.nar', download['final_url'])
        self.assertTrue(download['signed_query_redacted'])
        self.assertNotIn('fixture-secret', report_path.read_text())
        self.assertNotIn('fixture-token', report_path.read_text())

    def test_cp932_zip_member_names_reach_probe_unchanged(self):
        class CP932Info(zipfile.ZipInfo):
            def _encodeFilenameFlags(self):
                return self.filename.encode('cp932'), self.flag_bits & ~0x800
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, 'w') as archive:
            archive.writestr('ghost/master/descript.txt', 'name,Japanese fixture\nshiori,yaya.dll\n')
            archive.writestr(CP932Info('ghost/master/台詞.dic'), 'hello')
        self.serve('/cp932.nar', buf.getvalue())
        probe = self.write_probe('cp932.py',
            'import json,sys,pathlib\nr=json.load(sys.stdin)\n'
            'ok=(pathlib.Path(r["root"])/"ghost/master/台詞.dic").read_text()=="hello"\n'
            'print(json.dumps({"status":"pass" if ok else "error",'
            '"checks":{"runtime_executed":True,"cp932_filename":ok}}))\n')
        _, report, _, _ = self.run_cli(self.write_catalog([self.item(path='/cp932.nar')]),
            args=('--probe-command-json', json.dumps([sys.executable, probe])))
        runtime = self.expect_probe_outcome(self.only_item(report), 'pass')
        if runtime is not None:
            self.assertTrue(runtime['checks']['cp932_filename'])
        self.assert_no_artifact_leaks()

    def test_unicode_casefold_collision_is_rejected(self):
        self.serve('/collision.nar', build_zip({'payload/É.txt': b'a', 'payload/e\u0301.txt': b'b'}))
        _, report, _, _ = self.run_cli(self.write_catalog([self.item(path='/collision.nar')]))
        self.assertEqual('error', self.only_item(report)['archive']['status'])
        self.assert_no_artifact_leaks()

    def test_resume_cleans_interrupted_owned_directory_only(self):
        self.serve('/ghost.nar', ghost_zip())
        catalog = self.write_catalog([self.item()])
        _, _, output_path, _ = self.run_cli(catalog)
        state_path = next(self.work.glob('.state-*.json'))
        owned = self.work / 'item-interrupted-fixture'
        owned.mkdir()
        (owned / '.ourin-owned.json').write_text(json.dumps({'token': 'fixture-owner'}))
        (owned / 'download.nar').write_bytes(b'leftover')
        state_path.write_text(json.dumps({'active': [{'artifact': owned.name, 'token': 'fixture-owner'}]}))
        unrelated = self.work / 'item-not-owned'
        unrelated.mkdir()
        (unrelated / 'keep.txt').write_text('unchanged')
        _, report, _, _ = self.run_cli(catalog, args=('--resume',))
        self.assertFalse(owned.exists())
        self.assertEqual('unchanged', (unrelated / 'keep.txt').read_text())
        self.assertEqual([], report['cleanup_pending'])
        self.assertEqual(1, report['skipped_count'])

    def test_interrupted_marker_mismatch_is_never_deleted(self):
        self.serve('/ghost.nar', ghost_zip())
        catalog = self.write_catalog([self.item()])
        self.run_cli(catalog)
        state_path = next(self.work.glob('.state-*.json'))
        protected = self.work / 'item-protected-fixture'
        protected.mkdir()
        (protected / '.ourin-owned.json').write_text(json.dumps({'token': 'different-owner'}))
        (protected / 'keep.txt').write_text('unchanged')
        state_path.write_text(json.dumps({'active': [{'artifact': protected.name, 'token': 'wrong-owner'}]}))
        _, report, _, _ = self.run_cli(catalog, args=('--resume',))
        self.assertEqual('unchanged', (protected / 'keep.txt').read_text())
        self.assertIn(protected.name, report['cleanup_pending'])

    def test_timeout_kills_child_in_inherited_process_group(self):
        if not sandbox_available():
            self.skipTest('actual process-group isolation needs macOS sandbox-exec')
        self.serve('/ghost.nar', ghost_zip())
        probe = self.write_probe('child.py',
            'import json,sys,os,subprocess,time,pathlib\nr=json.load(sys.stdin)\n'
            'child=subprocess.Popen([sys.executable,"-c","import time; time.sleep(120)"])\n'
            '(pathlib.Path(r["root"])/"child-pid").write_text(str(child.pid))\n'
            'time.sleep(120)\n')
        catalog = self.write_catalog([self.item()])
        command = [sys.executable, str(RUNNER), '--catalog', str(catalog),
            '--output', str(self.tmp / 'child-report.json'), '--work-root', str(self.work),
            '--probe-command-json', json.dumps([sys.executable, probe]), '--probe-timeout', '2']
        runner = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        child_pid = None
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline and runner.poll() is None:
                markers = list(self.work.rglob('child-pid')) if self.work.exists() else []
                if markers:
                    child_pid = int(markers[0].read_text())
                    break
                time.sleep(0.02)
            stdout, stderr = runner.communicate(timeout=10)
            self.assertEqual(0, runner.returncode, (stdout, stderr))
            self.assertIsNotNone(child_pid, 'probe did not create child')
            deadline = time.monotonic() + 5
            alive = True
            while time.monotonic() < deadline:
                state = subprocess.run(['/bin/ps', '-p', str(child_pid), '-o', 'stat='], capture_output=True, text=True).stdout.strip()
                alive = bool(state) and not state.startswith('Z')
                if not alive:
                    break
                time.sleep(0.05)
            self.assertFalse(alive, 'timeout left an executing child process')
            self.assert_no_artifact_leaks()
        finally:
            if runner.poll() is None:
                runner.kill()
                runner.communicate()
            if child_pid is not None:
                try:
                    os.kill(child_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

if __name__ == '__main__':
    unittest.main()
