# 配布物の互換性を継続検証する

公開配布されているゴースト・バルーン・プラグインを、一時領域への取得、展開、検証、削除の順で確認します。作者の配布ページと直接ダウンロード先を残し、同じ結果データを docs と [Web の対応一覧](https://furinlab.com/ourin/compatibility/catalog/) に掲載します。

- [配布元・探索範囲](sources.md)
- [検証結果と対応率](results.md)
- [修正内容・最終検証・残る課題](validation.md)
- [カタログ JSON](catalog.json)
- [結果 JSON](results.json)

## 対応率の読み方

これはカタログに収録した取得候補についての標本調査です。伺か全体の作品数、利用者数、人気順を表す母集団ではありません。取得できなかった作品を未対応と断定せず、未検証・取得失敗・対応する実行経路なしを区別します。

| 層 | 確認すること | 確認できないこと |
| --- | --- | --- |
| 配布リンク | 作者ページ、直接 URL、取得時の状態、SHA-256 | 将来の配布継続、全素材の権利条件 |
| 展開 | サイズ制限、パス、ファイル構造 | Ourinへの実インストール、機能全体 |
| ゴースト実行 | Ourinが使う栞のhelper／同梱実ライブラリに辞書を渡した起動・イベント・終了 | 完全な会話網羅、画面操作、全SAORI、常用時の保存互換 |
| バルーン | Ourinの設定解析と画像デコード | 実アプリ上の文字配置、全方向の見た目 |
| プラグイン | 配布構造、メタデータ、実行形式 | Windows DLLのmacOS実行、外部サービス連携 |

「実行成功率」は実行した対象だけを分母にします。全収録数に対する成功数と、取得率・構造確認率も別に掲載します。バルーンの部分確認やプラグインのメタデータ確認を、栞実行の成功数へ混ぜません。実行対象が0件の種類について、成功率100%とは表示しません。

## 実行と削除の境界

取得物は新しい使い捨てディレクトリだけへ展開します。普段使っているOurinのゴースト保存先は入力にも出力にも使いません。ダウンロードしたDLLをそのまま実行せず、認識した栞をOurinのビルド済みhelper／同梱ライブラリへ割り当てます。

検証用Swiftコードのコンパイルは取得物の実行前に済ませます。macOSの実行検証には、ネットワークと一時ケース外への書き込みを拒否するOSのsandboxを使います。プロセス終了後にアーカイブ・展開物・その検証で生成された保存ファイルを除去し、削除の成否を結果へ残します。これは検証時の書き込み・通信制限であり、あらゆる悪意ある入力に対する安全性の保証ではありません。

公開するのはURL、ハッシュ、結果、短い診断分類です。辞書・会話の本文、画像・音声、第三者アーカイブはコミット／再配布しません。会話応答は長さ・有無・ハッシュで記録します。第三者の会話本文をモデルへの入力に送る必要はありません。

## 失敗から実装を直す

1. 取得失敗、検証器の不備、Ourinの未実装・互換性問題を切り分けます。
2. 同じ配布URLと取得物のSHA-256を記録して、再現対象を特定します。
3. 最小の自作入力や再配布可能なfixtureへ縮小し、SSP／UKADOCとOurin実装を比較します。
4. ホスト側を修正し、関連回帰テストと同じ実配布物で再検証します。ゴーストの辞書改変で成功に見せません。
5. 更新後の検証結果、残る制限、削除確認を再生成します。取得不能や未確認を成功へ書き換えません。

同一栞でも外部モジュールや独自機能によって結果が異なります。少数の成功作品を理由に、その栞のすべてのゴーストを対応済みにはしません。

## ローカルでの再実行

macOS、Xcode、Python 3、および検証対象のビルド済み `Ourin.app` を使用します。リポジトリのルートで実行し、`OURIN_APP` にはそのアプリの絶対パスを設定してください。アプリと下記helperは同じソースからビルドします。作業ルートはrunnerの許可領域から取得し、実配布物を普段のゴースト保存先へ入れません。

```sh
: "${OURIN_APP:?ビルド済み Ourin.app の絶対パスを設定してください}"
repo_root="$PWD"
engine_dir="$OURIN_APP/Contents/Frameworks"
corpus_root="$(python3 -c 'import sys; sys.path.insert(0,"scripts"); from compatibility_corpus import BASE; print(BASE)')"
mkdir -p "$corpus_root"
corpus_work="$corpus_root/work"
probe_cache="$(mktemp -d "$corpus_root/probe-cache.XXXXXX")"
probe_revision="local-$(date -u +%Y%m%dT%H%M%SZ)"

(cd yaya_core && ./build.sh)
(cd satori_core && ./build.sh)
python3 scripts/probe_corpus_content.py --preflight \
  --cache-dir "$probe_cache" --engine-dir "$engine_dir" \
  > "$probe_cache/preflight.json"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); sys.exit(0 if r.get("status")=="ok" else 1)' \
  "$probe_cache/preflight.json"
```

最後のコマンドが成功してから次へ進みます。準備時にSwiftの検証用プログラムをコンパイルし、実配布物を読み込む段階ではコンパイルしません。栞ライブラリはビルド済みアプリから読み込みます。

```sh
probe_command="$(python3 - "$repo_root/scripts/probe_corpus_content.py" "$probe_cache" "$engine_dir" <<'PY'
import json, sys
print(json.dumps([sys.executable, sys.argv[1], "--cache-dir", sys.argv[2], "--engine-dir", sys.argv[3]]))
PY
)"
run_corpus() {
  python3 scripts/compatibility_corpus.py \
    --catalog docs/compatibility-corpus/catalog.json \
    --output docs/compatibility-corpus/results.json \
    --markdown docs/compatibility-corpus/results.md \
    --work-root "$corpus_work" --max-items 100 \
    --timeout 30 --probe-timeout 30 \
    --probe-command-json "$probe_command" \
    --probe-revision "$probe_revision" "$@"
}
run_corpus
# 中断後、同じ変数・検証バイナリで再開する場合:
run_corpus --resume
# 同じ条件で、前回の未検証・部分確認・失敗も再試行する場合:
run_corpus --resume --retry-failed
```

`--resume` は入力・設定・runner・probeファイルの指紋が一致し、削除完了を確認した結果を再利用します。同梱エンジンやhelperを変更したら `probe_revision` を更新し、probeキャッシュも準備し直してください。別のシェルから再開する場合は、同じ作業ルート・キャッシュ・エンジンディレクトリ・revisionを再設定します。各段階でJSONを原子的に更新し、取得物・展開物は項目ごとの終了時に削除します。強制終了後の残存物は所有マーカーを照合して次回起動時に削除し、削除できないものは結果に残します。自作の検証キャッシュとビルド成果物は配布物とは別に保持します。

作者が直リンクの公開を禁止している場合は、カタログの `source_url` と `download_url` を同じGitHubリリースページにし、`github_release_asset` に対象ファイル名を指定できます。runnerが公開APIで取得先を内部解決し、結果の `final_url` にも作者ページを記録します。取得用URLや署名付きクエリは掲載しません。

## 作成分担と検証証跡

2026年10月25日に実Devin CLIの `swe-2-high`（SWE-2）を使用しました。最初の実行は接続エラーで終了し、ファイル編集はありませんでした。同じセッション `holistic-droplet` を再開し、担当をテストファイルに限定した実行は終了コード0で完了しました。runner本体はCodexが実装し、Devinが作成した27テストをCodexが実行・確認しています。別モデルでDevinの実行を代替していません。

初回27件に、CP932ファイル名、署名付きURLの非公開化、Unicodeパス衝突、所有マーカーによる再開時削除、子プロセス終了の6件を追加し、33件すべて成功しました。実macOS sandboxで外部書き込み・ネットワーク接続の拒否と、許可領域内の書き込みを確認しています。これは検証器の回帰テストであり、実配布物の対応数ではありません。

生のCLIログは公開しません。以下は実行記録を照合するためのSHA-256です。

| 記録 | SHA-256 |
| --- | --- |
| Devin初回・接続失敗 | `d721869841fd572a3c725ad2149e32665c7d6f5b0b541bf062a23879a6828fa2` |
| Devin再開・テスト作成完了 | `9b692b28378adbab1416bba1a04f5cde675efa30b5ea12a6a158b462abbc5c20` |
| 27件成功のテスト記録 | `dc28adc9ea6222e499d853b378205bbd335b2b725ff89bed7987cc71911e7468` |
| 33件成功のテスト記録 | `4b83eff87cd938f2f77805f8cc7050f9ff8e83c41267bca6ad6b7728865f1638` |

実配布物の初回実行で見つかった検証器の問題に対し、Windows形式のディレクトリと後発の親ディレクトリエントリ、子プロセスの `/dev/null` 利用、GitHubリリースの内部取得と公開URL保護の5件を追加しました。最終実行は **38件成功・失敗0・スキップ0** です。ネットワークと項目外へのファイル書き込みは引き続き拒否し、`/dev/null` だけを書き込みの例外にしています。

| 記録 | SHA-256 |
| --- | --- |
| 38件成功のテスト記録 | `eafec9a9a30aaed740450537126c274a407f2f2ed72eb128416672cbb19db8c4` |

検証器の回帰テストは次のコマンドで再実行できます。ローカルHTTPサーバーと自作ZIPを使用し、外部の実配布物をテストfixtureに含めません。

```sh
python3 scripts/test_compatibility_corpus.py -v
```

Cursorは検証probeの初期実装・修正、Devin SWE-2はrunnerの回帰テスト、agy経由のGeminiは公開メタデータ37件の分類照合を担当しました。Codexが独立監査し、製品側の互換性修正と実配布物の再実行を行いました。Geminiの範囲と未確認事項は[探索元の記録](sources.md)を参照してください。
