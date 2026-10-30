#!/bin/bash
# 許諾済みの YAYA / AYA5 互換 / なし栞だけを .plugin のまま配布用 DMG にまとめる。
# 原本と BUILD.json / SOURCE_MANIFEST.json の生成時 hash は変更しない。
# 公証の提出・staple・upload は行わない（最終 SHA-256 は staple 後に作成する）。
#
# 使い方:
#   SHIORI_PACKAGES_DIR=/path/to/build/engine-plugins/packages \
#     scripts/package-shiori-release.sh --check
#   SHIORI_PACKAGES_DIR=/path/to/build/engine-plugins/packages \
#     OUT_DIR=/new/output/directory scripts/package-shiori-release.sh
#
# OURIN_ROOT: この checkout（Info.plist の版数を使用）
# SIGN_IDENTITY / TEAM_ID: release.sh と同じ既存 Developer ID（証明書は変更しない）
# OUT_DIR: 未作成の専用ディレクトリ。既定 build/shiori-release-<版数>。
# --check: 原本の metadata / hash / CPU / 最低 OS / dyld 依存のみ確認する。
set -euo pipefail

case "${1:-}" in
    --help|-h)
        sed -n '2,15p' "$0"
        exit 0
        ;;
    --check) CHECK_ONLY=1; shift ;;
    "") CHECK_ONLY=0 ;;
    *) echo "使い方: $0 [--check|--help]" >&2; exit 2 ;;
esac
[ "$#" -eq 0 ] || { echo "引数が多すぎます" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OURIN_ROOT="${OURIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
SHIORI_PACKAGES_DIR="${SHIORI_PACKAGES_DIR:-$OURIN_ROOT/build/engine-plugins/packages}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: EITO HANAWA (ST983BCMDG)}"
TEAM_ID="${TEAM_ID:-ST983BCMDG}"

python3 - "$OURIN_ROOT" "$SHIORI_PACKAGES_DIR" "${OUT_DIR:-}" \
    "$SIGN_IDENTITY" "$TEAM_ID" "$CHECK_ONLY" "$0" <<'PY'
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def run(arguments: list[str]) -> str:
    result = subprocess.run(arguments, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(f"{arguments[0]} failed ({result.returncode}): {result.stderr.strip()}")
    return result.stdout + result.stderr


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(value, dict), f"Expected JSON object: {path.name}")
    return value


def tree_snapshot(bundle: Path) -> dict:
    # Same tree hash convention as engines/package-plugins.py. Directory names,
    # file permissions and file bytes are included; symlinks are not accepted here.
    digest = hashlib.sha256()
    total = 0
    files = {}
    for path in sorted(bundle.rglob("*")):
        require(not path.is_symlink(), f"Symlink is not allowed in release input: {path.name}")
        relative = path.relative_to(bundle).as_posix()
        digest.update(relative.encode() + b"\0")
        if path.is_file():
            mode = path.stat().st_mode & 0o777
            data = path.read_bytes()
            digest.update(b"file\0" + str(mode).encode() + b"\0")
            digest.update(data)
            total += len(data)
            files[relative] = {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data), "mode": oct(mode)}
        else:
            require(path.is_dir(), f"Unsupported filesystem entry: {relative}")
    return {"tree_sha256": digest.hexdigest(), "bytes": total, "files": files}


def version_tuple(value: str) -> tuple[int, ...]:
    require(bool(re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", value)), f"Invalid OS version: {value}")
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def load_commands(binary: Path, architecture: str) -> list[dict]:
    commands = []
    current = None
    for line in run(["xcrun", "otool", "-arch", architecture, "-l", str(binary)]).splitlines():
        text = line.strip()
        if text.startswith("cmd "):
            current = {"command": text[4:]}
            commands.append(current)
        elif current is not None:
            match = re.fullmatch(r"(name|path) (.+) \(offset [0-9]+\)", text)
            if match:
                current[match.group(1)] = match.group(2)
            elif text.startswith("minos "):
                current["minimum_os"] = text[6:]
            elif text.startswith("version ") and current["command"] == "LC_VERSION_MIN_MACOSX":
                current["minimum_os"] = text[8:]
    return commands


def is_macho(path: Path) -> bool:
    with path.open("rb") as stream:
        magic = stream.read(4)
    return magic in {
        b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
        b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
    }


def check_binary(binary: Path, bundle: Path, minimum_os: str) -> dict:
    architectures = run(["xcrun", "lipo", "-archs", str(binary)]).strip().split()
    require(set(architectures) == {"arm64", "x86_64"}, f"Universal2 required: {binary.name}: {architectures}")
    details = {}
    for architecture in sorted(architectures):
        commands = load_commands(binary, architecture)
        floors = [command["minimum_os"] for command in commands if "minimum_os" in command]
        require(bool(floors), f"No macOS deployment target in {binary.name}/{architecture}")
        require(all(version_tuple(value) <= version_tuple(minimum_os) for value in floors),
                f"Binary requires a newer OS than engine.json: {binary.name}/{architecture}: {floors}")
        rpaths = [command["path"] for command in commands if command["command"] == "LC_RPATH"]

        def internal_path(value: str) -> Path | None:
            if value.startswith("@loader_path/"):
                candidate = (binary.parent / value[len("@loader_path/"):]).resolve()
                require(candidate.is_relative_to(bundle.resolve()), f"External loader path: {binary.name}: {value}")
                return candidate
            return None

        for rpath in rpaths:
            require(internal_path(rpath) is not None, f"Nonportable LC_RPATH: {binary.name}: {rpath}")
        dependencies = []
        for command in commands:
            if command["command"] not in {"LC_LOAD_DYLIB", "LC_LOAD_WEAK_DYLIB", "LC_REEXPORT_DYLIB",
                                           "LC_LOAD_UPWARD_DYLIB", "LC_LAZY_LOAD_DYLIB"}:
                continue
            dependency = command.get("name", "")
            require(bool(dependency), f"Missing dyld dependency name: {binary.name}")
            if dependency.startswith(("/usr/lib/", "/System/Library/")):
                dependencies.append(dependency)
                continue
            candidate = internal_path(dependency)
            if dependency.startswith("@rpath/"):
                options = [internal_path(path + "/" + dependency[len("@rpath/"):]) for path in rpaths]
                candidate = next((path for path in options if path is not None and path.is_file()), None)
            require(candidate is not None and candidate.is_file(),
                    f"External/unresolved dyld dependency (Homebrew is not distributable here): {binary.name}: {dependency}")
            dependencies.append(dependency)
        details[architecture] = {"minimum_os": floors, "dependencies": dependencies, "rpaths": rpaths}
    return details


def signature(path: Path, expected_team: str, *, runtime: bool, expected_entitlements: dict | None = None) -> dict:
    run(["codesign", "--verify", "--strict", "--verbose=2", str(path)])
    details = run(["codesign", "-d", "--verbose=4", str(path)])
    fields = {}
    for line in details.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            if key in {"Authority", "TeamIdentifier", "CDHash", "Timestamp"}:
                fields.setdefault(key, []).append(value)
    authorities = fields.get("Authority", [])
    require(any(authority.startswith("Developer ID Application:") for authority in authorities),
            f"Developer ID signature required: {path.name}")
    require(fields.get("TeamIdentifier") == [expected_team], f"Unexpected signing team: {path.name}")
    require(bool(fields.get("Timestamp")), f"Secure timestamp missing: {path.name}")
    if runtime:
        require(bool(re.search(r"flags=.*\bruntime\b", details)), f"Hardened runtime flag missing: {path.name}")
    result = {"authorities": authorities, "team_identifier": expected_team,
              "cdhash": fields.get("CDHash", []), "timestamp": fields["Timestamp"][0], "hardened_runtime": runtime}
    if expected_entitlements is not None:
        probe = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(path)],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        require(probe.returncode == 0, f"Cannot inspect signed entitlements: {path.name}")
        actual = plistlib.loads(probe.stdout) if probe.stdout.strip() else {}
        require(actual == expected_entitlements, f"Unexpected signed entitlements: {path.name}")
        result["entitlements"] = actual
    return result


root, source_arg, output_arg, identity, team, check_arg, script_arg = sys.argv[1:]
root = Path(root).resolve(strict=True)
source = Path(source_arg).resolve(strict=True)
check_only = check_arg == "1"
allowed = ("yaya", "aya", "nashi")  # Fixed allowlist; never expand from the source catalog.
catalog = read_json(source.parent / "packages.json")
require(catalog.get("schema") == 1 and isinstance(catalog.get("packages"), list), "Unknown package catalog schema")
app_info = plistlib.loads((root / "Ourin/Resources/Info.plist").read_bytes())
version = app_info.get("CFBundleShortVersionString", "")
require(bool(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version)), "App must have a three-component release version")
require(str(app_info.get("LSMinimumSystemVersion")) == "13.0", "This distribution targets macOS 13.0")
require(bool(identity) and identity != "-", "A real Developer ID signing identity is required")
require(bool(re.fullmatch(r"[A-Z0-9]{10}", team)), "Invalid Developer ID team")
# Nashi is a standalone SAORI host. Reuse only the already-shipped host's
# library-loading entitlement; no new permission or JIT exception is introduced.
nashi_entitlements_path = root / "OurinShioriXPCService/OurinShioriXPCService.entitlements"
nashi_entitlements = plistlib.loads(nashi_entitlements_path.read_bytes())
require(nashi_entitlements == {"com.apple.security.cs.disable-library-validation": True},
        "Nashi signing requires exactly the existing host library-loading entitlement")

records = []
for engine_id in allowed:
    matches = [entry for entry in catalog["packages"] if entry.get("id") == engine_id]
    require(len(matches) == 1, f"Missing/duplicate catalog entry: {engine_id}")
    entry = matches[0]
    require(entry.get("licenseScope") == "redistributable" and entry.get("format") == "plugin",
            f"Package is not approved for redistribution: {engine_id}")
    bundle = source / (engine_id + ".plugin")
    require(bundle.is_dir() and not bundle.is_symlink(), f"Missing regular plugin bundle: {engine_id}")
    snapshot = tree_snapshot(bundle)
    require(snapshot["tree_sha256"] == entry.get("sha256") and snapshot["bytes"] == entry.get("bytes"),
            f"Input package differs from packages.json: {engine_id}")
    resources = bundle / "Contents/Resources"
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    descriptor = read_json(resources / "engine.json")
    provenance = read_json(resources / "SOURCE_MANIFEST.json")
    build = read_json(resources / "BUILD.json")
    upstream = read_json(resources / "UPSTREAM.json")
    require(info.get("OurinShioriEnginePackageVersion") == 1 and descriptor.get("schema") == 1,
            f"Unknown plugin schema: {engine_id}")
    require(info.get("CFBundleIdentifier") == "com.furinlab.ourin.shiori." + engine_id
            and info.get("CFBundlePackageType") == "BNDL", f"Bundle identity/type mismatch: {engine_id}")
    require(descriptor.get("id") == engine_id and provenance.get("id") == engine_id,
            f"Plugin identity mismatch: {engine_id}")
    require(bool(descriptor.get("name")) and descriptor.get("name") == info.get("CFBundleName")
            and descriptor.get("kind") == entry.get("kind"), f"Plugin name/kind mismatch: {engine_id}")
    require(descriptor.get("licenseScope") == provenance.get("licenseScope") == "redistributable",
            f"Unapproved descriptor/source license scope: {engine_id}")
    require(descriptor.get("minimumOSVersion") == info.get("LSMinimumSystemVersion") == "13.0",
            f"Minimum OS mismatch: {engine_id}")
    require(set(descriptor.get("architectures", [])) == {"arm64", "x86_64"}, f"Universal2 metadata required: {engine_id}")
    require(build.get("minimumOSVersion") == "13.0" and set(build.get("architectures", [])) == {"arm64", "x86_64"},
            f"Build CPU/OS metadata mismatch: {engine_id}")
    if engine_id in {"yaya", "aya"}:
        require(descriptor.get("kind") == "native" and descriptor.get("abi") == "yaya", f"Wrong native ABI: {engine_id}")
        licenses = ["licenses/LICENSE.YAYA.BSD-3-Clause", "licenses/LICENSE.AYA5-original.txt",
                    "licenses/LICENSE.parson", "licenses/LICENSE.tinyxml2", "licenses/LICENSE.gumbo.Apache-2.0",
                    "licenses/LICENSE.sqlite-mirror", "licenses/LICENSE.uka_regexp", "licenses/NOTICE.MT19937.txt",
                    "licenses/NOTICE.gumbo-utf8-MIT.txt", "licenses/NOTICE.sqlite-public-domain.txt"]
        require(upstream.get("yaya", {}).get("repository") == "https://github.com/YAYA-shiori/yaya-shiori",
                f"Unexpected upstream repository: {engine_id}")
        upstream_version = provenance.get("upstreamVersion")
        require(bool(upstream_version) and upstream_version == upstream["yaya"].get("tag"), f"Upstream version mismatch: {engine_id}")
        reported_version = upstream_version
    else:
        require(descriptor.get("kind") == "shiolink", "Nashi must use its isolated SHIOLINK process")
        licenses = ["upstream-LICENSE"]
        require(upstream.get("repository") == "https://github.com/yanashi-interface/nashi-shiori-studio"
                and upstream.get("license") == "Nashi License 1.1", "Unexpected Nashi source/license")
        require("Nashi License" in (resources / "upstream-LICENSE").read_text(encoding="utf-8"), "Nashi license text is missing")
        upstream_version = upstream.get("version")
        require(bool(upstream_version) and upstream_version == build.get("version"), "Nashi source version mismatch")
        reported_version = "1.0.0 (unchanged upstream metadata)"
    for relative in licenses:
        require((resources / relative).is_file() and (resources / relative).stat().st_size > 0,
                f"Required LICENSE/NOTICE is missing: {engine_id}/{relative}")
    for relative, expected in provenance.get("files", {}).items():
        path = (resources / relative).resolve()
        require(path.is_relative_to(resources.resolve()) and path.is_file(), f"Escaping/missing source-manifest file: {engine_id}")
        require(sha256(path) == expected, f"Pre-signing source hash mismatch: {engine_id}/{relative}")
    binaries = [path for path in sorted(bundle.rglob("*")) if path.is_file() and is_macho(path)]
    require(bool(binaries), f"No Mach-O payload: {engine_id}")
    primary = descriptor.get("module") if descriptor["kind"] == "native" else descriptor.get("executable")
    require(isinstance(primary, str) and not Path(primary).is_absolute() and ".." not in Path(primary).parts
            and (resources / primary).resolve().is_relative_to(resources.resolve())
            and (resources / primary) in binaries, f"Invalid primary engine payload: {engine_id}")
    checks = {path.relative_to(bundle).as_posix(): check_binary(path, bundle, "13.0") for path in binaries}
    records.append({"id": engine_id, "name": descriptor["name"], "bundle": engine_id + ".plugin",
                    "license_scope": "redistributable", "architectures": ["arm64", "x86_64"], "minimum_os": "13.0",
                    "upstream_version": upstream_version, "reported_shiori_version": reported_version,
                    "limitations": descriptor.get("limitations", ""), "license_files": licenses,
                    "input_package": snapshot, "original_source_manifest": provenance,
                    "original_build_record": build, "upstream": upstream, "binary_checks": checks})
    print(f"Validated {engine_id}.plugin: redistributable, Universal2, macOS 13.0", flush=True)

if check_only:
    print("SHIORI_RELEASE_INPUT_CHECK_PASS 3 packages; no files were copied or signed")
    raise SystemExit(0)

output = Path(output_arg).expanduser().resolve() if output_arg else root / "build" / ("shiori-release-" + version)
require(output != source and source not in output.parents and output not in source.parents, "OUT_DIR must be separate from the input packages")
require(not output.exists() and not output.is_symlink(), "OUT_DIR must be a new dedicated directory; existing payloads are never replaced")
output.mkdir(parents=True, exist_ok=False)
stage = output / "shiori-stage"
stage.mkdir()
for record in records:
    bundle = stage / record["bundle"]
    shutil.copytree(source / record["bundle"], bundle, copy_function=shutil.copy2)
    require(tree_snapshot(bundle) == record["input_package"], f"Copied package mismatch: {record['id']}")
    signatures = {}
    for relative in record["binary_checks"]:
        binary = bundle / relative
        arguments = ["codesign", "--force", "--timestamp", "--options", "runtime", "--sign", identity]
        entitlements = {}
        if record["id"] == "nashi" and relative == "Contents/Resources/nashi-shiolink":
            arguments += ["--entitlements", str(nashi_entitlements_path)]
            entitlements = nashi_entitlements
        run(arguments + [str(binary)])
        signatures[relative] = signature(binary, team, runtime=True, expected_entitlements=entitlements)
    record["signed_package"] = tree_snapshot(bundle)
    record["signatures"] = signatures

versions = {record["id"]: record["upstream_version"] for record in records}
readme = f"""Ourin SHIORIエンジンプラグイン — Ourin {version}用

対応環境: Ourin {version}以降、macOS 13.0以降。Apple Silicon / Intel（Universal2）。
本体アプリは別配布です。このDMGには許諾を確認した次の3つだけを収録しています。

・yaya.plugin: 公式YAYA {versions['yaya']}
・aya.plugin: 公式YAYA {versions['aya']}によるAYA5互換構成。原本AYA5やAYA1〜4の実装ではありません。
・nashi.plugin: なし栞 {versions['nashi']}系のmacOS移植。上流のSHIORI version応答1.0.0は保持しています。

導入手順
1. DMGを開き、Ourinの「プラグインを探す・管理…」を開きます。
2. 「SHIORIエンジン」→「プラグインを導入…」から、使う.pluginを選択します。
3. 対象ゴーストを再起動します。
.pluginは展開不要です。ゴーストの辞書やdescript.txtを書き換える必要はありません。
SAORIやイベントAPI用プラグインとは異なり、SHIORI（栞）を追加します。

利用範囲
Windows専用API、任意のWindows SAORI、全配布ゴーストの動作は保証しません。
なし栞の編集GUI「なしスタジオ」は含めません。macOS SAORIには対応するmalloc/free・C long ABIが必要です。
なし栞は許諾のある公式mainを移植しており、安定版v1.0.3や利用を避けるよう案内されたbetaの配布ではありません。
各.plugin内のLICENSE / NOTICE、INSTALL.txt、engine.jsonの制限を確認してください。

原作・ライセンス
YAYA: https://github.com/YAYA-shiori/yaya-shiori （元作者・依存ライセンスは各.plugin内に保持）
なし栞: https://github.com/yanashi-interface/nashi-shiori-studio （Nashi License 1.1）
Ourinの導入案内: https://furinlab.com/ourin/docs/library/shiori-engine-plugins/ja/

検証情報
RELEASE-MANIFEST.jsonのinput_packageは署名前、signed_packageはDeveloper ID署名後のファイルhashです。
BUILD.json / SOURCE_MANIFEST.json内の生成時hashは再現性情報として原文を保持し、署名後hashとは区別します。
"""
(stage / "はじめにお読みください.txt").write_text(readme, encoding="utf-8")
manifest = {
    "schema": 1, "ourin_version": version, "ourin_build": str(app_info["CFBundleVersion"]),
    "created_at": datetime.now(timezone.utc).isoformat(), "format": "dmg-containing-plugin-bundles",
    "included_ids": list(allowed), "packaging_script_sha256": sha256(Path(script_arg)),
    "hash_semantics": {"input_package": "Unmodified generated bundle before distribution signing",
                       "signed_package": "Exact bundle files after Developer ID signing; BUILD/source hashes remain original"},
    "packages": records,
}
(stage / "RELEASE-MANIFEST.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
require({path.name for path in stage.glob("*.plugin")} == {engine_id + ".plugin" for engine_id in allowed}, "Release allowlist mismatch")
for record in records:
    require(tree_snapshot(source / record["bundle"]) == record["input_package"], f"Original package changed during packaging: {record['id']}")

dmg = output / f"Ourin-SHIORI-{version}.dmg"
print("Creating DMG with the three .plugin bundles intact", flush=True)
run(["hdiutil", "create", "-srcfolder", str(stage), "-volname", "Ourin SHIORI " + version,
     "-format", "UDZO", str(dmg)])
run(["hdiutil", "verify", str(dmg)])
run(["codesign", "--force", "--timestamp", "--sign", identity, str(dmg)])
signature(dmg, team, runtime=False)
print(f"SHIORI_RELEASE_SIGNED {dmg}")
print("公証は未提出です。rootの配布工程で提出・staple・validate後にDMGの最終SHA-256を生成してください。")
PY
