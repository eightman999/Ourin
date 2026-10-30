"""Copy and relocate macOS runtime dependencies without modifying their sources.

Used only while building Ourin. System libraries remain supplied by macOS;
third-party dylibs are copied into the application and use loader-relative paths.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import shutil
import subprocess

_MAGIC = {b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
          b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}


def is_macho(path: Path) -> bool:
    if not path.is_file() or path.is_symlink():
        return False
    with path.open("rb") as stream:
        return stream.read(4) in _MAGIC


def _output(*arguments: str) -> str:
    return subprocess.check_output(arguments, text=True, stderr=subprocess.PIPE)


def _system(path: str) -> bool:
    return path.startswith(("/usr/lib/", "/System/Library/", "/Library/Apple/System/Library/"))


def _dependencies(binary: Path) -> list[str]:
    result = []
    # Universal binaries have a header for each slice. Preserve first-seen order.
    for line in _output("/usr/bin/otool", "-L", str(binary)).splitlines():
        if line.startswith("\t") and " (compatibility version" in line:
            dependency = line.strip().split(" (compatibility version", 1)[0]
            if dependency not in result:
                result.append(dependency)
    return result


def _rpaths(binary: Path) -> list[str]:
    lines = _output("/usr/bin/otool", "-l", str(binary)).splitlines()
    result = []
    for index, line in enumerate(lines):
        if line.strip() == "cmd LC_RPATH":
            for following in lines[index + 1:index + 4]:
                if following.strip().startswith("path "):
                    value = following.strip()[5:].rsplit(" (offset ", 1)[0]
                    if value not in result:
                        result.append(value)
    return result


def _identifier(binary: Path) -> str | None:
    lines = _output("/usr/bin/otool", "-D", str(binary)).splitlines()
    return next((line.strip() for line in lines if line and not line.endswith(":")
                 and "(architecture " not in line), None)


def _relative(target: Path, binary: Path) -> str:
    return "@loader_path/" + os.path.relpath(target, binary.parent)


def _relocate(binaries: list[Path], library_directory: Path,
              origins: dict[Path, Path] | None = None) -> list[Path]:
    library_directory.mkdir(parents=True, exist_ok=True)
    origins = dict(origins or {})
    copied: dict[Path, Path] = {}
    processed: set[Path] = set()
    queue = list(binaries)
    while queue:
        binary = queue.pop(0).resolve()
        if binary in processed:
            continue
        processed.add(binary)
        origin = origins.get(binary, binary)
        identifier = _identifier(binary)
        changes: list[str] = []
        for dependency in _dependencies(binary):
            if dependency == identifier or _system(dependency):
                continue
            source: Path | None = None
            if dependency.startswith("/"):
                source = Path(dependency)
            elif dependency.startswith("@loader_path/"):
                suffix = dependency[len("@loader_path/"):]
                if (binary.parent / suffix).is_file():
                    continue
                candidate = origin.parent / suffix
                if candidate.is_file():
                    source = candidate
                else:
                    raise FileNotFoundError(f"Missing loader-relative dependency of {binary.name}: {dependency}")
            elif dependency.startswith("@rpath/"):
                for rpath in _rpaths(binary):
                    expanded = rpath.replace("@loader_path", str(origin.parent))
                    if expanded.startswith("/"):
                        candidate = Path(expanded) / dependency[len("@rpath/"):]
                        if candidate.is_file():
                            source = candidate
                            break
            # Already-relative dependencies remain in their copied runtime tree.
            if source is None:
                continue
            if not source.is_file():
                raise FileNotFoundError(f"Missing runtime dependency of {binary.name}: {source}")
            source = source.resolve()
            try:
                source.relative_to(library_directory.parent.resolve())
                target = source
            except ValueError:
                target = copied.get(source)
                if target is None:
                    digest = hashlib.sha256(str(source).encode()).hexdigest()[:10]
                    target = library_directory / (digest + "-" + source.name)
                    if target.resolve() == source:
                        raise ValueError("Runtime relocation would modify its source")
                    # A copied runtime tree may already contain this target in
                    # the initial queue. Never overwrite its relocated bytes
                    # after it has been processed in this traversal.
                    if target.resolve() not in processed:
                        shutil.copy2(source, target)
                        target.chmod(target.stat().st_mode | 0o200)
                    copied[source] = target
                    origins[target.resolve()] = source
                    queue.append(target)
            changes.extend(["-change", dependency, _relative(target, binary)])
        if identifier:
            changes.extend(["-id", "@rpath/" + binary.name])
        for rpath in _rpaths(binary):
            if rpath.startswith("/") and not _system(rpath):
                changes.extend(["-delete_rpath", rpath])
        if changes:
            binary.chmod(binary.stat().st_mode | 0o200)
            subprocess.run(["/usr/bin/install_name_tool", *changes, str(binary)],
                           check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return sorted(processed)


def stage_executable(source: Path, destination: Path, library_directory: Path) -> list[Path]:
    """Copy a binary and its non-system dylib closure into a staging directory."""
    source = Path(source).resolve()
    destination = Path(destination)
    if source == destination.resolve():
        raise ValueError("Runtime source and destination must differ")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    if not is_macho(destination):
        raise ValueError(f"Not a macOS binary: {source}")
    return _relocate([destination], Path(library_directory), {destination.resolve(): source})


def relocate_tree(root: Path, library_directory: Path | None = None) -> list[Path]:
    """Relocate a runtime tree after copying it to its application destination."""
    root = Path(root).resolve()
    binaries = [path for path in root.rglob("*") if is_macho(path)]
    return _relocate(binaries, Path(library_directory) if library_directory else root / "lib")
