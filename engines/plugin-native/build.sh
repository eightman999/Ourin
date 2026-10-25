#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
out=${1:?Usage: build.sh OUTPUT_DIRECTORY}
mkdir -p "$out"
for kind in GetWindowTitle SendTalk; do
  defines=(-DOURIN_GETWINDOWTITLE=1)
  if [[ "$kind" == SendTalk ]]; then defines=(-DOURIN_SENDTALK=1); fi
  xcrun clang++ -std=c++17 -fobjc-arc -dynamiclib -O2 \
    -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 \
    -framework Foundation -framework AppKit -framework ApplicationServices \
    "${defines[@]}" "$root/native_saori.mm" -o "$out/Ourin${kind}.dylib"
done
