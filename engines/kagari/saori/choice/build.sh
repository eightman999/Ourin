#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/../../../../build/engines/kagari/saori/choice}"
mkdir -p "$OUT"
clang++ -std=c++17 -Wall -Wextra -Werror -O2 -dynamiclib -arch arm64 -arch x86_64 \
  -mmacosx-version-min=13.0 "$HERE/choice.cpp" -o "$OUT/choice.dylib"
codesign --force --sign - "$OUT/choice.dylib"
shasum -a 256 "$HERE/choice.cpp" "$OUT/choice.dylib"
