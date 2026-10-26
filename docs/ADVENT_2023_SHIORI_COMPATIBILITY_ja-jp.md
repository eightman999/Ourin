# Advent Calendar 2023掲載SHIORIの互換性

更新: 2026-10-25

対象は[Tatakinov氏の記事](https://gist.github.com/Tatakinov/cbaabd07069161e316a690b0e1ccbb69)の16種類。記事は2023年時点の紹介であり、Ourinでの動作保証ではない。

この作業ツリーにSHIOLINK外部プロセス接続、Native ABIの分離、KAGARIのUniversal 2同梱を追加した。全16エンジンのmacOS移植や全配布ゴーストの動作確認は完了していない。

## 接続経路と残件

| SHIORI | 確認した接続方式・条件 | 状態・残件 |
|---|---|---|
| [aktk](https://github.com/kinokon/aktk) | Windows HGLOBAL ABI、mruby | POSIX移植とmacOS実モジュールが必要 |
| [csaori](https://github.com/ukatech/csaori) | SAORI／PLUGIN作成ライブラリ | SHIORIとしての実装とmacOS移植が必要 |
| [cshiori](https://github.com/Narazaka/cshiori) | C製parser／builder、cshiolinkによるSHIOLINK実装 | macOS用executableと実辞書の検証が必要 |
| [dktrtk](https://github.com/kinokon/dktrtk) | Windows HGLOBAL ABI、AngelScript | POSIX移植とmacOS実モジュールが必要 |
| [D.N.Proxy](https://github.com/nikolat/dnproxy) | .NET Framework、Windows DLLの逆P/Invoke | macOS向けhost／runtimeの移植が必要 |
| [emo-rs](https://github.com/ekicyou/emo-rs) | Rust＋Lua、C exportsはWindows限定 | POSIX exportsとメモリ契約の移植が必要 |
| [kagari](https://github.com/Tatakinov/kagari_shiori) | instance ID付きPOSIX ABI | 固定版の実エンジンで起動・要求・終了・再load、in-process／XPCを確認。配布ゴースト「もす」は `lanes.core` 不足でload失敗。保存・再起動は未確認 |
| [Kanahebi](https://github.com/kanadelab/Kanahebi) | IronPython、.NET Framework 4.7.2、ukastream BRIDGE/1.0 | SHIOLINKとは別のtransportとmacOS runtime移植が必要 |
| [krht](https://github.com/kinokon/krht) | Windows HGLOBAL ABI、Tcl | POSIX移植とmacOS実モジュールが必要 |
| [lib_skeleton](https://github.com/Tatakinov/lib_skeleton) | SHIORI Request／Response型等の作成基盤 | 完成SHIORIとmacOS entry pointが必要 |
| [phiori](https://github.com/Tatakinov/phiori) | Windows HGLOBAL ABI、Python 3.12 Windows 32bit配布 | Python embeddingを含むPOSIX移植が必要 |
| [Rosalind](https://github.com/as-is-prog/rosalind) | SHIOLINK、.NET Framework 4.6以上 | 接続経路を追加。macOSで実エンジンを起動できる構成は未確認 |
| [sana](https://github.com/Narazaka/sana) | SHIOLINK＋Ruby | sana 0.0.4／shiolink 0.0.2の実パッケージで起動・日本語会話・NOTIFY・保存・再loadを確認。配布ゴーストは未検証 |
| [sanajk](https://github.com/Narazaka/sanajk) | shiolinkjs＋Node.js | sanajk 1.0.6／shiolinkjs 3.1.3の実パッケージで起動・日本語会話・NOTIFY・保存・再loadを確認。配布ゴーストは未検証 |
| [shioridll-nim](https://github.com/Narazaka/shioridll-nim) | POSIX分岐あり、C long長の標準ABI | Nim allocatorとmalloc/free契約の互換、macOS実モジュールを要確認 |
| [shiorigo](https://github.com/Narazaka/shiorigo) | Go用parser／builder | SHIOLINK hostを備えた実ゴーストでの検証が必要 |

## 導入

SHIOLINKの設定と制限は[SHIOLINK接続](SHIOLINK_ja-jp.md)を参照。macOSで動くNode.js／Ruby等の実行環境とエンジンを別途用意する。ゴーストのWindows設定を保全するため、同じ場所に `SHIOLINK.ourin.ini` を作成できる。パッケージをOurinから自動インストールしない。

Sanaのサンプルではイベントをpublicメソッドを持つオブジェクトに定義し、`Sana.new(events)` とする。Ruby 4では `ostruct` gemが別途必要。UTF-8 transportに合わせて `$stdin.set_encoding('UTF-8')`、pipe応答をflushするため `$stdout.sync = true` を設定する。SanaJKのReference取得例は `ctx.request.headers.Reference(0)`。

KAGARIは `shiori,kagari.dll`（相対サブディレクトリも可）を同梱macOSエンジンへ解決する。ゴースト内のmacOSモジュールがあればそちらを優先する。辞書のload先は同梱dylibの場所ではなく、指定したSHIORIのディレクトリ。上流revision・依存の版とハッシュは `engines/PINNED_UPSTREAM.json` および `engines/kagari/` のmanifestに固定し、LICENSEとABI metadataをアプリへ同梱する。

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
- 同梱Luaモジュールの9項目（複数instance／cwd分離／相対IO／子process／Native SAORI等）PASS。
- 実配布「もす」のNARを一時領域へ展開して実KAGARIで検証。最小辞書・再load・load失敗判定はPASS、実辞書は `lanes.core` 不足でFAIL。元NARのSHA256は実行前後で一致。
- 実アプリを一時 `OURIN_TEST_BASE_DIR` で起動し、SanaJKのOnBoot・OnSecondChangeをログ確認。画面取得はcomputer-useのtimeoutで失敗したため、表示・実ダブルクリックは未確認。

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
