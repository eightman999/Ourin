#!/usr/bin/env python3
"""Build pinned upstream KAWARI with its actual uka_regexp submodule on macOS."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LIMIT = 64 * 1024 * 1024


def unpack(pin, archive, destination):
    raw = archive.read_bytes()
    if len(raw) > LIMIT or hashlib.sha256(raw).hexdigest() != pin["sha256"]:
        raise ValueError("upstream archive size or SHA256 mismatch: " + pin["repository"])
    destination.mkdir(parents=True)
    with tarfile.open(archive) as tar:
        total = 0
        for member in tar:
            parts = PurePosixPath(member.name).parts
            if member.name.startswith("/") or ".." in parts or member.issym() or member.islnk():
                raise ValueError("unsafe upstream archive entry")
            if len(parts) < 2:
                continue
            target = destination.joinpath(*parts[1:])
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                total += member.size
                if total > LIMIT:
                    raise ValueError("expanded upstream exceeds limit")
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as source, target.open("wb") as output:
                    shutil.copyfileobj(source, output)
            else:
                raise ValueError("unsupported upstream archive entry")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/engines/kawari")
    parser.add_argument("--cache", type=Path, default=ROOT / "build/deps/kawari")
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--regexp-archive", type=Path)
    parser.add_argument("--arch", choices=["universal2", "arm64", "x86_64"], default="universal2")
    parser.add_argument("--cxx", default=os.environ.get("CXX", "/usr/bin/clang++"))
    args = parser.parse_args()
    pins = json.loads((HERE / "UPSTREAM.json").read_text())
    output, cache = args.output.resolve(), args.cache.resolve()
    output.mkdir(parents=True, exist_ok=True)
    cache.mkdir(parents=True, exist_ok=True)
    archives = {}
    for name, supplied in [("kawari", args.archive), ("uka_regexp", args.regexp_archive)]:
        pin = pins[name]
        archive = supplied or cache / (name + "-" + pin["revision"] + ".tar.gz")
        if supplied is None and not archive.exists():
            with urllib.request.urlopen(pin["url"], timeout=60) as response:
                raw = response.read(LIMIT + 1)
            if len(raw) > LIMIT or hashlib.sha256(raw).hexdigest() != pin["sha256"]:
                raise ValueError("download size or SHA256 mismatch: " + name)
            archive.write_bytes(raw)
        archives[name] = archive
    with tempfile.TemporaryDirectory(prefix="ourin-kawari-build-") as tmp:
        temporary = Path(tmp)
        source = temporary / "kawari"
        unpack(pins["kawari"], archives["kawari"], source)
        # GitHub archives contain an empty submodule directory, not its contents.
        regexp = source / "build/src/uka_regexp"
        regexp.rmdir()
        unpack(pins["uka_regexp"], archives["uka_regexp"], regexp)
        src = source / "build/src"
        # Preserve the exact upstream source list and the native-SAORI option.
        variables = {}
        for line in (src / "files.mak").read_text().replace("\\\n", " ").splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                key, value = line.split("=", 1)
                variables[key.strip()] = value.strip()

        def expand(value):
            return re.sub(r"\$\((\w+)\)", lambda match: expand(variables[match[1]]), value)

        files = (expand(variables["CORESRC"]) + " " + variables["CORESRC_NATIVE"]
                 + " " + variables["SHIOSRC"]).split()
        if len(files) != 48 or len(set(files)) != len(files):
            raise ValueError("unexpected upstream SHIORI source list")
        architectures = ["arm64", "x86_64"] if args.arch == "universal2" else [args.arch]
        products = []
        for arch in architectures:
            objects = temporary / ("objects-" + arch)
            objects.mkdir()
            flags = ["-std=c++14", "-O2", "-fPIC", "-DNDEBUG", "-DENABLE_SAORI_NATIVE",
                     "-mmacosx-version-min=13.0", "-arch", arch, "-I" + str(src)]

            def compile_one(index_file):
                index, filename = index_file
                obj = objects / (str(index) + ".o")
                subprocess.run([args.cxx] + flags + ["-c", str(src / filename), "-o", str(obj)],
                               check=True, timeout=120)
                return obj

            with ThreadPoolExecutor(max_workers=4) as pool:
                object_files = list(pool.map(compile_one, enumerate(files)))
            dylib = temporary / ("libkawari_shiori-" + arch + ".dylib")
            subprocess.run([args.cxx] + flags + ["-dynamiclib", "-install_name",
                "@rpath/libkawari_shiori.dylib", "-o", str(dylib)]
                + [str(obj) for obj in object_files] + ["-liconv"], check=True, timeout=120)
            products.append(dylib)
        final = output / "libkawari_shiori.dylib"
        if len(products) == 2:
            subprocess.run(["/usr/bin/lipo", "-create"] + [str(p) for p in products]
                           + ["-output", str(final)], check=True)
        else:
            shutil.copyfile(products[0], final)
        actual_architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(final)], text=True).split()
        if not set(architectures).issubset(actual_architectures):
            raise ValueError("built KAWARI library is missing a required architecture")
        final.with_suffix(".dylib.plist").write_bytes(plistlib.dumps({"OurinShioriABI": "ukagaka-long"}))
        shutil.copyfile(source / "LICENSE", output / "LICENSE.kawari")
        shutil.copyfile(regexp / "LICENSE", output / "LICENSE.uka_regexp")
        shutil.copyfile(HERE / "UPSTREAM.json", output / "UPSTREAM.json")
        (output / "BUILD.json").write_text(json.dumps({
            "upstream": pins, "architectures": architectures, "deployment_target": "13.0",
            "source_modifications": [], "native_saori": True, "abi": "ukagaka-long",
            "sources": {f: hashlib.sha256((src / f).read_bytes()).hexdigest() for f in files},
            "compiler": subprocess.check_output([args.cxx, "--version"], text=True).splitlines()[0],
            "artifact_sha256": hashlib.sha256(final.read_bytes()).hexdigest(),
        }, indent=2) + "\n")
    print("Built pinned KAWARI: " + str(final))


if __name__ == "__main__":
    main()
