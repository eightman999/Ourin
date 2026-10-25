#!/usr/bin/env bash
# Build the pinned KAGARI engine and embed its code, ABI metadata and notices.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT/build/engines/kagari"
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
if [[ "$fingerprint" != "$previous" || ! -f "$OUTPUT/libkagari.dylib" || ! -f "$OUTPUT/liblua.5.4.dylib" ]]; then
  OURIN_KAGARI_UNIVERSAL=1 bash "$ROOT/engines/kagari/build.sh"
  printf '%s\n' "$fingerprint" > "$OUTPUT/.build-inputs"
fi
for library in "$OUTPUT/"*.dylib; do
  lipo "$library" -verify_arch arm64 x86_64
done
if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${CONTENTS_FOLDER_PATH:-}" ]]; then
  echo "KAGARI built; no Xcode destination supplied."
  exit 0
fi
DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Frameworks"
NOTICES="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/EngineLicenses"
METADATA="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/EngineMetadata"
mkdir -p "$DEST" "$NOTICES" "$METADATA"
for library in "$OUTPUT/"*.dylib; do
  cp "$library" "$DEST/"
  if [[ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$DEST/$(basename "$library")"
  fi
done
cp "$OUTPUT/"*.plist "$METADATA/"
cp "$OUTPUT/"LICENSE* "$NOTICES/"
cp "$ROOT/engines/PINNED_UPSTREAM.json" "$NOTICES/"
cp "$OUTPUT/DEPENDENCIES.json" "$OUTPUT/MODULE_DEPENDENCIES.json" "$NOTICES/"
