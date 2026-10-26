#!/usr/bin/env python3
"""UGM replacement helper: real loopback HTTP and process lifecycle tests.
Self-authored fixtures only; no ghost data or external services.
"""
import http.client
import os
from pathlib import Path
import select
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = Path(os.environ.get('OURIN_UGM_HTTP_HELPER', ROOT / 'build/engines/plugins/ugm_http_helper'))


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


class UGMHTTPTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ourin-ugm-http-')
        self.payload = Path(self.temp.name).resolve() / 'payload'
        self.html = self.payload / 'localweb/html'
        self.html.mkdir(parents=True)
        (self.html / 'index.html').write_text('<h1>self-authored</h1>', encoding='utf-8')
        (self.html / 'res').mkdir()
        (self.html / 'res/data.json').write_text('{"fixture":true}', encoding='utf-8')
        (self.payload / 'private.txt').write_text('not public')
        self.port = free_port()
        (self.payload / 'ugm_config.txt').write_text(f'localhost_number,{self.port}\n')
        self.processes = []

    def tearDown(self):
        for process in self.processes:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=4)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=4)
            for stream in (process.stdout, process.stderr):
                if stream:
                    stream.close()
        self.temp.cleanup()

    def start(self):
        process = subprocess.Popen([str(HELPER), str(self.payload), str(os.getpid())],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.processes.append(process)
        self.assertTrue(select.select([process.stdout], [], [], 4)[0], 'helper never became ready')
        self.assertEqual(process.stdout.readline(), f'READY {self.port}\n')
        return process

    def request(self, path='/', method='GET', headers=None):
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=4)
        try:
            conn.request(method, path, headers=headers or {})
            response = conn.getresponse()
            return response.status, response.read(), dict(response.getheaders())
        finally:
            conn.close()

    def test_static_content_head_and_no_external_listener(self):
        self.start()
        status, body, headers = self.request()
        self.assertEqual((status, body), (200, b'<h1>self-authored</h1>'))
        self.assertEqual(headers['Content-Type'], 'text/html; charset=utf-8')
        self.assertEqual(self.request('/res/data.json?version=2')[:2], (200, b'{"fixture":true}'))
        self.assertEqual(self.request('/', 'HEAD')[:2], (200, b''))
        # A wildcard listener would accept another 127/8 address on macOS.
        with socket.socket() as s:
            s.settimeout(0.5)
            self.assertNotEqual(s.connect_ex(('127.0.0.2', self.port)), 0)

    def test_traversal_symlink_host_origin_and_method_rejected(self):
        (self.html / 'escape').symlink_to(self.payload)
        (self.html / 'secret.txt').symlink_to(self.payload / 'private.txt')
        self.start()
        for path in ('/../private.txt', '/%2e%2e/private.txt', '/escape/private.txt',
                     '/secret.txt', '/res/%2e%2e/%2e%2e/private.txt', '/%00', '/%5c../private.txt'):
            self.assertIn(self.request(path)[0], (400, 404), path)
        self.assertEqual(self.request(headers={'Host': 'untrusted.example'})[0], 403)
        self.assertEqual(self.request(headers={'Origin': 'https://untrusted.example'})[0], 403)
        self.assertEqual(self.request('/', 'POST')[0], 405)
        self.assertEqual(self.request(headers={'Host': f'localhost:{self.port}',
                                               'Origin': f'http://localhost:{self.port}'})[0], 200)

    def test_port_collision_is_failure_not_ready(self):
        self.start()
        duplicate = subprocess.run([str(HELPER), str(self.payload), str(os.getpid())],
                                   capture_output=True, text=True, timeout=4)
        self.assertEqual(duplicate.returncode, 3)
        self.assertNotIn('READY', duplicate.stdout)
        self.assertEqual(self.request()[0], 200)

    def test_shutdown_signal_removes_marker_and_releases_port(self):
        process = self.start()
        marker = self.payload / 'localweb/running.signal'
        self.assertTrue(marker.exists())
        (self.payload / 'localweb/shutdown.signal').touch()
        self.assertEqual(process.wait(timeout=4), 0)
        self.assertFalse(marker.exists())
        with socket.socket() as s:
            s.settimeout(0.5)
            self.assertNotEqual(s.connect_ex(('127.0.0.1', self.port)), 0)

    def test_parent_exit_stops_child(self):
        # The wrapper owns the child and exits without terminating it. The helper
        # must notice reparenting itself, rather than relying on test cleanup.
        wrapper = subprocess.Popen([sys.executable, '-c',
            'import os,subprocess,sys,time; p=subprocess.Popen(sys.argv[1:]+[str(os.getpid())],stdout=subprocess.PIPE,text=True); print(p.stdout.readline().strip(),flush=True); time.sleep(0.2)',
            str(HELPER), str(self.payload)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.processes.append(wrapper)
        self.assertTrue(select.select([wrapper.stdout], [], [], 4)[0])
        self.assertEqual(wrapper.stdout.readline(), f'READY {self.port}\n')
        self.assertEqual(wrapper.wait(timeout=4), 0)
        deadline = time.monotonic() + 4
        marker = self.payload / 'localweb/running.signal'
        while marker.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertFalse(marker.exists())

    def test_preexisting_shutdown_never_ready(self):
        (self.payload / 'localweb/shutdown.signal').touch()
        result = subprocess.run([str(HELPER), str(self.payload), str(os.getpid())],
                                capture_output=True, text=True, timeout=4)
        self.assertEqual(result.returncode, 5)
        self.assertFalse(result.stdout)
        self.assertFalse((self.payload / 'localweb/running.signal').exists())
        with socket.socket() as s:
            s.settimeout(0.5)
            self.assertNotEqual(s.connect_ex(('127.0.0.1', self.port)), 0)

    def test_preexisting_marker_or_symlinked_root_never_ready(self):
        (self.payload / 'localweb/running.signal').touch()
        result = subprocess.run([str(HELPER), str(self.payload), str(os.getpid())],
                                capture_output=True, text=True, timeout=4)
        self.assertEqual(result.returncode, 4)
        self.assertFalse(result.stdout)
        (self.payload / 'localweb/running.signal').unlink()
        external = Path(self.temp.name) / 'external'
        self.html.rename(external)
        self.html.symlink_to(external, target_is_directory=True)
        result = subprocess.run([str(HELPER), str(self.payload), str(os.getpid())],
                                capture_output=True, text=True, timeout=4)
        self.assertEqual(result.returncode, 2)
        self.assertFalse(result.stdout)


if __name__ == '__main__':
    unittest.main()
