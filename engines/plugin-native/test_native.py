#!/usr/bin/env python3
"""Real-process ABI and TCP tests; no speech service or TCC change required."""
import ctypes
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parent


class NativeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="ourin-native-plugin-tests-")
        cls.out = Path(cls.temp.name)
        subprocess.run(["bash", str(ROOT / "build.sh"), str(cls.out)], check=True)
        cls.libs = {}
        for name in ("GetWindowTitle", "SendTalk"):
            lib = ctypes.CDLL(str(cls.out / f"Ourin{name}.dylib"))
            lib.request.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
            lib.request.restype = ctypes.c_void_p
            cls.libs[name] = lib

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def tearDown(self):
        os.environ.pop("OURIN_BOUYOMI_PORT", None)

    def raw(self, name, wire):
        data = wire.encode() if isinstance(wire, str) else wire
        size = ctypes.c_size_t()
        pointer = self.libs[name].request(data, len(data), ctypes.byref(size))
        return ctypes.string_at(pointer, size.value).decode()

    def call(self, name, *args, charset="UTF-8"):
        return self.raw(name, "EXECUTE SAORI/1.0\r\nCharset: " + charset + "\r\n" +
                        "".join(f"Argument{i}: {a}\r\n" for i, a in enumerate(args)) + "\r\n")

    def test_version_and_invalid_input(self):
        for name in self.libs:
            self.assertIn("200 OK", self.raw(name, "GET Version SAORI/1.0\r\n\r\n"))
            for wire in ("", "EXECUTE SAORI/1.0\r\n", "GET PLUGIN/2.0\r\n\r\n",
                         "EXECUTE SAORI/1.0\r\nArgument0: a\r\nArgument0: b\r\n\r\n",
                         "EXECUTE SAORI/1.0\r\n\r\nextra", b"EXECUTE SAORI/1.0\r\nArgument0: \xff\r\n\r\n"):
                self.assertIn("400 Bad Request", self.raw(name, wire))

    def test_legacy_charset_and_command_allowlist(self):
        self.assertIn("200 OK", self.call("GetWindowTitle", "/charset", "sjis", charset="Shift_JIS"))
        self.assertIn("400 Bad Request", self.call("GetWindowTitle", "/charset", "bogus"))
        for path in ("/bin/sh", "../getWindowTitle.exe", "getWindowTitle.exe;echo secret"):
            self.assertIn("501 Not Implemented", self.call("GetWindowTitle", path))
        self.assertIn("501 Not Implemented", self.call("SendTalk", "hide", "../other.exe", "text"))

    def test_window_api_real_process(self):
        response = self.call("GetWindowTitle", "./getWindowTitle.exe")
        # Permission/API denial is explicitly reported, never presented as a
        # successful title capture. Do not print the user's foreground title.
        status = response.split("\r\n", 1)[0]
        self.assertIn(status, ("SAORI/1.0 200 OK", "SAORI/1.0 420 Refuse", "SAORI/1.0 503 Service Unavailable"))
        if "200 OK" in status:
            self.assertIn("\r\nResult: ", response)
            print("Window API: title received (value withheld)")
        else:
            self.assertNotIn("\r\nResult:", response)
            diagnostic = next(line for line in response.split("\r\n") if line.startswith("X-Ourin-Error:"))
            print("Window API:", status, diagnostic, "(capture not verified)")

    def test_tcp_packet_unicode_multiline(self):
        with socket.socket() as server:
            server.bind(("127.0.0.1", 0))
            server.listen(1)
            server.settimeout(4)
            os.environ["OURIN_BOUYOMI_PORT"] = str(server.getsockname()[1])
            received = bytearray()
            errors = []

            def receive():
                try:
                    with server.accept()[0] as client:
                        client.settimeout(4)
                        while True:
                            data = client.recv(4096)
                            if not data:
                                break
                            received.extend(data)
                except Exception as error:
                    errors.append(error)

            thread = threading.Thread(target=receive)
            thread.start()
            speech = "\\p[桜:0]こんにちは\n\\p[桜:1]次の台詞: 続き。\n"
            response = self.call("SendTalk", "hide", "..\\SendTalk.exe", speech)
            thread.join(5)
            self.assertFalse(thread.is_alive())
            self.assertEqual(errors, [])
            self.assertIn("200 OK", response)
            expected = struct.pack("<hhhhhBI", 1, -1, -1, -1, 0, 0, len(speech.encode())) + speech.encode()
            self.assertEqual(bytes(received), expected)

    def test_tcp_connection_failure_not_success(self):
        with socket.socket() as reserved:
            reserved.bind(("127.0.0.1", 0))  # reserved but not listening
            os.environ["OURIN_BOUYOMI_PORT"] = str(reserved.getsockname()[1])
            response = self.call("SendTalk", "hide", "..\\SendTalk.exe", "test")
            self.assertIn("503 Service Unavailable", response)
            self.assertNotIn("\r\nResult:", response)
        os.environ["OURIN_BOUYOMI_PORT"] = "50001;malicious"
        self.assertIn("400 Bad Request", self.call("SendTalk", "hide", "..\\SendTalk.exe", "test"))

    def test_title_escaping(self):
        # Compile a separate executable to exercise the pure formatting code;
        # this fixture never substitutes a fake title into the shipped dylib.
        source = self.out / "title_test.mm"
        source.write_text('#include "' + str(ROOT / "native_saori.mm") + '"\n'
                          'int main() { @autoreleasepool { return titleResult(@"桜\\\"\\\'%\\\\abc\\r\\nInjected: x") '
                          '== "桜\\\\\\\\abc  Injected: x" ? 0 : 1; } }\n')
        executable = self.out / "title_test"
        subprocess.run(["xcrun", "clang++", "-std=c++17", "-fobjc-arc", str(source),
                        "-framework", "AppKit", "-framework", "ApplicationServices", "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
