#!/usr/bin/env python3
"""Stage movable, self-contained .NET SHIORI engine plug-in products.

This builds local products only. It does not install or publish plug-ins, and
does not establish redistribution permission for an unlicensed upstream.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

from macho_bundle import is_macho, relocate_tree

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
RUNTIME_VERSION = "10.0.12"
HOSTS = {
    "dnproxy": ("DnProxyHost", ["dnproxy.dll"], ["dnproxy.ini"], "redistributable"),
    "kanahebi": ("KanahebiHost", ["kanahebi.dll"], ["main.py"], "unconfirmed"),
    "rosalind": ("Rosalind.NET.CSharp", ["rosalind.dll"], ["Ghost.csx"], "redistributable"),
}


def recipe_hash(engine):
    digest = hashlib.sha256()
    paths = [p for p in (HERE / engine).rglob("*")
              if p.is_file() and "__pycache__" not in p.parts]
    for file in sorted(paths):
        digest.update(str(file.relative_to(HERE)).encode())
        digest.update(file.read_bytes())
    return digest.hexdigest()


def verify_products(products, host, rid, require_relocated=False):
    build = json.loads((products / "BUILD.json").read_text())
    if (not build.get("self_contained") or build.get("runtime") != rid
            or build.get("runtime_version") != RUNTIME_VERSION):
        raise ValueError(f"{products}: expected pinned self-contained {rid} products")
    config = json.loads((products / (host + ".runtimeconfig.json")).read_text())["runtimeOptions"]
    if config.get("framework") or config.get("frameworks"):
        raise ValueError("Framework-dependent products cannot be packaged as standalone engines")
    if not any(item.get("name") == "Microsoft.NETCore.App"
               and item.get("version") == RUNTIME_VERSION
               for item in config.get("includedFrameworks", [])):
        raise ValueError("Published runtime version differs from pin")
    for name in [host, host + ".dll", "libhostfxr.dylib", "libhostpolicy.dylib", "libcoreclr.dylib"]:
        if not (products / name).is_file():
            raise ValueError(f"Incomplete self-contained publish: {products / name}")
    if not os.access(products / host, os.X_OK):
        raise ValueError("Published apphost is not executable")
    architecture = {"osx-arm64": "arm64", "osx-x64": "x86_64"}[rid]
    subprocess.run(["/usr/bin/lipo", str(products / host), "-verify_arch", architecture], check=True)
    for library in (p for p in products.rglob("*") if is_macho(p)):
        subprocess.run(["/usr/bin/lipo", str(library), "-verify_arch", architecture], check=True)
        identities = subprocess.check_output(["/usr/bin/otool", "-D", str(library)], text=True).splitlines()[1:]
        dependencies = subprocess.check_output(["/usr/bin/otool", "-L", str(library)], text=True)
        for line in dependencies.splitlines()[1:]:
            dependency = line.strip().split(" (", 1)[0]
            if dependency in identities:
                continue  # LC_ID_DYLIB is an identity, not a dependent library.
            if dependency.startswith("/") and not dependency.startswith(("/usr/lib/", "/System/Library/")):
                if require_relocated:
                    raise ValueError(f"External runtime library dependency: {library.name}: {dependency}")
                source = Path(dependency)
                if not source.is_file():
                    raise ValueError("Missing runtime build dependency: " + dependency)
                pins = json.loads((HERE / "rosalind/licenses/dotnet/MANIFEST.json").read_text())["brotli"]["library_sha256"]
                if source.name not in pins or hashlib.sha256(source.read_bytes()).hexdigest() != pins[source.name]:
                    raise ValueError("Unpinned runtime build dependency: " + dependency)
                for name, expected in pins.items():
                    sibling = source.parent / name
                    if not sibling.is_file() or hashlib.sha256(sibling.read_bytes()).hexdigest() != expected:
                        raise ValueError("Unpinned Brotli runtime dependency: " + name)


def relocate_runtime_identities(products):
    # Homebrew runtime packs use absolute LC_ID_DYLIB names. Copying the packs
    # preserves these identities although .NET loads the libraries from its own
    # directory. Normalize only the staged copies and replace invalid signatures.
    for library in relocate_tree(products, library_directory=products / "native-deps"):
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(library)],
                       check=True, capture_output=True)


def copy_notices(destination):
    source = HERE / "rosalind/licenses/dotnet"
    manifest = json.loads((source / "MANIFEST.json").read_text())
    for name, expected in manifest["files"].items():
        if hashlib.sha256((source / name).read_bytes()).hexdigest() != expected:
            raise ValueError("Pinned .NET license notice hash mismatch: " + name)
    shutil.copytree(source, destination / "DotNetRuntimeNotices", dirs_exist_ok=True)


def minimum_os_version(directory):
    """Return the highest macOS deployment target across all native code slices."""
    versions = []
    for binary in (path for path in directory.rglob("*") if is_macho(path)):
        output = subprocess.check_output(["/usr/bin/otool", "-l", str(binary)], text=True)
        command = None
        binary_versions = []
        for raw in output.splitlines():
            fields = raw.split()
            if fields[:2] == ["Load", "command"]:
                command = None
            elif len(fields) == 2 and fields[0] == "cmd":
                command = fields[1]
            elif command == "LC_BUILD_VERSION" and fields[:1] == ["platform"]:
                if fields[1].upper() not in ("1", "MACOS"):
                    raise ValueError("Non-macOS native runtime cannot be packaged: " + str(binary))
            elif (command == "LC_BUILD_VERSION" and fields[:1] == ["minos"]
                  or command == "LC_VERSION_MIN_MACOSX" and fields[:1] == ["version"]):
                version = tuple(int(component) for component in fields[1].split("."))
                binary_versions.append(version + (0,) * (3 - len(version)))
        if not binary_versions:
            raise ValueError("Native runtime has no macOS minimum-version declaration: " + str(binary))
        versions.extend(binary_versions)
    if not versions:
        raise ValueError("No native runtime found while determining minimum macOS version")
    major, minor, patch = max(versions)
    return f"{major}.{minor}" + (f".{patch}" if patch else "")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--dotnet", default="/opt/homebrew/bin/dotnet")
    parser.add_argument("--runtime", action="append", choices=["osx-arm64", "osx-x64"],
                        help="Repeat for both architectures; defaults to the build host")
    parser.add_argument("--rebuild", action="store_true")
    args = parser.parse_args()
    runtimes = args.runtime or [{"arm64": "osx-arm64", "x86_64": "osx-x64"}[platform.machine()]]
    destination = args.destination.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    entries = []
    for engine, (host, modules, markers, license_scope) in HOSTS.items():
        fingerprint = recipe_hash(engine)
        executables = {}
        for rid in dict.fromkeys(runtimes):
            products = ROOT / "build/engines" / (engine + "-selfcontained") / rid
            stamp = products / ".package-inputs"
            if args.rebuild or not stamp.is_file() or stamp.read_text().strip() != fingerprint:
                subprocess.run([sys.executable, str(HERE / engine / "build.py"),
                                "--self-contained", "--runtime", rid, "--dotnet", args.dotnet,
                                "--output", str(products)], check=True)
                verify_products(products, host, rid)
                stamp.write_text(fingerprint + "\n")
            verify_products(products, host, rid)
            target = destination / engine / rid
            shutil.copytree(products, target, dirs_exist_ok=True,
                            ignore=shutil.ignore_patterns(".package-inputs", "*.pdb"))
            relocate_runtime_identities(target)
            verify_products(target, host, rid, require_relocated=True)
            copy_notices(target)
            architecture = {"osx-arm64": "arm64", "osx-x64": "x86_64"}[rid]
            executables[architecture] = f"{engine}/{rid}/{host}"
        preferred = executables.get(platform.machine(), next(iter(executables.values())))
        entries.append({
            "id": engine, "kind": "shiolink", "executable": preferred,
            "architectureExecutables": executables, "architectures": list(executables),
            "arguments": [], "charset": "UTF-8", "moduleNames": modules,
            "markers": markers, "environment": {"DOTNET_MULTILEVEL_LOOKUP": "0"},
            "licenseScope": license_scope, "runtimeVersion": RUNTIME_VERSION,
            "minimumOSVersion": minimum_os_version(destination / engine), "launchTimeout": 30,
        })
    manifest = destination / "dotnet-manifest.json"
    manifest.write_text(json.dumps(entries, indent=2, ensure_ascii=False) + "\n")
    print("Staged self-contained .NET SHIORI engines: " + str(manifest))


if __name__ == "__main__":
    main()
