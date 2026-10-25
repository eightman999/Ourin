#!/bin/sh
# ScriptBridge をビルドし、build/ScriptBridge/（plugin/ に置くフォルダ）と build/ScriptBridge.nar を作る。
set -eu
cd "$(dirname "$0")"
OUT=build/ScriptBridge
BUNDLE="$OUT/ScriptBridge.plugin"
rm -rf build
mkdir -p "$BUNDLE/Contents/MacOS"
cp -R package/. "$OUT/"
cp Info.plist "$BUNDLE/Contents/Info.plist"
clang -std=c11 -O2 -Wall -Wextra -fvisibility=default -bundle \
  -arch arm64 -arch x86_64 -mmacosx-version-min=10.15 \
  src/scriptbridge.c -liconv -o "$BUNDLE/Contents/MacOS/ScriptBridge"
codesign --force --sign - "$BUNDLE" >/dev/null 2>&1 || true
(cd "$OUT" && zip -qr ../ScriptBridge.nar .)
echo "built: $OUT"
echo "built: build/ScriptBridge.nar"
