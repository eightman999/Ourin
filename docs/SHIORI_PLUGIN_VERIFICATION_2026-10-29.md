# SHIORIプラグイン検証記録

作業開始2026-10-29、最終確認2026-10-30（JST）。作業ツリーの既存変更を保持し、commit/push・外部公開・利用者のghostへのプラグイン導入は行っていません。

## .plugin形式への変更とGUI確認（2026-10-30追記）

利用者の指定で標準生成物を `<id>.plugin` へ変更しました。`Contents/Info.plist`（BNDL、OurinShioriEnginePackageVersion=1）と `Contents/Resources/engine.json`・runtimeを持ちます。ZIPは標準では生成せず、旧形式の読込は保持します。19bundleのplist・manifest・実行ファイルと内容hashは `/tmp/ourin-shiori-ui-review-20261030/bundle-audit.json` でPASS。

形式変更後の関連8suiteは **46 test PASS、skip 0**。記録は `/tmp/ourin-shiori-ui-review-20261030/tests-plugin-bundle.log`。実行用14bundleの導入→通常Factory→要求→終了→再ロード、新旧形式の重複拒否、別用途のbundle・外部payload拒否、転送ZIPの読込を含みます。

Macロック解除後、CUAで実アプリを操作して次を確認しました。検証用appは固有Bundle IDのコピー、主な操作の基準フォルダは `/tmp/ourin-shiori-ui-review-20261030/profile`。

- 設定→プラグイン管理→SHIORIタブを開き、`.plugin` 向けの案内・導入画面を確認。
- ファイル選択で `kawari.plugin` が種類「プラグイン」の1項目として表示されることを確認。展開せず選択し、導入完了メッセージと一覧を表示。
- 「ゴーストに使用…」で一時sakuraへ割当、再生ボタンで再起動。実XPC内のKAWARIから `桜鈴・華和梨起動` が返り、スクリプト再生へ到達。
- 実キャラクター上のダブルクリックからSHIORIを呼び、検証辞書の `GUI・華和梨プラグイン動作確認` が再生tokenへ到達。キャラクターの実描画も画面取得で確認。
- 「自動選択に戻す…」を操作して割当を解除し、再起動後もKAWARIが自動選択されることを確認。一時fixtureの入力hashは全て一致。

GUI記録は `/tmp/ourin-shiori-ui-review-20261030/gui-summary.json`、プロセス応答は同フォルダの `app-plugin.log`。UIツールが終了済みの検証コピーを環境指定なしで再起動する挙動があったため、そのコピーを終了し、操作前に画面のデータフォルダが一時プロファイルであることを確認して継続しました。

検証アプリはUIから正常終了し、対象PIDの消滅を確認。最後に追加で行った `xcodebuild build` は、先の46件成功後にXcodeから使用許諾への同意を要求され、exit 69で実行前に停止しました（`build-plugin.log`）。同意操作は実行していません。新形式のコードは先の46件のtest buildでコンパイルされ、その生成物をコピーして上記の実UI確認を行っています。

以下のZIP形式・Macロック待ちの記載は前段階の履歴です。現在の生成物とGUI確認は本節を参照してください。

## 実装

- `ShioriEnginePlugins` にZIP/フォルダ導入、インストール後の探索、DLL名・辞書マーカー・元SHIOLINK設定による識別、ゴーストごとのエンジン割当を追加。
- `ShioriRuntimeFactory` / `NativeShioriRuntime` / `ShiolinkAdapter` の通常経路へ接続。元macOSモジュールと明示Ourin設定を優先し、複数候補や不正overrideを黙って別エンジンへ変えない。
- `PluginBrowserView` にSHIORIタブ、導入、一覧、フォルダ表示、割当/解除を追加。
- KAWARI・Aosoraの固定版実装、MiyoJSの実エンジン接続と移植境界を追加。AosoraのPOSIX終了時の保存欠落を上流の`Unload()`呼出しで修正。
- .NET・Node・Ruby・Pythonの必要runtime、依存dylib、標準library、固定依存・通知をプラグインへ配置。ゴースト辞書やユーザーデータによる症状回避はしない。
- `engines/package-plugins.py` で19パッケージ（実行用14、開発用sample5）を生成。ZIPのSHA256・サイズは `build/engine-plugins/packages.json`。

## 確認済み

Xcode: `Ourin.xcodeproj` / scheme `Ourin` / Debug、DerivedData `/tmp/Ourin-Shiori-Plugins-20261029`、`CODE_SIGNING_ALLOWED=NO`、`-parallel-testing-enabled NO`。

- 最終の関連8suiteは**45 test PASS、skip 0**。記録 `/tmp/ourin-shiori-expansion-20261029/tests-verified.log`。Debug appのbuildも成功。
- 実行用14パッケージすべてを一時プロファイルへ導入し、通常Factoryから設定ファイル追加なしでロード、GET/NOTIFY、終了、再ロード、元fixture保持を確認。LuaJIT variantはOurin側の明示割当を使用。
- KAWARI/Aosoraの実Native・XPC、日本語path、Unicode/emoji、保存・再ロード。独立probeではUniversal2のarm64/Rosetta x86_64の計4ケースがPASS。
- .NET3種の移動先実行、外部dotnet無効、保存・別process再ロード、Brotli圧縮・展開。記録 `/tmp/ourin-dotnet-plugin-stage-final-process-20261029/summary.json`。
- script4種の移動先実行、日本語/emoji、保存再ロード、Windows設定内の日本語・空白付きentry選択、MiyoJSの分割UTF-8 frame。`PATH=/usr/bin:/bin`、実dyldログにruntimeのロードがありHomebrewはなし。記録 `/tmp/ourin-script-plugins-probe.json`。
- script runtimeの189 Mach-Oと.NETのnative依存を照合。外部の絶対dylib参照を除去し、stageしたバイナリへad hoc署名。最低OSとCPU条件は各manifestへ記録。
- importではパッケージrootのsymlink、パッケージ外への参照、コピー後に外部参照となるsymlinkを拒否。汎用名にはマーカー必須、曖昧一致は拒否。SDKサンプルを自動選択しない。
- 実KAWARIのZIPを導入し、汎用`shiori.dll`＋辞書マーカーから通常Factory/XPCで会話を取得。元ZIPの保持を確認。
- 19個のZIPすべてのSHA256・CRC・正規の`engine.json`名を照合してPASS。記録 `/tmp/ourin-shiori-expansion-20261029/package-audit.json`。

初回に見つかった `/tmp` と `/private/tmp` の非存在marker解決差、不正override無視、テストfixtureのsrc配置/プレースホルダー、XCTestの子processへの注入、case-insensitive volumeでのENGINE.json/engine.json衝突を修正した後の成功結果を採用します。MiyoJSの初回5秒超過も再現したため、重いruntimeの起動期限を通常要求と分け、再生成したパッケージで最終45件を実行しています。終了コード0でも実テスト0件の実行は検証件数に含めません。

## 制約

- MacロックによりCUAがNative appを取得できず、追加画面・ファイル選択の実操作と目視は検証待ち。ロック回避・権限変更は行っていません。解除後はSHIORIタブでZIPを導入し、一覧・割当・ゴースト再起動による会話表示を確認します。
- 公開配布を行っていません。Aosoraはローカル個人利用向け。他の許諾未確認分も、再配布可能という意味ではありません。
- 開発用sample5個は完成した汎用辞書interpreterではありません。任意のWindows DLL・Windows固有API・全第三者ghostへのフル互換を主張しません。
- .NET/Sana/phioriは今回の依存がmacOS26以降、MiyoJS/SanaJKは13.5以降。現stageのこれらはarm64のみ。Intel実機や古いmacOSは未確認。

導入・生成手順は [SHIORIエンジンプラグイン](SHIORI_ENGINE_PLUGINS_ja-jp.md) を参照してください。
