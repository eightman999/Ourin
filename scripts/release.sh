#!/bin/bash
# Developer ID で署名・公証した配布用 Ourin.app の zip を作る。
#
# 使い方:
#   scripts/release.sh
#
# バージョンは Ourin/Resources/Info.plist の CFBundleShortVersionString /
# CFBundleVersion が正（MARKETING_VERSION は使われていない）。
#
# 環境変数:
#   OURIN_ROOT       ビルド対象のチェックアウト（既定: このスクリプトのリポジトリ）
#   OUT_DIR          出力先（既定: $OURIN_ROOT/build/release）
#   SIGN_IDENTITY    署名 ID（既定: Developer ID Application: EITO HANAWA (ST983BCMDG)）
#   TEAM_ID          チーム ID（既定: ST983BCMDG）
#   NOTARY_PROFILE   notarytool の keychain profile（既定: ourin-notary）
#   SKIP_NOTARIZE=1  公証と staple を省略する（署名確認だけしたいとき）
#
# プロジェクトの DEVELOPMENT_TEAM は開発用のまま変えず、配布時だけここで署名し直す。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OURIN_ROOT="${OURIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
OUT_DIR="${OUT_DIR:-$OURIN_ROOT/build/release}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: EITO HANAWA (ST983BCMDG)}"
TEAM_ID="${TEAM_ID:-ST983BCMDG}"
NOTARY_PROFILE="${NOTARY_PROFILE:-ourin-notary}"

log() { printf '\n==> %s\n' "$*"; }

if ! security find-identity -v -p codesigning | grep -qF "\"$SIGN_IDENTITY\""; then
    echo "署名 ID が見つかりません: $SIGN_IDENTITY" >&2
    exit 1
fi

if [ -n "$(git -C "$OURIN_ROOT" status --porcelain --untracked-files=no)" ]; then
    echo "警告: $OURIN_ROOT に未コミットの変更があります" >&2
fi

ARCHIVE="$OUT_DIR/Ourin.xcarchive"
APP="$OUT_DIR/Ourin.app"
rm -rf "$ARCHIVE" "$APP"
mkdir -p "$OUT_DIR"

log "archive (Release, universal)"
xcodebuild -project "$OURIN_ROOT/Ourin.xcodeproj" -scheme Ourin -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
    archive > "$OUT_DIR/archive.log" 2>&1 || { tail -40 "$OUT_DIR/archive.log"; exit 1; }
ditto "$ARCHIVE/Products/Applications/Ourin.app" "$APP"

sign() {
    codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$@"
}

log "Developer ID で内側から署名"
# 同梱ヘルパー・dylib（メイン実行ファイルと XPC 以外の Mach-O）
while IFS= read -r -d '' f; do
    case "$f" in
        "$APP/Contents/MacOS/Ourin"|"$APP"/Contents/XPCServices/*) continue ;;
    esac
    if file -b "$f" | grep -q 'Mach-O'; then
        echo "  ${f#"$APP/"}"
        sign "$f"
    fi
done < <(find "$APP/Contents" -type f -print0)

for xpc in "$APP"/Contents/XPCServices/*.xpc; do
    [ -e "$xpc" ] || continue
    echo "  ${xpc#"$APP/"}"
    sign --entitlements "$OURIN_ROOT/OurinShioriXPCService/OurinShioriXPCService.entitlements" "$xpc"
done

sign --entitlements "$OURIN_ROOT/Ourin/Ourin.entitlements" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ZIP="$OUT_DIR/Ourin-$SHORT_VERSION.zip"
rm -f "$ZIP"

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
    ditto -c -k --keepParent "$APP" "$ZIP"
    log "公証を省略しました: $ZIP"
    exit 0
fi

log "公証 (notarytool)"
SUBMIT_ZIP="$OUT_DIR/Ourin-notarize.zip"
ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
if ! xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$NOTARY_PROFILE" \
        --team-id "$TEAM_ID" --output-format json > "$OUT_DIR/notary-submit.json"; then
    cat "$OUT_DIR/notary-submit.json" >&2
    exit 1
fi
SUBMISSION_ID="$(/usr/bin/plutil -extract id raw "$OUT_DIR/notary-submit.json")"
echo "submission: $SUBMISSION_ID"
# 待機中の回線断で提出ごとやり直さないよう、待機だけ再試行する。
STATUS=""
for attempt in 1 2 3; do
    if xcrun notarytool wait "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" \
            --timeout 30m --output-format json > "$OUT_DIR/notary.json"; then
        STATUS="$(/usr/bin/plutil -extract status raw "$OUT_DIR/notary.json" 2>/dev/null || true)"
        [ -n "$STATUS" ] && break
    fi
    echo "notarytool wait 失敗 ($attempt/3)、30 秒後に再試行" >&2
    sleep 30
done
cat "$OUT_DIR/notary.json"
if [ "$STATUS" != "Accepted" ]; then
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" "$OUT_DIR/notary-log.json" || true
    echo "公証に失敗しました ($STATUS): $OUT_DIR/notary-log.json" >&2
    exit 1
fi
rm -f "$SUBMIT_ZIP"

log "staple と Gatekeeper 確認"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -t exec -vv "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$OUT_DIR" && shasum -a 256 "$(basename "$ZIP")" | tee "$(basename "$ZIP").sha256")
log "完了: $ZIP"
