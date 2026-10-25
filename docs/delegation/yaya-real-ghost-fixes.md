# YAYA 実ゴースト互換修正（2026-10-25）

外部委譲はソース取得確認で停止し実編集がなかったため、共有worktreeで引き継いで実装した。ゴースト辞書・ユーザー保存データは変更していない。

## 実装

- ファイルAPIをYAYA標準のファイル名方式へ統一。`FOPEN` は失敗0、成功1、既存open2。読み取り失敗/EOFは `FREAD` の整数-1で、空行は空文字。CRLFを除去する。二重openで内容をtruncateしない。
- `FREAD` / `FWRITE` / `FCLOSE` / `FSEEK` / `FTELL` / binary・encode/decodeを同じVM所属registryへ接続。VM破棄でstreamを閉じる。`FWRITE` は改行を付加。`FREADENCODE` / `FWRITEDECODE` は既定base64、form/URLも対応。従来の独自整数handle返却は成功1/既存2と両立しないため、標準契約を優先した。
- `foreach` は対象が変数ならその変数の `SETDELIM` を使う。
- SAVEVAR JSONの各型付き値にdelimiterを保持。旧JSONにdelimiterが無ければカンマで復元。引数省略/空文字は元モジュールの `<module>_variable.cfg`。Swiftからload IPCの `save_file` を渡し、`basepath` と元DLL配置を区別。`GETSETTING('coreinfo.savefile')` でも同じパスを返す。load前の復元、framework unload後の保存を追加。
- 既存ファイルがOurin型付きJSON以外なら保存を拒否。上流YAYAテキスト/暗号化保存をJSONで破壊しない。辞書から指定する明示ファイルは従来の相対パス制約を保持。
- 実保存確認で `GETVARLIST(prefix)` が引数を無視する別不具合を発見。Taromati2の一時変数掃除が全globalを削除していたため、接頭辞フィルターを実装。

正本はローカル `CORE_SAMPLES/yaya-shiori-500/sysfunc.cpp` のFOPEN/FREAD/GETVARLIST/SAVEVAR、`file.cpp` / `file1.cpp`、`basis.h:119` の `load_path + modulename + "_variable.cfg"`、`basis.cpp` のload時RestoreVariable・unload時SaveVariable。Swift既定保存先はghost package外を拒否する。

## 検証

- `./yaya_core/build.sh`: 成功（2026-10-25）。
- `python3 yaya_core/tests/test_file_persistence.py -v`: **9 PASS / 0 FAIL / 0 SKIP**。欠落ファイル、EOFと空行、二重open、改行/binary、変数delimiter、新process復元、旧JSON、未知形式保全、モジュール別保存先、unload資源回収、prefix掃除を実helperで検証。
- Swiftの追加対象: `YayaFileFunctionTests/saveFileStaysBesideOriginalModuleWhenBasepathChanges`。Xcode実行は親タスクが管理。
- 実ゴーストコピー: Emily4は起動・クリック・終了・既定保存・別process再load成功。Taromati2のOnMinuteChangeは従来20秒timeoutから **51ms / SHIORI 200 / 82文字**へ改善。OnCloseも空応答から69文字へ改善し、89変数を含む保存ファイルを生成。元ツリーSHA-256は二件とも不変。
- 証跡: `/tmp/ourin-real-ghosts-20261025/yaya-fixed-prefix-results`。実行helper SHA-256 `1db0b4f2c2273ab77bccebefd8158a63124c3e6b019ad38232f5a15098be5a86`。

## OnDestroyの分類と追加検証

Taromati2のOnDestroy400は辞書の未定義イベントへの期待応答。`dic/aya/master/shiori.dic:439-449` のハンドラ不在分岐が `NoMatchingEvent` → `MakeBadResponse` を呼び、791–793行が400を生成する。load直後・OnClose後、GET/NOTIFYの双方と別の未定義イベントで同じ400を実測した。要求の解析は正常で、Ourinの未修正不具合や保存失敗とは分類しない。上流ISFUNCのソースは照合したが、上流バイナリとの同一入力比較は未実施。

harnessの `expected_statuses` にevent・method・単一status・reasonを必須にした。Taromati2のNOTIFY OnDestroy=400のみ辞書根拠付きで指定し、`yaya-expected-results` でEmily4 / Taromati2ともケース判定合格、元ツリー不変を確認。指定外の4xxは既定で不合格、別methodや500も通らない。境界テスト `scripts/test_verify_real_ghosts.py` は5 PASS。実ケース設定は `/tmp/ourin-real-ghosts-20261025/yaya-expected-cases.json`。

## 残る互換差分

- 上流YAYAのテキスト/暗号化保存形式のimport/exportは未対応。今回の保存成功はOurinの型付きJSON形式での結果。
- 実ゴーストはSAORIを提供しないhelper harnessで検証。GUI、バルーン、アニメーション、実SAORI連携を確認したものではない。
- 文字列 `[a,b]` の簡易配列rangeとUnicode文字rangeの差は今回未変更。GETVARLISTのlocal scope列挙や全ファイルAPIの細部まで上流と完全一致したという主張ではない。


## 全体テストで判明した旧fixtureの修正

r3全体試験の `ShioriLoaderTests` 2件は、FOPENの返り値を整数handleとして使い、FWRITEの改行を期待せず、FREADENCODE/FWRITEDECODEを文字コード変換として呼ぶ旧独自契約のfixtureだった。YAYA500のsysfunc.cpp:2310/2417とfile.cpp/file1.cppに照合し、fixtureを標準のファイル名方式・改行付きテキスト出力へ修正した。多言語ファイルはGBK/Big5/韓国語encodingのbytesをbase64形式で読み書きして内容を照合する。辞書charset変換の7種類×global/per-dictionaryの既存検証も保持。

`yaya_core/build.sh` とXcode buildは成功。Swift Testingはメソッド名に `()` を付けて3対象を実行し、**3 PASS / 0 FAIL / 0 SKIP**を確認（初回の括弧なしselectorは0件だったため検証成功に数えない）。結果: `/tmp/ourin-yaya-charset-targeted-r2-20261025.xcresult`。修正対象はテストfixtureで、本体の標準APIを旧契約へ戻していない。全体再実行は統合側が実施する。
