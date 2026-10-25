#!/usr/bin/env bash
# Build separately licensed SHIORI compatibility engines from fixed MIT sources.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/build/engines/additional}"
CACHE="${OURIN_ENGINE_SOURCE_CACHE:-$ROOT/build/engine-sources}"
REV="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["utatane_modules"]["revision"])' "$ROOT/engines/PINNED_UPSTREAM.json")"
EXPECTED="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["utatane_modules"]["archive_sha256"])' "$ROOT/engines/PINNED_UPSTREAM.json")"
REPO="$CACHE/utatane-modules"
SOURCE="$CACHE/utatane-modules-$REV-macos13"
SCRATCH="$CACHE/utatane-modules-$REV-build"
# Xcode Run Script phases export PRODUCT_NAME, EXECUTABLE_NAME and many other
# build settings. SwiftPM's multi-architecture builder invokes xcodebuild; letting
# those settings leak into it can rename every package product to Ourin.app.
# Preserve only tool selection and basic user/process locations.
SWIFT_BUILD=(env -i "PATH=$PATH" "HOME=$HOME" "TMPDIR=${TMPDIR:-/tmp}"
  "USER=${USER:-}" "LOGNAME=${LOGNAME:-}" "LANG=${LANG:-en_US.UTF-8}")
if [[ -n "${DEVELOPER_DIR:-}" ]]; then SWIFT_BUILD+=("DEVELOPER_DIR=$DEVELOPER_DIR"); fi
if [[ -n "${TOOLCHAINS:-}" ]]; then SWIFT_BUILD+=("TOOLCHAINS=$TOOLCHAINS"); fi
SWIFT_BUILD+=(/usr/bin/xcrun swift build)
mkdir -p "$CACHE" "$OUT"
if [[ ! -d "$REPO/.git" ]]; then
  git clone --filter=blob:none https://github.com/opera7133/utatane-modules.git "$REPO"
fi
if ! git -C "$REPO" cat-file -e "$REV^{commit}" 2>/dev/null; then
  git -C "$REPO" fetch origin "$REV"
fi
# Archive the commit object, never the mutable checkout; validate before applying our patch.
ARCHIVE="$(mktemp "$CACHE/utatane-source.XXXXXX")"
trap 'rm -f "$ARCHIVE"' EXIT
git -C "$REPO" archive "$REV" native LICENSE > "$ARCHIVE"
ACTUAL="$(shasum -a 256 "$ARCHIVE" | cut -d ' ' -f 1)"
[[ "$ACTUAL" == "$EXPECTED" ]] || { echo "SHIORI upstream source checksum mismatch" >&2; exit 1; }
# Re-extract fixed source inputs so stale local source edits cannot enter an app build.
mkdir -p "$SOURCE"
tar -xf "$ARCHIVE" -C "$SOURCE"
patch -d "$SOURCE" -p1 < "$ROOT/engines/additional/macos13.patch"
for product in akari ese-shiori niseshiori shino hisui yuhna misaka; do
  "${SWIFT_BUILD[@]}" --package-path "$SOURCE/native" --scratch-path "$SCRATCH" \
    -c release --arch arm64 --arch x86_64 --product "$product"
  BIN="$("${SWIFT_BUILD[@]}" --package-path "$SOURCE/native" --scratch-path "$SCRATCH" \
    -c release --arch arm64 --arch x86_64 --show-bin-path)"
  cp "$BIN/lib$product.dylib" "$OUT/"
  install_name_tool -id "@rpath/lib$product.dylib" "$OUT/lib$product.dylib"
  lipo "$OUT/lib$product.dylib" -verify_arch arm64 x86_64
  codesign --force --sign - "$OUT/lib$product.dylib"
  python3 - "$OUT/lib$product.dylib.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as output:
    plistlib.dump({'OurinShioriABI': 'ukagaka-int32'}, output)
PY
done
cp "$SOURCE/LICENSE" "$OUT/LICENSE-utatane-modules.txt"
cat > "$OUT/LICENSE-utatane-modules-NOTICE.txt" <<NOTICE
Akari, ese-shiori, NiseShiori, Shino, Hisui, Yuhna and Misaka native compatibility implementations
Copyright (c) 2026 opera7133. Licensed under MIT; see LICENSE-utatane-modules.txt.
Source: https://github.com/opera7133/utatane-modules
Revision: $REV
Source archive (git archive REV native LICENSE) SHA-256: $EXPECTED
Ourin modification: native/Package.swift minimum macOS target changed from 14 to 13.
Original Windows engines are separate works. Full original-engine compatibility is not claimed.
NOTICE
(cd "$OUT" && shasum -a 256 libakari.dylib libese-shiori.dylib libniseshiori.dylib libshino.dylib libhisui.dylib libyuhna.dylib libmisaka.dylib > SHA256SUMS)
printf '%s\n' "$REV" > "$OUT/REVISION"
