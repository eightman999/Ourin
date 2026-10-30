#!/usr/bin/env python3
"""Stage official YAYA and its accurately labelled AYA5 compatibility plugin."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--products", type=Path, default=ROOT / "build/engines")
    parser.add_argument("--build-missing", action="store_true")
    args = parser.parse_args()
    products, destination = args.products.resolve(), args.destination.resolve()
    if products == destination or products in destination.parents or destination in products.parents:
        raise ValueError("stage and build product trees must be separate")
    entries = []
    for engine, stem in [("yaya", "libyaya"), ("aya", "libaya5compat")]:
        source = products / engine
        required = [source / (stem + ".dylib"), source / (stem + ".dylib.plist"),
                    source / "BUILD.json", source / "UPSTREAM.json", source / "licenses"]
        if any(not path.exists() for path in required):
            if not args.build_missing:
                raise FileNotFoundError("Build the actual engine first: " + engine)
            subprocess.run([sys.executable, str(HERE / "build.py"), "--variant", engine,
                            "--output", str(source)], check=True)
        metadata = json.loads((source / "BUILD.json").read_text())
        tag = metadata["upstream"]["yaya"]["tag"]
        entry = {"id": engine, "name": "YAYA " + tag if engine == "yaya" else "AYA5互換（YAYA " + tag + "）",
                 "kind": "native", "module": engine + "/" + stem + ".dylib", "abi": "yaya",
                 "arguments": [], "charset": "UTF-8" if engine == "yaya" else "Shift_JIS",
                 "moduleNames": ["yaya.dll"] if engine == "yaya" else ["aya.dll", "aya5.dll"],
                 "markers": ["yaya.txt"] if engine == "yaya" else ["aya.txt", "aya5.txt"],
                 "architectures": metadata["architectures"], "minimumOSVersion": metadata["minimumOSVersion"],
                 "licenseScope": "redistributable", "upstreamVersion": tag,
                 "limitations": "公式YAYAのPOSIXビルド。Windows固有API・任意のWindows SAORI・全配布ゴーストは未検証。"}
        if engine == "aya":
            entry["limitations"] = "公式最新版YAYAを使うAYA5互換構成。原本AYA5やAYA1〜4の実装ではありません。 " + entry["limitations"]
        entries.append((entry, source, required))
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".yaya-stage-", dir=destination.parent) as temporary:
        staging = Path(temporary)
        for entry, source, required in entries:
            target = staging / entry["id"]
            target.mkdir()
            for path in required:
                if path.is_dir():
                    shutil.copytree(path, target / path.name)
                else:
                    shutil.copy2(path, target / path.name)
            shutil.copy2(source / "README.upstream.md", target / "README.upstream.md")
            entry["files"] = {str(path.relative_to(target)): hashlib.sha256(path.read_bytes()).hexdigest()
                              for path in sorted(target.rglob("*")) if path.is_file()}
            (target / "ENGINE.metadata.json").write_text(json.dumps(entry, ensure_ascii=False, indent=2) + "\n")
        for entry, source, required in entries:
            target = destination / entry["id"]
            if target.exists():
                if not (target / "ENGINE.metadata.json").is_file():
                    raise ValueError("Refusing to replace a non-generated engine directory: " + str(target))
                shutil.rmtree(target)
            shutil.move(str(staging / entry["id"]), target)
    manifest = destination / "yaya-manifest.json"
    manifest.write_text(json.dumps([entry for entry, _, _ in entries], ensure_ascii=False, indent=2) + "\n")
    print("Staged official YAYA / AYA5 compatibility engines: " + str(manifest))


if __name__ == "__main__":
    main()
