# SHIORI対応・続行第3部

確認日: 2026-10-28。[対象16種類の全体表](ADVENT_2023_SHIORI_COMPATIBILITY_ja-jp.md)／[第2部](SHIORI_CONTINUATION_2026-10-26_PART2.md)。以下は任意ローカルbuildと本番接続経路の検証。Windows PE DLL全般の実行、全配布ghostの互換性、アプリへの全runtime同梱を意味しない。

## 今回の実装

| 対象 | 実処理と検証範囲 |
|---|---|
| phiori | 固定上流Python moduleと元example.pyを実行するSHIOLINK host。上流frameworkのtemp persona終了処理だけ修正。元OnBoot／OnClose、自作callbackの日本語・絵文字、NOTIFY、variable.dat保存1→2を通常Factoryから確認。Python 3.14.8外部runtime |
| krht | 固定上流のTcl load/request/unloadをPOSIX化し、実Tcl 9.1.0をSHIOLINK childへ接続。自作Tclの会話・Unicode・保存・再load、不正sourceを確認。既存Tcl binaryに合わせ最低macOS 26.0。上流に辞書例・LICENSEなし |
| D.N.Proxy | 元IShiori30/ILoad/IUnloadを実装するmanaged moduleを.NET 10 hostから呼ぶ。未改変「クローラ＆ロダ」C#コードのCP932日本語会話・NOTIFY・別process起動を確認。保存は上流にないため別の実interface sampleで確認。public request(string)が必要。元Windows pointer ABI、AppDomain/CodeDom/WinForms等は対象外 |
| aktk | 固定上流＋実mruby 3.4.0のPOSIX／SHIOLINK移植。自作Rubyで日本語・絵文字・計算・保存・再load・例外と型不一致後の継続、不正source拒否を確認。上流終了callbackの常時false等をengine側で修正。上流に辞書例・LICENSEなし |
| dktrtk | 固定上流＋元13 addon＋AngelScript 2.30.0を実行。自作scriptの日本語・絵文字・array/dictionary/grid/sqrt・file保存・再load、不正script、途中EOFでのunloadを確認。x86_64 binary、Apple Siliconは既存Rosettaが必要。元addon APIを保つためarm64移植は未完。上流LICENSE未確認 |

手順: [phiori](../engines/phiori/README.md)、[krht](../engines/krht/README.md)、[D.N.Proxy](../engines/dnproxy/README.md)、[aktk](../engines/aktk/README.md)、[dktrtk](../engines/dktrtk/README.md)。元archiveをrevision/SHA256へ固定し、依存lock・上流noticeを保持する。権利未確認のコードを配布可能と判断して自動同梱する変更はない。

## 追加した最後の3種類

- Kanahebi: 元ModuleMain.csとSample/main.pyを改変せず、実IronPythonをSHIOLINK hostで実行。旧3.4.1/.NET 10のファイル読込み例外は公式IronPython 3.4.2＋DLR 1.3.5への更新で解消し、同版StdLibも固定する。Pythonのprintが通信stdoutへ混ざる問題はhostのstdoutをprocessレベルで分離して修正。未改変2.2 sampleの起動・ダブルクリック応答、別の実Python辞書のUnicode・ファイル保存・別process読み戻しを確認する。上流自身LICENSEは未確認で任意ローカルbuild限定。[手順](../engines/kanahebi/README.md)。
- csaori: 実CSAORIInput parserとCSAORIOutput builderを使うNative SHIORI sample。Windows独立部分を抽出し、wide文字列関数やlocale副作用をPOSIXへ移植。全Windows APIや完成SHIORIではない。[手順](../engines/csaori/README.md)。
- lib_skeleton: 未改変の実C++20 Request/Responseヘッダを使うNative SHIORI sample。自作sampleイベントと、実ライブラリによるprotocol処理を区別する。[手順](../engines/lib_skeleton/README.md)。

両ライブラリのsampleはukagaka-long ABIで本番Factory→XPCへ接続する。上流に完成SHIORIの同等例がないため自作sampleを使い、汎用辞書エンジンと呼ばない。

## 元descriptorの保全

`SHIOLINK.ourin.ini` に `module=phiori.dll` 等を明示すると、元 `descript.txt` のDLL名を保ったまま対象の移植hostを選択できる。設定は対象DLLと同じディレクトリに置く。ファイル名一致は大文字小文字を区別せず、別DLLへは適用しない。共通 `SHIOLINK.INI` のmodule指定は拒否する。通常起動・再loadで共通Factoryを使う。

SHIOLINK接続にも既存 `Shiori2CompatAdapter` を利用する。初期応答が成功のSHIORI/2.xなら検出し、以後Event／Sentence等を既存規則で変換する。明示communication.version=SHIORI/2.xにも対応。Sentence→Value、Shift_JIS→内部Unicode、NOTIFYの200→204、未知eventの204、unload後の状態resetを検証。forceEncoding=UTF-8ではwireのCharset宣言も一致させ、日本語・絵文字で確認する。全ての旧SHIORIの自動検出を保証するものではない。

## 実行結果

- `KrhtEngineTests`: **2 PASS**。
- `DnProxyEngineTests`: **2 PASS**。未改変crawlerと保存sampleを分けて実行。
- `AktkEngineTests`／`DktrtkEngineTests`: **計5 PASS**。
- module選択導入時の `ShiolinkTests`／`PhioriEngineTests`／`ShioriRuntimeTests`: **計25 PASS**。
- SHIORI2接続追加後の `ShiolinkTests` と phiori/Go/Rosalind/D.N.Proxy/krht/aktk/dktrtk: **計21 PASS、skip 0**。成功前にprivate型参照のcompile errorを修正して再実行。
- 文字コード修正後の `ShiolinkTests`／既存 `ShioriLoaderTests`: **計61 PASS**。2.x fixtureは第一行とEventヘッダーを検査する。
- `CsaoriEngineTests`／`LibSkeletonEngineTests`: **計4 PASS**。実parser、Unicode、疎Reference、不正protocol400、別PID、終了・再load。
- `KanahebiEngineTests`／最終 `ShiolinkTests`: **計12 PASS、skip 0**。未改変2.2 sample、実3.0辞書の保存・別process読み戻し、print隔離、構文エラー、途中EOFを確認。
- phioriを一時 `OURIN_TEST_BASE_DIR` の通常appで元 `shiori,phiori.dll` のまま起動。kind=shiolink、元OnBoot `Boot Event.` 応答、script text token、キャラクター画面を確認。Ourinメニューから終了し対象PIDの消滅を確認。shellはOurin DefaultGhostを借りたfixtureで実配布phiori ghostの試験ではない。balloon設定なし警告があり、会話の見た目全体・GUI終了時の保存完了は証明していない。

証拠: `/tmp/ourin-shiori-next-20261026/` の `xcode-krht.log`、`xcode-dnproxy.log`、`xcode-aktk-dktrtk.log`、`xcode-port-selection.log`、`xcode-shiolink-regression.log`、`gui-phiori-20261028.log`。利用者のインストール済みghostを改変していない。

Kanahebiも通常appの一時baseで元 `shiori,Kanahebi.dll` を保持して起動。未改変SampleのOnBoot日本語応答、キャラクター描画、実ダブルクリック→OnMouseDoubleClick→「つつくなよお。」応答→script text tokenを確認し、メニューから終了。shellとballoonはOurin DefaultGhost、要求surface20には同素材surface5のコピーを置いた検証用構成で、実配布ghostの見た目全体を証明するものではない。辞書main.pyは上流sampleとバイト同一を確認した。ログは `gui-kanahebi-20261028.log`。

追加の検証ログ: `xcode-shiori2-regression.log`、`xcode-library-samples.log`、`xcode-kanahebi.log`。

## 残件

14エンジンの実処理接続と2ライブラリの開発sampleを用意した。全第三者配布ghost、追加SAORI、Intel実機の試験と、未確認ライセンスの再配布可否は残る。各言語runtimeの自動導入・本番配布・commit／pushは実行していない。

第3部以降の未対応実装・実配布検証は [第4部](SHIORI_CONTINUATION_2026-10-28_PART4.md) を参照。
