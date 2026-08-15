# Ourin 監査項目 — 完了済み / Audit Items — Completed

**最終更新 / Last Updated**: 2026-08-15

> **注記 (2026-08-15)**: 本ファイルの `file:line` 引用は各項目の**判定時点**のものです。その後のリファクタで行番号はズレている可能性があります
> （2026-08-15 の抜き取り検証10件では、ファイル・シンボル不在は0件、行番号ズレは8件でした）。シンボル名・ファイルパスを優先して参照してください。
> Note: `file:line` citations reflect the state at audit time; line numbers may have drifted since (2026-08-15 sampling: 0 missing files/symbols, 8/10 line-number drifts). Prefer symbol names / file paths.
**集約元 / Consolidated from**: AUDIT_GLM / AUDIT_CODEX / AUDIT_CODEX_2026-06-27 / AUDIT_CLAUDE / AUDIT_AGY（各 ja-jp / en-us）
**検証方法 / Verification**: 全項目を現状ソースコード（file:line）と照合して完了判定。

---

## 日本語

### L. 2026-08-15 DevTools実ゴースト実行の対象解決

| 項目 | 根拠（実装・テスト・実機） |
|---|---|
| **SwiftUI delegateプロキシ環境での実ゴーストスクリプト実行** | `NSApp.delegate` は `SwiftUI.AppDelegate` プロキシになるため、`as? AppDelegate` が失敗していた。`OurinApp.swift` に `AppDelegate.resolve()`（直接 delegate を優先し、SwiftUI adaptor が保持する実体を weak に解決）を追加し、DevTools・GhostManager・EventBridge・SSTP・ドラッグ＆ドロップ等の本番参照を共通経路へ移行。`PluginTargetRoutingTests` は **4 passed / 0 failed**、`SSTPDispatcherTests` は **71 passed / 0 failed**、アプリ build は exit 0（既存警告のみ）。2026-08-15、実機の設定 → ヘッドライン・バルーン → 「スクリプト実行」で `実行対象: Emily/Phase4.5`、入力スクリプトの表示テキスト `AppDelegate resolver audit実ゴースト実行確認`、トークン（scope/surface/text/newline/end）を確認し、ゴーストウインドウが正立していることを目視確認。コミット `c5e9638`。 |

### M. 2026-08-15 音声認識権限要求クラッシュの解消

| 項目 | 根拠（実装・テスト・実機） |
|---|---|
| **起動時の音声認識権限要求を明示的操作へ分離** | `Ourin/SHIORIEvents/SpeechObserver.swift` の `poll()` から `SFSpeechRecognizer.requestAuthorization()` の自動呼び出しを削除し、権限未決定時は認識器を生成せず `OnVoiceRecognitionStatus`（`Reference0=0`, `Reference1=not_determined`）だけを配送する。設定画面の「音声認識を許可」ボタンからのみ明示要求する。`SpeechObserverTests` は **9 passed / 0 failed / 0 skipped**、アプリ build は exit 0（既存警告のみ）。2026-08-15、実ゴースト Emily4 を直接起動し、`Loaded 33/33 dictionaries`、`Starting EventBridge after OnBoot load (autoEvents=true)`、`EventBridge started`、`OnVoiceRecognitionStatus` を実ログで確認。12秒稼働中に `requestAuthorization`・`TCC`・`SIGABRT` は出ず、新規Ourinクラッシュレポートも生成されなかった。許可済みマイク入力による `OnVoiceRecognitionWord` は別途実機検証対象として残す。コミット `0d7b834`。 |

### N. 2026-08-15 SERIKOテストQoS warning解消

| 項目 | 根拠（file / result） |
|---|---|
| **非有効な音声合成器の終了時参照によるpriority inversionを解消** | `Ourin/Ghost/GhostManager.swift` の `shutdown()` は `\__v` 音声合成が有効化されたセッションだけ `stopSpeechSynthesis()` を呼ぶよう変更。修正前は `SurfaceImageOrientationTests` / `SurfaceOverlayOrderingTests` で runtime warning が発生（監査時9件、再現resultでは13/13 passed + 6件）。修正後のresult `/private/tmp/ourin-seriko-qos-fix.xcresult` は **13 passed / 0 failed / 0 skipped、Runtime Warning 0件**。アプリbuild `/private/tmp/ourin-seriko-qos-build` は exit 0（既存警告のみ）。コミット `43d1cb3`。 |

### O. 2026-08-15 SERIKO `\![anim,stop]` の always 停止

| 項目 | 根拠（実装・テスト・実ゴースト） |
|---|---|
| **手動停止後の `interval,always` アニメーション再起動を抑止** | `Ourin/Animation/SerikoExecutor.swift` に手動停止済み always ID の抑止状態を追加し、`startScheduledAnimations()` が次の tick で再起動しないようにした。明示的な `executeAnimation(id:)` とサーフェス定義置換では抑止を解除する。`Ourin/Ghost/GhostManager+Animation.swift` の `handleAnimStop()` はグローバル停止時に always 抑止を指定する。`SerikoExecutorTests` の停止後抑止・定義置換解除テストを含む対象テストは `** TEST SUCCEEDED **`。実ゴースト `Emily/Phase4.5` へ `\h\s[5]\![anim,50]SERIKO persistent overlay` → `\h\![anim,stop]SERIKO stopped` を投入し、停止後の `SERIKO pattern executed: anim=50` 件数を最新停止マーカーから再集計して **0件**と確認。続けて同じ anim コマンドを明示実行すると `surface4000.png` と `SERIKO pattern executed: anim=50` が再出現し、再生再開を確認。コミット `4e6bc74`。 |

### P. 2026-08-15 DevTools選択ゴーストへの実行対象配線

| 項目 | 根拠（実装・テスト・実機） |
|---|---|
| **ヘッドライン・バルーン画面のゴースト選択をスクリプト実行へ接続** | `Ourin/OurinApp.swift` に選択値を設定名・インストールフォルダ名へ照合する `ghostSelectionMatches` と、稼働中ゴースト／未起動ゴーストを配送する `runDevToolsScript` を追加。未起動時は `launchAdditionalGhost` 完了後にスクリプトを実行し、実行対象をUIへ返す。`Ourin/ContentView.swift` は選択値を渡し、起動完了後に結果を表示する。`DevToolsTargetRoutingTests` は **2 passed / 0 failed**。2026-08-15、専用ビルドで設定 → ヘッドライン・バルーン → ゴースト `emily4` を選択して実行し、未起動ゴーストを追加起動後、通知に **`実行対象: Emily/Phase4.5`** と表示テキスト `DevTools selected target verification` が出ることを確認（`bonsyou` への誤送信なし）。コミット `4457a36`。 |

### Q. 2026-08-15 SakuraScript `anim,add,text` 省略引数クラッシュ解消

| 項目 | 根拠（実装・テスト・実機） |
|---|---|
| **文字列以降の省略を安全な既定値で処理** | `Ourin/Ghost/GhostTypes.swift` の `AnimAddTextParameters.parse` に、仕様上必須の8引数（`anim,add,text,x,y,width,height,text`）と、表示時間・RGB・文字サイズ・フォントの省略時既定値を集約した。`Ourin/Ghost/GhostManager.swift` はこの値型を経由して `addTextAnimation` を呼び、`args[8]`〜`args[12]` の直接参照を廃止。`SakuraScriptEngineTests` に最小形と表示時間だけ指定した部分省略形の回帰テストを追加。権限付き `xcodebuild` のクラス実行結果は **219 passed / 0 failed / 0 skipped**（`xcresulttool` summary、`** TEST SUCCEEDED **`）。実ゴーストの専用ビルド起動までは確認したが、computer-use のアクセシビリティ取得が `-10005 timeoutReached` となったため、画面上のテキストアニメーション表示は未確認。コミット `275ba98`。 |

### R. 2026-08-15 生成HTMLのローカル参照切れ解消

| 項目 | 根拠（実装・テスト・生成物） |
|---|---|
| **Markdownリンクを生成先HTMLへ変換し、相対参照を再基準化** | `docs/generate_html.py` に生成済みMarkdown索引、言語版・旧`_JA`/`_EN`命名の解決、除外Markdownと`yaya_core`・プロジェクトREADME・`html/index.html`の相対パス変換、`href`/`src`のローカル参照変換を実装。`docs/test_generate_html.py` は **5 passed / 0 failed**。`cd docs && uv run --with markdown python3 generate_html.py` は **126 succeeded / 0 failed**。`static-site-check` は **127 HTML / 1151参照 / 壊れ参照0件 / 判定OK**。生成物は `docs/html/` 全体を更新。 |

### S. 2026-08-15 入力イベントの Reference 表駆動移行

| 項目 | 根拠（実装・テスト・監査） |
|---|---|
| **キーボード・クリック・ドラッグ系イベントの Reference 番号割当を `EventReferenceTable` 経由へ移行** | `Ourin/SHIORIEvents/InputMonitor.swift` にイベントIDごとの意味名から `ReferenceN` への変換を集約し、キー入力、クリック、ダブルクリック、複数クリック、ドラッグ開始・終了の発火を表駆動化した。`OurinTests/EventReferenceTableTests.swift` の `inputMonitorMouseReferencesRoundTripThroughEventReferenceTable` は、クリック系（R0〜R6）と移動系（R0〜R4/R6）の既存 raw パラメータとの完全一致を検証。権限付き `xcodebuild ... -only-testing:OurinTests test` でこの追加テストは passed。全体実行は **1073 passed / 21 failed / 0 skipped / 1094 total** で、別 issue の失敗群は `AUDITS_TODO.md` に記録した。マウス入退場・hover・select mode の raw 経路は次の移行スライスとして残る。 |

---

以下は過去の監査レポート（GLM / CODEX / CLAUDE / AGY, 2026-06-10〜2026-06-27）で指摘され、**現状コードで解決済み**であることを確認した項目です。

### A. SHIORI プロトコル

| 項目 | 根拠（file:line） |
|---|---|
| Reference順序が数値ソート化（辞書順ソートの修正） | `SHIORIEvents/EventBridge.swift:563-573`（`byIndex: [Int:String]` → `(0...maxIndex).map`） |
| `BridgeToSHIORI` 経由でNOTIFYメソッドが伝播 | `SSTP/BridgeToSHIORI.swift`（method引数貫通）、`SSTPDispatcher` で `.notify`/`.get`/`.give` 区別 |
| YAYA / Bundle / Dylib SHIORI の Charset 変換 | `USL/ShioriLoader.swift:623`（Charset検出＋変換） |
| SSTP応答で Reference1+ が反映（Reference0のみでない） | `SSTP/SSTPDispatcher.swift:747-755`, `677-681`（`responseReferenceIndex` で全Nを処理） |
| COMMUNICATE の Reference マッピング仕様準拠（R0=送信元名, R1=Sentence, R2=SSTP R0） | `SSTP/SSTPDispatcher.swift:601-610` |
| TEACH メソッドの互換マッピング | `USL/ShioriLoader.swift:247` |
| **Native SHIORIのXPCプロセス隔離** | `OurinShioriXPCService/`を同梱し、`ShioriLoader.XpcBackend`が既定でload/request/unloadを接続。Service側5秒watchdogでハング時にプロセス終了。`ShioriLoaderTests/loadRequestUnload`で実Service往復を確認。 |
| **YAYA/里々helperのtimeout復旧** | `Yaya/YayaAdapter.swift`、`USL/SatoriAdapter.swift`がhelper終了後に保存済みload contextを再適用。`ShioriRuntimeTests`の両runtime timeout回帰試験で確認。 |

### B. SSTP プロトコル

| 項目 | 根拠（file:line） |
|---|---|
| **SstpRouter 廃止・SSTPDispatcher へ一本化**（二重実装の解消） | `ExternalServer/OurinExternalServer.swift:53-65`（`handleRaw` → `SSTPDispatcher.dispatch`）。`SstpRouter.swift` は削除済み。テスト `ExternalServerTests.swift:6` も明記 |
| 応答ステータス行の `SSTP/SSTP/1.x` 二重プレフィクス バグ解消 | `SSTPResponse.swift:56`（`"\(version) ..."` のみ、再付加なし）。回帰テスト `ExternalServerTests.swift:64-69` |
| TCP/HTTP リスナーが host 引数で実際に bind（localhost限定デフォルト） | `ExternalServer/SstpTcpServer.swift:43-53`（`NWEndpoint.hostPort`）、デフォルト `127.0.0.1` |
| HTTP ポートを SSTP と同一の 9801 に統合（旧 9810 廃止） | `ExternalServer/SstpHttpServer.swift:31`（`port: 9801`）、`UnifiedSstpListener.swift` で多重化 |
| GIVE が SHIORI（OnChoiceSelect）へルーティング（204固定ではない） | `SSTP/SSTPDispatcher.swift:564-566`, `585-586` |
| SEND の Script ヘッダがバルーン再生される | `SSTP/SSTPDispatcher.swift:148`, `236-238`（`playScriptOnGhosts` → `gm.runScript`） |
| nodescript がバルーン表示のみ抑止（イベント dispatch は継続） | `SSTP/SSTPDispatcher.swift:230`, `181`。テスト `ExternalServerTests.swift:117-134` |
| IfGhost が順序保持リスト `[(key,value)]` で複数 Script/IfGhost ペア対応 | `SSTP/SSTPRequest.swift:29`, `85-100`。テスト `ExternalServerTests.swift:43-61`, `198-213` |
| SecurityLevel / SecurityOrigin 解釈（Origin優先・localhost判定） | `SSTP/SSTPDispatcher.swift`（統合後スタック） |
| **`Entry` ヘッダが本番経路で配線**（受信で保持・応答へエコー） | `SSTP/SSTPDispatcher.swift:51`（`mergeEntries`）、`156-157`, `290-291`（応答の `Entry` ヘッダ出力） |
| **HTTP レスポンス行末を `\r` → `\r\n` に修正**（RFC 7230 §3 準拠） | `ExternalServer/SstpHttpServer.swift:105-111`（SSTP成功応答の行末を `\r\n` 化。エラーパスも `\r\n`） |
| **外部SSTP NOTIFY の ValueNotify スクリプトがバルーン再生される** | `SSTP/SSTPDispatcher.swift:236-247`（`method != .notify` ガードを撤廃し、NOTIFY 由来 ValueNotify を `runNotifyScript` で再生）。`SHIORIEvents/EventBridge.swift:221-240`（`playScriptOnGhostsResolving(notify:)` 追加） |
| **SSTP パーサーが bare `\n` を許容**（LFのみ送信するツール向け正規化） | `SSTP/SSTPParser.swift:7-10`（先頭CR無しLFをCRLFへ正規化してから分割）。テスト `ExternalServerTests.swift`（`parserToleratesBareLFLineEndings`） |
| **SSTP 210 `nobreak` が実ゴーストのスクリプト再生完了まで待機** | `SHIORIEvents/EventBridge.swift:210-218`（登録済みゴーストの `isPlaying` を照会）、`SSTP/SstpBreakPolicy.swift:15-20`（`ShioriStatusStore` と再生状態を統合）。テスト `SSTPDispatcherTests.swift`（再生中待機・完了後200・タイムアウト409） |

### C. SakuraScript

| 項目 | 根拠（file:line） |
|---|---|
| `\t` = タイムクリティカルセクション（イベント抑止。ポーズではない） | `Ghost/GhostManager.swift:1045-1050`（`timeCriticalActive = true`） |
| `\-` = 当該ゴーストの終了（選択肢改行ではない） | `Ghost/GhostManager.swift:1081-1086`（`finalizeTermination()`） |
| `\v` = 最前面表示 / stay-on-top（設定ウィンドウではない） | `Ghost/GhostManager.swift:1107-1112`; `GhostManager+Window.swift:1012-1014`（`window.level = .floating`） |
| `\4`/`\5` = 相手キャラとの水平移動（Zオーダー切替ではない） | `Ghost/GhostManager.swift:1088-1094`; `GhostManager+Window.swift:293,312` |
| `\+`/`\_+` = 他ゴースト起動 | `Ghost/GhostManager.swift:1096-1105`; `GhostManager+System.swift:19,43` |
| `\*` = 選択肢タイムアウト無効化（ダイアログ表示ではない） | `Ghost/GhostManager.swift:1061-1065`（`choiceTimeoutDisabled = true`） |
| `\a` = OnAITalk 発生（ダイアログではない） | `Ghost/GhostManager.swift:1067-1079` |
| `\&[ID]` = 実体参照（アンカーではない） | `Ghost/GhostManager.swift:2355-2363`, `789-809`（`resolveEntityReference`） |
| `\j[ID]` ハンドラ実装（URL/イベントジャンプ） | `Ghost/GhostManager.swift:2365-2367`（`case "j"` → `handleJumpCommand`） |
| `\_V` と `\_v` の大小区別分岐（case-sensitive 早期分岐） | `Ghost/GhostManager.swift:1126-1136` |
| `\z` = キャンセル可能フラグ | `Ghost/GhostManager.swift:1056-1059` |
| **`\__v` 音声合成制御と `\_v` 音声アセット再生** | `Ghost/GhostManager.swift:241-246`（音声合成状態）、`2860-2906`（`enable`/`disable`/`alternate` と通常文の既定オフ）、`2619-2627`（`\_v` → `playSound`）、`2992-3000`（`\_V` の再生完了待ち）。通常文を macOS 既定音声へ自動投入せず、音声アセットは `ghost/master` を優先し、旧 `ghost/sound` を後方互換として再生する。 |
| **`\__t`(TeachBox) / `\__q`(選択肢キュー) / `\__c`(CommunicateBox) メタタグ実装** | `Ghost/GhostManager.swift`（`case "__t"`/`"__c"`）、`didEmit` の `case .choiceQueue`。テスト `SakuraScriptEngineTests.swift`（`metaTagTeachBox`/`metaTagCommunicateBox`/`choiceQueueCommand`/`choiceQueueRangeSyntaxBindsDisplayText`/`choiceQueueRangeTextNotShownInBalloon`/`choiceQueueScriptFormKeepsTitle`/`choiceQueueMultipleRangesProduceMultipleChoices`） |
| **`\__q` 範囲ベース表示テキスト結合（`\__q[ID,...]text\__q`）** | `SakuraScript/SakuraScriptEngine.swift`（`mergeChoiceQueueRanges` ポストプロセス + `.choiceQueue(title:id:references:)` トークン）。`Ghost/GhostManager.swift`（`case .choiceQueue` で title 付き選択肢生成）。ID 解釈は `\q` と同一（`script:`/`On*`/references）。※リッチラベル（画像・`\_l` 等のさくらスクリプト要素）はプレーンテキスト化される制限あり |
| `surfaces***.txt` の全読み込みとファイル名順結合（2026-06-27修正） | `Animation/SerikoParser.swift`, `Ghost/GhostManager+Animation.swift`（`docs/COMPAT_FIXES_2026-06.md` 参照） |
| **可変改行（`\\n[half]` / 数値・割合）を再生順序付きで表示** | `Ghost/GhostManager.swift` の `PlaybackUnit.newlineVariation` と `BalloonViewModel.lineAdvances`、`Ghost/BalloonView.swift` の行単位レイアウト。`\\n[half]`、正負の数値・割合を通常行高倍率として保持し、`\\c` の文字/行短縮時も同期。明示4スイート26件（改行・キュー順序・クリア整合性・装飾状態）で確認。負値の実表示はオフセット近似で、実ゴースト目視は未実施。 |
| **`\_a[ID,...]...\_a` の個別アンカー範囲とクリックルーティング** | `GhostManager.swift` の `BalloonAnchorRange` / `BalloonTextSegment`、`GhostManager+Balloon.swift` の `routeAnchorClick`・`onBalloonAnchorClicked`、`BalloonView.swift` の範囲別タップ処理。`On*` は指定イベントへ、その他は `OnAnchorSelectEx`（Reference0=クリック文字列、Reference1=ID、Reference2+=引数）→`OnAnchorSelect` へ振り分け、プラグイン起源も保持。`anchorstyle` / `anchorvisited*` の下線・矩形・背景・ペン色、3状態別文字色、訪問済み状態、`anchormethod` 系のSetROP2ピクセル合成まで実装。実ゴースト目視と実メディア環境での表示確認は未検証。関連テストを追加。 |
| **`%lastghostname` / `%lastobjectname`（インストール時用）対応** | `SakuraScript/EnvironmentExpander.swift`（static `lastInstalledGhostName`/`lastInstalledObjectName` + 展開）。併せて Pattern 2 の無条件 return を修正し bare `%key` が Pattern 3 で展開されるようにした。設定元 `Ghost/GhostManager+System.swift:1515-1516`（OnInstallComplete 直前）。テスト `EnvironmentExpanderTests.swift` |

### C-1. MAYUNA（着せ替え）

| 項目 | 根拠（file:line） |
|---|---|
| **`\\![bind,...]` / `\\![bind-noevent,...]` の実行経路・状態反映・通知** | `Ghost/GhostManager+Dressup.swift`（単一/複数タプル、カテゴリ一括、値省略・空値トグル、`bind-noevent`、既定着衣）。`Ghost/GhostManager+Effects.swift`（カテゴリ一括をパーツ差分へ展開、100要素以上は `OnDressupChanged` を省略）。`Ghost/GhostManager.swift` / `SHIORIEvents/EventBridge.swift`（起動時 NOTIFY、メニュー GET、スクリプト差分の最後だけ GET）。`OnDressupChanged` の Reference0..4 と `OnNotifyDressupInfo` の byte-value-1 区切り Reference* は UKADOC 準拠。テスト `OurinTests/DressupBindCommandTests.swift` 25件（実ランタイムへの GET wire 形式を含む）。 |

### D. SHIORIイベント

| 項目 | 根拠（file:line） |
|---|---|
| OnSecondChange/OnMinuteChange/OnHourTimeSignal に Reference0-4 付与 | `SHIORIEvents/TimerEmitter.swift:49-88`（`timeEventReferences()`） |
| cantalk に応じた GET/NOTIFY 切替（再生可能時はGET） | `SHIORIEvents/EventBridge.swift:430-454`（`Reference3` = cantalk、GET→再生 / NOTIFY→返値無視） |
| 見切れ/重なり（mikire/kasanari）のセッション単位充填 | `SHIORIEvents/EventBridge.swift`（`mikireScopes()`/`kasanariScopes()` が R1/R2 を補完） |
| OnBoot に Reference0（シェル名）付与 | `Ghost/GhostManager.swift:2688-2697` |
| OnFirstBoot に Reference0（vanish回数）付与 | `Ghost/GhostManager.swift:2675-2685` |
| 存在しない `OnSecondBoot` を削除（2回目起動も OnBoot） | `Ghost/GhostManager.swift:2670`（コメントで廃止を明記） |
| OnClose 応答スクリプトを再生してから終了 + Reference0（終了理由） | `Ghost/GhostManager.swift:738-768`（`beginCloseSequence` → `runScript` → 終了） |
| **CommunicateBox の `OnCommunicate` Reference 伝播** | `Ghost/GhostManager.swift` の `communicateBoxReferences` が `R0=user / R1=空 / R2=ECHO/1.0 / R3=本文` を生成し、`Ghost/GhostManager+System.swift` の送信経路へ接続。SSTP の `R0=Sender / R1=Sentence` 契約は維持。`GhostUtilityCommandTests` と `YayaEmily4RegressionTests` を含む対象56テストが通過し、2026-08-15の実操作（Emily4「話しかける」→`こんにちは`→OK）でも入力完了後に文字 `0`・浮遊パーツは表示されなかった。Emily4 の返却は辞書側の空表示スクリプト `\0\s[0]` であり、本文応答の有無はゴースト辞書の仕様範囲。 |
| イベントID定義の網羅性（UKADOC 252イベント中14未定義のみ） | `SHIORIEvents/EventID.swift`（469イベント定義、`EventReferenceTable` の `On*` ID は型付き網羅テスト済み） |
| **OnMouseClick の Reference4-6 が充足**（当たり判定名/ボタン/デバイス種別） | `SHIORIEvents/InputMonitor.swift:373-413`（R4=region, R5=button, R6="mouse"）。UKADOC list_shiori_event 準拠 |
| **`EventBridge.start(enableAutoEvents:)` を実ゴーストロード完了時に集約有効化** | `Ghost/GhostManager.swift:643-646`（OnBoot 後、`!isRunningUnderTests` で有効化）、`2719-2737`（`startEventBridgeIfNeeded` で再起動付き有効化） |
| **WebSocket/アーカイブ系14イベント実装** | `SHIORIEvents/EventID.swift`（14ケース追加）。ディスパッチ: `Web/GhostManager+WebSocket.swift`（OnExecuteWebSocket Open/Receive/Close/Error/Send/State）、`Ghost/GhostManager+System.swift`（OnExecuteHTTPStreaming, OnCompress/ExtractArchiveComplete/Failure）、`Ghost/GhostManager+Display.swift`（OnMusicPlay/OnMusicPlayEx/OnSoundLoop/OnSoundStop/OnVideoPlayEx）。既存の `notifyCustom` 文字列を型付き `notify(.X)` へ移行。テスト `EventIDAuditTests.swift` |
| **音声再生バックエンドと音声イベント** | `Ghost/SoundPlayer.swift`（AVAudioPlayer、volume/pan/rate/seektime、手動ループ境界、自然終了・エラー delegate）、`Ghost/GhostManager+Display.swift`（ghost/master 優先＋旧 ghost/sound フォールバック、同期的 play/load/stop/wait、プリロード・多重再生・状態掃除）。`OnSoundStop`（reason）、`OnSoundLoop`（周回境界）、`OnSoundError`（command/errorCode/filename/message）を発火。`OurinTests/SoundPlayerTests.swift` 27件、ビルド＋直列テストで確認。`![sound,wait]` は実行時 `waitForAudio` へ統一。 |
| **イベント Reference 仕様の表駆動化（基盤）** | `SHIORIEvents/EventReferenceSpec.swift` 新設（`EventReferenceTable.allSpecs` で主要約80イベントの Reference0..N 意味ラベル・カテゴリ・`notifyReturnIgnored` を一元定義）。`SHIORIEvents/EventBridge.swift`（`ShioriDispatcher.notifyReturnIgnored` を `EventReferenceTable.notifyReturnIgnoredIDs` から派生し、ハードコード Set を廃止）。2026-08-12に実際の自動発火ID（監視系・D&D・更新系を含む）を全列挙し、未定義IDを解消。Appearance/Network/Power/SystemLoad監視の意味値も `ShioriEvent(id:refs:)` 経由へ統一。テスト `EventReferenceTableTests.swift`（従来38件セットとの完全一致・重複IDなし・主要イベント Reference 検証）。※全216箇所の発火コードの表駆動移行は漸次対応 |
| **Observer の GET/NOTIFY 配信と OS 状態イベントの実データ化** | `SHIORIEvents/EventBridge.swift` に `ShioriEventDelivery` を導入し、Observer の既定 GET、起動時 NOTIFY、NOTIFY 応答スクリプト抑止を発火側で明示できるようにした。`DisplayObserver.swift` は `OnDisplayChange`（bpp/width/height）と `OnDisplayChangeEx`（モニタ列）を起動時/更新時に発火。`PowerObserver.swift` は IOKit の残量・残時間・電源状態・充電・低電力モードを `OnBattery*` に変換し、閾値遷移だけを追加通知。`SleepObserver.swift` は画面スリープを `OnDisplayPowerStatus` として扱い、スクリーンセーバー通知と混同しない。`SessionObserver.swift` は `NSWorkspace` のセッション切断/再接続を接続。テスト `PowerObserverTests.swift` を追加し、全804テストで確認。 |
| **OnDisplayHandover / OnRecycleBinStatusUpdate の実データ・実イベント接続** | `DisplayObserver.swift` のモニタスナップショットを実ウィンドウの初期配置・移動・リサイズへ接続し、`OnDisplayHandover` を初期 `NOTIFY`（R0=init、R1=scope、R2=空、R3=現在モニタ）とモニタ変更時の対象限定 `GET`（R0=update、R2=前、R3=現在）として発火。`RecycleBinObserver.swift` はホームおよび接続ボリュームの `.Trash`/`.Trashes/<uid>` を vnode 監視し、項目数・割当サイズ・差分を `OnRecycleBinStatusUpdate`（起動時 `NOTIFY`、更新時 `GET`、R4=1）へ接続。`executeEmptyRecycleBin()` 後の状態再読込も追加。テスト `DisplayHandoverTests.swift` / `RecycleBinObserverTests.swift`。 |
| **OnOSUpdateInfo の実データ監視・OnCloseAll の全ゴースト終了集約** | `OSUpdateObserver.swift` が macOS 標準 `/usr/sbin/softwareupdate --list/--history` の実出力を読み、確認時刻・最新実行時刻・成功済み更新履歴を `OnOSUpdateInfo` の R0/R1/R2〜へ変換。起動時 `NOTIFY`、履歴差分時 `GET`、応答スクリプト抑止を実装。`AppDelegate` と `GhostManager.beginCloseSequence` は全ゴーストへ `OnCloseAll` を送り、空応答・通常本文・`\\-` 応答の再生完了を集約してから終了する。テスト `OSUpdateObserverTests.swift` / `CloseAllSequenceTests.swift`。 |
| **初期 Notify 系の実データ化** | `SHIORIEvents/SystemNotificationData.swift` を新設し、`OnNotifyUserInfo`（呼び方/本名/未設定誕生日/`undef`）、`OnNotifyOSInfo`（macOS/CPU/メモリ/稼働分）、`OnNotifyFontInfo`（NSFontManager の Reference*）、`OnNotifyInternationalInfo`（UTC差分/DST/ISO国・言語）を実環境から生成。起動時通知、ユーザー名変更時の再通知、ロケール変更時の国際情報再通知を接続。`SystemNotificationDataTests.swift` 5件。 |

### E. プロパティシステム

| 項目 | 根拠（file:line） |
|---|---|
| 最長 prefix 解決（first-dot 分割→到達不能問題の解消） | `Property/PropertyManager.swift:128-141`（idx を長い方から走査） |
| `currentghost.balloon` プロバイダが到達可能 | `Property/PropertyManager.swift:29` |
| 値キャッシュの無効化 + `system.*`/`pluginlist.*` はキャッシュ除外 | `Property/PropertyManager.swift:155`, `159-169`, `222-225`（`uncachedPrefixes`） |
| `sakura.*`/`kero.*`/`ghost.*`/`shell.*` 名前空間エイリアス | `Property/PropertyManager.swift:40-43`, `279-299`（`AliasPropertyProvider`） |
| CPU使用率計算（恒常100%問題の解消） | `Property/PropertyManager.swift`（動的取得、キャッシュ除外対象） |
| **名前パラメータの case が保持される**（構造部のみ小文字化） | `Property/PropertyManager.swift:143-166`（`lowercasePreservingParams`。括弧内 `shelllist(MyShell)` 等を原文保持）。テスト `PropertyTests.swift`（`nameParametersPreserveOriginalCase`） |
| **深い階層プロパティの実態調査・実データ配線・UI機能の新規実装**（2026-07-01） | 監査の結果、`currentghost.seriko.cursor.*`/`tooltip.*`/`balloon.scope(ID).*` の**パース・SET/GETロジックは既に実装済み**（`GhostPropertyProvider.swift`/`BalloonPropertyProvider.swift`）と判明。ただし**真の根本原因**を特定：`Ghost/GhostManager.swift`（`SakuraScriptEngine()`のデフォルト初期化）で `sakuraEngine.propertyManager` が `PropertyManager.shared` と異なる独立インスタンスのままだったため、`\![set,property,...]` によるSETが `SSTPDispatcher`/`ResourceBridge` 等の読み取り経路から一切見えない配線切れがあった（cursor/tooltipに限らず全SETプロパティに影響）。`GhostManager.init`で`sakuraEngine.propertyManager = PropertyManager.shared`に修正。回帰テスト `OurinTests/PropertySetPropertyWiringTests.swift`。加えて、当たり判定連動のカーソル動的切り替え（`SHIORIEvents/SerikoCursorController.swift`新設、`NSCursor`使用箇所ゼロだった状態から実装）とツールチップ表示（`SHIORIEvents/SerikoTooltipController.swift`新設）のUI機能を新規実装し、既存の`InputMonitor.swift`当たり判定解決ロジック（`GhostManager+Surface.swift:459 collisionRegionName`）に接続。テスト `SerikoCursorControllerTests.swift`/`SerikoTooltipControllerTests.swift`。UKADOC 147項目の機械的突合により、真に未実装だったリーフ項目（`os.dst`, `os.locale.language/country`, `power.battery.lifetime`, `monitor.index(ID).bpp`, `disk.index(ID).type`, `network.type/.cost`）を`PropertyManager.swift`のSystemPropertyProviderへ追加。`network.downlink`/`downlink.estimate`はmacOSに公開APIが無いため未定義のまま（`dnd.mode`と同様のプラットフォーム制約として文書化）。テスト `PropertySystemTests.swift`（`System properties - deep leaf items`）。 |

### F. YAYA言語VM

| 項目 | 根拠（file:line） |
|---|---|
| **辞書ファイル CP932/Shift_JIS → UTF-8 変換（iconv実装）** | `yaya_core/src/DictionaryManager.cpp:13,46-89,119-172`（`convertWithIconv`/`decodeContent`、BOM処理込み） |
| `load()` が全辞書失敗時に false を返す | `yaya_core/src/DictionaryManager.cpp:296`（`success_count > 0 || dicEntries.empty()`） |
| yaya.txt `dic, filename, encoding` の per-dic encoding をC++側へ伝播 | `USL/ShioriLoader.swift:232-244` → `YayaCore.cpp:147-162` → `DictionaryManager::load` |
| SHIORI応答の全ヘッダ解析（"Value:" 部分文字列検索を廃止） | `yaya_core/src/YayaCore.cpp:265-301`（行単位で `shioriHeaders[key]=val`） |
| RE_GETSTR / RE_GETPOS / RE_GETLEN 実装 | `yaya_core/src/VM.cpp:2375-2387` |
| RE_OPTION 実装（icase/multiline） | `yaya_core/src/VM.cpp:2390-2396`, `2289-2294` |
| RE_REPLACEEX 実装 | `yaya_core/src/VM.cpp:2411` |
| RE_ASEARCH 実装 | `yaya_core/src/VM.cpp:2429-2442` |
| SAVEVAR / RESTOREVAR 実装（JSON永続化） | `yaya_core/src/VM.cpp:2603-2649`, `2652-2690` |
| DICLOAD / DICUNLOAD 実装 | `yaya_core/src/VM.cpp:2777-2785`, `2788-2794` |
| MKDIR / RMDIR / FENUM 実装（`std::filesystem`、実実装） | `yaya_core/src/VM.cpp:2153-2165`, `2168-2179`, `2039-2060` |
| **`&` by-reference 参照セマンティクス実装（E.Swap が in-place で動作）** | `yaya_core/src/VM.cpp:858-870`（Call サイトで `E.Swap` を特殊処理）、`1014-1055`（`tryResolveReference`/`readReference`/`writeReference`）。ローカル変数・配列要素・グローバル変数すべて交換可能。回帰テスト `OurinTests/ShioriLoaderTests.swift`（`yayaCoreESwapByReference`） |
| **standalone `when` の無条件実行を停止**（case 外の when はディスパッチ不能のため no-op） | `yaya_core/src/VM.cpp:943-952`（`WhenClause` ハンドラが本体を実行せず Void を返す）。case 内の when は従来通り `CaseNode` ハンドラが処理 |
| **`READFMO` を実装**（host_op:"fmo" 同期IPCでSwift側からFMOスナップショット取得） | `yaya_core/src/VM.cpp:2893-2906`（builtin）、`YayaCore.cpp:fmoOperation`（host_opブリッジ）、`VM.hpp:VMCallback::fmoOperation`。Swift側 `Yaya/YayaAdapter.swift`（`host_op:"fmo"` ハンドラ + `fmoSnapshotProvider`）、`OurinApp.swift:166-172`（provider設定）。テスト `ShioriLoaderTests.swift`（`yayaCoreReadFmoViaHostOp`） |
| **`ASEARCHPOS` 実装**（開始位置指定の配列検索、単一インデックス返却） | `yaya_core/src/VM.cpp`（`builtins_["ASEARCHPOS"]`、ASEARCHEX 直後に配置）。`FUNCTION_REFERENCE.md` / `examples/all_functions_test.dic` に追記 |
| **`SRAND` を実際にRNGへ反映（従来はシードを無視するスタブ）＋実在Emily4ゴーストの回帰テスト新設**（2026-07-01） | `yaya_core/src/RandomEngine.hpp`（新設、`RAND`/`ANY`/`Value::asString()`の配列→文字列ランダム選択が共有する`yaya_rng::engine()`）、`yaya_core/src/VM.cpp`（`SRAND`が`yaya_rng::engine().seed(...)`を呼ぶよう修正）、`yaya_core/src/Value.cpp`（array→string変換も共有エンジンを使用）。`OurinTests/YayaEmily4RegressionTests.swift`で、Emily4の実リクエストが200応答とSakura Scriptを返すこと、全33辞書のロード、`SRAND`固定シードによる雑談配列選択の再現性、YAYAの`REQ.COMMAND`・`--`出力エリア・`void`・裸の`return`を回帰確認。本番の`collectDicEntries`（`USL/ShioriLoader.swift`）をテストからも再利用し、`yaya.txt`のinclude/dic解決を本番と同一手順で検証 |

### G. プラグインシステム

| 項目 | 根拠（file:line） |
|---|---|
| PLUGIN/2.0M GET/NOTIFY フレーム構築 | `PluginHost/PluginProtocol.swift` |
| macOS `.plugin`/`.bundle` load/request/unload ライフサイクル | `PluginHost/Plugin.swift`, `PluginEvent/PluginEventDispatcher.swift` |
| Windows DLL 由来 plugin を metadata-only として区別（プラットフォーム差異を明文化） | `PluginHost/PluginRegistry.swift`（`canDispatchRequests=false`）、`docs/SPEC_PLUGIN_2.0M_ja-jp.md` |
| SAORI/1.0 ホスト（charset変換・Shift_JIS含む） | `SaoriHost/SaoriLoader.swift:44-61`, `SaoriProtocol.swift:158-176` |
| **PLUGIN/2.0 ホスト→プラグイン通知イベントの網羅性監査**（2026-07-01）。`docs/PLUGIN_EVENT_2.0M_SPEC_FULL_ja-jp.md` §4 の全17種通知イベント（`version`/`installedplugin`/`installedghostname`/`installedballoonname`/`ghostpathlist`/`balloonpathlist`/`headlinepathlist`/`pluginpathlist`/`OnSecondChange`/`OnOtherGhostTalk`/`OnGhostBoot`/`OnGhostExit`/`OnGhostInfoUpdate`/`OnMenuExec`/`OnInstallComplete`/`OnChoiceSelect(Ex)`/`OnAnchorSelect(Ex)`）に対し送信コードと呼び出し元の双方を確認、欠落なし | `PluginEvent/PluginEventDispatcher.swift`（送信）、`OurinApp.swift`/`Ghost/GhostManager.swift`/`Ghost/GhostManager+System.swift`/`Ghost/GhostManager+Balloon.swift`（呼び出し元）。未使用だった`onSecondChange()`公開メソッドは削除（実際の秒間隔通知は`setupTimer()`内で直接`sendFrame`済みのため冗長）。`calendarskinpathlist`/`calendarpluginpathlist`はUKADOC非準拠のOurin独自拡張と判明（別途文書化が望ましい） |

### H. NARパッケージ

| 項目 | 根拠（file:line） |
|---|---|
| `refreshundeletemask` がコロン区切り（UKADOC準拠、カンマも寛容に受容） | `NarInstall/InstallTxtParser.swift:102-108` |
| `refresh` / `refreshundeletemask` 保護マスク処理の実装 | `NarInstall/LocalNarInstaller.swift:83-85`, `175-184` |
| 同梱バルーン（`balloon.directory`）のインストール | `NarInstall/LocalNarInstaller.swift:94-102`, `207-223`（`installBundledBalloon`） |
| `accept` が上書き更新を許可（既存ディレクトリ衝突の即エラー解消） | `NarInstall/LocalNarInstaller.swift:71-80`（`accept` は shell/supplement の親ゴースト検証のみに使用） |
| ZIPエントリのバックスラッシュ → スラッシュ正規化（パス区切り問題） | `NarInstall/ZipUtil.swift:56-57`, `61-99`（`normalizeWindowsPaths` 再帰処理） |
| Zip Slip 対策・PK header 確認 | `NarInstall/LocalNarInstaller.swift:39-81`, `ZipUtil.swift` |
| **install.txt 自身の `charset` キーによる二段読み**（宣言エンコーディング優先） | `NarInstall/InstallTxtParser.swift:46-83`（`declaredCharset` で先頭行の charset を検出→優先デコード、失敗時は UTF-8→SJIS フォールバック） |

### I. FMO

| 項目 | 根拠（file:line） |
|---|---|
| **作成直後の shm_unlink を廃止**（プロセス生存中は名前を保持、終了時にunlink） | `FMO/FmoSharedMemory.swift:32-38`（作成時unlinkなし）, `80-86`（`close()` 時のみunlink） |
| 多重起動検出名を `/ourin_fmo` に統一（`/ninix`/`/ssp_fmo` のちゃんぽん解消） | `FMO/FmoManager.swift:91-92`, `98-111` |
| GetFMO が SSP互換レコード形式（`id.key\x01value\r\n`）を返す | `FMO/FmoManager.swift:156-178`（`buildSnapshot`）; `SSTP/SSTPDispatcher.swift:530-533` |
| `FmoCompatibilityView` / `FmoCompatibilityEntry` による構造化診断 | `FMO/FmoManager.swift:47-87`, `184-186` |
| POSIX共有メモリ方式をプラットフォーム差異として明文化 | `docs/About_FMO_ja-jp.md`, `docs/About_FMO_en-us.md` |

### J. バルーン・シェル・リソース

| 項目 | 根拠（file:line） |
|---|---|
| **balloon descript.txt の SJISフォールバック・`balloons*.txt` マージ** | `Balloon/DescriptorLoader.swift`, `Ghost/BalloonConfig.swift` |
| **descript.txt `charset` 行による二段読み**（宣言エンコーディング優先） | `Balloon/DescriptorLoader.swift:22-50`（isoLatin1 で charset 行を検出→Shift_JIS/UTF-8 再デコード）。テスト `BalloonTests.swift`（`descriptorCharsetTwoPassShiftJIS`） |
| SERIKO interval/pattern パース・実行 | `Animation/SerikoParser.swift`, `SerikoExecutor`, `AnimationEngine`（テスト `SerikoParserTests`/`SerikoExecutorTests`/`SurfaceOverlayOrderingTests`） |
| **SERIKO `collisionex` の geometry/画像色判定と animation-only 当たり判定**（2026-08-14） | `Animation/AnimationEngine.swift:75-208,342-488`（rectangle/ellipse/circle/polygon/region の形状保持、標準・旧形式パーサー、シェル相対画像のRGB領域・反転、`animation*.collision*` の実行中限定管理）、`Ghost/GhostManager+Animation.swift:370-378`（シェルディレクトリを解決基準として注入）、`Ghost/GhostManager+Surface.swift:636-656`（実行中IDを渡した実マウスイベントの領域解決）。テスト `AnimationEngineTests.swift`（通常時非表示、ellipse/circle、画像色・反転、優先順、再読込重複防止）。 |
| surfaces*.txt 全読み込み（2026-06-27修正） | `Animation/SerikoParser.swift`, `Ghost/GhostManager+Animation.swift` |
| **`surfacetable.txt` の体系的処理とサーフィステストUI**（2026-08-12） | `Animation/SurfaceTableParser.swift` 新設（`SurfaceTable`/`SurfaceGroup`/`SurfaceEntry` データモデル + `SurfaceTableParser.parse`）。`group,NAME { scope,N .. id,NAME }` 構文・`__disabled`/`__parts` マーカー・`option,DisableNoDefineSurfaces` を解釈。`Animation/SerikoParser.swift`（`SurfaceDefinitionLoader.loadSurfaceTable` 追加、surfacetable.txt を surfaces*.txt バンドルから分離）。`Ghost/GhostManager.swift`（`surfaceTestWindow`、`\![open,surfacetest]`）、`Ghost/SurfaceTestWindow.swift`（無効グループ除外、実画像プレビュー、scope切替、クリック適用）。テスト `SurfaceTableParserTests.swift` / `SurfaceTestCatalogTests.swift`。|

| **yaya_core 配列要素・範囲代入の書き戻し**（2026-08-12） | `yaya_core/src/Parser.cpp` / `VM.cpp`。`a[i]` の単一要素代入・複合代入に加え、YAYA準拠の閉区間 `a[start,end] = rhs`（空配列で削除、配列でスプライス）と `,=`、範囲読み取りを実装。Emily4 の `array_list[_i,10000] = IARRAY` / `active_array[15,10000] = IARRAY` を含む全辞書ロード成功。テスト `OurinTests/ShioriLoaderTests.swift` の49件を含む全体713件/59スイート成功。範囲の算術複合代入は誤って先頭要素だけを変更しないよう明示拒否。 |

### K. 2026-07-05 互換性向上ラウンド

Sonnet 調査エージェント3体による全域再監査（既存監査に無い新規ギャップの発見を含む）と、その修正ラウンドで解消した項目。

| 項目 | 根拠（file:line） |
|---|---|
| **yaya_core: `parallel` 修飾子を実装**（Emily4 で41箇所使用。未実装のため雑談候補配列が入れ子化しサイレント破壊されていた） | `yaya_core/src/AST.hpp`（`ParallelNode`）、`Parser.cpp`（文脈判定・キーワード化せず後方互換維持）、`VM.cpp`（array/sequential 収集での1段フラット化＋非 array 文脈での1要素ランダム選択、SRAND と同一 RNG）。実 Emily4 で候補プール 278件・入れ子0件を確認。テスト `OurinTests/YayaEmily4RegressionTests.swift`（フラット化検証・SRAND 再現） |
| **yaya_core: `executeBlock` が代入文の値をブロック値にしない**（`if { _tmp = 配列 }` 経由の入れ子配列リーク解消、本家「代入文は出力候補にならない」準拠） | `yaya_core/src/VM.cpp`（`executeBlock`） |
| **yaya_core: `#globaldefine` / `#define` プリプロセッサ実装**（Emily4 `aya_ghostchange_core.dic` で8箇所使用。従来は `#` 行が無条件コメント扱いで case 構文マクロが消失していた） | `yaya_core/src/DictionaryManager.cpp`（`preprocessDirectives`: 登録順の生置換、#define=ファイルスコープ / #globaldefine=以降の全ファイル）、`VM.hpp`（`registerGlobalDefine` で ISGLOBALDEFINE/PROCESSGLOBALDEFINE と整合） |
| **yaya_core: `LOGGING` / `TRANSLATE` の実処理化**（LOGGING=stderr 出力。TRANSLATE=本家 yaya-shiori sysfunc.cpp 準拠の文字集合対応変換、`-` 範囲展開・`\` エスケープ・変換先空での削除・不足分の末尾文字充填） | `yaya_core/src/VM.cpp` |
| **`OnDestroy` イベント発火**（NOTIFY、SHIORI unload 直前に対象ゴーストへ直接送信。リロード時は Reference0=`reload`、通常終了は Reference なし。UKADOC 準拠） | `Ourin/Ghost/GhostManager.swift`（`shutdown()` / `pendingDestroyReason`）、`SHIORIEvents/EventReferenceSpec.swift` |
| **マルチゴースト時の SSTP 応答副作用ルーティング**（Surface/Balloon/BalloonOffset/Icon/EXECUTE 系を ReceiverGhostName で対象ゴーストへ解決。未指定はプライマリ＝単一ゴースト構成の挙動不変） | `Ourin/OurinApp.swift`（`ghostManagerForShioriRequest` / `receiverTargetKey`）、`SSTP/SSTPDispatcher.swift`。テスト `SSTPDispatcherTests.swift`（照合キー生成） |
| **`OnOffscreen` / `OnOverlap` / `OnOtherOffscreen` / `OnOtherOverlap` 実装**（GET、Reference0=現在 / Reference1=直前、区切りはバイト値1。毎秒 tick で遷移検出、既存 `mikireScopes`/`kasanariScopes` 基盤を流用。OnOther 系は全ゴースト横断 `Sakura名/ID` 表記） | `Ourin/Ghost/GhostManager+Window.swift`（純関数 `offscreenRef0`/`overlapRef0` ＋ `overlapTransitionEvents`）、`SHIORIEvents/EventBridge.swift`（`dispatchOverlapTransitions`）。テスト `OverlapTransitionTests.swift` |
| **設定画面の保存値を実配線**（保存辞書の読み戻しバグ修正・SMAppService 自動起動（macOS 13+）・外部 SSTP の CP932 受理ゲート・ファイルログ sink。自動アップデート確認は「未使用」注記のみ） | `Ourin/ContentView.swift`、`ExternalServer/EncodingNormalizer.swift`（`acceptsCP932`、既定 true=現行挙動不変）、`Utils/Log.swift`（`LogFileSink`）。テスト `EncodingNormalizerCP932GateTests.swift` / `LogFileSinkTests.swift` |
| **NAR `type,saori` 対応**（accept あり → 対象ゴーストの `ghost/master/<dir>`、なし → 共有 `saori/<dir>`。UKADOC 未規定のため Ourin 定義として明記） | `Ourin/NarInstall/Paths.swift`（`installTarget`）。テスト `NarInstallTests.swift` |
| **SHIORI Resource のゴースト別分離**（`OurinResource.<ghostKey>.<key>` 名前空間化＋旧グローバル値は最初に起動したゴーストが一度だけ backfill。複数ゴースト同時起動時の値汚染を解消） | `Ourin/Property/ResourceManager.swift`、`Ghost/GhostManager.swift`（`lazy var resourceManager`）。テスト `ResourceManagerSeparationTests.swift` |
| **`\f[anchor*]` 装飾サブコマンド群の実装**（選択中・非選択・訪問済みのstyle/brush/pen/fontcolorを個別状態へ反映。ROP2の全SetROP2演算子を受理し、背景画像の実ピクセルへ合成） | `Ourin/Ghost/GhostManager.swift`（`\f` switch）、`Ghost/BalloonView.swift`、`Ghost/BalloonConfig.swift`、`Ghost/AnchorRasterOperation.swift`、`Ghost/AnchorRasterImageRenderer.swift` |
| **DevTools モック UI の裁定**（External Events Harness を実配線: 実サーバステータス・実 TCP/HTTP 送信・応答表示・全サーバ再起動。Headline/Balloon プレビュー・Signpost・Resource Overlay・Plugin Enabled トグルは「Preview only」注記） | `Ourin/ContentView.swift`、`ExternalServer/ServerMetrics.swift`（`requestCount` 公開） |
| **NAR 複合 install 種別の記載訂正**（AUDITS_TODO の「不足」記載は誤りで、実装済みだったことを確認） | `Ourin/NarInstall/Paths.swift:219-236`（calendar/skin・calendar/plugin・calendar 旧互換・language） |
| **NAR ネットワーク更新の delete.txt 対応とパス安全性**（2026-08-14） | `NarInstall/LocalNarInstaller.swift` が更新成功後（削除だけの更新を含む）に任意のサーバー `delete.txt` を取得し、`charset` 行を受理したうえで、対象ルート内の検証済みパスだけを削除。`testonly` は非破壊のまま。`InstallTxtParser.swift` は更新記述子のドットセグメント・絶対パス・ドライブパスを拒否し、`ZipUtil.swift` はコンポーネント単位のルート境界検証を使用。`NarInstallTests.swift` で MD5 検証付き更新、Windows形式 `delete.txt` パス、トラバーサル拒否、delete.txt 404（削除なし）を検証。 |

---

## English

### L. 2026-08-15 DevTools live-ghost target resolution

| Item | Evidence (implementation, tests, and device run) |
|---|---|
| **Live-ghost script execution through the SwiftUI delegate proxy** | `NSApp.delegate` is a `SwiftUI.AppDelegate` proxy, so `as? AppDelegate` returned nil. Added `AppDelegate.resolve()` in `OurinApp.swift` (prefer a direct AppKit delegate, otherwise resolve the weak instance retained by the SwiftUI adaptor) and migrated production lookups across DevTools, GhostManager, EventBridge, SSTP, drag-and-drop, and related paths. `PluginTargetRoutingTests`: **4 passed / 0 failed**; `SSTPDispatcherTests`: **71 passed / 0 failed**; app build exited 0 with existing warnings only. On 2026-08-15, the real-device Settings → Headline/Balloon → “Run Script” path returned `実行対象: Emily/Phase4.5`; the parsed display text was `AppDelegate resolver audit実ゴースト実行確認` with scope/surface/text/newline/end tokens, and the ghost window was visually confirmed upright. Commit `c5e9638`. |

### M. 2026-08-15 Startup speech-authorization crash resolved

| Item | Evidence (implementation, tests, and device run) |
|---|---|
| **Separate speech-recognition authorization from automatic startup events** | Removed the automatic `SFSpeechRecognizer.requestAuthorization()` call from `poll()` in `Ourin/SHIORIEvents/SpeechObserver.swift`; when authorization is undetermined, the observer does not create a recognizer and only dispatches `OnVoiceRecognitionStatus` (`Reference0=0`, `Reference1=not_determined`). Authorization is requested only by the explicit “音声認識を許可” settings action. `SpeechObserverTests`: **9 passed / 0 failed / 0 skipped**; app build exited 0 with existing warnings only. On 2026-08-15, Emily4 was launched directly as a real ghost; the live log confirmed `Loaded 33/33 dictionaries`, `Starting EventBridge after OnBoot load (autoEvents=true)`, `EventBridge started`, and `OnVoiceRecognitionStatus`. During 12 seconds of runtime, no `requestAuthorization`, `TCC`, or `SIGABRT` appeared, and no new Ourin crash report was generated. `OnVoiceRecognitionWord` with granted microphone input remains a separate live-device verification item. Commit `0d7b834`. |

### N. 2026-08-15 SERIKO test QoS warning resolved

| Item | Evidence (file / result) |
|---|---|
| **Removed priority inversion caused by querying an inactive speech synthesizer during shutdown** | `Ourin/Ghost/GhostManager.swift` `shutdown()` now calls `stopSpeechSynthesis()` only for sessions that enabled `\__v` speech synthesis. Before the fix, `SurfaceImageOrientationTests` / `SurfaceOverlayOrderingTests` emitted runtime warnings (nine in the audit run; the reproduced result had 13/13 passed plus six warnings). After the fix, `/private/tmp/ourin-seriko-qos-fix.xcresult` reports **13 passed / 0 failed / 0 skipped and zero Runtime Warnings**. The app build `/private/tmp/ourin-seriko-qos-build` exited 0 with existing warnings only. Commit `43d1cb3`. |

### O. 2026-08-15 SERIKO `\![anim,stop]` always suppression

| Item | Evidence (implementation, tests, and real ghost) |
|---|---|
| **Suppress automatic restart of `interval,always` animations after manual stop** | `Ourin/Animation/SerikoExecutor.swift` now tracks manually suppressed always animation IDs, so `startScheduledAnimations()` does not restart them on the next tick. Explicit `executeAnimation(id:)` and surface-definition replacement release the suppression. `Ourin/Ghost/GhostManager+Animation.swift` requests always suppression for global `handleAnimStop()`. The focused `SerikoExecutorTests` run, including stop suppression and definition-replacement release, ended with `** TEST SUCCEEDED **`. On real `Emily/Phase4.5`, `\h\s[5]\![anim,50]SERIKO persistent overlay` followed by `\h\![anim,stop]SERIKO stopped` produced **0** later `SERIKO pattern executed: anim=50` entries when counted from the latest stop marker. Replaying the same anim command explicitly produced `surface4000.png` and new `SERIKO pattern executed: anim=50` entries, confirming intentional restart. Commit `4e6bc74`. |

### P. 2026-08-15 DevTools execution routed to the selected ghost

| Item | Evidence (implementation, tests, live UI) |
|---|---|
| **Headline/Balloon ghost selection now controls script execution** | `Ourin/OurinApp.swift` adds `ghostSelectionMatches` for config/folder matching and `runDevToolsScript` for dispatch to running ghosts or an additional ghost when the selected ghost is not running. The script is sent after `launchAdditionalGhost` completes, and the execution target is returned to the UI. `Ourin/ContentView.swift` passes the selected value and presents the result after asynchronous boot. `DevToolsTargetRoutingTests`: **2 passed / 0 failed**. On 2026-08-15, the dedicated build selected `emily4` in Settings → Headline/Balloon and executed the script; the not-running ghost was launched as an additional ghost and the notification showed **`実行対象: Emily/Phase4.5`** with display text `DevTools selected target verification` (no dispatch to `bonsyou`). Commit `4457a36`. |

### Q. 2026-08-15 SakuraScript `anim,add,text` omitted-argument crash resolved

| Item | Evidence (implementation, tests, live UI) |
|---|---|
| **Safe defaults for optional fields after the text argument** | `Ourin/Ghost/GhostTypes.swift` now centralizes parsing in `AnimAddTextParameters.parse`: the eight fields through `text` remain required, while display time, RGB, font size, and font name receive safe defaults when omitted. `Ourin/Ghost/GhostManager.swift` calls `addTextAnimation` through this value type, removing the unconditional `args[8]`–`args[12]` reads. `SakuraScriptEngineTests` adds regression coverage for the minimum form and a form specifying only display time. The privileged `xcodebuild` class run reported **219 passed / 0 failed / 0 skipped** (`xcresulttool` summary, `** TEST SUCCEEDED **`). The dedicated app build launched the real-ghost path, but computer-use accessibility retrieval returned `-10005 timeoutReached`; the on-screen text-animation result remains unverified. Commit `275ba98`. |

### R. 2026-08-15 Broken local references in generated HTML resolved

| Item | Evidence (implementation, tests, generated output) |
|---|---|
| **Convert Markdown links to generated HTML and rebase local paths** | `docs/generate_html.py` now indexes generated Markdown sources, resolves language-neutral and legacy `_JA`/`_EN` names, rebases excluded Markdown plus `yaya_core`, project README, and `html/index.html` paths, and rewrites local `href`/`src` targets. `docs/test_generate_html.py`: **5 passed / 0 failed**. `cd docs && uv run --with markdown python3 generate_html.py`: **126 succeeded / 0 failed**. `static-site-check`: **127 HTML / 1151 references / 0 broken / OK**. The complete `docs/html/` generated output was updated. |

### S. 2026-08-15 Table-driven Reference migration for input events

| Item | Evidence (implementation, tests, audit) |
|---|---|
| **Route keyboard, click, and drag event Reference numbering through `EventReferenceTable`** | `Ourin/SHIORIEvents/InputMonitor.swift` now centralizes semantic-name to `ReferenceN` conversion per event ID and uses it for key input, click, double-click, multiple-click, and drag-start/end emission. `OurinTests/EventReferenceTableTests.swift` adds `inputMonitorMouseReferencesRoundTripThroughEventReferenceTable`, verifying exact equality with the existing raw parameters for click events (R0–R6) and move events (R0–R4/R6). The privileged `xcodebuild ... -only-testing:OurinTests test` run passed this added test. The full run was **1073 passed / 21 failed / 0 skipped / 1094 total**; the separate failure groups are recorded in `AUDITS_TODO.md`. Mouse enter/leave/hover and select-mode raw paths remain as the next migration slice. |

---

The following items were raised in prior audit reports (GLM / CODEX / CLAUDE / AGY, 2026-06-10–2026-06-27) and have been **verified as resolved** in the current source code.

### A. SHIORI Protocol

| Item | Evidence (file:line) |
|---|---|
| Reference order now numeric (fixed dict-string sort) | `SHIORIEvents/EventBridge.swift:563-573` (`byIndex: [Int:String]` → `(0...maxIndex).map`) |
| NOTIFY method propagated through `BridgeToSHIORI` | `SSTP/BridgeToSHIORI.swift`; `SSTPDispatcher` distinguishes `.notify`/`.get`/`.give` |
| YAYA / Bundle / Dylib SHIORI Charset conversion | `USL/ShioriLoader.swift:623` |
| SSTP responses reflect Reference1+ (not just Reference0) | `SSTP/SSTPDispatcher.swift:747-755`, `677-681` |
| COMMUNICATE Reference mapping spec-compliant (R0=sender, R1=Sentence, R2=SSTP R0) | `SSTP/SSTPDispatcher.swift:601-610` |
| TEACH method compatibility mapping | `USL/ShioriLoader.swift:247` |

### B. SSTP Protocol

| Item | Evidence (file:line) |
|---|---|
| **SstpRouter removed; consolidated into SSTPDispatcher** (dual-implementation resolved) | `ExternalServer/OurinExternalServer.swift:53-65`; `SstpRouter.swift` deleted. Test `ExternalServerTests.swift:6` confirms |
| Response status-line `SSTP/SSTP/1.x` double-prefix bug fixed | `SSTPResponse.swift:56`; regression test `ExternalServerTests.swift:64-69` |
| TCP/HTTP listeners actually bind to host (localhost-only default) | `ExternalServer/SstpTcpServer.swift:43-53` (`NWEndpoint.hostPort`), default `127.0.0.1` |
| HTTP port unified to 9801 (old 9810 removed) | `ExternalServer/SstpHttpServer.swift:31`; `UnifiedSstpListener.swift` multiplexes |
| GIVE routes to SHIORI OnChoiceSelect (not hard-coded 204) | `SSTP/SSTPDispatcher.swift:564-566`, `585-586` |
| SEND Script header replayed to balloon | `SSTP/SSTPDispatcher.swift:148`, `236-238` |
| nodescript suppresses balloon only (event dispatch continues) | `SSTP/SSTPDispatcher.swift:230`, `181`; test `ExternalServerTests.swift:117-134` |
| IfGhost order-preserving list `[(key,value)]`, multiple Script/IfGhost pairs | `SSTP/SSTPRequest.swift:29`, `85-100`; tests `ExternalServerTests.swift:43-61`, `198-213` |
| SecurityLevel / SecurityOrigin interpretation (Origin priority, localhost check) | `SSTP/SSTPDispatcher.swift` |
| **`Entry` header wired in production path** (stored on receive, echoed in response) | `SSTP/SSTPDispatcher.swift:51` (`mergeEntries`), `156-157`, `290-291` (`Entry` response header) |
| **HTTP response line ending fixed `\r` → `\r\n`** (RFC 7230 §3 compliant) | `ExternalServer/SstpHttpServer.swift:105-111` (SSTP success response now uses `\r\n`; error path already did) |
| **External SSTP NOTIFY ValueNotify script replayed to balloon** | `SSTP/SSTPDispatcher.swift:236-247` (removed `method != .notify` guard; NOTIFY ValueNotify replayed via `runNotifyScript`). `SHIORIEvents/EventBridge.swift:221-240` (added `playScriptOnGhostsResolving(notify:)`) |
| **SSTP parser tolerates bare `\n`** (LF-only normalization for de facto tools) | `SSTP/SSTPParser.swift:7-10` (normalizes CR-less LF to CRLF before splitting). Test `ExternalServerTests.swift` (`parserToleratesBareLFLineEndings`) |
| **SSTP 210 `nobreak` waits for live ghost script playback to finish** | `SHIORIEvents/EventBridge.swift:210-218` (query of registered ghosts' `isPlaying`), `SSTP/SstpBreakPolicy.swift:15-20` (combines `ShioriStatusStore` and playback state). Tests in `SSTPDispatcherTests.swift` cover waiting, post-playback 200, and timeout 409 |

### C. SakuraScript

| Item | Evidence (file:line) |
|---|---|
| `\t` = time-critical section (event suppression, not a pause) | `Ghost/GhostManager.swift:1045-1050` |
| `\-` = current ghost termination (not choice newline) | `Ghost/GhostManager.swift:1081-1086` |
| `\v` = stay-on-top / bring-to-front (not settings window) | `Ghost/GhostManager.swift:1107-1112`; `GhostManager+Window.swift:1012-1014` |
| `\4`/`\5` = horizontal movement toward/away from partner | `Ghost/GhostManager.swift:1088-1094`; `GhostManager+Window.swift:293,312` |
| `\+`/`\_+` = boot other/all ghosts | `Ghost/GhostManager.swift:1096-1105`; `GhostManager+System.swift:19,43` |
| `\*` = prevent choice timeout (not dialog trigger) | `Ghost/GhostManager.swift:1061-1065` |
| `\a` = trigger OnAITalk (not dialog) | `Ghost/GhostManager.swift:1067-1079` |
| `\&[ID]` = entity reference (not anchor) | `Ghost/GhostManager.swift:2355-2363`, `789-809` |
| `\j[ID]` handler implemented (URL/event jump) | `Ghost/GhostManager.swift:2365-2367` (`case "j"`) |
| `\_V` vs `\_v` case-sensitive early branch | `Ghost/GhostManager.swift:1126-1136` |
| `\z` = cancelability flag | `Ghost/GhostManager.swift:1056-1059` |
| **`\__v` voice synthesis control and `\_v` voice asset playback** | `Ghost/GhostManager.swift:241-246` (speech state), `2860-2906` (`enable`/`disable`/`alternate` and default-off ordinary text), `2619-2627` (`\_v` → `playSound`), `2992-3000` (`\_V` playback wait). Ordinary text is not sent to the macOS default voice automatically; voice assets play independently from `ghost/sound`. |
| **`\__t` (TeachBox) / `\__q` (choice queue) / `\__c` (CommunicateBox) meta-tags implemented** | `Ghost/GhostManager.swift` (`case "__t"`/`"__c"`), `didEmit` `case .choiceQueue`. Tests `SakuraScriptEngineTests.swift` (`metaTagTeachBox`/`metaTagCommunicateBox`/`choiceQueueCommand`/`choiceQueueRangeSyntaxBindsDisplayText`/`choiceQueueRangeTextNotShownInBalloon`/`choiceQueueScriptFormKeepsTitle`/`choiceQueueMultipleRangesProduceMultipleChoices`) |
| **`\__q` range-based display-text binding (`\__q[ID,...]text\__q`)** | `SakuraScript/SakuraScriptEngine.swift` (`mergeChoiceQueueRanges` post-process + `.choiceQueue(title:id:references:)` token). `Ghost/GhostManager.swift` (`case .choiceQueue` produces a titled choice). ID semantics identical to `\q` (`script:`/`On*`/references). ※Rich labels (images, `\__l` and other script elements) are flattened to plain text |
| `surfaces***.txt` full read + filename-order merge (fixed 2026-06-27) | `Animation/SerikoParser.swift`, `Ghost/GhostManager+Animation.swift` |
| **Variable newline spacing (`\\n[half]` / numeric or percentage)** | `Ghost/GhostManager.swift` (`PlaybackUnit.newlineVariation`, `BalloonViewModel.lineAdvances`) and `Ghost/BalloonView.swift` line-based layout. `\\n[half]` and signed numeric/percentage values are retained as normal-line-height multipliers in playback order; `\\c` character/line truncation keeps the state synchronized. An explicit four-suite run passed 26 tests covering mapping, queue ordering, clearing, and anchor decoration state. Negative-value rendering is an offset approximation; in-ghost visual verification remains pending. |
| **Per-range `\\_a[ID,...]...\\_a` anchors and click routing** | `GhostManager.swift` (`BalloonAnchorRange` / `BalloonTextSegment`), `GhostManager+Balloon.swift` (`routeAnchorClick` / `onBalloonAnchorClicked`), and `BalloonView.swift` per-range tap handling. `On*` IDs dispatch the specified event; other IDs dispatch `OnAnchorSelectEx` (Reference0=clicked text, Reference1=ID, Reference2+=arguments) followed by `OnAnchorSelect`, preserving plugin origin. Underline/rectangle/visited decoration remains incomplete. 17 tests in the same focused suite. |
| **`%lastghostname` / `%lastobjectname` (install-time) supported** | `SakuraScript/EnvironmentExpander.swift` (static `lastInstalledGhostName`/`lastInstalledObjectName` + expansion). Also fixed Pattern 2 unconditional return so bare `%key` reaches Pattern 3. Set in `Ghost/GhostManager+System.swift:1515-1516` (before OnInstallComplete). Test `EnvironmentExpanderTests.swift` |

### C-1. MAYUNA (dressup)

| Item | Evidence (file:line) |
|---|---|
| **`\\![bind,...]` / `\\![bind-noevent,...]` execution, state mutation, and official events** | `Ghost/GhostManager+Dressup.swift` (single/repeated tuples, category-wide operations, omitted/empty-value toggles, `bind-noevent`, default bindings). `Ghost/GhostManager+Effects.swift` (category-wide expansion to part deltas; skip `OnDressupChanged` for 100+ elements). `Ghost/GhostManager.swift` / `SHIORIEvents/EventBridge.swift` (startup NOTIFY, menu GET, script ordering with only the final delta as GET). `OnDressupChanged` Reference0..4 and byte-value-1-delimited `OnNotifyDressupInfo` Reference* follow UKADOC. `OurinTests/DressupBindCommandTests.swift` has 25 tests, including a runtime request spy. |

### D. SHIORI Events

| Item | Evidence (file:line) |
|---|---|
| OnSecondChange/OnMinuteChange/OnHourTimeSignal now include Reference0-4 | `SHIORIEvents/TimerEmitter.swift:49-88` |
| GET/NOTIFY switch based on cantalk (GET when playable) | `SHIORIEvents/EventBridge.swift:430-454` |
| mikire/kasanari filled per-session (Reference1/Reference2) | `SHIORIEvents/EventBridge.swift` |
| OnBoot Reference0 (shell name) | `Ghost/GhostManager.swift:2688-2697` |
| OnFirstBoot Reference0 (vanish count) | `Ghost/GhostManager.swift:2675-2685` |
| Non-existent `OnSecondBoot` removed | `Ghost/GhostManager.swift:2670` |
| OnClose response script replayed before exit + Reference0 (exit reason) | `Ghost/GhostManager.swift:738-768` |
| **CommunicateBox `OnCommunicate` Reference propagation** | `Ghost/GhostManager.swift` (`communicateBoxReferences`) now generates `R0=user / R1=empty / R2=ECHO/1.0 / R3=body`, and `Ghost/GhostManager+System.swift` uses it for the submit path. The SSTP `R0=Sender / R1=Sentence` contract remains unchanged. The focused 56-test run, including `GhostUtilityCommandTests` and `YayaEmily4RegressionTests`, passed; the 2026-08-15 real Emily4 flow (“Talk” → `こんにちは` → OK) completed without displaying a literal `0` or floating fragments. Emily4 returned its dictionary-defined empty-display script `\0\s[0]`; whether it produces body text is ghost-dictionary behavior. |
| Event ID coverage (only 14 undefined out of UKADOC 252) | `SHIORIEvents/EventID.swift` (469 events; all `On*` IDs in `EventReferenceTable` are covered by a typed-ID audit test) |
| **OnMouseClick Reference4-6 fulfilled** (hit name/button/device type) | `SHIORIEvents/InputMonitor.swift:373-413` (R4=region, R5=button, R6="mouse"). UKADOC list_shiori_event compliant |
| **`EventBridge.start(enableAutoEvents:)` consolidated on real ghost load** | `Ghost/GhostManager.swift:643-646` (after OnBoot, `!isRunningUnderTests`), `2719-2737` (`startEventBridgeIfNeeded` restart-with-auto-events) |
| **WebSocket/archive 14 events implemented** | `SHIORIEvents/EventID.swift` (14 cases added). Dispatch: `Web/GhostManager+WebSocket.swift` (OnExecuteWebSocket Open/Receive/Close/Error/Send/State), `Ghost/GhostManager+System.swift` (OnExecuteHTTPStreaming, OnCompress/ExtractArchiveComplete/Failure), `Ghost/GhostManager+Display.swift` (OnMusicPlay/OnMusicPlayEx/OnSoundLoop/OnSoundStop/OnVideoPlayEx). Migrated existing `notifyCustom` strings to typed `notify(.X)`. Test `EventIDAuditTests.swift` |
| **Audio backend and sound events** | `Ghost/SoundPlayer.swift` (AVAudioPlayer, volume/pan/rate/seektime, manual loop-boundary detection, natural-finish/error delegates), `Ghost/GhostManager+Display.swift` (ghost/master preferred with legacy ghost/sound fallback, synchronous play/load/stop/wait ordering, preload/multi-instance/state cleanup). Fires `OnSoundStop` (reason), `OnSoundLoop` (loop boundary), and `OnSoundError` (command/errorCode/filename/message). `OurinTests/SoundPlayerTests.swift` 27 tests; build and serial test run passed. `\![sound,wait]` now uses runtime `waitForAudio`. |
| **Event Reference spec table-driven (foundation)** | New `SHIORIEvents/EventReferenceSpec.swift` (`EventReferenceTable.allSpecs` centralizes ~80 major events' Reference0..N semantic labels, category, and `notifyReturnIgnored`). `SHIORIEvents/EventBridge.swift` (`ShioriDispatcher.notifyReturnIgnored` now derived from `EventReferenceTable.notifyReturnIgnoredIDs`, replacing the hardcoded Set). Test `EventReferenceTableTests.swift` (exact match with legacy 38-item set, no duplicate IDs, major-event Reference verification). ※Migrating all 216 inline dispatch sites to the table is incremental |
| **Observer GET/NOTIFY delivery and real OS-state references** | `SHIORIEvents/EventBridge.swift` now carries `ShioriEventDelivery`, so observers can distinguish default GET updates from startup NOTIFY and suppress startup response scripts explicitly. `DisplayObserver.swift` emits real bpp/width/height and multi-display references for `OnDisplayChange`/`OnDisplayChangeEx`. `PowerObserver.swift` converts IOKit capacity, remaining time, source state, charging, and low-power mode into `OnBattery*`, including threshold-transition events. `SleepObserver.swift` maps screen sleep to `OnDisplayPowerStatus` instead of falsely emitting a screen-saver event, and `SessionObserver.swift` connects `NSWorkspace` session disconnect/reconnect notifications. Covered by `PowerObserverTests.swift`; all 804 unit tests passed. |
| **Real data and event wiring for OnDisplayHandover / OnRecycleBinStatusUpdate** | `DisplayObserver.swift` snapshots are connected to actual window initial placement, movement, and resizing. `OnDisplayHandover` emits initial `NOTIFY` (R0=init, R1=scope, R2=empty, R3=current monitor) and target-scoped `GET` on monitor changes (R0=update, R2=previous, R3=current). `RecycleBinObserver.swift` watches the home and connected-volume `.Trash`/`.Trashes/<uid>` directories with vnode sources, and emits count, allocated size, deltas, and R4=1 through `OnRecycleBinStatusUpdate` (startup `NOTIFY`, updates `GET`). `executeEmptyRecycleBin()` now refreshes the aggregate state after completion. Tests: `DisplayHandoverTests.swift` and `RecycleBinObserverTests.swift`. |
| **Real-data OnOSUpdateInfo monitoring and all-ghost OnCloseAll termination aggregation** | `OSUpdateObserver.swift` reads the real output of macOS `/usr/sbin/softwareupdate --list/--history`, converts the check time, latest execution time, and successful installed-update history into OnOSUpdateInfo R0/R1/R2〜, and emits startup `NOTIFY` plus `GET` on history changes. `AppDelegate` and `GhostManager.beginCloseSequence` send `OnCloseAll` to every running ghost and wait for empty, normal, or `\\-` response playback completion before terminating. Tests: `OSUpdateObserverTests.swift` and `CloseAllSequenceTests.swift`. |
| **Real data for initial Notify events** | New `SHIORIEvents/SystemNotificationData.swift` builds `OnNotifyUserInfo` (address/full name/unknown birthday/`undef`), `OnNotifyOSInfo` (macOS/CPU/memory/uptime), `OnNotifyFontInfo` (NSFontManager Reference*), and `OnNotifyInternationalInfo` (UTC offset/DST/ISO country/language) from the host. Startup delivery, user-name-change refresh, and locale-change international refresh are wired. Five tests in `SystemNotificationDataTests.swift`. |

### E. Property System

| Item | Evidence (file:line) |
|---|---|
| Longest-prefix resolution (first-dot split fixed) | `Property/PropertyManager.swift:128-141` |
| `currentghost.balloon` provider reachable | `Property/PropertyManager.swift:29` |
| Value cache invalidation + `system.*`/`pluginlist.*` excluded from cache | `Property/PropertyManager.swift:155`, `159-169`, `222-225` |
| `sakura.*`/`kero.*`/`ghost.*`/`shell.*` namespace aliases | `Property/PropertyManager.swift:40-43`, `279-299` |
| CPU usage calculation (perpetual 100% fixed) | `Property/PropertyManager.swift` |
| **Name parameters preserve case** (structural parts lowercased only) | `Property/PropertyManager.swift:143-166` (`lowercasePreservingParams`; preserves `shelllist(MyShell)` etc.). Test `PropertyTests.swift` (`nameParametersPreserveOriginalCase`) |
| **Deep hierarchy properties: root-cause fix, live wiring, and new UI features** (2026-07-01) | Audit found the `currentghost.seriko.cursor.*`/`tooltip.*`/`balloon.scope(ID).*` parse/SET/GET logic was **already implemented** (`GhostPropertyProvider.swift`/`BalloonPropertyProvider.swift`). Identified the actual root cause: `Ghost/GhostManager.swift` left `sakuraEngine.propertyManager` on `SakuraScriptEngine()`'s default (a `PropertyManager` instance separate from `PropertyManager.shared`), so `\![set,property,...]` writes were invisible to every other read path (`SSTPDispatcher`/`ResourceBridge`/etc.) — a gap affecting all settable properties, not just cursor/tooltip. Fixed by assigning `sakuraEngine.propertyManager = PropertyManager.shared` in `GhostManager.init`. Regression test `OurinTests/PropertySetPropertyWiringTests.swift`. Also implemented new UI features for collision-region-driven cursor switching (new `SHIORIEvents/SerikoCursorController.swift`; previously zero `NSCursor` usage anywhere) and tooltip display (new `SHIORIEvents/SerikoTooltipController.swift`), wired into the existing hit-test resolution in `InputMonitor.swift` (`GhostManager+Surface.swift:459 collisionRegionName`). Tests `SerikoCursorControllerTests.swift`/`SerikoTooltipControllerTests.swift`. A mechanical cross-check against the 147 UKADOC property system items added the genuinely-missing leaf properties (`os.dst`, `os.locale.language/country`, `power.battery.lifetime`, `monitor.index(ID).bpp`, `disk.index(ID).type`, `network.type/.cost`) to `SystemPropertyProvider` in `PropertyManager.swift`. `network.downlink`/`downlink.estimate` remain undefined — macOS has no public API for link bandwidth (documented as a platform limitation, same as `dnd.mode`). Test `PropertySystemTests.swift` (`System properties - deep leaf items`). |

### F. YAYA Language VM

| Item | Evidence (file:line) |
|---|---|
| **Dictionary CP932/Shift_JIS → UTF-8 conversion (iconv)** | `yaya_core/src/DictionaryManager.cpp:13,46-89,119-172` |
| `load()` returns false on total failure | `yaya_core/src/DictionaryManager.cpp:296` |
| Per-dic encoding propagated to C++ side | `USL/ShioriLoader.swift:232-244` → `YayaCore.cpp:147-162` |
| Full SHIORI response header parsing ("Value:" substring search removed) | `yaya_core/src/YayaCore.cpp:265-301` |
| RE_GETSTR / RE_GETPOS / RE_GETLEN | `yaya_core/src/VM.cpp:2375-2387` |
| RE_OPTION (icase/multiline) | `yaya_core/src/VM.cpp:2390-2396` |
| RE_REPLACEEX | `yaya_core/src/VM.cpp:2411` |
| RE_ASEARCH | `yaya_core/src/VM.cpp:2429-2442` |
| SAVEVAR / RESTOREVAR (JSON persistence) | `yaya_core/src/VM.cpp:2603-2690` |
| DICLOAD / DICUNLOAD | `yaya_core/src/VM.cpp:2777-2794` |
| MKDIR / RMDIR / FENUM (real `std::filesystem` implementations) | `yaya_core/src/VM.cpp:2153-2179`, `2039-2060` |
| **`&` by-reference semantics implemented (E.Swap mutates in-place)** | `yaya_core/src/VM.cpp:858-870` (E.Swap special-cased at Call site), `1014-1055` (`tryResolveReference`/`readReference`/`writeReference`). Swaps locals, array elements, and globals. Regression test `OurinTests/ShioriLoaderTests.swift` (`yayaCoreESwapByReference`) |
| **standalone `when` no longer executes unconditionally** (a `when` outside `case` has no dispatch value → no-op) | `yaya_core/src/VM.cpp:943-952` (`WhenClause` handler returns Void without running body). `when` inside `case` still handled by the `CaseNode` handler |
| **`READFMO` implemented** (synchronous host_op:"fmo" IPC fetches FMO snapshot from Swift) | `yaya_core/src/VM.cpp:2893-2906` (builtin), `YayaCore.cpp:fmoOperation` (host_op bridge), `VM.hpp:VMCallback::fmoOperation`. Swift: `Yaya/YayaAdapter.swift` (`host_op:"fmo"` handler + `fmoSnapshotProvider`), `OurinApp.swift:166-172` (provider wiring). Test `ShioriLoaderTests.swift` (`yayaCoreReadFmoViaHostOp`) |
| **`ASEARCHPOS` implemented** (position-based array search returning a single index) | `yaya_core/src/VM.cpp` (`builtins_["ASEARCHPOS"]`, placed after ASEARCHEX). Documented in `FUNCTION_REFERENCE.md` / `examples/all_functions_test.dic` |
| **`SRAND` now actually seeds the RNG (was a no-op stub) + new real-Emily4-ghost regression tests** (2026-07-01) | `yaya_core/src/RandomEngine.hpp` (new; the shared `yaya_rng::engine()` used by `RAND`/`ANY`/`Value::asString()`'s array→string random selection), `yaya_core/src/VM.cpp` (`SRAND` now calls `yaya_rng::engine().seed(...)`), `yaya_core/src/Value.cpp` (array→string conversion also uses the shared engine). `OurinTests/YayaEmily4RegressionTests.swift` verifies real Emily4 requests return HTTP 200 with Sakura Script, all 33 dictionaries load cleanly, fixed `SRAND` seeds reproduce random-talk selection, and YAYA `REQ.COMMAND`, `--` output areas, `void`, and bare `return` semantics. It reuses production `collectDicEntries` (`USL/ShioriLoader.swift`) so `yaya.txt` include/dic resolution matches production exactly |

### G. Plugin System

| Item | Evidence (file:line) |
|---|---|
| PLUGIN/2.0M GET/NOTIFY frame construction | `PluginHost/PluginProtocol.swift` |
| macOS `.plugin`/`.bundle` lifecycle | `PluginHost/Plugin.swift`, `PluginEvent/PluginEventDispatcher.swift` |
| Windows DLL plugins metadata-only, distinguished (platform difference documented) | `PluginHost/PluginRegistry.swift`; `docs/SPEC_PLUGIN_2.0M_ja-jp.md` |
| SAORI/1.0 host (charset conversion incl. Shift_JIS) | `SaoriHost/SaoriLoader.swift:44-61`, `SaoriProtocol.swift:158-176` |
| **PLUGIN/2.0 host→plugin notification event coverage audit** (2026-07-01). All 17 notification events from `docs/PLUGIN_EVENT_2.0M_SPEC_FULL_ja-jp.md` §4 (`version`/`installedplugin`/`installedghostname`/`installedballoonname`/`ghostpathlist`/`balloonpathlist`/`headlinepathlist`/`pluginpathlist`/`OnSecondChange`/`OnOtherGhostTalk`/`OnGhostBoot`/`OnGhostExit`/`OnGhostInfoUpdate`/`OnMenuExec`/`OnInstallComplete`/`OnChoiceSelect(Ex)`/`OnAnchorSelect(Ex)`) verified to have both send code and a call site; no gaps found | `PluginEvent/PluginEventDispatcher.swift` (senders), `OurinApp.swift`/`Ghost/GhostManager.swift`/`Ghost/GhostManager+System.swift`/`Ghost/GhostManager+Balloon.swift` (call sites). Removed the unused `onSecondChange()` public method (the actual per-second notification already calls `sendFrame` directly inside `setupTimer()`). `calendarskinpathlist`/`calendarpluginpathlist` were found to be UKADOC-non-standard Ourin extensions (worth documenting separately) |

### H. NAR Packages

| Item | Evidence (file:line) |
|---|---|
| `refreshundeletemask` colon-delimited (UKADOC; comma tolerated) | `NarInstall/InstallTxtParser.swift:102-108` |
| `refresh`/`refreshundeletemask` protection mask implemented | `NarInstall/LocalNarInstaller.swift:83-85`, `175-184` |
| Bundled balloon (`balloon.directory`) installed | `NarInstall/LocalNarInstaller.swift:94-102`, `207-223` |
| `accept` allows overwrite updates | `NarInstall/LocalNarInstaller.swift:71-80` |
| ZIP entry backslash → forward slash normalization | `NarInstall/ZipUtil.swift:56-57`, `61-99` |
| Zip Slip mitigation, PK header validation | `NarInstall/LocalNarInstaller.swift:39-81` |
| **install.txt `charset` key two-pass read** (declared encoding priority) | `NarInstall/InstallTxtParser.swift:46-83` (`declaredCharset` detects charset line → preferred decode, fallback UTF-8→SJIS) |

### I. FMO

| Item | Evidence (file:line) |
|---|---|
| **No premature shm_unlink** (name retained during process lifetime) | `FMO/FmoSharedMemory.swift:32-38`, `80-86` |
| Multi-instance detection name unified to `/ourin_fmo` | `FMO/FmoManager.swift:91-92`, `98-111` |
| GetFMO returns SSP-compatible record format (`id.key\x01value\r\n`) | `FMO/FmoManager.swift:156-178`; `SSTP/SSTPDispatcher.swift:530-533` |
| `FmoCompatibilityView` structured diagnostics | `FMO/FmoManager.swift:47-87` |
| POSIX shared memory documented as platform difference | `docs/About_FMO_ja-jp.md`, `docs/About_FMO_en-us.md` |

### J. Balloons, Shells, Resources

| Item | Evidence (file:line) |
|---|---|
| Balloon descript.txt SJIS fallback, `balloons*.txt` merge | `Balloon/DescriptorLoader.swift`, `Ghost/BalloonConfig.swift` |
| **descript.txt `charset` line two-pass read** (declared encoding priority) | `Balloon/DescriptorLoader.swift:22-50` (detect charset via isoLatin1 → re-decode Shift_JIS/UTF-8). Test `BalloonTests.swift` (`descriptorCharsetTwoPassShiftJIS`) |
| SERIKO interval/pattern parsing & execution | `Animation/SerikoParser.swift`, `SerikoExecutor`, `AnimationEngine` |
| **SERIKO `collisionex` geometry/image-colour hit testing and animation-only regions** (2026-08-14) | `Animation/AnimationEngine.swift:75-208,342-488` (rectangle/ellipse/circle/polygon/region shape retention, standard/legacy parsing, shell-relative image RGB regions with inversion, and active-only `animation*.collision*` storage), `Ghost/GhostManager+Animation.swift:370-378` (injects the shell directory as the resolver), `Ghost/GhostManager+Surface.swift:636-656` (live mouse-event resolution with active IDs). `AnimationEngineTests.swift` covers inactive filtering, ellipse/circle, image-colour inversion, precedence, and reload deduplication. |
| surfaces*.txt full read (fixed 2026-06-27) | `Animation/SerikoParser.swift`, `Ghost/GhostManager+Animation.swift` |
| **`surfacetable.txt` systematic processing and surface-test UI** (2026-08-12) | New `Animation/SurfaceTableParser.swift` (`SurfaceTable`/`SurfaceGroup`/`SurfaceEntry` data model + `SurfaceTableParser.parse`). Parses `group,NAME { scope,N .. id,NAME }` syntax, `__disabled`/`__parts` markers, and `option,DisableNoDefineSurfaces`. `Animation/SerikoParser.swift` separates surfacetable.txt from the surfaces*.txt bundle. `Ghost/GhostManager.swift` routes `\![open,surfacetest]` to `Ghost/SurfaceTestWindow.swift`, which provides disabled-group filtering, real image previews, scope switching, and click-to-apply. Tests: `SurfaceTableParserTests.swift` / `SurfaceTestCatalogTests.swift`.|

### K. 2026-07-05 Compatibility Improvement Round

Items resolved in the fix round following a full re-audit by three Sonnet investigation agents (including new gaps absent from prior audits).

| Item | Evidence (file:line) |
|---|---|
| **yaya_core: implemented the `parallel` modifier** (used in 41 places in Emily4; its absence silently corrupted random-talk candidate arrays via nesting) | `yaya_core/src/AST.hpp` (`ParallelNode`), `Parser.cpp` (contextual detection, not keyword-ized for backward compat), `VM.cpp` (one-level flattening in array/sequential collection + uniform random pick in non-array contexts, same RNG as SRAND). Verified against real Emily4: candidate pool 278 entries / 0 nested. Tests in `OurinTests/YayaEmily4RegressionTests.swift` (flattening + SRAND reproducibility) |
| **yaya_core: `executeBlock` no longer uses assignment values as block values** (fixes nested-array leak via `if { _tmp = array }`; matches upstream "assignments are not output candidates") | `yaya_core/src/VM.cpp` (`executeBlock`) |
| **yaya_core: `#globaldefine` / `#define` preprocessor** (used 8 times in Emily4 `aya_ghostchange_core.dic`; previously `#` lines were unconditionally treated as comments, losing case-syntax macros) | `yaya_core/src/DictionaryManager.cpp` (`preprocessDirectives`: raw replacement in registration order; #define=file scope / #globaldefine=all subsequent files), `VM.hpp` (`registerGlobalDefine` aligned with ISGLOBALDEFINE/PROCESSGLOBALDEFINE) |
| **yaya_core: real `LOGGING` / `TRANSLATE`** (LOGGING=stderr output; TRANSLATE per upstream yaya-shiori sysfunc.cpp: per-character set mapping with `-` range expansion, `\` escapes, delete mode when target set empty, last-char padding) | `yaya_core/src/VM.cpp` |
| **`OnDestroy` event now fired** (NOTIFY, sent directly to the target ghost just before SHIORI unload; Reference0=`reload` on reload, no Reference otherwise; per UKADOC) | `Ourin/Ghost/GhostManager.swift` (`shutdown()` / `pendingDestroyReason`), `SHIORIEvents/EventReferenceSpec.swift` |
| **Multi-ghost SSTP response side-effect routing** (Surface/Balloon/BalloonOffset/Icon/EXECUTE resolved to the target ghost via ReceiverGhostName; unspecified falls back to primary = unchanged single-ghost behavior) | `Ourin/OurinApp.swift` (`ghostManagerForShioriRequest` / `receiverTargetKey`), `SSTP/SSTPDispatcher.swift`. Test in `SSTPDispatcherTests.swift` |
| **`OnOffscreen` / `OnOverlap` / `OnOtherOffscreen` / `OnOtherOverlap` implemented** (GET; Reference0=current / Reference1=previous, byte-1 separators; transition detection on the per-second tick reusing `mikireScopes`/`kasanariScopes`; OnOther* span all ghosts with `SakuraName/ID` labels) | `Ourin/Ghost/GhostManager+Window.swift` (pure functions `offscreenRef0`/`overlapRef0` + `overlapTransitionEvents`), `SHIORIEvents/EventBridge.swift` (`dispatchOverlapTransitions`). Tests in `OverlapTransitionTests.swift` |
| **Settings values actually wired** (fixed read-back bug; SMAppService login item (macOS 13+); CP932 acceptance gate for external SSTP; file log sink; auto-update check marked "unused" in UI) | `Ourin/ContentView.swift`, `ExternalServer/EncodingNormalizer.swift` (`acceptsCP932`, default true = unchanged behavior), `Utils/Log.swift` (`LogFileSink`). Tests `EncodingNormalizerCP932GateTests.swift` / `LogFileSinkTests.swift` |
| **NAR `type,saori` support** (with accept → target ghost's `ghost/master/<dir>`; without → shared `saori/<dir>`; documented as an Ourin-defined extension since UKADOC does not specify it) | `Ourin/NarInstall/Paths.swift` (`installTarget`). Test in `NarInstallTests.swift` |
| **Per-ghost SHIORI Resource separation** (`OurinResource.<ghostKey>.<key>` namespace + one-time backfill of legacy global values by the first ghost launched; fixes cross-contamination with concurrent ghosts) | `Ourin/Property/ResourceManager.swift`, `Ghost/GhostManager.swift` (`lazy var resourceManager`). Tests in `ResourceManagerSeparationTests.swift` |
| **`\f[anchor*]` decoration subcommands implemented** (selected/non-selected/visited style, brush, pen, and font colors are applied as independent states; all SetROP2 method variants are parsed and composited against balloon pixels) | `Ourin/Ghost/GhostManager.swift` (`\f` switch), `Ghost/BalloonView.swift`, `Ghost/BalloonConfig.swift`, `Ghost/AnchorRasterOperation.swift`, `Ghost/AnchorRasterImageRenderer.swift` |
| **DevTools mock UI adjudication** (External Events Harness wired to real APIs: live server status, real TCP/HTTP sends with response display, restart-all-servers; Headline/Balloon preview, Signpost, Resource Overlay, and Plugin Enabled toggle marked "Preview only") | `Ourin/ContentView.swift`, `ExternalServer/ServerMetrics.swift` (public `requestCount`) |
| **Corrected NAR composite-install documentation** (the "missing" claim in AUDITS_TODO was wrong; already implemented) | `Ourin/NarInstall/Paths.swift:219-236` (calendar/skin, calendar/plugin, legacy calendar, language) |
| **NAR network update deletion and path safety** (2026-08-14) | `NarInstall/LocalNarInstaller.swift` retrieves the optional server-side `delete.txt` after a successful update (including deletion-only updates), accepts its `charset` line, removes only validated paths under the target root, and keeps `testonly` non-mutating. `InstallTxtParser.swift` rejects dot-segment / absolute / drive paths in update descriptors; `ZipUtil.swift` uses component-aware root checks. `NarInstallTests.swift` covers MD5-verified update + Windows-style `delete.txt` paths, traversal rejection, and no-delete 404 behavior. |

---

## 移管記録（2026-08-15 AUDITS_TODO.md 一新に伴う）/ Items migrated from AUDITS_TODO.md (2026-08-15 renewal)

`AUDITS_TODO.md` を未完項目のみに一新した際、同ファイル内に「完了」注記付きで残っていた以下の項目を本ファイルへ移管した。各項目の詳細な根拠・経緯は本ファイルの既存セクションおよび `AUDITS_TODO.md` の git 履歴（2026-08-15 以前）に保存されている。

When `AUDITS_TODO.md` was renewed to pending-only, the following items (already marked completed there) were migrated here. Full evidence remains in the sections above and in the pre-2026-08-15 git history of `AUDITS_TODO.md`.

| 分野 / Area | 項目 / Item | 完了日 / Completed |
|---|---|---|
| SHIORI | SHIORI 2.x ABI 互換レイヤーコア（`Shiori2CompatAdapter`、GET Version検出・イベント/TEACH/レスポンス変換・Shift_JIS） | 2026-07-09 |
| SHIORI | Word/String/Status/OwnerGhostName/OtherGhostName/Communicate 変換の単体テスト＋`OnTalkRequest` 不一致修正 | 2026-07-09 |
| SHIORI | SHIORI 2.x「二重実装」懸念は disjoint な役割分担と確認（統合不要と判定） | 2026-07-09 |
| SHIORI | SecurityLevel external 伝播（`dispatchExternal` 集約、TCP/HTTP/XPC 全経路） | 2026-07-08 |
| SSTP | 210 Break nobreak キューイング＋実ゴースト再生状態接続（`SSTPBreakQueue`/`isAnyGhostPlaying`） | 2026-07-08 / 2026-08-12 |
| SakuraScript | `\![cancel,http,...]`（`httpStreamingTasks` 追跡＋`cancelHTTPStreaming`） | 2026-07-09 |
| SakuraScript | `moveasync` キャンセル・レガシー `fix` 軸・時限 `scaling`/`alpha`（`GhostUtilityCommandTests`） | 2026-08-14 |
| SakuraScript | lexicon 内蔵辞書（`SakuraScriptLexicon.json` 10キー注入） | 2026-07-08 |
| SHIORIイベント | `EventReferenceTable` の `On*` 型定義網羅＋発火側静的照合（`EventIDAuditTests` 3種、`OnArchiveComplete` 型付き化） | 2026-08-14 |
| NAR | 同時インストール `*.directory` 系完全処理＋`ZipUtil.secureCopyTree` の /private/var バグ修正 | 2026-07-08 |
| バルーン | レガシー画像透過（バルーン側左上ピクセル `applyTopLeftPixelChromakey`） | 2026-07-08 |
| バルーン | 動画レンダラ非対応コーデックのサイレント失敗解消（`OnVideoPlayFailure` 新設） | 2026-07-09 |
| K監査 | アンカー装飾（`anchorstyle`/`anchorvisited*`/ROP2合成）実装 | 2026-08-14 |
| K監査 | `\n[half]`/`%` 改行間隔（`lineAdvances` 接続、4スイート26件） | 2026-08-14 |
| K監査 | `vanishbymyself` 消滅経路（確認・イベント・ゴミ箱・次ゴースト起動） | 2026-08-14 |
| K監査 | `updateother` 対象解決（balloon/shell/plugin/headline/language、`testonly` 回帰テスト） | 2026-08-14 |
| K監査 | `\f[cursor*]` と選択肢 hover（`OnChoiceEnter`/500ms `OnChoiceHover`） | 2026-08-14 |
| K監査 | `BalloonRichTextViewModel` スタブ解消（valign/subscript/superscript） | 2026-08-14 |
| K監査 | `PropertyManager` AppKit スレッド安全性 | 2026-08-14 |
| ドキュメント | L監査対応: 完了済み計画・テンプレ19ファイルを `docs/archive/` へ移動、`yaya_core/README.md` 同期、BLOCKER_TRACKER と IMPLEMENTATION_STATUS_SUMMARY のブロッカー矛盾解消、`.serena/memories`（SstpRouter・macOS版数）修正、CLAUDE/AGENTS の AppDelegate 記述修正、yaya_core 進捗系md への時点注記追加 | 2026-08-15 |

---

*本ファイルは監査レポート（GLM/CODEX/CLAUDE/AGY）の完了項目を集約したものです。未完項目は `AUDITS_TODO.md` を参照してください。*

*This file consolidates completed items from audit reports (GLM/CODEX/CLAUDE/AGY). For pending items, see `AUDITS_TODO.md`.*
