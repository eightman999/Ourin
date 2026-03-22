#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/build"
mkdir -p "$OUT_DIR"

swiftc \
  -emit-library \
  -module-name SimpleSaori \
  -parse-as-library \
  "$SCRIPT_DIR/SimpleSaori.swift" \
  -o "$OUT_DIR/libsimple_saori_swift.dylib"

echo "Built: $OUT_DIR/libsimple_saori_swift.dylib"
