#!/usr/bin/env bash
# Build the pinned upstream engine for both supported macOS architectures.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/build/engines/kawari}"
CACHE="${OURIN_ENGINE_SOURCE_CACHE:-$ROOT/build/engine-sources}"
REV="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["kawari"]["revision"])' "$ROOT/engines/PINNED_UPSTREAM.json")"
mkdir -p "$OUT" "$CACHE"
for arch in arm64 x86_64; do
  SRC="$CACHE/kawari-$arch"
  if [[ ! -d "$SRC/.git" ]]; then
    git clone --filter=blob:none https://github.com/ukatech/kawari.git "$SRC"
  fi
  if [[ "$(git -C "$SRC" rev-parse HEAD)" != "$REV" ]]; then
    git -C "$SRC" fetch --depth 1 origin "$REV"
    git -C "$SRC" checkout --detach "$REV"
  fi
  git -C "$SRC" submodule update --init --recursive build/src/uka_regexp
  CXX="clang++ -arch $arch -mmacosx-version-min=13.0"
  make -C "$SRC/build/src" -f gcc.mak MACH_TYPE=darwin CXX="$CXX" UPX= depend
  make -C "$SRC/build/src" -f gcc.mak MACH_TYPE=darwin CXX="$CXX" UPX= -j4
  cp "$SRC/build/mach/darwin/libshiori.bundle" "$OUT/libkawari_shiori.$arch.dylib"
done
lipo -create "$OUT/libkawari_shiori.arm64.dylib" "$OUT/libkawari_shiori.x86_64.dylib" -output "$OUT/libkawari_shiori.dylib"
install_name_tool -id '@rpath/libkawari_shiori.dylib' "$OUT/libkawari_shiori.dylib"
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
  '<plist version="1.0"><dict><key>OurinShioriABI</key><string>ukagaka-long</string></dict></plist>' > "$OUT/libkawari_shiori.dylib.plist"
cp "$SRC/LICENSE" "$OUT/LICENSE.kawari"
cp "$SRC/build/src/uka_regexp/LICENSE" "$OUT/LICENSE.uka_regexp"
printf '%s\n' "$REV" > "$OUT/REVISION.kawari"
lipo -info "$OUT/libkawari_shiori.dylib"
