# SHIORI対応・残件の続行第4部

確認日: 2026-10-28。[全体表](ADVENT_2023_SHIORI_COMPATIBILITY_ja-jp.md)／[第3部](SHIORI_CONTINUATION_2026-10-28_PART3.md)。検証は任意ローカルbuildと一時fixtureで実施し、インストール済み利用者ghostは変更していない。

## 未対応部分の実装

- **emo-rs／実配布「えも？」**: 元NARには整数除算、utf8標準library、日本語識別子があり、従来LuaJIT版とは異なる。別variant `--lua lua54` を追加し、lua-src546.0.2/ucidとCargo.lua54.lockを固定。配布の旧emo/frameworkとdicを新版scriptへ置換しない。[手順](../engines/emo-rs/README.md)。元NARのrevisionは6722ba895f1aa1e7d5f37c2a72a14ec56861a257、SHA256は9048182947acbdb917baf5a389bfd75118a7e587deecaca5863956757904b3d9。全元ファイルのhashを保存し、初回起動・通常起動・ダブルクリック応答・Unicode・NOTIFY・保存再load前後で一致を確認。
- **choice SAORI**: もす同梱READMEの「引数のうちランダムにどれか1つを返す」に基づく独自互換実装を追加。Universal2の実moduleでUTF8/CP932、乱数選択、終了・再loadを確認。KAGARIのnewSaoriがsaori.confのbackslashを未変換だった問題も修正。元もすNAR・全元ファイルを変えずに実キーイベント由来のSAORIトークまで確認し、load警告を解消。原Windows DLLとの全入力比較は未検証。[範囲・境界](../engines/kagari/saori/choice/README.md)。
- **krht**: Tcl9.1.0を固定sourceから静的buildし、HomebrewのmacOS26専用dylibへの依存を除去。隣接lib/tcl9.1の実script/encodingを使う移動可能なruntimeにした。arm64、Mach-O minimum OS11.0、リンク先はOS標準のみ。日本語pathへ移して会話し、途中EOFでも実_unloadで保存することを確認。古いmacOSでの実行は未検証。[手順](../engines/krht/README.md)。
- **D.N.Proxy**: 元dnproxy.iniのcolonキー、継続行、sourceの再帰directory/glob等を読み、本物Roslyn4.14.0のC#/VB compilerで一時領域へcompileする経路を追加。クローラの元ini/srcをread-onlyのまま起動し、CP932日本語応答を確認。別の実C#/VB辞書ではUnicode、Logger、保存・別process読み戻しも確認。元ghostへのuser.dll/profile生成なし。Windows固有機能や元D.N.Compiler全APIの実装とは区別する。[対応設定と制限](../engines/dnproxy/README.md)。
- **dktrtk ARM64**: 旧x86版を保ちながら `--arch arm64` で公式AngelScript SDK2.38.0＋全13addon＋datetimeを使うnative版を追加。array/stringの旧length()/length両形式を維持する限定SDK修正を加え、同じ辞書を旧/新双方へ通して確認。math/grid/filesystem/any/ref/weakref/complex/array/dictionary、保存・再load、異常script、EOFを実processで検証。CP932と全既存辞書は未検証。[手順・差分](../engines/dktrtk/README.md)。

いずれもengineの成功応答だけを作るstubへ置換していない。固定上流・依存のhashとnoticeを保持し、上流許諾が未確認のものは任意ローカルbuild限定。利用者ghostへの配置、自動同梱、外部配布は行っていない。

## 実配布確認で見つかったOurin側の不具合

**scopeごとのsurface alias**: 従来はsakura/keroの同名別名が上書きされ、名前を再生queueへ積む時点で解決していた。scope別の候補配列を保持し、数値別名・名前別名・重複による重みを扱う。名前の解決を実再生時へ移し、選ばれたsurfaceを再度aliasとして解釈しない。shell切替のcache無効化、overlay、dump、surface test一覧にもscopeを適用した。[UKADOCのalias仕様](https://ssp.shillest.net/ukadoc/manual/descript_shell_surfaces.html)。

**Windows形式NARの展開**: 実えもNARには先頭のbackslashルート項目と、backslash区切りのDOS directory項目がある。dittoはこれらを空の通常fileとして出力する場合があり、旧正規化は展開rootや既存の移動先を削除してしまう。空markerを限定処理し、directoryを正しく再構成・mergeするよう修正。衝突時に既存fileを上書きせず拒否し、親directory参照も拒否する。利用者の設置先へ書かず、ZipUtil.extractZipとNarInstaller.inspectManifestを実NARで検証する。

**実行状態Status**: 実アプリの自動OnSecondChangeで、会話中にもStatusヘッダが付かず、元「えも？」frameworkのwait_sec初期化が通らない問題を再現。ShioriDispatcherの通常/カスタムGET/NOTIFYと辞書取得で、実際のtalking/induction/passive/timecritical/nouserbreak/online状態を送る。元Luaへの初期値追加では回避しない。[SHIORI Status仕様](https://ssp.shillest.net/ukadoc/manual/spec_shiori3.html)。元frameworkには会話中tick前にidle tickを受けるとnil参照する境界があるため、会話中→idleの実イベント経路で検証する。

## 検証と証跡

- krht: Xcode **3 test PASS**。移動したsource-built runtimeと不完全要求EOFでの保存を追加。
- emo: Xcode **2 test PASS**。旧LuaJIT上流fixtureと、未改変実NAR＋Lua54のFactory/XPCを分けて確認。
- dktrtk両版／KAGARI／Windows形式NARの最終再実行: **計9 test PASS、skip 0**。
- Windows形式NAR: Xcode **3 test PASS、5 cases**。空rootのfile/directory両形式、衝突、親参照、実NAR展開・manifest検査。
- Statusヘッダ／未改変えもNARの本番dispatcher: **計2 test PASS**。会話中→idleの実要求、通常/カスタムGET/NOTIFY/辞書取得、状態解除、外部security保持を確認。
- scoped alias／Seriko parser／overlay／D.N.Proxy: Xcode **40 test PASS**。元INI/src read-only、C#/VBの両compiler、scope変更queue、候補の保持、shell切替を含む。

証跡は `/tmp/ourin-shiori-phase4-20261028/`、choiceは `/tmp/ourin-choice-final-20261028/summary.json`、ARM64は `/tmp/ourin-dktrtk-arm64-20261028/`。build失敗や不完全なNAR正規化を修正した後の最終成功結果を採用する。終了コードだけでなく実応答・保存・入力hashを照合する。

実GUIでも元えもシェル（element合成・scope別表情alias）を表示し、実ダブルクリックから元Lua応答「ダブルクリックで位置調整なんや。」のscript再生を確認。修正前GUIでOnSecondChangeのnil参照を観測し、Status修正後は自動イベント53回の記録中にLuaエラー・不明aliasがないことを確認。修正前の検証processは終了し、修正後はOurinメニューから正常終了。元NARの137ファイルすべてのSHA256一致、実save.luaのwait_sec保存、PID消滅を確認。付属balloonの元画像は検証用ghost/balloonへ配置したが、Lua・元シェル・元descriptorは変更していない。

GUI証跡: `gui-emo-distribution.log`（修正前）、`gui-emo-distribution-status-fixed.log`（修正後）。Status試験は `xcode-status.log`、最終全成功の3suiteは `xcode-final-engines-verified.log`、実NAR単体は `xcode-nar-final.log`。

## 「節美亜シンク」の実配布確認

SanaJK自体の実package試験は成功しているが、記事掲載のこのghostは公開物が不足している。[固定README](https://github.com/nodeshells/fusimiasync/blob/dffa6d3e12b704276c117eaeb96ce88e0342471d/readme.md#L8)は開発用とし、一般配布は将来予定。GitHub releases/tagsは空。更新一覧にはsecret/keys.tsやnode_modules実行JSの記録があるが、固定revisionの公開実体は404。元sourceはsecret/keysを無条件importし、起動前にmodule解決が止まる。正規の起動可能NARも確認できなかった。[更新一覧](https://github.com/nodeshells/fusimiasync/blob/dffa6d3e12b704276c117eaeb96ce88e0342471d/updates.txt)、[除外設定](https://github.com/nodeshells/fusimiasync/blob/dffa6d3e12b704276c117eaeb96ce88e0342471d/.gitignore#L2)。

秘密fileはHEADで存在だけ確認し、値は取得していない。偽key、偽認証module、辞書の機能削除で成功扱いにしない。正規配布artifactまたは必要moduleが揃うまで実配布ghostの確認は残件とする。Sanaには上流が案内する配布ghostが見当たらず、元packageと例による検証範囲を維持する。

## 残る条件

全第三者配布ghost、Windows固有API、任意の外部module/import、Intel実機、古いmacOS実機、未確認ライセンスの再配布可否は残る。「全16種の全ghostがそのまま動く」とは主張しない。commit／pushは実行していない。
