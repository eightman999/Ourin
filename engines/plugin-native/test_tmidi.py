#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
import ctypes
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parent
PROTOCOL = "ourin-tmidi-dde/1"


class TMIDITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="ourin-tmidi-tests-")
        cls.bundle = Path(cls.temp.name) / "TMIDI.plugin"
        subprocess.run(["bash", str(ROOT / "build_tmidi.sh"), str(cls.bundle)], check=True)
        cls.lib = ctypes.CDLL(str(cls.bundle / "Contents/MacOS/OurinTMIDI"))
        cls.lib.request.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
        cls.lib.request.restype = ctypes.c_void_p
        cls.lib.loadu.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
        cls.resources = cls.bundle / "Contents/Resources"
        metadata = dict(line.split(',', 1) for line in
                        (cls.resources / 'descript.txt').read_text().splitlines() if ',' in line)
        assert metadata['id'] == 'B5F4E3D2-1A6C-4B8E-9F0D-7C8A2E3B1D5F'
        assert metadata['filename'] == 'tmidi_msg.dll'
        assert metadata['secondchangeinterval'] == '1'


    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def setUp(self):
        self.lib.loadu(None, 0)
        os.environ.pop("OURIN_TMIDI_BRIDGE_PORT", None)
        (self.resources / "sstp_sample.txt").unlink(missing_ok=True)

    def tearDown(self):
        os.environ.pop("OURIN_TMIDI_BRIDGE_PORT", None)

    def raw(self, request):
        data = request.encode() if isinstance(request, str) else request
        length = ctypes.c_size_t()
        pointer = self.lib.request(data, len(data), ctypes.byref(length))
        return ctypes.string_at(pointer, length.value).decode()

    def call(self, event="OnSecondChange", method="GET"):
        return self.raw(f"{method} PLUGIN/2.0\r\nCharset: UTF-8\r\nID: {event}\r\n\r\n")

    def bridge(self, snapshots):
        errors = []
        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen(5)
        server.settimeout(4)
        os.environ["OURIN_TMIDI_BRIDGE_PORT"] = str(server.getsockname()[1])

        def run():
            try:
                for snapshot in snapshots:
                    with server.accept()[0] as client:
                        client.settimeout(3)
                        wire = bytearray()
                        while not wire.endswith(b"\n"):
                            chunk = client.recv(4096)
                            if not chunk:
                                raise ValueError("bridge client disconnected")
                            wire.extend(chunk)
                        self.assertEqual(json.loads(wire), {"protocol": PROTOCOL, "service": "TMIDI", "topic": "TMIDI", "query": "snapshot"})
                        client.sendall(json.dumps(snapshot, ensure_ascii=False).encode() + b"\n")
            except Exception as error:
                errors.append(error)
            finally:
                server.close()

        thread = threading.Thread(target=run)
        thread.start()
        return thread, errors

    @staticmethod
    def instance(state="play", filename="music.mid", title="曲名", identity="1", **extra):
        return dict(id=identity, getstatus=state, getplayfile="0", getfilename=filename, gettitle=title, **extra)

    @staticmethod
    def snapshot(*instances, session="test-session"):
        return dict(protocol=PROTOCOL, session=session, instances=list(instances))

    def finish(self, thread, errors):
        thread.join(5)
        self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])

    def test_unconfigured_failure_and_protocol(self):
        self.assertIn("503 Service Unavailable", self.call())
        self.assertIn("tmidi_bridge_not_configured", self.call())
        self.assertIn("Value: Ourin TMIDI bridge/1.0", self.call("version"))
        self.assertIn("204 No Content", self.call("OnMenuExec"))
        self.assertIn("204 No Content", self.call("OnPluginLoad"))
        self.assertIn("400 Bad Request", self.raw("GET PLUGIN/2.0\r\nID: version\r\nID: OnSecondChange\r\n\r\n"))
        self.assertIn("400 Bad Request", self.raw(b"GET PLUGIN/2.0\r\nID: \xff\r\n\r\n"))
        os.environ["OURIN_TMIDI_BRIDGE_PORT"] = "-1"
        self.assertIn("503 Service Unavailable", self.call())

    def test_state_transitions_and_title_escaping(self):
        states = [self.instance(), self.instance("pause"), self.instance(), self.instance("stop"),
                  self.instance(title="桜\\test\r\nInjected: no"), self.instance(filename="next.neo", title="次の曲")]
        thread, errors = self.bridge([self.snapshot(i) for i in states])
        for _ in range(4):
            self.assertIn("204 No Content", self.call())
        result = self.call()
        self.assertIn("Script: \\0\\s[0]桜\\\\test  Injected: no\\n\\e", result)
        self.assertNotIn("\r\nInjected:", result)
        self.assertIn("次の曲", self.call())
        self.finish(thread, errors)

    def test_simultaneous_instances_are_not_lost(self):
        initial = self.snapshot(self.instance("stop"), self.instance("stop", identity="2"))
        playing = self.snapshot(self.instance(title="first"), self.instance(title="second", identity="2"))
        thread, errors = self.bridge([initial, playing, playing, playing])
        self.assertIn("204", self.call())
        self.assertIn("first", self.call())
        self.assertIn("second", self.call())
        self.assertIn("204", self.call())
        self.finish(thread, errors)

    def test_templates_and_bridge_restart(self):
        (self.resources / "sstp_sample.txt").write_text("#NoWRD\nScript: plain $title $format\n#NeoWRD\nScript: neo $title $format\n", encoding="utf-8")
        thread, errors = self.bridge([
            self.snapshot(self.instance("stop")),
            self.snapshot(self.instance(filename="track.neo", title="ネオ", wrd="NeoWRD")),
            self.snapshot(self.instance(title="restart"), session="restarted")])
        self.assertIn("204", self.call())
        self.assertIn("Script: neo ネオ NEO", self.call())
        self.assertIn("204", self.call())
        self.finish(thread, errors)

    def test_invalid_snapshot_and_disconnect(self):
        snapshots = [{"protocol": PROTOCOL, "session": "x", "error": "DDE service unavailable"},
                     self.snapshot(self.instance(), self.instance()),
                     self.snapshot({"id": "a"})]
        thread, errors = self.bridge(snapshots)
        for _ in snapshots:
            self.assertIn("503 Service Unavailable", self.call())
        self.finish(thread, errors)
        self.assertIn("503 Service Unavailable", self.call())

    def test_producer_contract_without_windows_claim(self):
        spec = importlib.util.spec_from_file_location("ourin_tmidi_windows", ROOT / "tmidi_windows_bridge.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        class Fixture:
            def snapshot(self):
                return [{"id": "fixture"}]
        query = {"protocol": PROTOCOL, "service": "TMIDI", "topic": "TMIDI", "query": "snapshot"}
        self.assertEqual(module.answer(query, Fixture(), "x")["instances"], [{"id": "fixture"}])
        self.assertIn("error", module.answer({**query, "query": "execute"}, Fixture(), "x"))
        class Failed:
            def snapshot(self):
                raise RuntimeError("No TMIDI")
        self.assertIn("error", module.answer(query, Failed(), "x"))
        self.assertEqual(module.wrd_type("music.neo"), "NeoWRD")
        if os.name != "nt":
            with self.assertRaisesRegex(RuntimeError, "Windows DDEML"):
                module.DDEClient()


if __name__ == "__main__":
    unittest.main(verbosity=2)
