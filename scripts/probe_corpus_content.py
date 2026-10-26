#!/usr/bin/env python3
"""stdin JSON corpus probe → stdout JSON result (one object, no third-party raw text)."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

from corpus_probe.balloon import probe_balloon
from corpus_probe.build import preflight, validate_cache_dir
from corpus_probe.ghost import probe_ghost
from corpus_probe.io_util import emit, read_stdin_json, reject_symlink, resolve_under_root, trim_id, validate_extracted_root
from corpus_probe.plugin import probe_plugin

VALID_KINDS = {"ghost", "balloon", "plugin"}
VALID_STATUS = {"pass", "partial", "unsupported", "error"}


def error_result(probe_id: str | None, reason: str, kind: str | None = None) -> dict:
    payload = {"id": probe_id or "unknown", "status": "error", "reason": reason, "checks": {"runtime_executed": False}}
    if kind:
        payload["kind"] = kind
    return payload


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preflight", action="store_true", help="Compile probe helpers into --cache-dir")
    parser.add_argument("--cache-dir", type=Path, required=True, help="Absolute /tmp cache (read-only at runtime)")
    parser.add_argument(
        "--engine-dir",
        type=Path,
        action="append",
        default=[],
        help="Trusted built SHIORI dylib directory (repeatable)",
    )
    parser.add_argument("--repo", type=Path, default=REPO, help="Ourin repository root")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    repo = args.repo.resolve()
    cache_dir = args.cache_dir.resolve()
    cache_err = validate_cache_dir(cache_dir)
    if cache_err:
        emit({"status": "error", "reason": cache_err, "checks": {"runtime_executed": False}})
        return 0

    engine_dirs = [path.resolve() for path in args.engine_dir if path]

    if args.preflight:
        result = preflight(repo, cache_dir)
        emit({"status": "ok" if result.get("ok") else "error", "preflight": result})
        return 0

    payload, err = read_stdin_json()
    if err:
        emit(error_result(None, err))
        return 0

    probe_id_raw = payload.get("id")
    kind = payload.get("kind")
    root_raw = payload.get("root")
    engine_hint = payload.get("engine_hint")

    if not isinstance(probe_id_raw, str) or not probe_id_raw.strip():
        emit(error_result(None, "missing_id"))
        return 0
    probe_id = trim_id(probe_id_raw)

    if not isinstance(kind, str) or kind not in VALID_KINDS:
        emit(error_result(probe_id, "invalid_kind"))
        return 0
    if not isinstance(root_raw, str) or not root_raw:
        emit(error_result(probe_id, "missing_root", kind))
        return 0
    if engine_hint is not None and not isinstance(engine_hint, str):
        emit(error_result(probe_id, "invalid_engine_hint", kind))
        return 0

    root = Path(root_raw)
    if not root.is_absolute():
        emit(error_result(probe_id, "root_must_be_absolute", kind))
        return 0
    if reject_symlink(root):
        emit(error_result(probe_id, "root_symlink", kind))
        return 0
    if not root.is_dir():
        emit(error_result(probe_id, "root_not_directory", kind))
        return 0
    if resolve_under_root(root, root) is None:
        emit(error_result(probe_id, "root_resolution_failed", kind))
        return 0

    tree_error = validate_extracted_root(root)
    if tree_error:
        emit(error_result(probe_id, tree_error, kind))
        return 0

    try:
        if kind == "ghost":
            result = probe_ghost(root, repo, probe_id, engine_hint, cache_dir, engine_dirs)
        elif kind == "balloon":
            result = probe_balloon(root, repo, probe_id, cache_dir)
        else:
            result = probe_plugin(root, probe_id)
    except Exception:
        emit(error_result(probe_id, "internal_failure", kind))
        return 0

    if result.get("status") not in VALID_STATUS:
        result["status"] = "error"
        result["reason"] = "invalid_status_internal"
    result.setdefault("checks", {}).setdefault("runtime_executed", False)
    if result.get("status") == "pass" and not result["checks"]["runtime_executed"]:
        result["status"] = "partial"
        result["reason"] = "runtime_not_executed"
    emit(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
