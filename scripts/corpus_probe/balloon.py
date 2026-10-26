"""Balloon descript + PNG decode probe (static; UI not verified)."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

from .build import require_balloon_probe
from .discovery import find_package_root


def probe_balloon(root: Path, repo: Path, probe_id: str, cache_dir: Path) -> dict:
    balloon_root, descript, locate_err = find_package_root(root, "balloon")
    if locate_err or not balloon_root or not descript:
        return _balloon_result(probe_id, "error", locate_err or "balloon_descript_missing", {})

    binary, cache_err = require_balloon_probe(cache_dir, repo)
    if cache_err or not binary:
        return _balloon_result(
            probe_id,
            "error",
            cache_err or "missing_preflight",
            {"structure": {"balloon_root": True}},
        )

    descript_path = balloon_root / "descript.txt"
    try:
        completed = subprocess.run(
            [str(binary), str(descript_path), str(balloon_root)],
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return _balloon_result(probe_id, "error", "balloon_probe_timeout", {})

    if completed.returncode != 0:
        return _balloon_result(probe_id, "partial", "balloon_probe_failed", {"exit_code": completed.returncode, "runtime_executed": False, "parser_executed": True})

    try:
        payload = json.loads(completed.stdout.strip() or "{}")
    except json.JSONDecodeError:
        return _balloon_result(probe_id, "error", "balloon_probe_invalid_output", {})

    checks = {
        "runtime_executed": False, "parser_executed": True,
        "verification_layer": "production balloon parser and image decoder; GUI unverified",
        "structure": {"balloon_root": str(balloon_root.name)[:128]},
        "descript": payload.get("descript", {}),
        "png": payload.get("png", {}),
    }
    descript_ok = payload.get("descript", {}).get("parsed") is True
    png_block = payload.get("png", {})
    png_ok = int(png_block.get("decodedCount", png_block.get("decoded_count", 0))) > 0
    if descript_ok and png_ok:
        status = "partial"
        reason = "static_parse_and_png_decode_ui_unverified"
    elif descript_ok:
        status = "partial"
        reason = "descript_parsed_png_missing_or_undecodable"
    else:
        status = "error"
        reason = "descript_parse_failed"
    return _balloon_result(probe_id, status, reason, checks)


def _balloon_result(probe_id: str, status: str, reason: str, checks: dict) -> dict:
    return {"id": probe_id, "kind": "balloon", "status": status, "reason": reason, "checks": checks}
