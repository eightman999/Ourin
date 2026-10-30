# lib_skeleton のNative SHIORI開発サンプル

[lib_skeleton](https://github.com/Tatakinov/lib_skeleton) はprotocol用ライブラリです。完成した汎用SHIORIエンジンや既存辞書互換層ではありません。この導線は実上流の `shiori::Request::parse` と `shiori::Response` を使う自作SHIORIサンプルをビルドします。

```sh
python3 engines/lib_skeleton/build.py
```

上流revision・アーカイブSHA256・MIT本文を固定・保存します。取得済みアーカイブは `--archive /absolute/path.tar.gz`、出力先は `--output` で指定できます。Apple clang++のC++20対応が必要です。追加ライブラリやsystem設定変更は不要です。上流ヘッダには変更を加えません。

出力は `build/engines/lib_skeleton/libskeleton-shiori.dylib` と、ABI宣言の `.dylib.plist`。両方をゴーストの `ghost/master` へ置き、`shiori,skeleton-shiori.dll` を指定すると、Ourinの既存NativeローダーがmacOS dylibを見つけます。ABIは `ukagaka-long`（公開bufferはmalloc/free、lengthはlong、load/unloadはint32）です。既定はXPC隔離で、追加Factory caseは不要です。

サンプルの自作イベントは `version`、`name`、日本語 `OnBoot`、`OnEcho`（Reference0）、`OnSparse`（Reference2）です。要求のprotocol解析・ヘッダ解析・応答の電文化は実ライブラリが行い、別の簡易parserへ置き換えていません。load/unloadのファイルは検証用markerです。辞書読込みや既存ゴーストのイベント群を実装したものではありません。

`LibSkeletonEngineTests` は本番Factory経由のロード・別PID、日本語・絵文字・NOTIFY、終了・再ロード、raw要求による疎Referenceと不正protocolの400応答を検証します。未ビルド時はopt-in試験を明示的にskipします。`BUILD.json` は使用した実ヘッダのhashとコンパイラ版を記録します。自動同梱・配布は追加しません。
