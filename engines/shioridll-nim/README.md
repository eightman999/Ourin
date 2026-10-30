# shioridll-nim の macOS Native ビルド

[shioridll-nim](https://github.com/Narazaka/shioridll-nim) はNimでSHIORIを作るためのDLLインターフェースです。固定上流を実際のNim Compilerでコンパイルし、Ourinの既存Native SHIORI接続へ渡します。

```sh
python3 engines/shioridll-nim/build.py
# 元のarm64出力先を保持してIntel用を別prefixへ
python3 engines/shioridll-nim/build.py --arch x86_64 --output build/engines/shioridll-nim-x86_64
# 両sliceを持つUniversal2 dylib
python3 engines/shioridll-nim/build.py --arch universal2 --output build/engines/shioridll-nim-universal2
```

`UPSTREAM.json` に固定した公式Nim 2.2.4 macOS arm64バイナリとshioridllのアーカイブを取得し、SHA256を照合してからビルドします。Nimはビルド用一時ディレクトリだけに展開し、終了時に破棄します。システムへのインストール、PATHの変更、nimbleパッケージ導入は行いません。ユーザー・親ディレクトリ・プロジェクトのNim設定も読みません。`--mm:arc --threads:on --tlsEmulation:off` を固定し、直列呼出しの間にホストpthreadが切り替わる場合も扱います。外部Nimble依存はなく、標準ライブラリとランタイムは固定コンパイラ配布物に含まれます。

取得済みアーカイブを使う場合は `--archive /absolute/shioridll.tar.gz --compiler-archive /absolute/nim.tar.xz` を指定できます。この場合もハッシュを照合します。Nimの公式ダウンロードページに掲載された `.sha256` URLは取得時404だったため、コンパイラの固定ハッシュは公式配布バイナリの実ダウンロード値です。ビルド用コンパイラ自体はmacOS arm64バイナリのため、ビルドhostは引き続きarm64 Macです。出力は `--arch arm64`（default）、`--arch x86_64`、`--arch universal2` を選べます。Nimのtarget CPUとApple Clangのarchitectureを明示して各sliceをコンパイルし、Universal2はlipoで両sliceをまとめます。出力のsliceをlipoで検査し、各dylibのIDは `@rpath/ライブラリ名` に固定します。既存arm64成果物を保つ場合は、上のように別の `--output` を指定してください。今回のIntel/Universal2検証も別prefixへ出力しています。

出力先は `build/engines/shioridll-nim/`（`--output` で変更可）。

- `libupstream-basic.dylib`: 上流 `example/basic.nim` のイベント本文をバイト単位で保ってビルド。
- `libnimshiori.dylib`: 実shioridllをimportする自作の日本語・Unicode往復用callback例。
- 各 `.dylib.plist`: `OurinShioriABI=ukagaka-long` の明示的ABI宣言。
- `BUILD.json`: 実コンパイラの版・revision、target slices、builder architecture、SDK/Clang、deployment target、上流サンプルのhash。
- 上流宣言、改変したABIソース、NimのMITライセンス本文。

上流shioridllはMITを宣言していますが、リンク先の全文サイトが取得時到達不能でした。出力には確認できた上流の宣言・参照先を保持し、未取得の全文を取得済みとは扱いません。配布用同梱はこのスクリプトの対象外です。

## Ourin での利用

ゴーストの `ghost/master` に `libnimshiori.dylib` と同名の `.dylib.plist` を置き、`descript.txt` に次を指定します。

```text
shiori,nimshiori.dll
```

Ourinが既存のmacOSモジュール代替検索からロードします。新たなFactory caseや曖昧なABI推測は追加しません。上流ソース側のPOSIX移植差分は [PATCHES.md](PATCHES.md) に記録しています。独自ゴーストを作る場合は自分のcallbackをビルドしてください。

`NimShioriEngineTests` は上流未改変サンプルと日本語例を標準Factoryから起動し、GET、日本語・絵文字Reference往復、NOTIFY、loadディレクトリ、unload、reloadを確認します。先に上記をビルドしてください。出力先を変えた場合は `OURIN_NIM_SHIORI_PRODUCTS` で指定できます。未ビルド時はopt-inテストを明示的にskipします。

## Intel / Universal2 の検証

2026-10-28、arm64 Macの既存Rosettaで、thin x86_64とUniversal2のx86_64 sliceを実行しました。`probe/NativeProbe.swift` を本番 `Ourin/USL/NativeShioriModule.swift` と共にIntel向けSwift CLIへコンパイルし、実Nimモジュールのロード・日本語/絵文字・NOTIFY/OnClose・unload/reloadを2周、新規foreign pthread上の要求を繰り返し確認しました。同一processで上流basicも同時に保持し、別モジュールへの干渉も確認しています。CLI内の `sysctl.proc_translated=1` はRosetta実行の証拠です。Universal2のarm64 sliceも同じ本番ローダーprobeで回帰しました。

```sh
swiftc -target x86_64-apple-macos13.0 Ourin/USL/NativeShioriModule.swift engines/shioridll-nim/probe/NativeProbe.swift -o /tmp/nim-native-probe-x86_64
/usr/bin/arch -x86_64 /tmp/nim-native-probe-x86_64 "$PWD/build/engines/shioridll-nim-universal2"
```

ARC・thread有効・native TLSの修正は両sliceで同じです。`NimShioriEngineTests` にUniversal2を本番Factoryから起動する回帰と、Intel Swift CLIで本番ローダー/foreign threadを動かすoptional testを追加しています。Universal2出力を変える場合は `OURIN_NIM_SHIORI_UNIVERSAL_PRODUCTS` を指定します。Apple SiliconでRosettaが利用できなければIntel testはskipし、追加インストールは行いません。Factory/XPCの検証と、独立CLIによるABI/thread検証は別の層です。

ビルドの最低OS指定は従来どおり13.0、検証SDKは26.5です。Intel実機と古いmacOS実機の動作は未検証であり、SDKでのビルドやRosetta上の成功を、その実機動作確認として扱いません。配布用同梱やsystem installは追加していません。
