# SHIORIエンジンプラグイン

2026-10-30。SHIORIの追加実装と、その実行環境をまとめて導入するための `.plugin` パッケージです。Finderでは1つのファイルとして表示され、展開せずにOurinへ導入できます。伺かのPLUGINイベントAPIとは別の機能です。YAYA・里々・KAGARIの既存内蔵経路を維持します。

追加パッケージは**22個（実行用17・開発用サンプル5）**です。公式YAYA Tc607-2、AYA5互換構成、なし栞の移植版を追加しました。Ourin 0.2.0では、許諾済みの新3種を[配布DMG](https://github.com/eightman999/Ourin/releases/download/v0.2.0-beta.1/Ourin-SHIORI-0.2.0.dmg)として提供します。全22パッケージの一括配布ではありません。

## Ourin・栞・MAKOTO・SAORIの役割

Ourinは、SSPに相当する**ベースウェア本体**です。クリックや時刻のイベントをSHIORIへ送り、返ってきた桜スクリプトを解析して文字・表情・画像・アニメーションへ反映します。YAYAなどのSHIORIは、辞書から応答を作るエンジンです。この`.plugin`はそのSHIORIを追加する仕組みです。

表示前の順序は「SHIORI応答 → 環境変数展開 → 同じSHIORIのOnTranslate → ゴースト側MAKOTO → シェル側MAKOTO → Ourinで桜スクリプト再生」です。MAKOTOは任意の変換器で、すべてのSHIORI要求を中継する必須部品ではありません。

SAORIは主にSHIORIから必要時に呼ぶ補助機能です。Ourin本体からイベントを受け取るPLUGINイベントAPIとも区別します。SAORIやMAKOTOのWindows DLLも、macOSで利用可能な実装や接続経路が必要です。

## 導入

1. Ourinの「プラグインを探す・管理…」を開き、「SHIORIエンジン」を選びます。
2. 「プラグインを導入…」で、生成した `kawari.plugin` などのファイルを選びます。
3. 対象ゴーストを再起動します。

複数のエンジンやemoのvariantを使い分ける場合は、導入済みエンジンの「ゴーストに使用…」で対象フォルダを選びます。割当はOurin側の設定へ保存し、「自動選択に戻す…」で解除できます。元の辞書・descriptorには書き込みません。

追加先はOurinの基準フォルダ内の `shiori-engines/<id>.plugin/`。通常は `~/Documents/Ourin/shiori-engines/` です。テストでは `OURIN_TEST_BASE_DIR`、エンジン探索だけの指定には `OURIN_SHIORI_ENGINE_PLUGINS` を使えます。導入処理は既存IDを上書きしません。インポート時にはbundle情報・engine.json・相対パス・パッケージ外へのsymlinkを検証し、コピー後にも確認します。旧形式のフォルダとZIPの導入にも対応します。

ゴーストの `descript.txt`、辞書、元のWindows DLLを変更しません。ゴースト自身のmacOSモジュールと `SHIOLINK.ourin.ini` を優先します。通常のDLL名から追加エンジンを選び、汎用の `shiori.*` / `SHIOLINK.*` は辞書マーカー・元のコマンド指定も照合します。複数候補が一致した場合は推測で選びません。

## パッケージの範囲

| パッケージ | 内容 |
|---|---|
| YAYA Tc607-2 | 2026-10-30に公式最新版stableを確認。固定公式source＋5依存、Universal2/macOS13以降、multi-instance POSIX ABI |
| AYA5互換（YAYA Tc607-2） | 同じ公式YAYAを使い`aya.txt` / `aya5.txt`を探索。Universal2/macOS13以降。原本AYA5やAYA1〜4の実装ではない |
| なし栞 1.0.4-alpha系（macOS移植） | 許諾された公式mainの実interpreterをSHIOLINK子processで実行。Universal2/macOS13以降、`ghost.json`と保存に対応。上流version応答1.0.0は保持 |
| 華和梨（KAWARI） | 固定上流・正規uka_regexp、Universal2、標準C long ABI |
| Aosora | 固定上流・同梱jsoncpp、Universal2、instance ID付きPOSIX ABI。終了時の保存欠落を境界で修正 |
| aktk / dktrtk / krht | 実mruby / AngelScript / TclとSHIOLINK host。Tcl標準ライブラリも同梱 |
| emo-rs / emo-rs-lua54 | LuaJIT版とLua5.4版。`emo.dll` の自動選択は配布「えも？」で使うLua5.4版 |
| D.N.Proxy / Kanahebi / Rosalind | 実エンジン、コンパイラ・IronPython等の依存、.NET runtimeを同梱。外部dotnet不要 |
| MiyoJS / SanaJK / Sana / phiori | 実エンジンpackageとNode.js / Ruby / Pythonの実行環境・標準ライブラリを同梱 |
| cshiori / shioridll-nim / shiorigo / csaori / lib_skeleton | コンパイル済みの開発用サンプル・通知。任意のWindowsゴーストの代替として自動選択しない |

C/C++/Nim/Goでイベント処理をDLLへコンパイルする形式は、辞書インタープリターと同じ差し替え方では実行できません。個別handlerをmacOSへビルドしたモジュールは従来のNative経路で接続します。SDKのサンプル導入を、その言語で作られた全ゴーストの動作保証として扱いません。

公式YAYAプラグインを導入した場合は、`yaya.dll`を公式Native/XPCエンジンへ接続します。未導入なら従来のOurin独自`yaya_core`を使います。複数候補の一致や指定先の消失では、旧VMへ黙って切り替えません。ゴースト自身のmacOS実装がある場合はそれを優先します。

Nativeエンジンの通信文字コードは、ゴーストの`shiori.encoding` / `shiori.forceencoding`の明示値を優先します。未指定のときだけプラグインの既定値を使い、AYA5互換ではShift_JISに合わせます。辞書の`charset.output`が既定と異なる場合は、対応する通信設定が必要です。

## ローカル生成

```sh
python3 engines/package-plugins.py
```

生成物は `build/engine-plugins/packages/<id>.plugin`。一覧・パッケージ内容のSHA256は `build/engine-plugins/packages.json` です。ZIPは標準では作成しません。転送用のZIPも必要な場合だけ `--archives` を付けると `<id>.plugin.zip` を追加します。このコマンドはユーザーのプロファイルへ導入せず、外部公開もしません。

必要なbuild toolchainと固定依存は各 `engines/<id>/README.md` を参照してください。エンドユーザーの実行時にはHomebrew・開発SDK・言語インストール先を要求しません。初回のローカルビルドには依存の取得と容量が必要です。各groupの生成済みstageは `--stage /absolute/path` を繰り返して再利用できます。

`.plugin` は `Contents/Info.plist` と `Contents/Resources/` を持つbundleです。Info.plistの `OurinShioriEnginePackageVersion=1` でSHIORI用と識別します。単にZIPの拡張子を変更したものではありません。イベント用や他アプリの `.plugin` はこの形式として読み込みません。

`Contents/Resources/engine.json` にはschema 1、ID、種類、実行ファイルまたはmoduleのpayload内相対path、引数、環境変数、DLL名、辞書マーカー、architecture、利用条件を記録します。`{engineRoot}` は導入先の `Contents/Resources`、`{ghostRoot}` は実SHIORIディレクトリに展開します。shell文字列は評価しません。Native ABIは隣接plistで宣言し、XPCの隔離経路を使います。

## 利用条件と未確認範囲

固定revisionとLICENSE/NOTICEをパッケージへ保持します。Aosoraは[上流のsource利用条件](https://github.com/kanadelab/aosora-shiori/blob/b9f6641c58ca4bfdaa775960e4b666c7282339db/license.txt)に従いローカル個人利用用です。aktk・dktrtk・krht・Kanahebi等の許諾未確認分を、再配布可能とみなして公開しません。phioriの許諾表記の不一致も従来の記録を保持します。

Windows固有API、任意のSAORI/native拡張、すべての第三者配布ゴースト、Intel実機と古いmacOS実機は別途確認が必要です。.NET／Node・Ruby・Python runtimeの今回の成果物はarm64です。KAWARI／Aosora／Nimに加え、公式YAYA／AYA5互換／なし栞の3パッケージはUniversal2です。全パッケージをUniversal2と表記しません。

今回のruntimeに記録された最低OSはMiyoJS/SanaJKが13.5、Sana/phiori/.NET3種が26.0です。Ruby/PythonとBrotliのビルド元に由来します。CPU・OSが合わないパッケージは画面へ表示し、自動選択から除外します。新しい配置先の初回loadはOSのコード検証やruntime初期化で5秒を超える場合があり、phioriの初期化だけ60秒、他のscript/.NETは30秒を上限とします。通常の要求期限は別に保持します。

今回の追加分は[2026-10-30の拡充・検証記録](SHIORI_ADDITIONS_2026-10-30.md)、以前の19パッケージは[初期プラグインの記録](SHIORI_PLUGIN_VERIFICATION_2026-10-29.md)を参照してください。
