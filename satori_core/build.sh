#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
cd "$(dirname "$0")"

if ! command -v cmake >/dev/null 2>&1; then
  echo "Error: cmake not found on PATH. Install via Homebrew: 'brew install cmake'" >&2
  exit 127
fi

mkdir -p build
cmake -S . -B build \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="11.0"
cmake --build build --parallel "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo "satori_core built at: $(pwd)/build/satori_core"
