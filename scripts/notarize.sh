# shellcheck shell=bash
# release.sh / build-installer.sh から source する公証ヘルパー。
#
#   notarize_and_staple <app> <作業ディレクトリ> <keychain profile> <team id>
#
# app を zip にして notarytool へ提出し、Accepted なら staple して Gatekeeper で確認する。

notarize_and_staple() {
    local app="$1" work="$2" profile="$3" team="$4"
    local name submit_zip submission status
    name="$(basename "$app" .app | tr ' ' '-')"
    submit_zip="$work/$name-notarize.zip"

    printf '\n==> 公証 (notarytool): %s\n' "$app"
    ditto -c -k --keepParent "$app" "$submit_zip"
    if ! xcrun notarytool submit "$submit_zip" --keychain-profile "$profile" \
            --team-id "$team" --output-format json > "$work/$name-notary-submit.json"; then
        cat "$work/$name-notary-submit.json" >&2
        return 1
    fi
    submission="$(/usr/bin/plutil -extract id raw "$work/$name-notary-submit.json")"
    echo "submission: $submission"

    # 待機中の回線断で提出ごとやり直さないよう、待機だけ再試行する。
    status=""
    for attempt in 1 2 3; do
        if xcrun notarytool wait "$submission" --keychain-profile "$profile" \
                --timeout 30m --output-format json > "$work/$name-notary.json"; then
            status="$(/usr/bin/plutil -extract status raw "$work/$name-notary.json" 2>/dev/null || true)"
            [ -n "$status" ] && break
        fi
        echo "notarytool wait 失敗 ($attempt/3)、30 秒後に再試行" >&2
        sleep 30
    done
    cat "$work/$name-notary.json"
    if [ "$status" != "Accepted" ]; then
        xcrun notarytool log "$submission" --keychain-profile "$profile" "$work/$name-notary-log.json" || true
        echo "公証に失敗しました ($status): $work/$name-notary-log.json" >&2
        return 1
    fi
    rm -f "$submit_zip"

    printf '\n==> staple と Gatekeeper 確認: %s\n' "$app"
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl -a -t exec -vv "$app"
}
