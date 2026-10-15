#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$ROOT_DIR/Ourin.xcodeproj"
SCHEME="Ourin"
CONFIGURATION="Debug"
DERIVED_DATA_PATH="$ROOT_DIR/.build/DerivedData"
SKIP_BUILD=0

usage() {
  cat <<'EOF'
Usage: ./run_ourin.sh [options]

Build and launch the Ourin app.

Options:
  --release           Build with Release configuration
  --debug             Build with Debug configuration (default)
  --skip-build        Launch without building
  --derived-data DIR  Set custom DerivedData output path
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release)
      CONFIGURATION="Release"
      shift
      ;;
    --debug)
      CONFIGURATION="Debug"
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --derived-data)
      if [[ $# -lt 2 ]]; then
        echo "error: --derived-data requires a path" >&2
        exit 1
      fi
      DERIVED_DATA_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "error: Ourin.xcodeproj not found at $PROJECT_PATH" >&2
  exit 1
fi

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Ourin.app"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  echo "==> Building Ourin ($CONFIGURATION)..."
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found: $APP_PATH" >&2
  echo "hint: run without --skip-build first." >&2
  exit 1
fi

# Ourin は単一インスタンス（既に稼働中ならそちらを前面に出して新しい方が終了する）。
# 新しいビルドで起動し直すため、稼働中の Ourin を正常終了させてから起動する。
if pgrep -f "/Ourin.app/Contents/MacOS/Ourin" >/dev/null 2>&1; then
  echo "==> Quitting running Ourin"
  osascript -e 'quit app id "furin-lab.Ourin"' >/dev/null 2>&1 || true
  # ゴーストの終了トーク（OnClose）を待つため最大 30 秒待つ。残っていれば起動しない。
  for _ in $(seq 1 300); do
    pgrep -f "/Ourin.app/Contents/MacOS/Ourin" >/dev/null 2>&1 || break
    sleep 0.1
  done
  if pgrep -f "/Ourin.app/Contents/MacOS/Ourin" >/dev/null 2>&1; then
    echo "error: running Ourin did not quit; close it and retry" >&2
    exit 1
  fi
fi

echo "==> Launching $APP_PATH"
open "$APP_PATH"
