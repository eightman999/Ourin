# 華和梨（KAWARI）のmacOSプラグイン用エンジン

[ukatech/kawari](https://github.com/ukatech/kawari) と上流が指定する実submodule [uka_regexp](https://github.com/ukatech/uka_regexp) を、revisionとアーカイブSHA256で固定してビルドします。辞書を別実装へ変換せず、実KAWARI interpreterを使用します。

```sh
bash engines/kawari/build.sh
# 任意の出力先、またはthin版
python3 engines/kawari/build.py --output /absolute/path --arch arm64
```

標準出力は `build/engines/kawari/libkawari_shiori.dylib`（arm64/x86_64 Universal2、macOS 13以降）とABI sidecar `.dylib.plist` です。Apple Clang・SDK・Python 3が必要です。外部package managerは使いません。取得cacheは `build/deps/kawari/`。取得済みアーカイブは `--archive` / `--regexp-archive` で渡せ、必ず固定hashを再検証します。

元ソースの変更はありません。上流 `files.mak` のSHIORI/core/native-SAORI 48ソースをC++14でコンパイルし、macOSのiconvをリンクします。上流の `loadu`、`request`、`unload` を `ukagaka-long` ABI（C long長、malloc/free所有権）で呼びます。上流のloadは辞書がない場合も成功を返すため、空ディレクトリをロード失敗と見せかけません。

KAWARIとuka_regexpのライセンス本文はそれぞれ `LICENSE.kawari`（BSD-2-Clause）、`LICENSE.uka_regexp`（Unlicense）へ保存します。`BUILD.json` に全ソースのSHA256、実compiler、CPU slices、成果物hashを記録します。プラグイン化するときはdylib、ABI metadata、両noticeをまとめて配置します。

`KawariEngineTests` は本番Factory/XPCと直接Nativeローダーで、相対サブディレクトリと日本語load path、日本語/絵文字応答、GET/NOTIFY、終了、保存、再ロードを確認します。標準build出力を使い、`OURIN_KAWARI_ENGINE` で別のdylibも指定できます。Factory試験は使い捨てghostへローカルmacOS moduleを置き、元のWindowsモジュール指定を維持して通常の代替検索から接続します。`example/kawarirc.kis` は自作の最小辞書です。第三者配布ゴースト全体、Windows依存SAORI、Intel実機や古いmacOS実機の互換性を保証する試験ではありません。
