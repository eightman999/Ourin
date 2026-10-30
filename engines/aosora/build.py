#!/usr/bin/env python3
"""Build the pinned real Aosora interpreter for a local macOS engine plugin."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
MAX_ARCHIVE = 128 * 1024 * 1024
MAX_EXPANDED = 512 * 1024 * 1024


def extract(archive, destination, expected):
    raw = archive.read_bytes()
    if len(raw) > MAX_ARCHIVE or hashlib.sha256(raw).hexdigest() != expected:
        raise ValueError("Aosora archive size or SHA256 mismatch")
    destination.mkdir()
    with tarfile.open(archive) as tar:
        total = 0
        for member in tar:
            parts = PurePosixPath(member.name).parts
            if member.name.startswith("/") or ".." in parts or member.issym() or member.islnk():
                raise ValueError("unsafe Aosora archive member")
            if len(parts) < 2:
                continue
            # The upstream archive also contains an entire Windows SSP tree.
            # Build only the interpreter, its POSIX entry and vendored jsoncpp.
            if parts[1] not in {"aosora-shiori", "aosora-shiori-dll", "thirdparty", "license.txt", "readme.md"}:
                continue
            target = destination.joinpath(*parts[1:])
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                total += member.size
                if total > MAX_EXPANDED:
                    raise ValueError("expanded Aosora source exceeds limit")
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as source, target.open("wb") as output:
                    shutil.copyfileobj(source, output)
            else:
                raise ValueError("unsupported Aosora archive member")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/engines/aosora")
    parser.add_argument("--cache", type=Path, default=ROOT / "build/deps/aosora")
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--arch", choices=["universal2", "arm64", "x86_64"], default="universal2")
    parser.add_argument("--cxx", default=os.environ.get("CXX", "/usr/bin/clang++"))
    args = parser.parse_args()
    pin = json.loads((HERE / "UPSTREAM.json").read_text())
    cache, output = args.cache.resolve(), args.output.resolve()
    cache.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    archive = args.archive or cache / "upstream.tar.gz"
    if args.archive is None and not archive.exists():
        with urllib.request.urlopen(pin["url"], timeout=60) as response:
            raw = response.read(MAX_ARCHIVE + 1)
        if len(raw) > MAX_ARCHIVE or hashlib.sha256(raw).hexdigest() != pin["sha256"]:
            raise ValueError("downloaded Aosora archive size or SHA256 mismatch")
        archive.write_bytes(raw)
    with tempfile.TemporaryDirectory(prefix="ourin-aosora-build-") as temporary:
        temporary = Path(temporary)
        source = temporary / "source"
        extract(archive, source, pin["sha256"])
        entrypoint = source / "aosora-shiori-dll/dllmain.cpp"
        original = entrypoint.read_bytes()
        before = b"\tif (shioriInstance.count(id) != 0) {\n\t\tshioriInstance.erase(id);\n\t}"
        after = b"\tif (shioriInstance.count(id) != 0) {\n\t\t// Ourin POSIX lifecycle: match Windows unload and save persistent state.\n\t\tshioriInstance[id]->Unload();\n\t\tshioriInstance.erase(id);\n\t}"
        if original.count(before) != 1:
            raise ValueError("unexpected Aosora POSIX unload entrypoint")
        entrypoint.write_bytes(original.replace(before, after))
        files = sorted((source / "aosora-shiori").rglob("*.cpp"))
        files += sorted((source / "aosora-shiori-dll").rglob("*.cpp"))
        files += sorted((source / "thirdparty/jsoncpp-1.9.6/src/lib_json").glob("*.cpp"))
        if len(files) != 27:
            raise ValueError("unexpected Aosora source list")
        architectures = ["arm64", "x86_64"] if args.arch == "universal2" else [args.arch]
        libraries = []
        diagnostics = []
        for arch in architectures:
            objects = temporary / ("objects-" + arch)
            objects.mkdir()
            flags = ["-std=c++20", "-O2", "-fPIC", "-DNDEBUG", "-mmacosx-version-min=13.0",
                     "-arch", arch, "-I" + str(source / "aosora-shiori"),
                     "-I" + str(source / "thirdparty/jsoncpp-1.9.6/include")]

            def compile_one(pair):
                index, path = pair
                obj = objects / (str(index) + ".o")
                result = subprocess.run([args.cxx, *flags, "-c", str(path), "-o", str(obj)],
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)
                if result.stdout:
                    diagnostics.append(result.stdout)
                if result.returncode:
                    print(result.stdout)
                    result.check_returncode()
                return obj

            with ThreadPoolExecutor(max_workers=4) as pool:
                compiled = list(pool.map(compile_one, enumerate(files)))
            library = temporary / ("libaosora-" + arch + ".dylib")
            subprocess.run([args.cxx, *flags, "-dynamiclib", "-install_name", "@rpath/libaosora.dylib",
                            "-o", str(library), *[str(obj) for obj in compiled]], check=True, timeout=120)
            libraries.append(library)
        final = output / "libaosora.dylib"
        if len(libraries) == 2:
            subprocess.run(["/usr/bin/lipo", "-create", *[str(p) for p in libraries], "-output", str(final)], check=True)
        else:
            shutil.copyfile(libraries[0], final)
        actual_architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(final)], text=True).split()
        if not set(architectures).issubset(actual_architectures):
            raise ValueError("built Aosora library is missing a required architecture")
        final.with_suffix(".dylib.plist").write_bytes(plistlib.dumps({"OurinShioriABI": "aosora"}))
        shutil.copyfile(source / "license.txt", output / "LICENSE.aosora-local-use.txt")
        shutil.copyfile(source / "readme.md", output / "README.upstream.md")
        shutil.copyfile(source / "thirdparty/jsoncpp-1.9.6/LICENSE", output / "LICENSE.jsoncpp")
        shutil.copyfile(HERE / "UPSTREAM.json", output / "UPSTREAM.json")
        (output / "BUILD.json").write_text(json.dumps({
            "upstream": pin, "architectures": architectures, "abi": "aosora", "deployment_target": "13.0",
            "compiler": subprocess.check_output([args.cxx, "--version"], text=True).splitlines()[0],
            "source_modifications": [pin["source_patch"]], "jsoncpp": "1.9.6 (vendored)",
            "debugger_md5": "upstream default disabled; no OpenSSL dependency",
            "sources": {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
            "upstream_entrypoint_sha256": hashlib.sha256(original).hexdigest(),
            "artifact_sha256": hashlib.sha256(final.read_bytes()).hexdigest(),
        }, indent=2) + "\n")
        if diagnostics:
            (output / "BUILD_WARNINGS.log").write_text("\n".join(diagnostics))
            print("Upstream compiler diagnostics: " + str(output / "BUILD_WARNINGS.log"))
    print("Built local-use Aosora plugin engine: " + str(final))


if __name__ == "__main__":
    main()
