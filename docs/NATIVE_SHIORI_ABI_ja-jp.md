# ネイティブ SHIORI の ABI

[English](NATIVE_SHIORI_ABI_en-us.md)

更新: 2026-10-25。開発版の実装契約。公開済みバイナリの対応を示すものではありません。

## macOS用モジュールの選択

`descript.txt` でWindows用の `shiori` を維持したまま、macOS用モジュールを明示できます。

```text
shiori,yaya.dll
shiori.macos,native/libyaya.dylib
```

空でない `shiori.macos` を通常起動・再ロードの両方で優先します。パスは `ghost/master` からの相対指定で、Windowsの `\` 区切りも受け付けます。`yaya` などの名前でも明示選択したファイルをNative経路で読み、同梱helperへ置換しません。空欄は従来の `shiori` へ戻り、指定ファイルが無い場合はロード失敗になります。辞書ディレクトリは選択したモジュールの親フォルダです。下記ABI宣言も必要です。

同梱互換エンジンを自動選択する場合は `shiori.macos` を追加せず、元の `shiori` を使います。[追加栞の手順と制約](ADDITIONAL_SHIORI_ja-jp.md)を参照してください。

## 宣言

macOS の `.bundle` / `.plugin` は `Contents/Info.plist`、単体ライブラリはファイル名に `.plist` を追加した隣接ファイル（例: `engine.dylib.plist`）に `OurinShioriABI` を指定します。

```xml
<key>OurinShioriABI</key>
<string>ukagaka-int32</string>
```

| 値 | load | request | unload |
|---|---|---|---|
| `ourin` | `bool(const char *)` | `bool(const unsigned char *, size_t, unsigned char **, size_t *)` | `void(void)` |
| `ukagaka-long` | `int32_t(void *, long)` | `void *(void *, long *)` | `int32_t(void)` |
| `ukagaka-int32` | `int32_t(void *, int32_t)` | `void *(void *, int32_t *)` | `int32_t(void)` |
| `kagari` | `int32_t(void *, long)` → instance ID | `void *(int32_t id, void *, long *)` | `int32_t(int32_t id)` |

`ukagaka-long` の `long` は macOS の64bit整数です。`kagari` は [KAGARI POSIX ビルド](KAWARI_KAGARI_ENGINES_ja-jp.md) の `kagari_load` / `kagari_request` / `kagari_unload` 専用で、標準 2 引数 `request` とは別契約です。Windows由来の32bit長さを使用する移植版には `ukagaka-int32` を使用します。これは SHIORI 用のキーであり、SAORI等の `OurinModuleABI` とは別の契約です。

宣言がない場合は、既存の `shiori_request` を持つ Ourin 独自ABIのみ受け付けます。無印の `request` は署名を推測せず拒否します。不明な宣言値もロードエラーになります。

## シンボルと所有権

`loadu` を優先し、`shiori_loadu`、`loadu`、`shiori_load`、`load` の順に探索します。要求は `shiori_request` / `request`、終了は `shiori_unloadu` / `unloadu` / `shiori_unload` / `unload` です。`load` と `unload` は省略可能で、存在する `load` が失敗を返すとロード全体を失敗にします。

- `ourin`: 入力はホスト所有で、関数から戻るまで有効です。応答はホストが複製し、`shiori_free`、なければ libc `free` で解放します。
- `ukagaka-*`: load/request の入力は NUL 終端した `malloc` 領域で、所有権をモジュールへ渡します。長さに NUL は含みません。request の長さは入出力引数です。応答はモジュールが `malloc` で確保し、ホストが複製後 `free` します。
- 負の応答長と64 MiBを超える応答は拒否します。これで不正なネイティブコード全般を安全にできるわけではありません。

## 辞書ディレクトリとプロセス

実行ライブラリの保存場所と `load` のディレクトリは別値です。ゴースト起動時は `ghostRoot` と元の `shiori` 相対パスから辞書ディレクトリを決め、UTF-8・末尾 `/` 付きで渡します。`loadu` が無い `load` にもUTF-8を渡す契約です。旧ACP/Shift_JISパス専用モジュールは変換wrapperが必要です。KAGARI の instance ID 付き ABI は `OurinShioriABI` = `kagari` で明示する。

単体ロードAPIで `loadDirectory` を省略するとライブラリの親ディレクトリです。

アプリ内とXPCサービスは同一の `NativeShioriModule` を使います。既定のXPC隔離で接続やロードに失敗しても、アプリ内ロードへ自動的に切り替えません。SHIORI/2.xの変換は既存adapterが担当します。ABI対応だけで個々の栞や辞書の互換性が確認できたことにはなりません。

## 検証

`NativeShioriABITests` は標準ABIの2種類を実Cライブラリとしてビルドし、GET/NOTIFY、辞書パス、unload、ロード失敗、宣言不足、XPCの別PIDを検証します。既存独自ABIの回帰は `ShioriLoaderTests` の `nativeDylibFixture*` で検証します。

翻訳: Codex。日英内容照合: 2026-10-25。実行結果は各検証レポートを参照してください。
