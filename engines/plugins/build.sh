#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${OURIN_PLUGIN_BUILD_DIR:-$ROOT/build/engines/plugins}"
mkdir -p "$OUT"
JSON_INCLUDE="${NLOHMANN_JSON_INCLUDE_DIR:-/opt/homebrew/include}"
if [[ ! -f "$JSON_INCLUDE/nlohmann/json.hpp" ]]; then
  JSON_INCLUDE=/usr/local/include
fi
INCLUDES=(-I"$JSON_INCLUDE")
if [[ ! -f "$JSON_INCLUDE/nlohmann/json.hpp" ]]; then
  VTK_INCLUDE="$(find /usr/local/include /opt/homebrew/include -path '*/vtknlohmannjson/include/vtknlohmann/json.hpp' -print 2>/dev/null | head -1 || true)"
  if [[ -z "$VTK_INCLUDE" ]]; then
    echo 'nlohmann/json.hpp is required; set NLOHMANN_JSON_INCLUDE_DIR' >&2; exit 1
  fi
  mkdir -p "$OUT/include/nlohmann"
  cat > "$OUT/include/nlohmann/json.hpp" <<'HEADER'
#pragma once
#define VTK_NLOHMANN_JSON(x) <vtknlohmann/x>
#include <vtknlohmann/json.hpp>
HEADER
  INCLUDES=(-I"$OUT/include" -I"$(dirname "$(dirname "$VTK_INCLUDE")")")
fi
for ENGINE in yaya akari; do
  if [[ ! -f "$ROOT/engines/plugins/${ENGINE}_adapter.cpp" ]]; then continue; fi
  if [[ "$ENGINE" == yaya ]]; then NAME=OurinYayaPlugin; else NAME=OurinAkariPlugin; fi
  xcrun clang++ -std=c++17 -O2 -dynamiclib -arch arm64 -arch x86_64 \
    -mmacosx-version-min=13.0 "${INCLUDES[@]}" -liconv \
    "$ROOT/engines/plugins/${ENGINE}_adapter.cpp" -o "$OUT/$NAME.dylib"
  codesign --force --sign - "$OUT/$NAME.dylib"
  echo "$OUT/$NAME.dylib"
done

xcrun clang++ -std=c++17 -O2 -arch arm64 -arch x86_64 \
  -mmacosx-version-min=13.0 "${INCLUDES[@]}" \
  "$ROOT/engines/plugins/akari_helper.cpp" -o "$OUT/akari_helper"
codesign --force --sign - "$OUT/akari_helper"

# Explicit, narrowly scoped replacement for UGM's Windows static-file server.
xcrun clang++ -std=c++17 -O2 -arch arm64 -arch x86_64 \
  -mmacosx-version-min=13.0 "$ROOT/engines/plugins/ugm_http_helper.cpp" -o "$OUT/ugm_http_helper"
codesign --force --sign - "$OUT/ugm_http_helper"
