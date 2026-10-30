# CSAORIのNative SHIORI開発サンプル

[CSAORI](https://github.com/ukatech/csaori) はSAORI/PLUGINを作る基盤です。完成した汎用SHIORIエンジンではありません。上流 `CSAORIInput::parseString` と `CSAORIOutput::toString` を実際にコンパイルし、SHIORIのprotocol定数を指定した自作subclassから利用する開発サンプルを提供します。

```sh
python3 engines/csaori/build.py
```

固定上流アーカイブのrevisionとSHA256を `UPSTREAM.json` で検証します。取得済みアーカイブは `--archive /absolute/path.tar.gz`、出力先は `--output` で指定できます。必要なのはApple clang++と標準C++ライブラリです。アーカイブ内の辞書・他のSAORI・DLL等はビルドに使いません。

元のWindows DLL entry、GUI、path補助を含む移植ではありません。上流のparser/builder関数と、その関数が使う実getLine・status文字列・charset文字列処理を抽出してコンパイルします。独自parserに置き換えていません。公開インターフェース側のUTF-8と上流string_t/wstring間を標準C++変換で接続します。サンプルの対応文字コードはUTF-8です。

POSIXで必要な変更は、Windowsの型宣言とwide文字列関数名の対応、swprintfへのbuffer長追加、constructorによるprocess全体のlocale変更の抑止です。Windows専用メソッドの宣言は残っていても、その実装は含まれません。CSAORIの全APIをmacOSへ移植したものではありません。UTF-8変換にはC++17で利用できる互換APIを使っており、現在のClangではdeprecated警告が出ます。

出力は `build/engines/csaori/libcsaori-shiori.dylib` とABI sidecar `.dylib.plist`。両方をゴーストの `ghost/master` へ置き、`shiori,csaori-shiori.dll` を指定すると、Ourinの既存Native/XPC経路へ接続できます。ABIは `ukagaka-long` で、追加Factory caseは不要です。

自作イベントは `version`、`name`、日本語OnBoot、Reference0のecho、Reference2の疎なecho、NOTIFYです。上流に同じSHIORIの完成例は無いため、これらは自作sampleと明示します。任意の既存CSAORI DLLやゴーストが動くという互換性主張ではありません。

`CsaoriEngineTests` は本番Factoryと別PIDのXPCを使い、日本語・絵文字・NOTIFY、終了・再ロード、実parserの疎Referenceと不正protocol400を確認します。未ビルド時はopt-inとしてskipします。`BUILD.json` に実source hashとコンパイラ版を保存します。

上流の配布条件はreadme.txtにあるゴースト用途条件／修正BSDです。本文をそのまま `LICENSE.csaori-readme.txt` として保存します。sample自身のライセンスと、使うライブラリの条件は区別してください。アプリへの自動同梱や配布は追加しません。
