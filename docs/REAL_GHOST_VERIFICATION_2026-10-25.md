# 実ゴースト・helper再検証（2026-10-25）

本記録は辞書とSHIORI応答を実プロセスで検証した結果であり、Ourinの画面、クリックの座標変換、バルーン表示、アニメーションを確認したものではない。Windows DLLや第三者NARはリポジトリへ同梱しない。

## 方法と再実行

`scripts/verify_real_ghosts.py` にJSON形式のケース一覧と**新規**出力ディレクトリを渡す。入力ツリーの全ファイルをSHA-256で記録して一時コピーを作り、そのコピーだけを実行する。終了後に元ツリーの不変を再確認する。YAYAの設定は現在の `ShioriLoader.swift` の本番 `DicCollector` / `collectDicEntries` / `applyYayaBasePath` を抽出してSwiftコンパイルし、同じ処理で解決する。

```sh
python3 scripts/verify_real_ghosts.py --cases /tmp/cases.json --output /tmp/new-ghost-results
```

```json
[
  {"name":"Emily4","engine":"yaya_core","root":"/absolute/path/to/emily4"},
  {"name":"Taromati2","engine":"yaya_core","root":"/absolute/path/to/Taromati2","config":"ghost/master/shiori/aya.txt"},
  {"name":"Satori","engine":"satori_core","root":"/absolute/path/to/ghost"},
  {"name":"LOBO","engine":"kawari","root":"/absolute/path/to/LOBO","library":"/absolute/path/to/libshiori.bundle"}
]
```

各ケースの `events` でイベントを指定できる。既定は `OnNotifyUserInfo` → `OnBoot` → `OnMouseDoubleClick` → `OnCommunicate` → `OnClose` → `OnDestroy` → unload。別プロセスを起動し、保存を残した同じコピーを再loadしてOnBoot/OnClose/OnDestroy/unloadを実行する。既存GhostManagerと同様、コピーの辞書rootに空のprofileディレクトリを準備する。YAYAのFMO応答は空のデスクトップ相当とし、plugin/execute等は未提供エラーを返す。したがってSAORI実連携の確認ではない。

`result.json` の `passed` は要求が期限内に正常応答し元ツリーが不変だったことのみを示す。修正版harnessではSHIORI 4xx/5xxも既定で不合格とする。ケースが特定イベント・method・期待status・辞書根拠を明示した場合だけ、その正確なstatusを期待応答として評価する。保存・GUI・会話内容の完全な互換性判定とは分ける。要求期限は通常20秒、辞書loadは60秒。stderrをファイルに流してpipe詰まりを避け、タイムアウト時は当該子プロセスを終了する。

## 修正前の実測結果

| 対象 | 起動・会話・終了 | 保存と別プロセス再起動 | 判定 |
|---|---|---|---|
| Emily/Phase4.5（Emily4） / Ourin yaya_core | 33辞書load、OnBoot 200/830文字、ダブルクリック200/710文字、OnCommunicate 204、OnClose 200/30文字、OnDestroy 204、unload成功 | 再load/OnBoot/OnClose成功。ただし2cycleともファイル変更なし。既定SAVEVAR未対応が残る | 通信は成功、保存は未達 |
| Taromati2 / Ourin yaya_core | 77辞書load、OnBoot 200/34文字、クリック200/73文字。OnMinuteChangeが20秒でtimeout | 新processで再load成功、OnClose200/空、unload成功。profile/debeso.db等の初期コピーは生じたが設定保存成功の証拠ではない | 不合格：定期イベント停止 |
| LOBO 1.0.0 / KAWARI上流8098dfb | load、OnBoot200/30文字、クリック200/524文字、OnCommunicate204、OnClose200/64文字、OnDestroy204、unload成功 | `profile/dict-savedata.txt`（546 bytes）とbackupを生成。User・talkinterval=300等を保存したコピーを別processで再loadし、OnBoot200/130文字・終了成功 | 実nativeライブラリと実辞書の通信・保存cycle成功。Ourinのloader/XPC/GUIは別途検証 |
| 里々 / repository basic fixture | 実satori_core load、OnBoot200/21文字、OnClose200/17文字、unload成功。クリック/OnCommunicate204 | savedata生成、別process再load/OnBoot/OnClose成功 | fixture回帰成功。第三者ゴースト9-1の再確認とは扱わない |

全4入力ツリーは実行前後でファイルハッシュ不変。応答文字数は今回の一例で、乱数や時刻で変わる。入力・応答全文は公開資料へ転載せず、結果JSONには応答長・応答SHA-256を記録している。

LOBOの初回harnessではprofileディレクトリ準備が不足し、KAWARIログにsave failedが出た。GhostManagerの通常準備と同じ空profile作成・OnDestroy通知を加え、上表の結果まで再検証した。ゴースト辞書本体は変更していない。

里々9-1の2026-07-14検証は既存互換表に記録されているが、今回読み取り可能なコピーと配布元を特定できなかった。ユーザーContainers内ghost一覧取得が応答せず、当該読み取りを打ち切った。権限変更や迂回は行っていない。今回実行したbasic fixtureを「9-1再検証」と読み替えない。

## 出所とチェックサム

- Emily4: 既存検証用 `emily4_backup` を使用。descriptには `[SSPBT/GL03B]Emily Development Team` と `http://ssp.shillest.net/` を記載。今回配布元から再取得していないため配布版の同一性は未確認。
- Taromati2: 既存のNAR展開検証コピー `bsdchk/Taromati2` を使用。descriptに [Taromati2/Taromati2](https://github.com/Taromati2/Taromati2) を記載。今回再取得していない。
- LOBO: [Okuajub/pcPetsのNAR](https://github.com/Okuajub/pcPets/blob/508f130e/Ukagakas/LOBO/LOBO_1.0.0.nar) を親タスクが取得。NARのWindows区切り文字をパス区切りとして展開したコピー。
- KAWARI: 親タスクが上流commit `8098dfb` を `/tmp/ourin-kawari-build-20261025` に固定してbuildした `build/mach/darwin/libshiori.bundle`。`shiori.h` のPOSIX `long` ABIと `loadu` をctypes子processから使用。

| 入力 | SHA-256 |
|---|---|
| Emily4ファイル一覧＋各内容hashのJSON | `0b20b191baaad7f34edac19bef75d18b1d3dd0b8ba7ebdc6ebd570266409225c` |
| Taromati2同上 | `ebecac382e1e12c19141d51d47e4e7d2826c4c715b979066ceb911d1957022af` |
| LOBO同上 | `bb4ddb09feca884f235b40c8d4cbd358b86278684649f4d03006d446162b9b35` |
| LOBO_1.0.0.nar | `f4e90615cf40801d4a7a7170762b6c0d6dddf18324f9ba146f4a700cbe2bebf7` |
| 実行yaya_core | `48b443fd4b30f46106c33c59df9cae0817c6c876e950aec006e48e8443401968` |
| 実行KAWARI library | `ad9d408f6266b90c27319748368fc44fce5f24154a0ef4620565141c280efce1` |

ローカル証跡は `/tmp/ourin-real-ghosts-20261025/` の `lifecycle-results/Emily4/result.json`、`existing-results-r2/Taromati2/result.json`、`lobo-lifecycle-profile-results/LOBO/result.json`、`satori-fixture-results/Satori-upstream-fixture/result.json`。一時領域のため永続配布物ではない。

## 修正前のTaromati2停止と最小再現

stderrの最後は `OnMinuteChange` → `AgendaMonitor` → `OnEventRead` → year/month/day。

- `dic/system/clock.dic:150` がAgendaMonitorを呼ぶ。定義は796行。
- `dic/system/Calendar.dic:1097` のOnEventReadは、ファイル名でFOPEN/FREAD/FCLOSEし、FREADが `-1` になるまでwhileを続ける（1114行以降）。
- 今回実行版 `yaya_core/src/VM.cpp:2919` はFOPEN失敗で `-1`（真）を返す。2966行のFREADは整数handle方式で、不明handle/EOFで空文字を返す。ファイル名を渡す実辞書との組合せでwhileが終了できない。
- ローカル上流500 `CORE_SAMPLES/yaya-shiori-500/sysfunc.cpp:2176` はFOPEN失敗0、2230行のFREADはファイル名を引き、失敗/EOFで `-1`。ゴーストのwhileを書き換える修正は不適切。

次は実データと独立した再現辞書であり、元ゴーストへのパッチではない。

```text
ProbeOpen { "value=%(FOPEN('missing.txt', 'r'))" }
ProbeRead { "value=%(FREAD('missing.txt'))" }
ProbeDelim {
    _s = "a|b"
    SETDELIM(_s, "|")
    _count = 0
    foreach _s; _entry { _count++ }
    "%(_count)"
}
ProbeSave { Persisted = 42
    "value=%(SAVEVAR())" }
```

この辞書をloadし、上記4関数へrequestした結果は順に `value=-1`、`value=`、`1`、`value=0`。`/tmp/ourin-real-ghosts-20261025/minimal-repro/` に辞書、入力JSONL、stdout、stderrを保存した。

SETDELIMの別問題はforeach実装（VM.cpp:1136）が変数固有delimiterでなく `arrayDelimiter_` を使う点。`a|b` は2要素でなく1要素になる。これは予定表の読み取り停止を解消した後も残る互換差分であり、今回timeoutの直接原因と同一視しない。

SAVEVARの別問題は引数省略で即0を返す点（VM.cpp:3783）。上流500のsysfunc.cpp:5635は省略時に既定のSaveVariableを呼ぶ。Emily4のyaya_shiori3.dic:107等は `SAVEVAR()` を使用するため、通信成功のみで永続化成功と判断できない。実行版のSAVEVARは独自JSON形式であり、既存YAYA保存形式との互換確認も必要。

修正後は、最小再現→Taromati2のOnMinuteChange→OnDestroy/unload→保存状態を残した再loadの順で確認した（後述）。SAORI未提供エラーが別に10回発生したため、SAORI連携を含む完全な会話確認は実app経路で別途必要。


## YAYA修正後の再検証

2026-10-25にファイル名方式のFOPEN/FREAD、EOF、変数delimiter、既定保存先、保存/復元を修正。実検証でさらにGETVARLIST(prefix)の無視を発見したため修正した。prefix無視によりTaromati2の一時変数掃除が全globalを削除していた。詳細と残件は [実装記録](delegation/yaya-real-ghost-fixes.md)。上の修正前結果は比較のため保持する。

| 対象 | 修正後の実process応答 | 保存・再起動 |
|---|---|---|
| Emily4 | 33辞書load、OnBoot200/830文字、クリック200/707文字、OnCommunicate204、OnClose200/30文字、OnDestroy204、unload成功 | `ghost/master/yaya_variable.cfg` を生成。別processで再load、OnBoot200/475文字・OnClose/OnDestroy/unload成功。2cycle終了時5457 bytes・84変数 |
| Taromati2 | 77辞書load、OnBoot200/34文字、クリック200/73文字、OnMinuteChange **200/82文字、51ms**、OnClose200/69文字 | `ghost/master/shiori/aya_variable.cfg` を生成。別process再load、OnBoot200/34文字・OnClose200/69文字・unload成功。2cycle終了時5900 bytes・89変数。両cycleのOnDestroyは400。追加調査により辞書の未定義イベントへの期待応答と判明 |

実行helper SHA-256: `1db0b4f2c2273ab77bccebefd8158a63124c3e6b019ad38232f5a15098be5a86`。証跡は `/tmp/ourin-real-ghosts-20261025/yaya-fixed-prefix-results/{Emily4,Taromati2}/result.json`。元ツリーhashは修正前表と同一で不変。実ゴーストの保存ファイル内容が次processで使えることに加え、独立fixtureで数値とカスタムdelimiterの別process復元をassertした。既存上流テキスト/暗号化保存のimportは未対応で、未知の既存保存ファイルは上書きしない。

最小再現4件は順に `value=0`、`value=-1`、`2`、`value=1` に改善。`yaya_core/tests/test_file_persistence.py` の9テストが全PASS。Xcode/実GUIはこのhelper検証とは別であり、Taromati2のSAORI未提供は未検証として残す。OnDestroy400は以下のとおり対象辞書の非対応応答であり、Ourinの未修正不具合とは分類しない。


## OnDestroy400の分類と期待status指定

Taromati2の `dic/aya/master/shiori.dic:439-449` は、イベント関数が存在せず `SHIORI_FW.IsImportantEvent` でもない場合に `SHIORI_FW.NoMatchingEvent` → `MakeBadResponse` を呼ぶ。791–793行が400応答を生成する。OnDestroy / SHIORI_EV.OnDestroyは未定義で、ログでは要求解析とID解決が正常に完了した後、この分岐を通る。別コピーでload直後のNOTIFY OnDestroy、GET OnDestroy、別の未定義イベント、OnClose後のOnDestroyがすべて400となり、既知のOnBoot/OnCloseは200だった。したがって終了処理や保存失敗による400ではなく、辞書が実装しないイベントへの明示応答と分類する。上流YAYAのISFUNC未定義=0はソースで照合したが、上流バイナリとの同一入力実行比較は未実施。

ケースJSONには以下のように例外を限定して指定できる。method・イベント名のワイルドカードや根拠の省略は拒否する。指定外イベント、GET OnDestroy、期待400に対する500等は不合格のまま。結果JSONは `status_matches` / `expected_status` / `expected_status_reason` を保持する。

```json
"expected_statuses": [
  {
    "event": "OnDestroy",
    "method": "NOTIFY",
    "status": 400,
    "reason": "Taromati2 shiori.dic:439-449 routes undefined events to NoMatchingEvent; :791-793 returns 400. OnDestroy is not defined."
  }
]
```

根拠付き設定 `/tmp/ourin-real-ghosts-20261025/yaya-expected-cases.json` で新たなコピーを実行し、Emily4 / Taromati2とも起動・会話要求・終了・保存・別process再loadのケース判定に合格した。証跡は `yaya-expected-results/{Emily4,Taromati2}/result.json`。元ツリーhashは不変。これは設定したhelper検証範囲での合格であり、GUI・SAORI・全ゴースト・上流保存形式の互換性を保証しない。期待status境界の `scripts/test_verify_real_ghosts.py` は5件PASS。


## Ourin実アプリでの華和梨起動（統合側）

2026-10-25、`/tmp/ourin-integration-dd-20261025/Build/Products/Debug/Ourin.app` を `OURIN_TEST_BASE_DIR=/tmp/ourin-lobo-app-r2-20261025`、起動ghost LOBOで起動。原NARを正規化済みコピーから配置し、実データには触れていない。通常factoryから `shiori.dll`→同梱 `libkawari_shiori.dylib`→XPCへ接続し、`kind=native`、OnBoot成功・本文34文字を実appログで確認。ログ: `/tmp/ourin-lobo-app-r2-20261025.log`。Macがロック中のため描画・クリック操作は未確認。試行したSSTPクリック要求は400となり、操作検証の成功には数えない。検証用app processは終了済み。

同梱エンジン/XPCと入力窓関連の対象テストは42実行・35固有テスト、失敗0/skip0。結果 `/tmp/ourin-engines-targeted-20261025.xcresult`。これは後続のYAYA GETVARLIST修正を含む全体結果ではない。


## 最終アプリ単体テスト / Final app unit test run

後続のYAYA GETVARLIST・ファイルAPI・FINE単一宛先修正を含むOurinTests全体は **1,541実行ケース / 1,520集計テスト、失敗0・報告skip0**。`/tmp/ourin-delegated-unit-final-r4-20261025.xcresult`（macOS 26.6.2 / arm64）。optional fixture未指定の早期returnがあり、実ゴースト・GUI網羅を意味しない。

The final unit run passed after all listed changes. Parameter-expanded executions and aggregate test count differ; environment-dependent early returns are not reported as skips. Real-ghost and GUI coverage remains as recorded above.
