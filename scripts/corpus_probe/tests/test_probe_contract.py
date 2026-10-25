#!/usr/bin/env python3
"""Contract tests for corpus probes (owned fixtures only)."""
from __future__ import annotations

import base64
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "scripts"))
PROBE = REPO / "scripts/probe_corpus_content.py"
FIXTURES = Path(__file__).resolve().parent / "temp"
CACHE = Path(os.environ.get("OURIN_CORPUS_PROBE_CACHE", "/tmp/ourin-corpus-cursor-20261025"))
TINY_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)


def run_preflight() -> None:
    result = subprocess.run(
        [sys.executable, str(PROBE), "--preflight", "--cache-dir", str(CACHE), "--repo", str(REPO)],
        check=True,
        timeout=300,
        capture_output=True,
    )
    payload = json.loads(result.stdout)
    if payload.get("status") != "ok" or payload.get("preflight", {}).get("ok") is not True:
        raise AssertionError("Probe preflight failed: " + json.dumps(payload, sort_keys=True))


def run_probe(payload: dict, extra_args: list[str] | None = None) -> dict:
    command = [sys.executable, str(PROBE), "--cache-dir", str(CACHE), "--repo", str(REPO)]
    if extra_args:
        command.extend(extra_args)
    result = subprocess.run(
        command,
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        timeout=180,
    )
    return json.loads(result.stdout.strip())


def copy_fixture(name: str) -> Path:
    source = FIXTURES / name
    tmp = Path(tempfile.mkdtemp(prefix=f"ourin-probe-{name}-"))
    shutil.copytree(source, tmp, dirs_exist_ok=True)
    return tmp


class ProbeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        CACHE.mkdir(parents=True, exist_ok=True)
        run_preflight()

    def test_yaya_lifecycle_inside_actual_corpus_sandbox(self):
        from compatibility_corpus import run_probe, SANDBOX_EXEC
        if not SANDBOX_EXEC:
            self.skipTest("macOS sandbox-exec unavailable")
        if not (REPO / "yaya_core/build/yaya_core").is_file():
            self.skipTest("yaya_core helper not built")
        with tempfile.TemporaryDirectory(prefix="ourin-sandbox-probe-", dir="/tmp") as tmp:
            work = Path(tmp).resolve()
            root = work / "extracted"
            shutil.copytree(FIXTURES / "minimal_yaya", root)
            result = run_probe(
                [sys.executable, str(PROBE), "--cache-dir", str(CACHE)],
                {"id": "sandbox-yaya", "kind": "ghost", "engine_hint": "YAYA"},
                root, work, {"probe_timeout": 20, "max_probe_output_bytes": 1024 * 1024})
            self.assertEqual(result["status"], "pass", result.get("reason"))
            self.assertTrue(result["executed"])
            self.assertTrue(result["checks"]["runtime_executed"])

    def test_malformed_json(self):
        result = subprocess.run(
            [sys.executable, str(PROBE), "--cache-dir", str(CACHE)],
            input="{not json",
            capture_output=True,
            text=True,
        )
        payload = json.loads(result.stdout)
        self.assertEqual(payload["status"], "error")
        self.assertEqual(payload["reason"], "invalid_json")

    def test_deep_json_rejected(self):
        nested: dict = {"id": "deep", "kind": "plugin", "root": "/tmp/x"}
        current = nested
        for _ in range(40):
            current["n"] = {}
            current = current["n"]
        current["root"] = "/tmp/x"
        proc = subprocess.run(
            [sys.executable, str(PROBE), "--cache-dir", str(CACHE)],
            input=json.dumps(nested),
            capture_output=True,
            text=True,
        )
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["status"], "error")
        self.assertEqual(payload["reason"], "json_too_deep")

    def test_invalid_kind_type(self):
        out = run_probe({"id": "bad", "kind": 123, "root": "/tmp/x"})
        self.assertEqual(out["status"], "error")
        self.assertEqual(out["reason"], "invalid_kind")

    def test_missing_root(self):
        out = run_probe({"id": "a", "kind": "ghost"})
        self.assertEqual(out["status"], "error")
        self.assertEqual(out["reason"], "missing_root")

    def test_cache_miss_without_preflight_artifacts(self):
        empty_cache = Path(tempfile.mkdtemp(prefix="ourin-probe-empty-cache-", dir="/tmp"))
        self.addCleanup(shutil.rmtree, empty_cache, ignore_errors=True)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copytree(FIXTURES / "minimal_balloon", root, dirs_exist_ok=True)
            (root / "balloons0.png").write_bytes(TINY_PNG)
            proc = subprocess.run(
                [sys.executable, str(PROBE), "--cache-dir", str(empty_cache), "--repo", str(REPO)],
                input=json.dumps({"id": "miss", "kind": "balloon", "root": str(root.resolve())}),
                capture_output=True,
                text=True,
            )
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["status"], "error")
        self.assertEqual(payload["reason"], "missing_preflight")

    def test_symlink_root_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "real"
            target.mkdir()
            link = Path(tmp) / "link"
            link.symlink_to(target)
            out = run_probe({"id": "symlink", "kind": "plugin", "root": str(link)})
            self.assertEqual(out["status"], "error")
            self.assertEqual(out["reason"], "root_symlink")

    def test_symlink_in_tree_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "ghost" / "master").mkdir(parents=True)
            (root / "ghost" / "master" / "descript.txt").write_text(
                "name,g\nshiori,yaya.dll\ncharset,UTF-8\n",
                encoding="utf-8",
            )
            (root / "ghost" / "master" / "yaya.txt").write_text("dic,probe.dic\n", encoding="utf-8")
            (root / "ghost" / "master" / "probe.dic").write_text("OnBoot\n{\n}\n", encoding="utf-8")
            (root / "ghost" / "master" / "secret").symlink_to("/etc/passwd")
            out = run_probe({"id": "tree", "kind": "ghost", "root": str(root.resolve())})
            self.assertEqual(out["status"], "error")
            self.assertIn(out["reason"], {"symlink_in_tree", "ghost_descript_missing"})

    def test_windows_plugin_unsupported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "descript.txt").write_text(
                "type,plugin\nname,Win\nid,win.test\nfilename,plugin.dll\n",
                encoding="utf-8",
            )
            out = run_probe({"id": "win", "kind": "plugin", "root": str(root.resolve())})
            self.assertEqual(out["status"], "unsupported")
            self.assertIn("windows", out["reason"])
            self.assertFalse(out["checks"]["execution"]["can_dispatch_requests"])

    def test_plugin_path_traversal(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "descript.txt").write_text(
                "type,plugin\nname,Bad\nid,bad.test\nfilename,../outside.dll\n",
                encoding="utf-8",
            )
            out = run_probe({"id": "trav", "kind": "plugin", "root": str(root.resolve())})
            self.assertEqual(out["status"], "error")
            self.assertEqual(out["reason"], "path_traversal_rejected")

    def test_ghost_without_type_descript(self):
        with tempfile.TemporaryDirectory() as tmp:
            master = Path(tmp) / "ghost" / "master"
            master.mkdir(parents=True)
            shutil.copytree(FIXTURES / "minimal_yaya" / "ghost" / "master", master, dirs_exist_ok=True)
            (master / "descript.txt").write_text(
                "charset,UTF-8\nname,NoType\nshiori,yaya.dll\n",
                encoding="utf-8",
            )
            helper = REPO / "yaya_core/build/yaya_core"
            if not helper.is_file():
                self.skipTest("yaya_core helper not built")
            out = run_probe({"id": "notype", "kind": "ghost", "root": str(Path(tmp).resolve())})
            self.assertIn(out["status"], {"pass", "partial"})
            self.assertEqual(out["checks"]["structure"]["ghost_master"], "ghost/master")

    def test_balloon_without_type_via_install(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "install.txt").write_text("type,balloon\n", encoding="utf-8")
            (root / "descript.txt").write_text(
                "charset,UTF-8\nname,B\nfont.color.r,1\nfont.color.g,2\nfont.color.b,3\norigin.x,0\norigin.y,0\n",
                encoding="utf-8",
            )
            (root / "balloons0.png").write_bytes(TINY_PNG)
            out = run_probe({"id": "b", "kind": "balloon", "root": str(root.resolve())})
            self.assertEqual(out["status"], "partial")

    def test_balloon_static_partial(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copytree(FIXTURES / "minimal_balloon", root, dirs_exist_ok=True)
            for index in range(2):
                (root / f"balloons{index}.png").write_bytes(TINY_PNG)
            out = run_probe({"id": "balloon", "kind": "balloon", "root": str(root.resolve())})
            self.assertEqual(out["status"], "partial")
            self.assertIn("ui_unverified", out["reason"])

    def test_windows_dll_in_ghost_not_executed(self):
        with tempfile.TemporaryDirectory() as tmp:
            master = Path(tmp) / "ghost" / "master"
            master.mkdir(parents=True)
            (master / "descript.txt").write_text(
                "type,ghost\nshiori,custom.dll\ncharset,UTF-8\nname,WinDll\n",
                encoding="utf-8",
            )
            (master / "custom.dll").write_bytes(b"MZ")
            out = run_probe({"id": "dll", "kind": "ghost", "root": str(Path(tmp).resolve())})
            self.assertEqual(out["status"], "unsupported")
            self.assertEqual(out["reason"], "windows_shiori_not_executable")
            self.assertTrue(out["checks"]["engine"]["ghost_windows_module_present"])

    def test_yaya_lifecycle_pass_when_helper_present(self):
        helper = REPO / "yaya_core/build/yaya_core"
        if not helper.is_file():
            self.skipTest("yaya_core helper not built")
        root = copy_fixture("minimal_yaya")
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        out = run_probe({"id": "yaya", "kind": "ghost", "root": str(root.resolve())})
        self.assertEqual(out["status"], "pass")
        self.assertTrue(out["checks"]["conversation"].get("value_nonempty"))
        boot = [row for row in out["checks"]["lifecycle"] if row.get("event") == "OnBoot"]
        self.assertTrue(boot and boot[0].get("ok"))
        self.assertFalse(out["checks"]["persistence"]["persistence_semantically_verified"])

    def test_descript_inline_url_preserved(self):
        from corpus_probe.io_util import parse_descript

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "descript.txt"
            path.write_text("homepage,https://example.com/path\nname,Test\n", encoding="utf-8")
            parsed = parse_descript(path)
            self.assertIsNotNone(parsed)
            self.assertEqual(parsed.get("homepage"), "https://example.com/path")

    def test_mach_o_accepts_fat_header(self):
        from corpus_probe.engine import is_mach_o

        with tempfile.TemporaryDirectory() as tmp:
            fat = Path(tmp) / "libfake.dylib"
            fat.write_bytes(b"\xca\xfe\xba\xbe" + b"\x00" * 16)
            self.assertTrue(is_mach_o(fat))

    def test_trusted_engine_dir_optional_native(self):
        configured = os.environ.get("OURIN_CORPUS_ENGINE_DIR")
        if not configured:
            self.skipTest("OURIN_CORPUS_ENGINE_DIR not configured")
        trusted = Path(configured)
        self.assertTrue(trusted.is_dir(), "Configured trusted engine directory is absent")
        dylibs = [p for p in trusted.iterdir() if p.suffix == ".dylib" and p.is_file()]
        if not dylibs:
            self.skipTest("no dylibs in trusted engine dir")
        from corpus_probe.engine import is_mach_o

        self.assertTrue(any(is_mach_o(p) for p in dylibs))

    def test_partial_when_conversation_empty(self):
        helper = REPO / "yaya_core/build/yaya_core"
        if not helper.is_file():
            self.skipTest("yaya_core helper not built")
        with tempfile.TemporaryDirectory() as tmp:
            master = Path(tmp) / "ghost" / "master"
            master.mkdir(parents=True)
            (master / "descript.txt").write_text(
                "type,ghost\ncharset,UTF-8\nname,EmptyTalk\nshiori,yaya.dll\n",
                encoding="utf-8",
            )
            (master / "yaya.txt").write_text("dic,empty.dic\n", encoding="utf-8")
            (master / "empty.dic").write_text(
                "OnBoot\n{\n}\n\nOnMouseDoubleClick\n{\n}\n\nOnClose\n{\n}\n",
                encoding="utf-8",
            )
            out = run_probe({"id": "empty", "kind": "ghost", "root": str(Path(tmp).resolve())})
            self.assertEqual(out["status"], "partial")
            self.assertIn("conversation", out["reason"])


if __name__ == "__main__":
    unittest.main()
