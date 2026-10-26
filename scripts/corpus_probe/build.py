"""Preflight compilation for probe helpers (writes only under --cache-dir)."""
from __future__ import annotations

import hashlib
import subprocess
from pathlib import Path

COLLECTOR_NAME = "yaya_dic_collector"
BALLOON_PREFIX = "balloon_probe_"


def validate_cache_dir(cache_dir: Path) -> str | None:
    if not cache_dir.is_absolute():
        return "cache_dir_not_absolute"
    if cache_dir.is_symlink():
        return "cache_dir_symlink"
    resolved = str(cache_dir.resolve())
    if not (resolved.startswith("/tmp/") or resolved.startswith("/private/tmp/")):
        return "cache_dir_must_be_under_tmp"
    return None


def _stamp(paths: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in sorted(paths):
        if path.is_file():
            digest.update(path.name.encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()[:16]


def _collector_sources(repo: Path) -> tuple[str, Path]:
    source = (repo / "Ourin/USL/ShioriLoader.swift").read_text(encoding="utf-8")
    start = source.index("// MARK: - YAYA Config Parsing Helpers")
    end = source.index("// MARK: - YayaBackend Helpers")
    runner = """
let config = URL(fileURLWithPath: CommandLine.arguments[1])
let limit = URL(fileURLWithPath: CommandLine.arguments[2])
let content = try (try? String(contentsOf: config, encoding: .utf8)) ?? String(contentsOf: config, encoding: .shiftJIS)
var collector = DicCollector()
collectDicEntries(content: content, baseURL: config.deletingLastPathComponent(), sourceName: config.lastPathComponent, collector: &collector, visited: [])
let resolved = applyYayaBasePath(collector, root: config.deletingLastPathComponent(), within: limit)
var result: [String: Any] = ["cmd": "load", "ghost_root": resolved.root.path, "encoding": collector.globalCharset ?? "auto", "dic_entries": resolved.entries.map { entry -> [String:String] in
    var value = ["path": entry.path]
    if let encoding = entry.encoding { value["encoding"] = encoding }
    return value
}]
result["save_file"] = config.deletingPathExtension().path + "_variable.cfg"
if let depth = collector.functionDepth { result["fncdepth"] = depth }
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
"""
    swift_body = "import Foundation\n" + source[start:end] + runner
    return swift_body, repo / "Ourin/USL/ShioriLoader.swift"


def compile_yaya_collector(repo: Path, cache_dir: Path) -> tuple[Path | None, str | None]:
    err = validate_cache_dir(cache_dir)
    if err:
        return None, err
    stamp = _stamp([repo / "Ourin/USL/ShioriLoader.swift"])
    binary = cache_dir / f"{COLLECTOR_NAME}_{stamp}"
    marker = cache_dir / f".{COLLECTOR_NAME}_{stamp}.ok"
    if binary.is_file() and marker.is_file():
        return binary, None
    cache_dir.mkdir(parents=True, exist_ok=True)
    swift_body, _ = _collector_sources(repo)
    swift = cache_dir / f"{COLLECTOR_NAME}_{stamp}.swift"
    swift.write_text(swift_body, encoding="utf-8")
    try:
        subprocess.run(
            ["/usr/bin/swiftc", str(swift), "-o", str(binary)],
            check=True,
            timeout=120,
            capture_output=True,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return None, "swiftc_collector_failed"
    marker.write_text("ok", encoding="utf-8")
    return binary, None


def balloon_source_paths(repo: Path) -> list[Path]:
    swift_dir = repo / "scripts/corpus_probe/swift"
    return [
        repo / "Ourin/SSTP/EncodingAdapter.swift",
        repo / "Ourin/Compat/LegacyDescriptor.swift",
        repo / "Ourin/Ghost/AnchorRasterOperation.swift",
        repo / "Ourin/Balloon/RetinaImageLoader.swift",
        repo / "Ourin/Ghost/BalloonConfig.swift",
        swift_dir / "AnchorDecorationStyle.swift",
        swift_dir / "balloon_probe_cli.swift",
    ]


def compile_balloon_probe(repo: Path, cache_dir: Path) -> tuple[Path | None, str | None]:
    err = validate_cache_dir(cache_dir)
    if err:
        return None, err
    sources = balloon_source_paths(repo)
    for source in sources:
        if not source.is_file():
            return None, "missing_swift_source"
    stamp = _stamp(sources)
    out = cache_dir / f"{BALLOON_PREFIX}{stamp}"
    marker = cache_dir / f".{BALLOON_PREFIX}{stamp}.ok"
    if out.is_file() and marker.is_file():
        return out, None
    cache_dir.mkdir(parents=True, exist_ok=True)
    tmp = cache_dir / f"{BALLOON_PREFIX}{stamp}.build"
    command = ["/usr/bin/swiftc", "-O", "-o", str(tmp), *[str(path) for path in sources]]
    try:
        subprocess.run(command, check=True, timeout=120, capture_output=True)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return None, "swiftc_failed"
    tmp.replace(out)
    marker.write_text("ok", encoding="utf-8")
    return out, None


def require_yaya_collector(cache_dir: Path, repo: Path) -> tuple[Path | None, str | None]:
    err = validate_cache_dir(cache_dir)
    if err:
        return None, err
    stamp = _stamp([repo / "Ourin/USL/ShioriLoader.swift"])
    binary = cache_dir / f"{COLLECTOR_NAME}_{stamp}"
    marker = cache_dir / f".{COLLECTOR_NAME}_{stamp}.ok"
    if binary.is_file() and marker.is_file():
        return binary, None
    return None, "missing_preflight"


def require_balloon_probe(cache_dir: Path, repo: Path) -> tuple[Path | None, str | None]:
    err = validate_cache_dir(cache_dir)
    if err:
        return None, err
    sources = balloon_source_paths(repo)
    stamp = _stamp(sources)
    out = cache_dir / f"{BALLOON_PREFIX}{stamp}"
    marker = cache_dir / f".{BALLOON_PREFIX}{stamp}.ok"
    if out.is_file() and marker.is_file():
        return out, None
    return None, "missing_preflight"


def preflight(repo: Path, cache_dir: Path) -> dict:
    collector, collector_err = compile_yaya_collector(repo, cache_dir)
    balloon, balloon_err = compile_balloon_probe(repo, cache_dir)
    return {
        "cache_dir": str(cache_dir),
        "yaya_collector": str(collector) if collector else None,
        "yaya_collector_error": collector_err,
        "balloon_probe": str(balloon) if balloon else None,
        "balloon_probe_error": balloon_err,
        "ok": collector is not None and balloon is not None,
    }
