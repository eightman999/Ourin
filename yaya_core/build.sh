#!/bin/bash
# Build script for yaya_core
# This builds the yaya_core executable for inclusion in the Ourin.app bundle

set -e

# Change to script directory
cd "$(dirname "$0")"

echo "Building yaya_core..."

# Create build directory
mkdir -p build
cd build

# Configure with CMake
cmake ..

# Build
make -j$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

echo "✅ yaya_core built successfully at: $(pwd)/yaya_core"
echo ""
echo "To integrate with Xcode:"
echo "1. Add yaya_core/build/yaya_core to Ourin target as 'Copy Files' build phase"
echo "2. Set destination to 'Executables'"
echo "3. The binary will be available via Bundle.main.url(forAuxiliaryExecutable: \"yaya_core\")"
