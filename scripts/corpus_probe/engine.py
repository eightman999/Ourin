"""Resolve SHIORI engine from descript.txt (mirrors ShioriRuntimeFactory / BundledShioriEngine)."""
from __future__ import annotations

from pathlib import Path


BUNDLED_ENGINES = {
    # Optional personal build: resolved only from explicitly trusted --engine-dir.
    "aosora": ("aosora", ("libaosora.dylib",)),
    "kawari": ("ukagaka-long", ("libkawari_shiori.dylib", "libshiori.dylib", "shiori.dylib", "kawari.dylib")),
    "kagari": ("kagari", ("libkagari.dylib", "kagari.dylib")),
    "akari": ("ukagaka-int32", ("libakari.dylib",)),
    "ese-shiori": ("ukagaka-int32", ("libese-shiori.dylib",)),
    "niseshiori": ("ukagaka-int32", ("libniseshiori.dylib",)),
    "nise-shiori": ("ukagaka-int32", ("libniseshiori.dylib",)),
    "shino": ("ukagaka-int32", ("libshino.dylib",)),
    "hisui": ("ukagaka-int32", ("libhisui.dylib",)),
    "yuhna": ("ukagaka-int32", ("libyuhna.dylib",)),
    "misaka": ("ukagaka-int32", ("libmisaka.dylib",)),
}

PROCESS_ENGINES = {
    "yaya": "yaya_core",
    "yaya_core": "yaya_core",
    "satori": "satori_core",
    "satoriya": "satori_core",
    "satori_core": "satori_core",
    "shiolink": "shiolink_core",
    "shiolink_core": "shiolink_core",
    "rishu_proxy": "rishu_proxy",
}

MACHO_MAGICS = {
    b"\xfe\xed\xfa\xce",
    b"\xce\xfa\xed\xfe",
    b"\xfe\xed\xfa\xcf",
    b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe",  # FAT_MAGIC (universal)
    b"\xbe\xba\xfe\xca",  # FAT_CIGAM
}


def _normalized_module_path(name: str) -> str:
    return name.replace("\\", "/")


def _module_stem(module_name: str) -> str:
    stem = Path(_normalized_module_path(module_name)).stem.lower()
    if stem.startswith("lib"):
        stem = stem[3:]
    return stem


def _yaya_config_url(module_name: str, master_root: Path) -> Path:
    module = Path(_normalized_module_path(module_name))
    base = master_root / module.parent
    return base / f"{module.stem}.txt"


def _is_yaya_config(path: Path) -> bool:
    if not path.is_file():
        return False
    try:
        data = path.read_bytes()
    except OSError:
        return False
    text = data.decode("latin-1", errors="replace")
    for line in text.splitlines():
        body = line.split("//", 1)[0]
        if "," not in body:
            continue
        key = body.split(",", 1)[0].strip().lower()
        if key in {"dic", "dicdir", "include"}:
            return True
    return False


def _is_kawari_dictionary_root(directory: Path) -> bool:
    if not directory.is_dir():
        return False
    markers = {"kawarirc.ini", "kawarirc.kis"}
    try:
        for entry in directory.iterdir():
            if entry.name.lower() in markers:
                return True
    except OSError:
        return False
    return False


def recognize_bundled(module_name: str, master_root: Path) -> str | None:
    stem = _module_stem(module_name)
    bare = stem
    if bare in BUNDLED_ENGINES:
        return bare if bare != "nise-shiori" else "niseshiori"
    if bare == "kosui":
        return "kawari"
    if bare == "shiori":
        module_path = Path(_normalized_module_path(module_name))
        dict_dir = master_root / module_path.parent
        return "kawari" if _is_kawari_dictionary_root(dict_dir) else None
    return None


def runtime_kind(module_name: str, master_root: Path, configuration: dict[str, str]) -> str:
    native = (configuration.get("shiori.macos") or "").strip()
    if native and _normalized_module_path(native) == _normalized_module_path(module_name):
        return "native"
    stem = _module_stem(module_name)
    if stem in PROCESS_ENGINES:
        return PROCESS_ENGINES[stem]
    if module_name.lower().endswith(".dll"):
        config = _yaya_config_url(module_name, master_root)
        if _is_yaya_config(config):
            return "yaya_core"
        return "native"
    return "native"


def is_mach_o(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            magic = handle.read(4)
    except OSError:
        return False
    return magic in MACHO_MAGICS


def search_engine_dirs(engine_dirs: list[Path], names: tuple[str, ...]) -> Path | None:
    for directory in engine_dirs:
        if not directory.is_dir():
            continue
        for name in names:
            candidate = directory / name
            if candidate.is_file() and is_mach_o(candidate):
                return candidate
    return None


def resolve_engine(
    master_root: Path,
    package_root: Path,
    descript: dict[str, str],
    repo: Path,
    engine_hint: str | None,
    engine_dirs: list[Path],
) -> dict:
    module = (descript.get("shiori") or "shiori.dll").strip()
    macos_override = (descript.get("shiori.macos") or "").strip()
    effective_module = macos_override or module
    kind = runtime_kind(effective_module, master_root, descript)
    bundled = recognize_bundled(effective_module, master_root)
    hint_normalized = (engine_hint or "").strip().lower()
    hint_applied = bool(hint_normalized) and hint_normalized in {
        kind,
        bundled or "",
        _module_stem(effective_module),
    }

    helper_name: str | None = None
    abi: str | None = None
    native_artifact: Path | None = None
    ghost_windows_module = False
    unsupported_reason: str | None = None

    module_rel = _normalized_module_path(effective_module)
    if module_rel.startswith("/") or ".." in module_rel.split("/"):
        unsupported_reason = "invalid_module_path"
    else:
        local_module = master_root / module_rel
        if local_module.is_file() and effective_module.lower().endswith(".dll"):
            ghost_windows_module = True

    search_dirs = list(engine_dirs) + [
        repo / "build/engines/additional",
        repo / "build/engines/kawari",
        repo / "engines",
    ]

    if bundled == "aosora":
        search_dirs = list(engine_dirs)

    if kind == "yaya_core":
        helper_name = "yaya_core"
    elif kind == "satori_core":
        helper_name = "satori_core"
    elif kind in PROCESS_ENGINES.values():
        helper_name = kind
    elif bundled:
        abi, names = BUNDLED_ENGINES[bundled]
        native_artifact = search_engine_dirs(search_dirs, names)
        helper_name = "native_dylib" if native_artifact else None
        if not native_artifact:
            unsupported_reason = "bundled_engine_binary_missing"
    elif kind == "native" and not ghost_windows_module:
        # Downloaded binaries and their self-declared ABI metadata are not a
        # trust source. Only bundled names resolved from operator-provided
        # built-engine directories may enter the native worker.
        unsupported_reason = "downloaded_native_module_not_trusted"
    elif ghost_windows_module:
        unsupported_reason = "windows_shiori_not_executable"

    available = False
    if helper_name == "yaya_core":
        available = (repo / "yaya_core/build/yaya_core").is_file()
    elif helper_name == "satori_core":
        available = (repo / "satori_core/build/satori_core").is_file()
    elif helper_name == "native_dylib":
        available = native_artifact is not None and native_artifact.is_file() and is_mach_o(native_artifact)

    supported = (
        helper_name is not None
        and available
        and unsupported_reason is None
        and not (ghost_windows_module and helper_name not in {"yaya_core", "satori_core"} and not bundled)
    )

    return {
        "module_stem": _module_stem(effective_module),
        "runtime_kind": kind,
        "bundled_engine": bundled,
        "helper": helper_name,
        "abi": abi,
        "native_artifact": native_artifact.name[:128] if native_artifact else None,
        "windows_only_metadata": ghost_windows_module and not bundled and helper_name not in {"yaya_core", "satori_core"},
        "ghost_windows_module_present": ghost_windows_module,
        "engine_hint_applied": hint_applied,
        "unsupported_reason": unsupported_reason,
        "supported": supported,
    }
