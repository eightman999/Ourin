# Aosora（蒼空）のローカルエンジンプラグイン

[kanadelab/aosora-shiori](https://github.com/kanadelab/aosora-shiori) の固定版C++20 interpreterと、同じarchiveに含まれるjsoncpp 1.9.6を実際にビルドします。

```sh
python3 engines/aosora/build.py
```

出力は `build/engines/aosora/libaosora.dylib` とABI sidecar（`OurinShioriABI=aosora`）。標準はmacOS 13以降のUniversal2（arm64/x86_64）で、`--arch arm64` 等も選べます。Apple Clang・SDK・Python 3のみ必要です。上流既定のデバッガMD5機能は無効のため、Makefileで列挙されるOpenSSLは実際には必要ありません。jsoncppは上流同梱ソースを使い、外部package managerを使いません。

上流revision・SHA256を `UPSTREAM.json` に固定します。`--archive` / `--cache` / `--output` で取得済みarchive・cache・出力先を指定できます。archiveのWindows SSP treeや配布ghostは展開・同梱せず、interpreter/POSIX entry/jsoncpp/通知だけを使用します。

POSIX ABIは `aosora_load(char*, long) -> long instanceId`、`aosora_request(long instanceId, char*, long*) -> char*`、`aosora_unload(long)`。公開bufferはmalloc/freeで所有権を移し、instance IDは正のC longです。上流POSIXのunloadが `Shiori::Unload()` を呼ばないため、元の `SaveData::Save` が実行されず保存されないことを再現しました。Windows側と同様に、instance破棄前に `Unload()` を呼ぶ1箇所だけを変更し、保存・再ロードを検証します。辞書への変更や保存機能の代替実装はしません。

**上流はsourceの利用を、個別の許可がある場合を除き個人利用・プロジェクト参加に限定しています。** このビルドとプラグインは利用者のローカル用途です。Windows版の配布許可をこのmacOS移植版の再配布許諾と解釈しません。元の `license.txt` とREADME、jsoncppの通知を出力へ保全します。

`AosoraEngineTests` は最小の自作 `.as` 辞書を本番Native/XPC/Factory経路から実行し、日本語/絵文字、NOTIFY、不正要求、終了、保存、再ロードを検証します。第三者配布ghost、Windows専用Aosoraプラグイン・SAORI、デバッガ接続、Intel実機や古いmacOS実機は未確認です。
