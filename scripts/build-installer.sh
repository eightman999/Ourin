#!/bin/bash
# Ourin 専用インストーラー（Ourin Installer.app）を組み立てる。
#
# 使い方:
#   scripts/build-installer.sh <署名・公証済みの Ourin.app> [出力先]
#
# 環境変数:
#   SIGN_IDENTITY    署名 ID。空なら ad-hoc 署名（ローカル確認用）
#   NOTARY_PROFILE   設定すると公証・staple・zip 化まで行う（scripts/notarize.sh を使う）
#   TEAM_ID          公証時のチーム ID（既定: ST983BCMDG）
#
# 同梱する Ourin.app は再署名しない（release.sh で署名・公証・staple 済みのものを
# そのまま Contents/Helpers に入れ、外側だけ署名する）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PAYLOAD="${1:?Ourin.app のパスを指定してください}"
OUT_DIR="${2:-$ROOT/build/release}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
TEAM_ID="${TEAM_ID:-ST983BCMDG}"

log() { printf '\n==> %s\n' "$*"; }

[ -f "$PAYLOAD/Contents/Info.plist" ] || { echo "Ourin.app ではありません: $PAYLOAD" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PAYLOAD/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PAYLOAD/Contents/Info.plist")"
APP="$OUT_DIR/Ourin Installer.app"
mkdir -p "$OUT_DIR"

log "インストーラーをビルド (universal)"
swift build --package-path "$ROOT/Installer" -c release --arch arm64 --arch x86_64 \
    > "$OUT_DIR/installer-build.log" 2>&1 || { tail -40 "$OUT_DIR/installer-build.log"; exit 1; }
BIN_DIR="$(swift build --package-path "$ROOT/Installer" -c release --arch arm64 --arch x86_64 --show-bin-path)"

log ".app を組み立て"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp "$BIN_DIR/OurinInstaller" "$APP/Contents/MacOS/OurinInstaller"
# SwiftPM のリソースバンドル（ローカライズ等）があれば同梱する。
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] && ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done
cp "$ROOT/Ourin/Ourin.icns" "$APP/Contents/Resources/AppIcon.icns"
ditto "$PAYLOAD" "$APP/Contents/Helpers/Ourin.app"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>ja</string>
	<key>CFBundleDisplayName</key>
	<string>Ourin インストーラー</string>
	<key>CFBundleExecutable</key>
	<string>OurinInstaller</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>furin-lab.Ourin.Installer</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Ourin Installer</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$BUILD</string>
	<key>LSMinimumSystemVersion</key>
	<string>12.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>© 2025 Furin Lab and contributors</string>
</dict>
</plist>
PLIST

log "署名"
if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

ZIP="$OUT_DIR/Ourin-Installer-$VERSION.zip"
if [ -n "$NOTARY_PROFILE" ]; then
    # shellcheck source=notarize.sh
    . "$SCRIPT_DIR/notarize.sh"
    notarize_and_staple "$APP" "$OUT_DIR" "$NOTARY_PROFILE" "$TEAM_ID"
fi
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$OUT_DIR" && shasum -a 256 "$(basename "$ZIP")" | tee "$(basename "$ZIP").sha256")
log "完了: $ZIP"
