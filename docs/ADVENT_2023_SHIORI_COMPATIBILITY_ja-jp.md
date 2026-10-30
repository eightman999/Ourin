# Advent Calendar 2023掲載SHIORIの互換性

更新: 2026-10-28

対象は[Tatakinov氏の記事](https://gist.github.com/Tatakinov/cbaabd07069161e316a690b0e1ccbb69)の16種類。記事は2023年時点の紹介であり、Ourinでの動作保証ではない。

この作業ツリーにSHIOLINK外部プロセス接続、Native ABIの分離、KAGARIのUniversal 2同梱を追加した。記事の14エンジンには実処理への接続、2ライブラリにはmacOS開発sampleを用意した。各種の制限は下表に記載する。全配布ゴーストの互換性、全Windows API移植、自動導入・同梱は完了していない。

## 接続経路と残件

| SHIORI | 確認した接続方式・条件 | 状態・残件 |
|---|---|---|
| [aktk](https://github.com/kinokon/aktk) | Windows HGLOBAL ABI、mruby | 固定上流＋実mruby 3.4.0をPOSIX／SHIOLINKへ移植。自作Ruby fixtureの会話、Unicode、例外、保存・再load、不正source拒否を確認。上流辞書例・LICENSEなし。任意ローカルbuildのみ |
| [csaori](https://github.com/ukatech/csaori) | SAORI／PLUGIN作成ライブラリ | 実parser／builderを使うmacOS Native SHIORI開発sampleを追加。通常Factory→別PIDのXPCでUnicode、疎Reference、不正protocol、再loadを確認。完成SHIORIやWindows全API移植ではない |
| [cshiori](https://github.com/Narazaka/cshiori) | C製parser／builder、cshiolinkによるSHIOLINK実装 | 固定上流のmacOS SHIOLINK executableをビルド。本番adapterでShift_JIS日本語応答・NOTIFY・終了・再loadを確認。独自配布ゴーストは未検証 |
| [dktrtk](https://github.com/kinokon/dktrtk) | Windows HGLOBAL ABI、AngelScript | 旧SDK2.30.0 x86版に加え、公式SDK2.38.0＋全13addon＋datetimeのnative ARM64版を追加。旧length()/length property互換修正を含め両版でUnicode・addon・CP932 wire・保存再load・不正script・EOFを確認。sourceはUTF-8限定で非UTF-8を明示拒否。上流LICENSE不明、任意ローカルbuildのみ |
| [D.N.Proxy](https://github.com/nikolat/dnproxy) | .NET Framework、Windows DLLの逆P/Invoke | 元dnproxy.iniからRoslynでC#/VBを実compileする.NET10 hostを追加。元クローラのini/srcを未改変で起動し、CP932会話と別C#/VB辞書の保存再loadを確認。Windows専用API/AppDomain/WinForms等は対象外 |
| [emo-rs](https://github.com/ekicyou/emo-rs) | Rust＋Lua、C exportsはWindows限定 | LuaJIT版に加え、Lua5.4＋Unicode識別子対応の別variantを追加。実配布「えも？」NARのLua/framework/画像/descriptorを未変更で、本番Factory→XPCの初回起動・会話・ダブルクリック応答・Unicode・保存再loadを確認 |
| [kagari](https://github.com/Tatakinov/kagari_shiori) | instance ID付きPOSIX ABI | 固定版の実エンジンで起動・要求・終了・再load、in-process／XPCを確認。Lanes 3.17.2／MIMEを同梱。配布ゴースト「もす」の未改変辞書で起動・会話・メニュー変更・保存・別process再loadを確認 |
| [Kanahebi](https://github.com/kanadelab/Kanahebi) | IronPython、.NET Framework 4.7.2、ukastream BRIDGE/1.0 | 元ModuleMainと未改変Sampleを.NET 10／IronPython 3.4.2＋StdLib／DLR 1.3.5で実行するSHIOLINK hostを追加。元2.2会話と自作3.0辞書のUnicode・保存・再loadを検証。旧BRIDGE・Windows依存全体は対象外、上流自身LICENSE未確認 |
| [krht](https://github.com/kinokon/krht) | Windows HGLOBAL ABI、Tcl | 固定Tcl9.1.0を静的buildし、HomebrewのmacOS26専用依存を除去。arm64/x86_64別成果物、実Rosetta、別pathへのruntime移動、途中EOFでの保存を確認。古いmacOSとIntel実機は未確認。上流LICENSE不明、任意ローカルbuildのみ |
| [lib_skeleton](https://github.com/Tatakinov/lib_skeleton) | SHIORI Request／Response型等の作成基盤 | 未改変の実C++20ヘッダを使うmacOS Native SHIORI開発sampleを追加。通常Factory→別PIDのXPCでUnicode、疎Reference、不正protocol、再loadを確認。辞書エンジンではない |
| [phiori](https://github.com/Tatakinov/phiori) | Windows HGLOBAL ABI、Python 3.12 Windows 32bit配布 | 元Python module＋exampleをSHIOLINK hostで実行。通常factoryで元DLL名から選択し、OnBoot／OnClose・Unicode callback・保存・再loadを確認。外部Python 3.14.8、Windows C DLLは使わない。許諾表記の不一致はREADMEに記録 |
| [Rosalind](https://github.com/as-is-prog/rosalind) | SHIOLINK、.NET Framework 4.6以上 | 上流modern .NET版をSDK 10.0.401でビルド。CRLF/EOFを移植し、実Rosalind/Roslyn C# scriptの会話・Unicode・保存・別process再loadを確認。.NET 10 runtimeが必要 |
| [sana](https://github.com/Narazaka/sana) | SHIOLINK＋Ruby | sana 0.0.4／shiolink 0.0.2の実パッケージで起動・日本語会話・NOTIFY・保存・再loadを確認。配布ゴーストは未検証 |
| [sanajk](https://github.com/Narazaka/sanajk) | shiolinkjs＋Node.js | 実packageの会話・保存再loadは確認済み。記事掲載「節美亜シンク」は元sourceが欠けたsecret/keysを無条件importするため、実配布の確認状況は第4部を参照。鍵や認証stubは補っていない |
| [shioridll-nim](https://github.com/Narazaka/shioridll-nim) | POSIX分岐あり、C long長の標準ABI | 固定上流のPOSIX境界をmalloc/freeとcintへ移植。実Nim 2.2.4／ARCのarm64/x86_64/Universal2で上流basic例と日本語例をビルドし、通常factory・XPC・異なるforeign thread・再loadを確認。Intel側は実Rosetta、Intel実機と配布ゴーストは未検証 |
| [shiorigo](https://github.com/Narazaka/shiorigo) | Go用parser／builder | 固定shiorigo＋実Gohst handlerを未改変でビルドし、SHIOLINKの起動・日本語会話・NOTIFY・終了・再processを確認。上流に保存機能はない |

## 導入

2026-10-29: 追加実装と実行環境をまとめる[SHIORIエンジンプラグイン](SHIORI_ENGINE_PLUGINS_ja-jp.md)の導入経路を追加。以下の個別手動設定は既存の接続方法として引き続き利用できます。開発用sampleと汎用辞書エンジン、ローカル用途と再配布可能なパッケージは同ページで区別します。

SHIOLINKの設定と制限は[SHIOLINK接続](SHIOLINK_ja-jp.md)を参照。macOSで動くNode.js／Ruby等の実行環境とエンジンを別途用意する。ゴーストのWindows設定を保全するため、同じ場所に `SHIOLINK.ourin.ini` を作成できる。元のDLL名を持つ移植エンジンには、Ourin専用設定で `module=phiori.dll` 等を明示すると `descript.txt` を保全したまま選択できる。パッケージをOurinから自動インストールしない。

Sanaのサンプルではイベントをpublicメソッドを持つオブジェクトに定義し、`Sana.new(events)` とする。Ruby 4では `ostruct` gemが別途必要。UTF-8 transportに合わせて `$stdin.set_encoding('UTF-8')`、pipe応答をflushするため `$stdout.sync = true` を設定する。SanaJKのReference取得例は `ctx.request.headers.Reference(0)`。

KAGARIは `shiori,kagari.dll`（相対サブディレクトリも可）を同梱macOSエンジンへ解決する。ゴースト内のmacOSモジュールがあればそちらを優先する。辞書のload先は同梱dylibの場所ではなく、指定したSHIORIのディレクトリ。上流revision・依存の版とハッシュは `engines/PINNED_UPSTREAM.json` および `engines/kagari/` のmanifestに固定し、LICENSEとABI metadataをアプリへ同梱する。

cshioriの導入は [ビルド手順](../engines/cshiori/README.md)、Nimは [ビルド手順](../engines/shioridll-nim/README.md) を参照。どちらもOurinへの自動同梱は行わない。Nim上流のMIT宣言は保存済みだがリンク先全文は取得できず、配布準備は未完。

追加の手順: [emo-rs](../engines/emo-rs/README.md)、[shiorigo／Gohst](../engines/shiorigo/README.md)、[Rosalind](../engines/rosalind/README.md)。追加の手順: [aktk](../engines/aktk/README.md)、[dktrtk](../engines/dktrtk/README.md)、[D.N.Proxy](../engines/dnproxy/README.md)、[krht](../engines/krht/README.md)、[phiori](../engines/phiori/README.md)。[Kanahebi](../engines/kanahebi/README.md)、[csaori](../engines/csaori/README.md)、[lib_skeleton](../engines/lib_skeleton/README.md) の手順も参照。実測は [第2部](SHIORI_CONTINUATION_2026-10-26_PART2.md)／[第3部](SHIORI_CONTINUATION_2026-10-28_PART3.md)／[第4部](SHIORI_CONTINUATION_2026-10-28_PART4.md)／[第5部](SHIORI_CONTINUATION_2026-10-28_PART5.md)。

## Native ABI

Windows PE DLLとLinux ELFはmacOSで直接ロードできない。macOS Mach-Oモジュールと一致するCPU architecture・依存ライブラリが必要。

モジュール横の `<module名>.plist`（bundleならInfo.plist）で `OurinShioriABI` を指定する。

| 値 | 関数・メモリ契約 |
|---|---|
| `ourin` | 既存Ourinの4引数Bool返却request。入力は借用し、出力はshiori_free（無い場合free）で解放 |
| `ukagaka-long` | 2引数pointer返却request、長さはmacOS C long。入力はモジュールへ所有権移譲、出力はホストがfree |
| `ukagaka-int32` | 同上、長さは32bit整数 |
| `kagari` | kagari_load/request/unload、instance IDを保持する専用ABI |

宣言がなくても `shiori_request` は既存Ourin ABI、`kagari_request` はKAGARI ABIとして扱う。無印 `request` の署名を推測せず、明示宣言がなければロードを拒否する。モジュール側allocatorがmalloc/freeと互換でない場合、この標準ABI設定だけでは接続できない。標準ABIのload／unloadは整数の成功値を返す契約。

## 検証と再実行

- `ShiolinkTests`: 実C子プロセス、Unicode、GET／NOTIFY、load先、unload、設定優先順位、ハング・大量出力・EOF・同期違反・子回収。
- `NativeShioriABITests`: 32bit／C long ABI、load失敗、loadディレクトリ、曖昧ABI拒否、相対パス。in-processと別PIDのXPCで実C fixtureを実行。
- `KagariEngineTests`: 実同梱エンジン、instance ID fixture、load失敗、再load、通常factoryからの接続。
- 既存 `ShioriRuntimeTests`／`ShioriLoaderTests` を含む初回81件PASS。追加したfactory検証1件もPASS（KAGARI suiteを再実行）。
- `ShiolinkRealEngineTests`: 実Sana／SanaJKの2件PASS。独自の最小イベント辞書を使用し、第三者配布ゴーストの検証とは区別する。
- 同梱Luaモジュールの10項目PASS。実Lanes worker生成、Linda queue、子Lua stateへのghostごとのcwd／preload継承、MIME base64、既存複数instance／相対IO／Native SAORIも確認。
- 実配布「もす」のNARを一時領域へ展開して実KAGARIで検証。追加Nativeモジュールをghost内へ配置しないbundled-only方式で起動・会話・メニュー変更（30秒→1分）・終了・保存・別process再load後の値保持を確認。最小辞書／load失敗判定もPASS。元NARのSHA256は実行前後で一致。この時点で残ったSAORI `choice` のload警告は、第4部の独自互換SAORIとbackslash解決修正で解消した。
- 2026-10-25のSanaJK GUI試験はログ確認まで。2026-10-26は「もす」を実アプリの一時 `OURIN_TEST_BASE_DIR` で起動し、起動トーク・キャラクターの画面取得、実ダブルクリック入力→SHIORI応答→再生トークン、終了操作とsavedata生成を確認。利用者のインストール済みghostは使用していない。
- 初回element専用surfaceが出ない順序バグと、OnLanguageChangeのローカライズ言語名で辞書が一致しない問題を修正。初回画像とJapanese/Englishの通知を回帰試験で確認。
- 続行分の詳細は [2026-10-26検証記録](SHIORI_CONTINUATION_2026-10-26.md) を参照。

通常テストは外部パッケージを取得しない。実エンジン試験は、リポジトリ外のprefixに `sanajk@1.0.6 shiolinkjs@3.1.3` をnpm install、別のgem prefixに `sana:0.0.4 shiolink:0.0.2 ostruct` をgem installしたうえで実行する。言語本体はmacOS用を用意する。

```sh
TEST_RUNNER_OURIN_SHIOLINK_NPM_ROOT=/path/to/npm-prefix \
TEST_RUNNER_OURIN_SHIOLINK_GEM_ROOT=/path/to/gem-prefix \
TEST_RUNNER_OURIN_SHIOLINK_NODE=/absolute/path/to/node \
TEST_RUNNER_OURIN_SHIOLINK_RUBY=/absolute/path/to/ruby \
xcodebuild -project Ourin.xcodeproj -scheme Ourin \
  -parallel-testing-enabled NO \
  -only-testing:OurinTests/ShiolinkRealEngineTests test
```

prefix未指定時は実エンジン試験を明示skipする。実行環境だけ入っていてもエンジン依存が不足していれば失敗する。

## 一次資料

- [SHIOLINKの同期・load・unload](https://github.com/Narazaka/shiolinkjs/blob/master/lib/shiolink.ts)
- [cshioriのSHIOLINK実装](https://github.com/Narazaka/cshiori/blob/master/cshiolink.c)
- [aktk Windows entry point](https://github.com/kinokon/aktk/blob/master/aktk/dllmain.cpp)、[dktrtk](https://github.com/kinokon/dktrtk/blob/master/dktrtk/dllmain.cpp)、[krht](https://github.com/kinokon/krht/blob/master/krht/dllmain.cpp)
- [emo-rsのWindows限定exports](https://github.com/ekicyou/emo-rs/blob/master/src/windows.rs)
- [KanahebiのBRIDGE/1.0](https://github.com/kanadelab/Kanahebi/blob/master/ukastream/dllmain.cpp)
- [phioriの実行条件](https://github.com/Tatakinov/phiori/blob/master/README.md)
- [shioridll-nimのPOSIX実装](https://github.com/Narazaka/shioridll-nim/blob/master/shioridll.nim)

上流branchリンクは調査用参照。同梱コードの固定revision・ライセンス管理はmanifestを基準とする。
