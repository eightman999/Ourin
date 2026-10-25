"""Locate ghost/balloon/plugin package roots without requiring descript type."""
from __future__ import annotations

from pathlib import Path

from .io_util import parse_descript, parse_install_type, reject_symlink

GHOST_KEYS = frozenset({"shiori", "shiori.macos", "name", "charset", "icon", "sakura", "kero"})
BALLOON_KEYS = frozenset({"font.color.r", "font.color.g", "font.color.b", "origin.x", "origin.y"})
PLUGIN_KEYS = frozenset({"id", "filename", "dllname", "name"})


def _read_descript(directory: Path) -> dict[str, str] | None:
    path = directory / "descript.txt"
    if not path.is_file() or reject_symlink(path):
        return None
    return parse_descript(path)


def _type_matches(kind: str, descript: dict[str, str], directory: Path) -> bool:
    declared = (descript.get("type") or "").strip().lower()
    if declared:
        return declared == kind
    install_type = parse_install_type(directory)
    if install_type:
        return install_type == kind
    if kind == "ghost":
        return bool(GHOST_KEYS & descript.keys()) or "shiori" in descript
    if kind == "balloon":
        return bool(BALLOON_KEYS <= descript.keys()) or _has_balloon_png(directory)
    if kind == "plugin":
        filename = (descript.get("filename") or descript.get("dllname") or "").strip()
        return bool(descript.get("name")) and bool(descript.get("id")) and bool(filename)
    return False


def _has_balloon_png(directory: Path) -> bool:
    for name in ("balloons0.png", "balloon0.png", "normalPNG.png", "balloonk0.png"):
        candidate = directory / name
        if candidate.is_file() and not candidate.is_symlink():
            return True
    return False


def _preferred_paths(root: Path, kind: str) -> list[Path]:
    if kind == "ghost":
        return [root / "ghost" / "master", root / "master", root]
    if kind == "balloon":
        return [root, root / "balloon"]
    return [root]


def find_package_root(root: Path, kind: str) -> tuple[Path | None, dict[str, str] | None, str | None]:
    if reject_symlink(root) or not root.is_dir():
        return None, None, "invalid_root"

    ranked: list[tuple[int, int, Path, dict[str, str]]] = []
    seen: set[Path] = set()

    for priority, candidate in enumerate(_preferred_paths(root, kind)):
        if candidate in seen or not candidate.is_dir():
            continue
        seen.add(candidate)
        descript = _read_descript(candidate)
        if descript and _type_matches(kind, descript, candidate):
            ranked.append((priority, len(candidate.parts), candidate, descript))

    try:
        for path in root.rglob("descript.txt"):
            if path.is_symlink():
                return None, None, "symlink_in_tree"
            if not path.is_file():
                continue
            parent = path.parent
            if parent in seen:
                continue
            descript = parse_descript(path)
            if not descript or not _type_matches(kind, descript, parent):
                continue
            depth = len(parent.relative_to(root).parts)
            priority = 10 + depth
            if parent.name == "master" and kind == "ghost":
                priority = 5 + depth
            ranked.append((priority, depth, parent, descript))
            seen.add(parent)
    except OSError:
        return None, None, "tree_scan_failed"

    if not ranked:
        missing = {"ghost": "ghost_descript_missing", "balloon": "balloon_descript_missing", "plugin": "plugin_descript_missing"}
        return None, None, missing[kind]

    ranked.sort(key=lambda row: (row[0], row[1], str(row[2])))
    best_priority = ranked[0][0]
    best = [row for row in ranked if row[0] == best_priority]
    if len(best) > 1 and len({row[2] for row in best}) > 1:
        return None, None, f"ambiguous_{kind}_root"
    chosen = best[0]
    return chosen[2], chosen[3], None


def package_root_for_master(root: Path, master: Path) -> Path:
    if master.name == "master" and master.parent.name == "ghost":
        return master.parent.parent
    return root
