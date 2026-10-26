#!/bin/bash
# BOOTH で配布する zip を作る。scripts/release.sh で署名・公証した成果物を使う。
#
# 使い方:
#   scripts/package-booth.sh [release.sh の出力先（既定: build/release）]
#
# 出力: <出力先>/Ourin-<版>-booth.zip と .sha256
#   Ourin-<版>/
#     Ourin Installer.app   （公証・staple 済み）
#     Ourin.app             （公証・staple 済み）
#     はじめにお読みください.txt
#     ライセンス/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${1:-$ROOT/build/release}"
APP="$OUT_DIR/Ourin.app"
INSTALLER="$OUT_DIR/Ourin Installer.app"

for bundle in "$APP" "$INSTALLER"; do
    [ -d "$bundle" ] || { echo "見つかりません: $bundle（先に scripts/release.sh を実行）" >&2; exit 1; }
    # BOOTH 経由の配布物は Gatekeeper の確認を必ず受けるので、公証の staple が無ければ中止する。
    xcrun stapler validate "$bundle" >/dev/null || { echo "公証の staple がありません: $bundle" >&2; exit 1; }
    spctl -a -t exec "$bundle" || { echo "Gatekeeper で拒否されます: $bundle" >&2; exit 1; }
done

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
STAGE="$OUT_DIR/booth/Ourin-$VERSION"
rm -rf "$OUT_DIR/booth"
mkdir -p "$STAGE/ライセンス"

ditto "$INSTALLER" "$STAGE/Ourin Installer.app"
ditto "$APP" "$STAGE/Ourin.app"
sed "s/{{VERSION}}/$VERSION/g" "$ROOT/docs/booth/README_ja-jp.txt" > "$STAGE/はじめにお読みください.txt"
cp "$ROOT/LICENSE" "$STAGE/ライセンス/LICENSE.txt"
for license in "$ROOT"/LICENSES/*.txt "$ROOT"/Ourin/Resources/Licenses/*.txt; do
    cp "$license" "$STAGE/ライセンス/"
done
# 同梱エンジン（KAGARI・Lua 等）のライセンスはアプリ内のものをそのまま添える。
if [ -d "$APP/Contents/Resources/EngineLicenses" ]; then
    ditto "$APP/Contents/Resources/EngineLicenses" "$STAGE/ライセンス/エンジン"
fi

ZIP="$OUT_DIR/Ourin-$VERSION-booth.zip"
rm -f "$ZIP"
# Finder の「圧縮」と同じ形式（拡張属性と staple を保つ）。
ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$ZIP"
(cd "$OUT_DIR" && shasum -a 256 "$(basename "$ZIP")" | tee "$(basename "$ZIP").sha256")
echo "完了: $ZIP"
