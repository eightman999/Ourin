# 栞拡張の検証記録（2026-10-25）

対象は `master 88b8172` を基点とする開発ブランチ `codex/site-docs-and-more-shiori`。公開済み v0.0.1.21 への収録を意味しません。

## 確認した変更

- 灯・ese-shiori・偽栞・忍・翡翠・結奈・美坂の独立した互換実装を固定ソースから同梱。既存のDLL名から通常のNative runtimeへ接続。
- 里珠の `rishu_proxy.dll` を専用Perl/TCP adapterへ接続。
- `shiori.macos` を通常起動・再ロードの優先モジュールにし、明示指定時は同梱helperへ置換しない。
- MiyoJSは既存SHIOLINK adapterとの実エンジン接続を確認。

## Ourinアプリと実プロセスでの試験

macOS 26.6.2 / Apple Silicon / Xcode 26.5 SDK、直列実行。

| 検証 | 結果 | 確認範囲 |
|---|---|---|
| OurinTests全体 | **1,535テスト・1,589実行、失敗0、フレームワーク報告skip 0** | arm64・直列、UI suiteは含まない。任意fixture未指定で早期終了する試験は実ゴースト確認と区別 |
| Emily4実辞書の追加回帰 | **15テスト、失敗0** | 既存の検証用Emily4コピーを明示して実helperで再実行。辞書は各試験の一時コピーを使用 |
| 関連6 suite | **59テスト・99実行、失敗0、skip 0** | GhostConfigurationTests / ShioriRuntimeTests / AdditionalShioriEngineTests / MisakaEngineTests / RishuProxyTests / ShiolinkTests |
| 新7栞 | **PASS** | 実同梱dylib、in-processとembedded XPC、通常factory、起動・会話・終了・保存・再ロード |
| macOS明示モジュール | **PASS** | `libyaya.dylib`をhelperへ誤認しない、実CライブラリとXPC別PID、未存在ファイルの失敗、別cache identity |
| 里珠 | **PASS** | 実Perl fixtureで通常経路、日本語/UTF-8/Unicode escape、起動失敗、応答期限、切断、不正長、過大応答、子PID回収 |
| 同一栞の二重load | **保護動作PASS・同時使用は制限あり** | 先に起動した辞書の状態が二重load失敗で壊れない。XPCは接続ごとの独立PIDを保証しない |
| アプリ同梱物 | **PASS** | 新7dylibのUniversal 2・全14sliceの最低OS13.0・署名検証・ABI metadata・MIT本文/NOTICE/固定版一覧の一致 |
| リリースmetadata | **PASS** | 版数、8設定の最低OS13.0、READMEとの一致 |

再現:

```sh
xcodebuild -project Ourin.xcodeproj -scheme Ourin \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:OurinTests/GhostConfigurationTests \
  -only-testing:OurinTests/ShioriRuntimeTests \
  -only-testing:OurinTests/AdditionalShioriEngineTests \
  -only-testing:OurinTests/MisakaEngineTests \
  -only-testing:OurinTests/RishuProxyTests \
  -only-testing:OurinTests/ShiolinkTests test
```

## 外部実装の確認

| 対象 | 入力 | 結果・限界 |
|---|---|---|
| 灯・ese-shiori・偽栞・忍・翡翠・結奈 | Ourin作成の最小辞書 | 実ライブラリでarm64/Rosetta x86_64の起動・会話・終了、変数37の保存→別process再load前読み出しに成功。実配布ゴーストではない |
| MiyoJS 2.0.3 | 公式npm実エンジン＋最小YAML辞書 | 実adapterの起動、日本語/絵文字、終了、PID回収に成功。MiyoPreviewは配布元timeoutで未入手 |
| 里珠1.1.32 | 未改変の作者配布echoサンプル | 実adapterのLOAD、GET/NOTIFY、日本語、Content-Length、UNLOAD/EXIT、PID回収に成功。人格ゴーストではない |

手順・固定版・ライセンス: [追加7栞](ADDITIONAL_SHIORI_ja-jp.md)、[里珠](RISHU_ja-jp.md)、[MiyoJS/SHIOLINK](SHIOLINK_ja-jp.md)。第三者ゴーストの本文・素材をテストfixtureやこの資料に同梱していません。

## 未確認の範囲

新7栞の配布ゴースト全体、GUIでのクリック/選択肢/表示、実SAORI、全辞書構文、Windows版との同一入力比較、既存保存形式の移行、macOS13実機、Intel Mac実機。里珠の追加Perl依存やMiyoJSの追加フィルタも個別確認が必要です。同じ栞の複数ゴースト同時実行は対応済みと扱いません。

華和梨LOBO・YAYA Emily4/Taromati2・里々の過去の実配布ゴースト検証は、[別の実測記録](REAL_GHOST_VERIFICATION_2026-10-25.md)で対象と版を区別しています。KAGARIのもすは不足するmacOSネイティブ依存が残ります。
