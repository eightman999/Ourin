#!/usr/bin/env python3
"""Build pinned official YAYA and its AYA5 configuration variant for macOS."""
from __future__ import annotations

import argparse
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
LIMIT = 64 * 1024 * 1024


def extract(pin: dict, archive: Path, target: Path) -> None:
    raw = archive.read_bytes()
    if len(raw) > LIMIT or hashlib.sha256(raw).hexdigest() != pin["sha256"]:
        raise ValueError("upstream size or SHA256 mismatch: " + pin["repository"])
    target.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as tar:
        total = 0
        for member in tar:
            parts = PurePosixPath(member.name).parts
            if member.name.startswith("/") or ".." in parts or member.issym() or member.islnk():
                raise ValueError("unsafe archive member")
            if len(parts) < 2:
                continue
            destination = target.joinpath(*parts[1:])
            if member.isdir():
                destination.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                total += member.size
                if total > 256 * 1024 * 1024:
                    raise ValueError("expanded upstream exceeds limit")
                destination.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as source, destination.open("wb") as output:
                    shutil.copyfileobj(source, output)
            else:
                raise ValueError("unsupported archive member")


def port_source(source: Path) -> list[str]:
    # CP932/CRLF is the upstream contract. Keep it intact; its Makefile performs
    # strict CP932 -> UTF-8 conversion for each compiled translation unit.
    path = source / "basis.cpp"
    raw = path.read_bytes()
    boundary = b"#elif defined(POSIX)\r\nyaya::global_t\tCBasis::ExecuteRequest"
    if raw.count(boundary) != 1:
        raise ValueError("unexpected YAYA POSIX request boundary")
    before, after = raw.split(boundary)
    allocation = b"\tstd::string istr(h, *len);\r\n"
    if after.count(allocation) != 1:
        raise ValueError("unexpected YAYA request ownership")
    after = after.replace(allocation, allocation +
        b"\t// Ourin POSIX port: consume the owned request after copying, like Windows.\r\n"
        b"\tfree(h);\r\n\th = NULL;\r\n")
    raw = before + boundary + after
    naming = b'\tmodulename = L"yaya";\r\n\tconst std::string dir_path = posix_path(base_path);'
    replacement = b'''\tconst std::string dir_path = posix_path(base_path);
#if defined(OURIN_AYA5_COMPAT)
\t// Ourin AYA5 configuration variant: preserve original config/save filenames.
\tmodulename = L"aya5";
\tstruct stat aya5_config, aya_config;
\tif (::stat((dir_path + "aya5.txt").c_str(), &aya5_config) != 0 &&
\t    ::stat((dir_path + "aya.txt").c_str(), &aya_config) == 0) modulename = L"aya";
#else
\tmodulename = L"yaya";
#endif'''.replace(b"\n", b"\r\n")
    if raw.count(naming) != 1:
        raise ValueError("unexpected YAYA POSIX configuration discovery")
    raw = raw.replace(naming, replacement)
    signature = b'file_content_search(dir_path + fname, "yaya.dll") != std::string::npos'
    if raw.count(signature) != 1:
        raise ValueError("unexpected YAYA DLL signature discovery")
    raw = raw.replace(signature, b'''(file_content_search(dir_path + fname, "yaya.dll") != std::string::npos
#if defined(OURIN_AYA5_COMPAT)
\t\t    || file_content_search(dir_path + fname, "aya5.dll") != std::string::npos
#endif
\t\t)'''.replace(b"\n", b"\r\n"))
    path.write_bytes(raw)
    path = source / "aya5.cpp"
    raw = path.read_bytes()
    begin = raw.index(b'extern "C" DLLEXPORT yaya::global_t FUNCATTRIB multi_request')
    before, after = raw[:begin], raw[begin:]
    refusal = b'\t\treturn 0;\r\n'
    position = after.index(refusal)
    after = after[:position] + b'''#if defined(POSIX)
\t\tfree(h);
\t\tif (len) *len = 0;
#endif
'''.replace(b"\n", b"\r\n") + after[position:]
    path.write_bytes(before + after)
    return ["POSIX request buffers are freed after copying and on invalid multi IDs.",
            "Optional OURIN_AYA5_COMPAT selects aya5.txt/aya.txt and recognizes the original AYA5 DLL name; version/interpreter are unchanged."]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variant", choices=["yaya", "aya"], default="yaya")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--cache", type=Path, default=ROOT / "build/deps/yaya")
    parser.add_argument("--arch", choices=["universal2", "arm64", "x86_64"], default="universal2")
    parser.add_argument("--developer-dir", type=Path,
                        default=Path(os.environ.get("DEVELOPER_DIR", "/Library/Developer/CommandLineTools")))
    args = parser.parse_args()
    output = (args.output or ROOT / "build/engines" / args.variant).resolve()
    cache = args.cache.resolve()
    for directory in [output, cache]:
        directory.mkdir(parents=True, exist_ok=True)
    pins = json.loads((HERE / "UPSTREAM.json").read_text())
    archives = {}
    for name, pin in [("upstream", pins["yaya"]), *pins["dependencies"].items()]:
        archive = cache / (name + ".tar.gz")
        if not archive.exists():
            with urllib.request.urlopen(pin["url"], timeout=60) as response:
                raw = response.read(LIMIT + 1)
            if len(raw) > LIMIT or hashlib.sha256(raw).hexdigest() != pin["sha256"]:
                raise ValueError("download size or SHA256 mismatch: " + name)
            archive.write_bytes(raw)
        archives[name] = archive
    env = {**os.environ, "DEVELOPER_DIR": str(args.developer_dir)}
    architectures = ["arm64", "x86_64"] if args.arch == "universal2" else [args.arch]
    architecture_flags = " ".join("-arch " + arch for arch in architectures) + " -mmacosx-version-min=13.0"
    stem = "libyaya" if args.variant == "yaya" else "libaya5compat"
    with tempfile.TemporaryDirectory(prefix="ourin-official-yaya-") as temporary:
        source = Path(temporary) / "source"
        extract(pins["yaya"], archives["upstream"], source)
        for name, pin in pins["dependencies"].items():
            extract(pin, archives[name], source / name)
        modifications = port_source(source)
        flags = "-O2 -Wall -std=c++11 -fvisibility=hidden -fvisibility-inlines-hidden " + architecture_flags
        if args.variant == "aya":
            flags += " -DOURIN_AYA5_COMPAT"
        command = ["/usr/bin/make", "-f", "makefile.posix", "-j4", "LIBAYA5=" + stem + ".dylib",
                   "ARCH_FLAGS=" + architecture_flags, "CXXFLAGS=" + flags,
                   "LDFLAGS=-dynamiclib -liconv " + architecture_flags + " -install_name @rpath/" + stem + ".dylib"]
        with (output / "BUILD.log").open("w") as log:
            result = subprocess.run(command, cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            print((output / "BUILD.log").read_text(errors="replace")[-6000:])
            result.check_returncode()
        module = output / (stem + ".dylib")
        shutil.copyfile(source / module.name, module)
        actual_architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(module)], env=env, text=True).split()
        if set(actual_architectures) != set(architectures):
            raise ValueError("YAYA artifact architectures differ: " + repr(actual_architectures))
        module.with_suffix(".dylib.plist").write_bytes(plistlib.dumps({"OurinShioriABI": "yaya"}))
        licenses = output / "licenses"
        licenses.mkdir(exist_ok=True)
        for origin, target in [
            ("LICENSE", "LICENSE.YAYA.BSD-3-Clause"), ("readme-original.txt", "LICENSE.AYA5-original.txt"),
            ("parson/LICENSE", "LICENSE.parson"), ("tinyxml2/LICENSE.txt", "LICENSE.tinyxml2"),
            ("uka_regexp/LICENSE", "LICENSE.uka_regexp"), ("sqlite/LICENSE", "LICENSE.sqlite-mirror"),
            ("gumbo/doc/COPYING", "LICENSE.gumbo.Apache-2.0"),
        ]:
            shutil.copyfile(source / origin, licenses / target)
        for origin, target, lines in [("mt19937ar.cpp", "NOTICE.MT19937.txt", 43),
                                     ("gumbo/src/utf8.c", "NOTICE.gumbo-utf8-MIT.txt", 59),
                                     ("sqlite/sqlite3.h", "NOTICE.sqlite-public-domain.txt", 11)]:
            (licenses / target).write_bytes(b"".join((source / origin).read_bytes().splitlines(keepends=True)[:lines]))
        shutil.copyfile(source / "README.md", output / "README.upstream.md")
        shutil.copyfile(source / "tests/posix_smoke.c", output / "posix_smoke.upstream.c")
        shutil.copyfile(HERE / "UPSTREAM.json", output / "UPSTREAM.json")
        metadata = {"upstream": pins, "variant": args.variant, "abi": "yaya", "architectures": architectures,
                    "minimumOSVersion": "13.0", "source_modifications": modifications,
                    "version_response": "Unmodified official GETSETTING(0)",
                    "compiler": subprocess.check_output(["/usr/bin/clang++", "--version"], env=env, text=True).splitlines()[0],
                    "artifact_sha256": hashlib.sha256(module.read_bytes()).hexdigest()}
        (output / "BUILD.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
    print("Built official " + pins["yaya"]["tag"] + " variant=" + args.variant + ": " + str(module))


if __name__ == "__main__":
    main()
