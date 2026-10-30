#!/usr/bin/env python3
"""Stage real native SHIORI hosts and explicitly labelled development samples.

This builds local application resources. License scope is retained in the manifest;
staging a local build does not grant permission to publish third-party components.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass, field
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile

from macho_bundle import is_macho, relocate_tree

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


@dataclass
class Recipe:
    id: str
    product: str
    binary: str
    kind: str
    license_scope: str
    build: list[str]
    module_names: list[str] = field(default_factory=list)
    markers: list[str] = field(default_factory=list)
    charset: str = "UTF-8"
    arguments: list[str] = field(default_factory=list)
    extra_files: list[str] = field(default_factory=list)
    extra_directories: list[str] = field(default_factory=list)
    abi: str = "ukagaka-long"


def recipes(arch: str, products: Path) -> list[Recipe]:
    def build(engine: str, product: str | None = None, *arguments: str) -> list[str]:
        return [sys.executable, str(HERE / engine / "build.py"), "--output",
                str(products / (product or engine)), *arguments]

    dktrtk = "dktrtk-arm64" if arch == "arm64" else "dktrtk"
    krht = "krht" if arch == "arm64" else "krht-x86_64"
    return [
        Recipe("kawari", "kawari", "libkawari_shiori.dylib", "native", "redistributable",
               build("kawari"), ["kawari.dll", "kosui.dll"],
               extra_files=["libkawari_shiori.dylib.plist"]),
        Recipe("aosora", "aosora", "libaosora.dylib", "native", "local-use-only",
               build("aosora"), ["aosora.dll"], ["ghost.asproj"],
               extra_files=["libaosora.dylib.plist"], abi="aosora"),
        Recipe("aktk", "aktk", "aktk-shiolink", "shiolink", "unconfirmed",
               build("aktk"), ["aktk.dll"], ["index.rb"]),
        Recipe("dktrtk", dktrtk, "dktrtk-host", "shiolink", "unconfirmed",
               build("dktrtk", dktrtk, "--arch", arch), ["dktrtk.dll"], ["index.as"]),
        Recipe("krht", krht, "krht-shiolink", "shiolink", "unconfirmed",
               build("krht", krht, "--arch", arch), ["krht.dll"], ["index.tcl"],
               extra_directories=["lib"]),
        Recipe("emo-rs", "emo-rs", "libemo.dylib", "native", "redistributable",
               [sys.executable, str(HERE / "emo-rs/build.py"), "--lua", "luajit52"],
               extra_files=["libemo.dylib.plist", "Cargo.lock", "DEPENDENCIES.json"],
               extra_directories=["licenses"]),
        Recipe("emo-rs-lua54", "emo-rs-lua54", "libemo.dylib", "native", "redistributable",
               [sys.executable, str(HERE / "emo-rs/build.py"), "--lua", "lua54"],
               ["emo.dll"], ["emo/shiori/init.lua"],
               extra_files=["libemo.dylib.plist", "Cargo.lock", "DEPENDENCIES.json"],
               extra_directories=["licenses"]),
        Recipe("cshiori", "cshiori", "shiori", "development-sample", "redistributable",
               build("cshiori"), charset="Shift_JIS"),
        Recipe("shioridll-nim", "shioridll-nim-universal2", "libnimshiori.dylib", "development-sample", "unconfirmed",
               build("shioridll-nim", "shioridll-nim-universal2", "--arch", "universal2"),
               extra_files=["libnimshiori.dylib.plist", "libupstream-basic.dylib", "libupstream-basic.dylib.plist",
                            "basic.upstream.nim", "shioridll.nimble", "shioridll.patched.nim"]),
        Recipe("shiorigo", "shiorigo", "gohst-shiolink", "development-sample", "unconfirmed",
               build("shiorigo")),
        Recipe("csaori", "csaori", "libcsaori-shiori.dylib", "development-sample", "redistributable",
               build("csaori"), extra_files=["libcsaori-shiori.dylib.plist"]),
        Recipe("lib_skeleton", "lib_skeleton", "libskeleton-shiori.dylib", "development-sample", "redistributable",
               build("lib_skeleton"), extra_files=["libskeleton-shiori.dylib.plist"]),
    ]


def architectures(binary: Path) -> list[str]:
    if not is_macho(binary):
        raise ValueError("Native engine is not a macOS Mach-O file: " + str(binary))
    return subprocess.check_output(["/usr/bin/lipo", "-archs", str(binary)], text=True).split()


def required(recipe: Recipe, product: Path) -> list[Path]:
    result = [product / recipe.binary, product / "UPSTREAM.json", product / "BUILD.json"]
    result += [product / name for name in recipe.extra_files + recipe.extra_directories]
    return result


def stage(recipe: Recipe, product: Path, target: Path, arch: str) -> dict:
    missing = [str(path) for path in required(recipe, product) if not path.exists()]
    if missing:
        raise FileNotFoundError("Incomplete native engine build: " + ", ".join(missing))
    slices = architectures(product / recipe.binary)
    if arch not in slices:
        raise ValueError(f"{recipe.id} has {slices}, cannot embed for {arch}; build the requested architecture first")
    target.mkdir()
    for name in [recipe.binary, "UPSTREAM.json", "BUILD.json", *recipe.extra_files]:
        shutil.copy2(product / name, target / name)
    for name in recipe.extra_directories:
        shutil.copytree(product / name, target / name)
    # Include complete source notices. Do not copy runtime test ghosts, NARs,
    # distribution/ or upstream-script/ from build products into the application.
    notices = []
    for path in sorted(product.iterdir()):
        if not path.is_file() or path.name in ["UPSTREAM.json", "BUILD.json"]:
            continue
        lowered = path.name.lower()
        if any(word in lowered for word in ["license", "notice", "legal", "readme", "local_build_only"]):
            shutil.copy2(path, target / path.name)
            notices.append(path.name)
    if not notices:
        raise ValueError("Native engine has no retained license/notice: " + recipe.id)
    relocated = relocate_tree(target)
    for binary in relocated:
        if arch not in architectures(binary):
            raise ValueError("A native dependency lacks the requested architecture: " + str(binary))
    entry = {
        "id": recipe.id, "kind": recipe.kind,
        "moduleNames": recipe.module_names, "markers": recipe.markers,
        "arguments": recipe.arguments, "charset": recipe.charset,
        "licenseScope": recipe.license_scope, "architectures": slices,
        "notices": [recipe.id + "/" + name for name in notices],
        "buildMetadata": recipe.id + "/BUILD.json",
    }
    key = "module" if recipe.binary.endswith(".dylib") else "executable"
    entry[key] = recipe.id + "/" + recipe.binary
    if key == "module":
        entry["abi"] = recipe.abi
    if recipe.kind == "development-sample":
        entry["sampleOnly"] = True
        entry["compatibility"] = "Compiled callback example; not a generic Windows DLL replacement."
    # Record hashes after relocation; the source build remains unchanged.
    entry["files"] = {
        str(path.relative_to(target)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(target.rglob("*")) if path.is_file()
    }
    (target / "ENGINE.json").write_text(json.dumps(entry, ensure_ascii=False, indent=2) + "\n")
    return entry


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--products", type=Path, default=ROOT / "build/engines")
    parser.add_argument("--arch", choices=["arm64", "x86_64"], default=platform.machine())
    parser.add_argument("--build-missing", action="store_true")
    args = parser.parse_args()
    products = args.products.resolve()
    destination = args.destination.resolve()
    # Build products and destination may never be the same tree.
    if destination == products or products in destination.parents or destination in products.parents:
        raise ValueError("Native resource destination must be separate from build products")
    selected = recipes(args.arch, products)
    for recipe in selected:
        product = products / recipe.product
        if any(not path.exists() for path in required(recipe, product)):
            if not args.build_missing:
                raise FileNotFoundError("Build native engine first: " + recipe.id)
            if recipe.id.startswith("emo-rs") and products != ROOT / "build/engines":
                raise ValueError("emo-rs builder uses its standard output; prebuild custom products explicitly")
            print("Building missing native engine: " + recipe.id, flush=True)
            subprocess.run(recipe.build, cwd=ROOT, check=True)
    destination.mkdir(parents=True, exist_ok=True)
    # Prepare all engine resources before replacing any previously generated
    # resource directory. No user ghost or original build output is modified.
    with tempfile.TemporaryDirectory(prefix=".ourin-native-stage-", dir=destination.parent) as temporary:
        staging = Path(temporary)
        entries = [stage(recipe, products / recipe.product, staging / recipe.id, args.arch)
                   for recipe in selected]
        for recipe in selected:
            target = destination / recipe.id
            if target.exists():
                shutil.rmtree(target)
            shutil.move(str(staging / recipe.id), target)
        manifest = destination / "native-manifest.json"
        manifest.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n")
    print("Staged native SHIORI resources: " + str(manifest))


if __name__ == "__main__":
    main()
