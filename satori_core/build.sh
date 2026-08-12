#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
cd "$(dirname "$0")"

if ! command -v cmake >/dev/null 2>&1; then
  echo "Error: cmake not found on PATH. Install via Homebrew: 'brew install cmake'" >&2
  exit 127
fi

mkdir -p build
if ! cmake -S . -B build \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="11.0"; then
  existing_binary="build/satori_core"
  newer_source="$(find src third_party -type f -newer "$existing_binary" -print -quit 2>/dev/null || true)"
  architectures_ok=true
  if command -v lipo >/dev/null 2>&1; then
    lipo "$existing_binary" -verify_arch arm64 x86_64 >/dev/null 2>&1 || architectures_ok=false
  fi

  if [[ -x "$existing_binary" && -z "$newer_source" && "$architectures_ok" == true ]]; then
    echo "Warning: satori_core dependencies are unavailable; reusing up-to-date $existing_binary" >&2
    exit 0
  fi
  exit 1
fi
cmake --build build --parallel "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo "satori_core built at: $(pwd)/build/satori_core"
