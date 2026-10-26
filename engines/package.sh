#!/usr/bin/env bash
# Build pinned engines when their build inputs change, then embed signed dylibs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT/build/engines"
mkdir -p "$OUTPUT"
fingerprint="$(python3 - "$ROOT/engines" <<'PY'
from pathlib import Path
import hashlib, sys
root = Path(sys.argv[1])
h = hashlib.sha256()
for path in sorted(root.rglob('*')):
    if path.is_file() and path.suffix in {'.sh', '.json', '.patch', '.cpp', '.c', '.h', '.py'}:
        h.update(str(path.relative_to(root)).encode())
        h.update(path.read_bytes())
print(h.hexdigest())
PY
)"
previous="$(cat "$OUTPUT/.build-inputs" 2>/dev/null || true)"
if [[ "$fingerprint" != "$previous" || ! -f "$OUTPUT/kawari/libkawari_shiori.dylib" || ! -f "$OUTPUT/kagari/libkagari.dylib" || ! -f "$OUTPUT/kagari/liblua.5.4.dylib" || ! -f "$OUTPUT/additional/libakari.dylib" || ! -f "$OUTPUT/additional/libese-shiori.dylib" || ! -f "$OUTPUT/additional/libniseshiori.dylib" || ! -f "$OUTPUT/additional/libshino.dylib" || ! -f "$OUTPUT/additional/libhisui.dylib" || ! -f "$OUTPUT/additional/libyuhna.dylib" || ! -f "$OUTPUT/additional/libmisaka.dylib" ]]; then
  bash "$ROOT/engines/kawari/build.sh"
  OURIN_KAGARI_UNIVERSAL=1 bash "$ROOT/engines/kagari/build.sh"
  bash "$ROOT/engines/additional/build.sh"
  printf '%s\n' "$fingerprint" > "$OUTPUT/.build-inputs"
fi
for library in "$OUTPUT/kawari/libkawari_shiori.dylib" "$OUTPUT/kagari/libkagari.dylib" "$OUTPUT/kagari/liblua.5.4.dylib" "$OUTPUT/additional/"*.dylib; do
  lipo "$library" -verify_arch arm64 x86_64
done
if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${CONTENTS_FOLDER_PATH:-}" ]]; then
  echo "Native engines built; no Xcode destination supplied."
  exit 0
fi
DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Frameworks"
NOTICES="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/EngineLicenses"
METADATA="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/EngineMetadata"
mkdir -p "$DEST" "$NOTICES" "$METADATA"
for engine in kawari kagari additional; do
  for library in "$OUTPUT/$engine/"*.dylib; do
    case "$library" in *.arm64.dylib|*.x86_64.dylib) continue ;; esac
    cp "$library" "$DEST/"
    if [[ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]]; then
      codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$DEST/$(basename "$library")"
    fi
  done
  for metadata in "$OUTPUT/$engine/"*.plist; do
    cp "$metadata" "$METADATA/"
    # Remove only obsolete sidecars created by this phase in prior local builds.
    rm -f "$DEST/$(basename "$metadata")"
  done
  cp "$OUTPUT/$engine/"LICENSE* "$NOTICES/"
done
cp "$ROOT/engines/PINNED_UPSTREAM.json" "$NOTICES/"
