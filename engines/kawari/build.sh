#!/usr/bin/env bash
# Fixed KAWARI/uka_regexp, built without a package manager or mutable checkout.
set -euo pipefail
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ $# -gt 0 && "$1" != -* ]]; then
  destination="$1"
  shift
  exec python3 "$ENGINE_DIR/build.py" --output "$destination" "$@"
fi
exec python3 "$ENGINE_DIR/build.py" "$@"
