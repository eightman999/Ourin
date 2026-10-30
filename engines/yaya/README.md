# 公式YAYA最新版のmacOSエンジン

2026-10-30に[公式GitHub Releases](https://github.com/YAYA-shiori/yaya-shiori/releases/latest)とAPIを確認した最新版は、**Tc607-2**（2026-10-19公開、draft=false / prerelease=false）です。[固定release](https://github.com/YAYA-shiori/yaya-shiori/releases/tag/Tc607-2)、revision `21b6c8317bd68561286c2109673f178f1d12173b` を使用します。600 branchのrelease後の未公開変更は含めません。

```sh
python3 engines/yaya/build.py
python3 engines/aya/build.py
python3 engines/yaya/package.py --destination /absolute/engine-stage
```

`build/engines/yaya/libyaya.dylib` と `build/engines/aya/libaya5compat.dylib` はmacOS 13以降を対象とするUniversal2です。`--arch arm64` / `--arch x86_64` と `--output` / `--cache` も指定できます。既存Apple Command Line Toolsを標準でコマンド単位選択します。別toolchainは `--developer-dir` で指定します。Xcodeの利用規約への同意やsystem設定の変更は行いません。

Ourin独自の `yaya_core` を更新・置換するものではなく、公式C++ interpreterを別のSHIORIエンジンプラグインとしてビルドします。公式のmacOS Makefileと全49ソース（SQLite・Gumbo等のC部分を含む）を使います。5つの正規submodule、revision、取得archive SHA256を `UPSTREAM.json` へ固定します。sourceのCP932/CRLFを保持し、公式Makefileの厳密なUTF-8変換でコンパイルします。標準library以外の動的依存はmacOSのlibiconvのみです。

## 移植境界とABI

`multi_loadu(char*, long) -> long`、`multi_request(long, char*, long*) -> char*`、`multi_unload(long) -> int` を使い、ABIは `yaya` と明示します。正のC long instance IDごとにVMを保持し、load/request入力はengineへ所有権を渡します。応答はhostがfreeします。旧single APIで複数ghostを同じVMへ上書きしません。

Tc607-2のPOSIX requestは、正常経路で受領bufferを解放していません（Windows側とPOSIX早期エラー経路は解放しています）。文字列へコピーした直後のfreeと、無効なmulti IDの入力回収を境界で追加します。parser、VM、組み込み関数、`aya_version` やversion応答は変更しません。AYA5構成の名前探索は[AYA5互換variant](../aya/README.md)を参照してください。

`LICENSE`（BSD-3-Clause）、AYA5原本のghost用途ライセンス、各依存の全文・noticeを出力の `licenses/` へ保持します。原本Windows DLLや配布ghostをパッケージへ含めません。`BUILD.json` は実compiler・CPU・最低OS指定・移植差分・成果物hashを記録します。

## 検証の範囲

`example/` は実parser/VMを使う自作辞書です。versionは固定文字列ではなく公式の `GETSETTING(0)`、nameは `GETSETTING(3)` から取得します。GET/NOTIFY、日本語・emoji、正規表現、変数保存、再ロード、別process、複数VMの独立性とCP932も確認します。公式 `tests/posix_smoke.c` は未改変のまま出力に保持し、公式の機能差分試験として実行できます。

AYA/YAYAは辞書がrequest関数とSHIORI protocol応答を実装します。出力wireの文字コードは `charset.output` 設定に従うため、Shift_JIS辞書の検証ではホスト側wire設定も一致させます。Windows専用API、任意のWindows SAORI、全第三者ghost、Intel実機・古いmacOS実機の互換性まで検証済みとは扱いません。
