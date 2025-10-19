#!/bin/bash
# Build script for yaya_core
# This builds the yaya_core executable for inclusion in the Ourin.app bundle

set -euo pipefail

# Ensure common tool locations are on PATH (Xcode shells may miss Homebrew bins)
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

# Change to script directory
cd "$(dirname "$0")"

echo "Building yaya_core..."

# Preflight: check required tools
if ! command -v cmake >/dev/null 2>&1; then
  echo "Error: cmake not found on PATH. Install via Homebrew: 'brew install cmake'" >&2
  exit 127
fi
if ! command -v make >/dev/null 2>&1; then
  echo "Error: make not found on PATH. Ensure Xcode Command Line Tools are installed: 'xcode-select --install'" >&2
  exit 127
fi

# Create build directory
mkdir -p build
cd build

# Configure with CMake
cmake ..

# Build
cores=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
make -j"${cores}"

echo "✅ yaya_core built successfully at: $(pwd)/yaya_core"
echo ""
echo "To integrate with Xcode:"
echo "1. Add yaya_core/build/yaya_core to Ourin target as 'Copy Files' build phase"
echo "2. Set destination to 'Executables'"
echo "3. The binary will be available via Bundle.main.url(forAuxiliaryExecutable: \"yaya_core\")"
