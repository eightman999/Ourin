"""Ghost SHIORI lifecycle probes (helper layer, not GUI)."""
from __future__ import annotations

import fcntl
import hashlib
import json
import os
import queue
import select
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

from .build import require_yaya_collector
from .discovery import find_package_root, package_root_for_master
from .engine import resolve_engine
from .io_util import (
    MAX_HELPER_LINE_BYTES,
    MAX_HELPER_LINES,
    MAX_HELPER_REQUESTS,
    MAX_HELPER_STDOUT_BYTES,
    bounded_tree_digest,
    reject_symlink,
    validate_extracted_root,
)

EVENT_TIMEOUT = 25.0
LOAD_TIMEOUT = 60.0
MAX_VALUE_BYTES = 64 * 1024
STDIN_WRITE_TIMEOUT = 10.0
REQUIRED_LIFECYCLE = ("load", "OnBoot", "OnClose", "unload")


class BoundedSession:
    """JSON-line helper session with bounded stdout/stdin and process-group cleanup."""

    def __init__(self, command: list[str], cwd: Path):
        self._owns_process_group = os.environ.get("OURIN_CORPUS_PARENT_OWNS_GROUP") != "1"
        self.proc = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            cwd=str(cwd),
            start_new_session=self._owns_process_group,
            bufsize=0,
        )
        self._stdout_fd = self.proc.stdout.fileno() if self.proc.stdout else -1
        self._stdin_fd = self.proc.stdin.fileno() if self.proc.stdin else -1
        if self._stdin_fd >= 0:
            try:
                flags = fcntl.fcntl(self._stdin_fd, fcntl.F_GETFL)
                fcntl.fcntl(self._stdin_fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)
            except OSError:
                pass
        self.lines: queue.Queue[bytes | None] = queue.Queue(maxsize=MAX_HELPER_LINES)
        self._requests = 0
        self.host_operations: set[str] = set()
        self._closed = False
        self._stdout_bytes = 0
        self._thread = threading.Thread(target=self._read_stdout, daemon=True)
        self._thread.start()

    def _read_stdout(self) -> None:
        if self._stdout_fd < 0:
            return
        buffer = bytearray()
        while not self._closed:
            try:
                ready, _, _ = select.select([self._stdout_fd], [], [], 0.25)
            except (OSError, ValueError):
                break
            if not ready:
                if self.proc.poll() is not None:
                    break
                continue
            try:
                chunk = os.read(self._stdout_fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            self._stdout_bytes += len(chunk)
            if self._stdout_bytes > MAX_HELPER_STDOUT_BYTES:
                self._fail_session()
                return
            buffer.extend(chunk)
            while True:
                newline = buffer.find(b"\n")
                if newline < 0:
                    if len(buffer) > MAX_HELPER_LINE_BYTES:
                        self._fail_session()
                        return
                    break
                line = bytes(buffer[: newline + 1])
                del buffer[: newline + 1]
                if len(line) > MAX_HELPER_LINE_BYTES + 1:
                    self._fail_session()
                    return
                try:
                    self.lines.put(line, timeout=1.0)
                except queue.Full:
                    self._fail_session()
                    return
        try:
            self.lines.put(None, timeout=1.0)
        except queue.Full:
            pass

    def _fail_session(self) -> None:
        self._terminate_process_group()
        try:
            self.lines.put(None, timeout=0.1)
        except queue.Full:
            pass

    def _terminate_process_group(self) -> None:
        if self.proc.poll() is not None:
            return
        try:
            if self._owns_process_group:
                os.killpg(self.proc.pid, signal.SIGTERM)
            else:
                self.proc.terminate()
        except ProcessLookupError:
            pass
        try:
            self.proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                if self._owns_process_group:
                    os.killpg(self.proc.pid, signal.SIGKILL)
                else:
                    self.proc.kill()
            except ProcessLookupError:
                self.proc.kill()
            self.proc.wait(timeout=3)

    def send(self, message: dict) -> bool:
        if self._requests >= MAX_HELPER_REQUESTS:
            return False
        self._requests += 1
        if self._stdin_fd < 0:
            return False
        wire = json.dumps(message, ensure_ascii=False) + "\n"
        payload = wire.encode()
        started = time.monotonic()
        offset = 0
        while offset < len(payload):
            if time.monotonic() - started > STDIN_WRITE_TIMEOUT:
                return False
            remaining = STDIN_WRITE_TIMEOUT - (time.monotonic() - started)
            try:
                _, ready_out, _ = select.select([], [self._stdin_fd], [], min(0.25, remaining))
            except (OSError, ValueError):
                return False
            if not ready_out:
                continue
            try:
                written = os.write(self._stdin_fd, payload[offset:])
            except BlockingIOError:
                time.sleep(0.01)
                continue
            except OSError:
                return False
            if written <= 0:
                time.sleep(0.01)
                continue
            offset += written
        return True

    def exchange(self, message: dict, timeout: float) -> dict:
        if not self.send(message):
            return {"ok": False, "error_category": "request_budget_exceeded"}
        started = time.monotonic()
        while True:
            remaining = timeout - (time.monotonic() - started)
            if remaining <= 0:
                return {"ok": False, "error_category": "timeout"}
            try:
                line = self.lines.get(timeout=min(0.25, remaining))
            except queue.Empty:
                continue
            if line is None:
                return {"ok": False, "error_category": "helper_exited", "exit_code": self.proc.poll()}
            try:
                response = json.loads(line)
            except json.JSONDecodeError:
                return {"ok": False, "error_category": "invalid_helper_json"}
            if "host_op" in response:
                self.host_operations.add(str(response["host_op"])[:64])
                if response["host_op"] == "fmo":
                    if not self.send({"ok": True, "snapshot": ""}):
                        return {"ok": False, "error_category": "host_op_reply_failed"}
                else:
                    if not self.send({"ok": False, "error": "harness_unavailable"}):
                        return {"ok": False, "error_category": "host_op_reply_failed"}
                continue
            value = response.get("value") or ""
            if isinstance(value, str) and len(value) > MAX_VALUE_BYTES:
                value = value[:MAX_VALUE_BYTES]
            return {
                "ok": response.get("ok"),
                "status": response.get("status"),
                "value_length": len(value) if isinstance(value, str) else 0,
                "value_nonempty": bool(value) if isinstance(value, str) else False,
                "value_sha256": hashlib.sha256(value.encode()).hexdigest() if isinstance(value, str) else None,
                "error_category": "helper_reported_failure" if response.get("error") else None,
            }

    def close(self) -> None:
        self._closed = True
        self._terminate_process_group()
        if self.proc.stdin:
            try:
                self.proc.stdin.close()
            except OSError:
                pass
        if self.proc.stdout:
            try:
                self.proc.stdout.close()
            except OSError:
                pass


def _summarize_event(label: str, response: dict) -> dict:
    status = response.get("status")
    ok = response.get("ok")
    value_ok = response.get("value_nonempty") is True
    if label == "load":
        matches = ok is True
    elif label == "unload":
        matches = ok is True and not response.get("error_category")
    else:
        matches = isinstance(status, int) and 200 <= status < 300 and ok is not False
    if label in {"OnMouseDoubleClick", "OnAITalk"}:
        matches = matches and value_ok
    return {
        "event": label,
        "ok": matches,
        "http_status": status if isinstance(status, int) else None,
        "value_length": response.get("value_length", 0),
        "value_nonempty": response.get("value_nonempty", False),
        "value_sha256": response.get("value_sha256"),
        "error_category": response.get("error_category"),
    }


def _helper_command(repo: Path, engine_info: dict, native_library: Path | None) -> list[str] | None:
    helper = engine_info.get("helper")
    if helper == "yaya_core":
        binary = repo / "yaya_core/build/yaya_core"
        if not binary.is_file():
            return None
        return [str(binary)]
    if helper == "satori_core":
        binary = repo / "satori_core/build/satori_core"
        if not binary.is_file():
            return None
        return [str(binary)]
    if helper == "native_dylib":
        if not native_library or not engine_info.get("abi"):
            return None
        worker = repo / "scripts/corpus_probe/native_shiori_worker.py"
        return [
            sys.executable,
            str(worker),
            "--abi",
            engine_info["abi"],
            "--library",
            str(native_library),
        ]
    return None


def _yaya_config_path(master: Path, descript: dict[str, str]) -> Path | None:
    module = (descript.get("shiori") or "shiori.dll").strip()
    module_path = Path(module.replace("\\", "/"))
    base = master / module_path.parent if module_path.parent.parts else master
    config = base / f"{module_path.stem}.txt"
    if config.is_file():
        return config
    fallback = master / "yaya.txt"
    return fallback if fallback.is_file() else None


def _yaya_load_plan(
    repo: Path,
    package_root: Path,
    master: Path,
    descript: dict[str, str],
    cache_dir: Path,
) -> tuple[dict | None, str | None]:
    collector, cache_err = require_yaya_collector(cache_dir, repo)
    if cache_err or not collector:
        return None, cache_err or "missing_preflight"
    config = _yaya_config_path(master, descript)
    if not config:
        return None, "yaya_config_missing"
    result = subprocess.run(
        [str(collector), str(config), str(package_root)],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    if result.returncode != 0:
        return None, "yaya_collector_failed"
    try:
        load = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None, "yaya_collector_invalid_json"
    profile = Path(load["ghost_root"]) / "profile"
    if not profile.is_dir():
        try:
            profile.mkdir(exist_ok=True)
        except OSError:
            return None, "profile_dir_failed"
    return load, None


def _run_lifecycle(
    session: BoundedSession,
    plan: list[tuple[str, dict]],
    conversation_labels: set[str],
) -> tuple[list[dict], dict, list[str]]:
    lifecycle: list[dict] = []
    conversation: dict = {}
    host_ops: list[str] = []
    for label, request in plan:
        timeout = LOAD_TIMEOUT if label == "load" else EVENT_TIMEOUT
        response = session.exchange(request, timeout)
        summary = _summarize_event(label, response)
        if label in conversation_labels:
            conversation = summary
        else:
            lifecycle.append(summary)
        if response.get("host_op"):
            host_ops.append(str(response.get("host_op")))
        if not summary.get("ok") and label not in {"OnDestroy"}:
            break
    return lifecycle, conversation, host_ops


def _ensure_shutdown(session: BoundedSession, headers: dict, load_message: dict) -> list[dict]:
    tail: list[dict] = []
    for label, request in [
        ("OnClose", {"cmd": "request", "method": "GET", "id": "OnClose", "headers": headers, "ref": ["user"]}),
        ("unload", {"cmd": "unload"}),
    ]:
        tail.append(_summarize_event(label, session.exchange(request, EVENT_TIMEOUT)))
    return tail


def probe_ghost(
    root: Path,
    repo: Path,
    probe_id: str,
    engine_hint: str | None,
    cache_dir: Path,
    engine_dirs: list[Path],
) -> dict:
    tree_err = validate_extracted_root(root)
    if tree_err:
        return _ghost_result(probe_id, "error", tree_err, {})

    before, digest_err = bounded_tree_digest(root)
    if digest_err:
        return _ghost_result(probe_id, "error", digest_err, {})

    master, descript, locate_err = find_package_root(root, "ghost")
    if locate_err or not master or not descript:
        return _ghost_result(probe_id, "error", locate_err or "ghost_descript_missing", {"tree": before})

    package_root = package_root_for_master(root, master)
    engine_info = resolve_engine(master, package_root, descript, repo, engine_hint, engine_dirs)
    native_library: Path | None = None
    if engine_info.get("helper") == "native_dylib":
        bundled = engine_info.get("bundled_engine")
        if bundled:
            from .engine import BUNDLED_ENGINES, search_engine_dirs

            _, names = BUNDLED_ENGINES[bundled]
            search = list(engine_dirs) + [repo / "build/engines/additional", repo / "build/engines/kawari", repo / "engines"]
            native_library = search_engine_dirs(search, names)

    try:
        master_rel = str(master.relative_to(root))
    except ValueError:
        master_rel = "master"

    checks: dict = {
        "structure": {
            "ghost_master": master_rel[:256],
            "source_tree_sha256": before.get("tree_sha256"),
            "source_file_count": before.get("file_count"),
            "digest_complete": before.get("digest_complete"),
        },
        "engine": {key: engine_info[key] for key in engine_info if key != "supported"},
    }

    if not engine_info["supported"]:
        reason = engine_info.get("unsupported_reason") or "unknown_or_unavailable_engine"
        return _ghost_result(probe_id, "unsupported", reason, checks)

    command = _helper_command(repo, engine_info, native_library)
    if not command:
        return _ghost_result(probe_id, "unsupported", "helper_binary_missing", checks)

    load_err: str | None = None
    if engine_info["helper"] == "yaya_core":
        load, load_err = _yaya_load_plan(repo, package_root, master, descript, cache_dir)
        if not load:
            return _ghost_result(probe_id, "partial", load_err or "yaya_config_unresolved", checks)
    else:
        load = {"cmd": "load", "ghost_root": str(master)}
        profile = master / "profile"
        try:
            profile.mkdir(exist_ok=True)
        except OSError:
            return _ghost_result(probe_id, "error", "profile_dir_failed", checks)

    headers = {"Sender": "Ourin", "Charset": "UTF-8", "SecurityLevel": "local"}
    conversation_event = {
        "id": "OnMouseDoubleClick",
        "method": "GET",
        "ref": ["100", "100", "0", "0", "head"],
    }
    lifecycle_plan = [
        ("load", load),
        ("OnBoot", {"cmd": "request", "method": "GET", "id": "OnBoot", "headers": headers, "ref": ["0"]}),
        (conversation_event["id"], {"cmd": "request", **conversation_event, "headers": headers}),
        ("OnClose", {"cmd": "request", "method": "GET", "id": "OnClose", "headers": headers, "ref": ["user"]}),
        ("OnDestroy", {"cmd": "request", "method": "NOTIFY", "id": "OnDestroy", "headers": headers}),
        ("unload", {"cmd": "unload"}),
    ]

    checks["runtime_executed"] = False
    checks["verification_layer"] = "SHIORI helper lifecycle; GUI and external SAORI unverified"
    lifecycle: list[dict] = []
    conversation: dict = {}
    host_ops: set[str] = set()
    session = BoundedSession(command, package_root)
    checks["runtime_executed"] = True
    try:
        for label, request in lifecycle_plan:
            response = session.exchange(request, LOAD_TIMEOUT if label == "load" else EVENT_TIMEOUT)
            summary = _summarize_event(label, response)
            if label == "OnMouseDoubleClick":
                conversation = summary
                if not summary["ok"] and not response.get("error_category"):
                    talk = session.exchange({"cmd": "request", "method": "GET", "id": "OnAITalk", "headers": headers}, EVENT_TIMEOUT)
                    conversation = _summarize_event("OnAITalk", talk)
                    if talk.get("error_category"):
                        break
            else:
                lifecycle.append(summary)
            if response.get("error_category") or (label == "load" and not summary["ok"]):
                break
        host_ops.update(session.host_operations)
    finally:
        session.close()

    mid, digest_error = bounded_tree_digest(root)
    persistence = {
        "tree_sha256_after_cycle": mid.get("tree_sha256") if mid else None,
        "tree_changed": bool(mid and before["tree_sha256"] != mid["tree_sha256"]),
        "save_file_observed": None,
        "persistence_semantically_verified": False,
        "digest_error": digest_error,
    }
    lifecycle_ok = all(any(row.get("event") == event and row.get("ok") for row in lifecycle)
                       for event in REQUIRED_LIFECYCLE)
    cycle2: list[dict] = []
    if lifecycle_ok:
        session2 = BoundedSession(command, package_root)
        try:
            for label, request in [
                ("load", load),
                ("OnBoot", {"cmd": "request", "method": "GET", "id": "OnBoot", "headers": headers, "ref": ["0"]}),
                ("OnClose", {"cmd": "request", "method": "GET", "id": "OnClose", "headers": headers, "ref": ["user"]}),
                ("unload", {"cmd": "unload"}),
            ]:
                response = session2.exchange(request, LOAD_TIMEOUT if label == "load" else EVENT_TIMEOUT)
                cycle2.append(_summarize_event(label, response))
                if response.get("error_category") or (label == "load" and not cycle2[-1]["ok"]):
                    break
            host_ops.update(session2.host_operations)
        finally:
            session2.close()
    persistence["cycle2"] = cycle2
    persistence["cycle2_load_ok"] = bool(cycle2 and cycle2[0]["ok"])
    persistence["cycle2_complete"] = len(cycle2) == 4 and all(row["ok"] for row in cycle2)
    checks["lifecycle"] = lifecycle
    checks["conversation"] = conversation
    checks["persistence"] = persistence
    unavailable = sorted(host_ops - {"fmo"})
    checks["host_capabilities"] = {"unavailable_ops": unavailable, "fmo_empty_snapshot": "fmo" in host_ops}
    if lifecycle_ok and conversation.get("ok") and not unavailable and persistence["cycle2_complete"]:
        status, reason = "pass", "helper_lifecycle_verified"
    elif lifecycle_ok:
        status = "partial"
        reason = ("reopen_failed" if not persistence["cycle2_complete"] else
                  "host_capability_unavailable" if unavailable else "lifecycle_without_conversation")
    elif any(row.get("ok") for row in lifecycle):
        status, reason = "partial", "incomplete_lifecycle_or_conversation"
    else:
        status, reason = "error", "helper_failed"
    return _ghost_result(probe_id, status, reason, checks)


def _ghost_result(probe_id: str, status: str, reason: str, checks: dict) -> dict:
    return {"id": probe_id, "kind": "ghost", "status": status, "reason": reason, "checks": checks}
