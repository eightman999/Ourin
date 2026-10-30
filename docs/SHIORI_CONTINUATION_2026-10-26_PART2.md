# SHIORI対応・続行第2部

確認日: 2026-10-26。[全16種の状況](ADVENT_2023_SHIORI_COMPATIBILITY_ja-jp.md)。今回の実装はオプションでビルドする3エンジンと回帰試験であり、Ourinへ言語runtimeや任意のWindows DLLを自動導入する変更ではない。

## 今回の追加

| 対象 | 実装と確認 |
|---|---|
| emo-rs | 固定上流Rust/Lua本体＋shiori3 parser。POSIX C long ABI、UTF-8、検索path区切りを移植。上流frameworkの存在しないshiori.cts参照をlibs.ctsへ修正し、利用者イベント辞書は変えていない。本番Factory→Native XPCでOnBoot、OnTranslateの日本語・絵文字、NOTIFY、unload保存・再load後の初回値保持を確認 |
| shiorigo／Gohst | 固定parserと実配布Gohstのrequesthandlersをバイト未変更でビルド。Windows/cgo entryとWin32 loggerをSHIOLINK hostへ置換。本番Factoryから日本語OnBoot／OnClose、resource、NOTIFY、会話counter、子回収、再processを確認。上流OnUnloadは保存を行わず、保存拡張は追加していない |
| Rosalind | 上流に既存のmodern .NET C#実装を採用。SDK 10.0.401でnet10.0へretarget、Costura除去、POSIX CRLF/LF・EOF・flushを修正。実Rosalind/Roslynで自作C# scriptを実行し、Unicode会話、GET/NOTIFY、Boots保存値1→2、別process再load、要求途中EOFでも保存・終了コード0を確認 |

手順・固定版・制限: [emo-rs](../engines/emo-rs/README.md)、[shiorigo](../engines/shiorigo/README.md)、[Rosalind](../engines/rosalind/README.md)。上流archiveはrevision＋SHA256、Rust依存はCargo.lock、NuGet依存はlock＋contentHash、Goはローカル固定moduleで解決する。コードとビルド出力へLICENSE/NOTICE情報を保持する。全第三者素材の再配布準備完了を意味しない。

## 実行検証

- 3種類とも固定入力から実compilerでビルド成功。
- `EmoRustEngineTests`、`GoShioriEngineTests`: Xcode **2 test PASS、skip 0**。
- `RosalindEngineTests`: Xcode **2 test PASS、skip 0**。正常会話に加えて不完全要求のEOFを検証。
- emo-rsの上流OnClose／resource versionは未実装で204となる。テスト用の200応答へ置換せず、上流の状態コードを保持する。保存は上流unload処理。
- emo-rsの実アプリを一時OURIN_TEST_BASE_DIRで起動。通常factoryのkind=native、OnBootの「起動トークです。」応答とscript再生、scope1キャラクターの画面を確認。画像はOurinの既存DefaultGhostを使った検証用fixtureで、「えも？」の実配布シェル試験ではない。Ourinメニューから正常終了し、save.lua生成を確認。

証拠: `/tmp/ourin-shiori-next-20261026/xcode-engines.log`、`xcode-rosalind.log`、`emo-build.log`、`gui-emo.log`、`gui-base/ghost/emo/ghost/master/profile/emo/save/save.lua`。利用者のインストール済みghostは検証対象にしていない。

## 後続の状況

2026-10-26時点ではD.N.Proxy、aktk、dktrtk、krht、phiori、Kanahebiの移植が残っていた。続く実装・検証の結果と、現在の制限は [第3部](SHIORI_CONTINUATION_2026-10-28_PART3.md) と [全体表](ADVENT_2023_SHIORI_COMPATIBILITY_ja-jp.md) に記録する。

commit、push、本番配布は実行していない。
