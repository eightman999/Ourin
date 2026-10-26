"""Bounded I/O and safe path checks for corpus probes."""
from __future__ import annotations

import fcntl
import hashlib
import json
import os
import select
import time
from pathlib import Path

MAX_STDIN_BYTES = 64 * 1024
MAX_JSON_DEPTH = 32
MAX_ID_LENGTH = 256
MAX_HELPER_LINE_BYTES = 256 * 1024
MAX_HELPER_LINES = 4096
MAX_HELPER_REQUESTS = 64
MAX_HELPER_STDOUT_BYTES = 16 * 1024 * 1024
MAX_FILE_DIGEST_BYTES = 8 * 1024 * 1024
MAX_LISTED_FILES = 5000
MAX_TREE_BYTES = 128 * 1024 * 1024
STDIN_READ_DEADLINE = 5.0
MAX_IMAGE_BYTES = 16 * 1024 * 1024
MAX_IMAGE_PIXELS = 4096 * 4096


def read_stdin_json() -> tuple[dict | None, str | None]:
    fd = 0
    try:
        flags = fcntl.fcntl(fd, fcntl.F_GETFL)
        fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)
    except OSError:
        return None, "stdin_read_failed"

    chunks: list[bytes] = []
    total = 0
    deadline = time.monotonic() + STDIN_READ_DEADLINE
    while time.monotonic() < deadline:
        if total > MAX_STDIN_BYTES:
            return None, "input_too_large"
        remaining = deadline - time.monotonic()
        try:
            ready, _, _ = select.select([fd], [], [], min(0.25, remaining))
        except (OSError, ValueError):
            return None, "stdin_read_failed"
        if not ready:
            if chunks:
                break
            continue
        try:
            piece = os.read(fd, min(4096, MAX_STDIN_BYTES + 1 - total))
        except BlockingIOError:
            continue
        except OSError:
            return None, "stdin_read_failed"
        if not piece:
            if chunks:
                break
            continue
        chunks.append(piece)
        total += len(piece)
        if total > MAX_STDIN_BYTES:
            return None, "input_too_large"
        raw = b"".join(chunks)
        try:
            payload = json.loads(raw.decode("utf-8"))
        except UnicodeDecodeError:
            return None, "invalid_json"
        except RecursionError:
            return None, "json_too_deep"
        except json.JSONDecodeError:
            continue
        if not isinstance(payload, dict):
            return None, "invalid_payload_type"
        depth_err = _json_depth_error(payload, 0)
        if depth_err:
            return depth_err
        return payload, None
    if not chunks:
        return None, "empty_input"
    return None, "invalid_json"
def _json_depth_error(value: object, depth: int) -> tuple[None, str] | None:
    if depth > MAX_JSON_DEPTH:
        return None, "json_too_deep"
    if isinstance(value, dict):
        for item in value.values():
            err = _json_depth_error(item, depth + 1)
            if err:
                return err
    elif isinstance(value, list):
        for item in value:
            err = _json_depth_error(item, depth + 1)
            if err:
                return err
    return None


def emit(result: dict) -> None:
    sys_stdout_write(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n")


def sys_stdout_write(text: str) -> None:
    os.write(1, text.encode("utf-8"))


def parse_install_type(directory: Path) -> str | None:
    path = directory / "install.txt"
    if not path.is_file() or reject_symlink(path):
        return None
    try:
        data = path.read_bytes()
    except OSError:
        return None
    if len(data) > 64 * 1024:
        return None
    text = data.decode("utf-8", errors="replace")
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("//"):
            continue
        if "," not in stripped:
            continue
        key, value = stripped.split(",", 1)
        if key.strip().lower() == "type":
            return value.strip().lower()
    return None


def parse_descript(path: Path) -> dict[str, str] | None:
    if not path.is_file() or reject_symlink(path):
        return None
    try:
        size = path.stat().st_size
    except OSError:
        return None
    if size > MAX_FILE_DIGEST_BYTES:
        return None
    try:
        data = path.read_bytes()
    except OSError:
        return None
    text = _decode_descript_bytes(data)
    if text is None:
        return None
    return _parse_descript_text(text)


def _decode_descript_bytes(data: bytes) -> str | None:
    if data.startswith(b"\xef\xbb\xbf"):
        return data[3:].decode("utf-8", errors="replace")
    for encoding in ("utf-8", "cp932", "shift_jis", "latin-1"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    return None


def _parse_descript_text(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith("//"):
            continue
        if "," not in line:
            continue
        key, value = line.split(",", 1)
        key = key.strip().lower()
        value = value.strip()
        if key:
            result[key] = value
    return result


def file_digest(path: Path, limit: int = MAX_FILE_DIGEST_BYTES) -> tuple[str, bool]:
    h = hashlib.sha256()
    truncated = False
    try:
        size = path.stat().st_size
    except OSError:
        return "", True
    if size > limit:
        truncated = True
    with path.open("rb") as handle:
        remaining = limit
        while remaining > 0:
            chunk = handle.read(min(1024 * 1024, remaining))
            if not chunk:
                break
            h.update(chunk)
            remaining -= len(chunk)
    return h.hexdigest(), truncated


def bounded_tree_digest(root: Path) -> tuple[dict | None, str | None]:
    files: dict[str, str] = {}
    total_bytes = 0
    truncated_files = 0
    try:
        stack = [root]
        visited = 0
        while stack:
            current = stack.pop()
            try:
                entries = sorted(current.iterdir(), key=lambda p: p.name)
            except OSError:
                return None, "tree_scan_failed"
            for path in entries:
                if path.is_symlink():
                    return None, "symlink_in_tree"
                if path.is_dir():
                    if resolve_under_root(root, path) is None:
                        return None, "path_outside_root"
                    stack.append(path)
                    continue
                if not path.is_file():
                    continue
                if resolve_under_root(root, path) is None:
                    return None, "path_outside_root"
                visited += 1
                if visited > MAX_LISTED_FILES:
                    return None, "tree_too_large"
                try:
                    size = path.stat().st_size
                except OSError:
                    return None, "tree_scan_failed"
                total_bytes += size
                if total_bytes > MAX_TREE_BYTES:
                    return None, "tree_too_large"
                rel = str(path.relative_to(root))
                digest, truncated = file_digest(path)
                if truncated:
                    truncated_files += 1
                files[rel] = digest
    except OSError:
        return None, "tree_scan_failed"
    digest = hashlib.sha256(json.dumps(files, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    payload = {
        "file_count": len(files),
        "tree_sha256": digest,
        "digest_complete": truncated_files == 0,
        "truncated_file_count": truncated_files,
    }
    return payload, None


def validate_extracted_root(root: Path) -> str | None:
    if reject_symlink(root):
        return "root_symlink"
    try:
        stack = [root]
        visited = 0
        while stack:
            current = stack.pop()
            for path in current.iterdir():
                visited += 1
                if visited > MAX_LISTED_FILES:
                    return "tree_too_large"
                if path.is_symlink():
                    return "symlink_in_tree"
                name = path.name
                if name in {".", ".."} or name.startswith("/") or "\\" in name:
                    return "invalid_path_component"
                if path.is_dir():
                    stack.append(path)
    except OSError:
        return "tree_scan_failed"
    return None


def resolve_under_root(root: Path, candidate: Path) -> Path | None:
    root = root.resolve()
    try:
        resolved = candidate.resolve()
    except OSError:
        return None
    if resolved == root or root in resolved.parents:
        return resolved
    return None


def reject_symlink(path: Path) -> bool:
    return path.is_symlink()


def trim_id(value: str) -> str:
    return value.strip()[:MAX_ID_LENGTH]
