# Ourin 監査項目 — 完了済み / Audit Items — Completed

**最終更新 / Last Updated**: 2026-07-13
**集約元 / Consolidated from**: AUDIT_GLM / AUDIT_CODEX / AUDIT_CODEX_2026-06-27 / AUDIT_CLAUDE / AUDIT_AGY（各 ja-jp / en-us）
**検証方法 / Verification**: 全項目を現状ソースコード（file:line）と照合して完了判定。

---

## 日本語

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
| **HTTP レスポンス行末を `\r` → `\r\n` に修正**（RFC 7230 §3 準拠） | `ExternalServer/SstpHttpServer.swift:112-118`, `149-154`（成功/MCPパスの行末を `\r\n` 化。エラーパスは元から `\r\n`） |
| **外部SSTP NOTIFY の ValueNotify スクリプトがバルーン再生される** | `SSTP/SSTPDispatcher.swift:236-247`（`method != .notify` ガードを撤廃し、NOTIFY 由来 ValueNotify を `runNotifyScript` で再生）。`SHIORIEvents/EventBridge.swift:221-240`（`playScriptOnGhostsResolving(notify:)` 追加） |
| **SSTP パーサーが bare `\n` を許容**（LFのみ送信するツール向け正規化） | `SSTP/SSTPParser.swift:7-10`（先頭CR無しLFをCRLFへ正規化してから分割）。テスト `ExternalServerTests.swift`（`parserToleratesBareLFLineEndings`） |

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
| **`\__t`(TeachBox) / `\__q`(選択肢キュー) / `\__c`(CommunicateBox) メタタグ実装** | `Ghost/GhostManager.swift`（`case "__t"`/`"__c"`）、`didEmit` の `case .choiceQueue`。テスト `SakuraScriptEngineTests.swift`（`metaTagTeachBox`/`metaTagCommunicateBox`/`choiceQueueCommand`/`choiceQueueRangeSyntaxBindsDisplayText`/`choiceQueueRangeTextNotShownInBalloon`/`choiceQueueScriptFormKeepsTitle`/`choiceQueueMultipleRangesProduceMultipleChoices`） |
| **`\__q` 範囲ベース表示テキスト結合（`\__q[ID,...]text\__q`）** | `SakuraScript/SakuraScriptEngine.swift`（`mergeChoiceQueueRanges` ポストプロセス + `.choiceQueue(title:id:references:)` トークン）。`Ghost/GhostManager.swift`（`case .choiceQueue` で title 付き選択肢生成）。ID 解釈は `\q` と同一（`script:`/`On*`/references）。※リッチラベル（画像・`\_l` 等のさくらスクリプト要素）はプレーンテキスト化される制限あり |
| `surfaces***.txt` の全読み込みとファイル名順結合（2026-06-27修正） | `Animation/SerikoParser.swift`, `Ghost/GhostManager+Animation.swift`（`docs/COMPAT_FIXES_2026-06.md` 参照） |
| **`%lastghostname` / `%lastobjectname`（インストール時用）対応** | `SakuraScript/EnvironmentExpander.swift`（static `lastInstalledGhostName`/`lastInstalledObjectName` + 展開）。併せて Pattern 2 の無条件 return を修正し bare `%key` が Pattern 3 で展開されるようにした。設定元 `Ghost/GhostManager+System.swift:1515-1516`（OnInstallComplete 直前）。テスト `EnvironmentExpanderTests.swift` |

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
| イベントID定義の網羅性（UKADOC 252イベント中14未定義のみ） | `SHIORIEvents/EventID.swift`（404イベント定義） |
| **OnMouseClick の Reference4-6 が充足**（当たり判定名/ボタン/デバイス種別） | `SHIORIEvents/InputMonitor.swift:373-413`（R4=region, R5=button, R6="mouse"）。UKADOC list_shiori_event 準拠 |
| **`EventBridge.start(enableAutoEvents:)` を実ゴーストロード完了時に集約有効化** | `Ghost/GhostManager.swift:643-646`（OnBoot 後、`!isRunningUnderTests` で有効化）、`2719-2737`（`startEventBridgeIfNeeded` で再起動付き有効化） |
| **WebSocket/アーカイブ系14イベント実装** | `SHIORIEvents/EventID.swift`（14ケース追加）。ディスパッチ: `Web/GhostManager+WebSocket.swift`（OnExecuteWebSocket Open/Receive/Close/Error/Send/State）、`Ghost/GhostManager+System.swift`（OnExecuteHTTPStreaming, OnCompress/ExtractArchiveComplete/Failure）、`Ghost/GhostManager+Display.swift`（OnMusicPlay/OnMusicPlayEx/OnSoundLoop/OnSoundStop/OnVideoPlayEx）。既存の `notifyCustom` 文字列を型付き `notify(.X)` へ移行。テスト `EventIDAuditTests.swift` |
| **イベント Reference 仕様の表駆動化（基盤）** | `SHIORIEvents/EventReferenceSpec.swift` 新設（`EventReferenceTable.allSpecs` で主要約80イベントの Reference0..N 意味ラベル・カテゴリ・`notifyReturnIgnored` を一元定義）。`SHIORIEvents/EventBridge.swift`（`ShioriDispatcher.notifyReturnIgnored` を `EventReferenceTable.notifyReturnIgnoredIDs` から派生し、ハードコード Set を廃止）。テスト `EventReferenceTableTests.swift`（従来38件セットとの完全一致・重複IDなし・主要イベント Reference 検証）。※全216箇所の発火コードの表駆動移行は漸次対応 |

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
| **`SRAND` を実際にRNGへ反映（従来はシードを無視するスタブ）＋実在Emily4ゴーストの回帰テスト新設**（2026-07-01） | `yaya_core/src/RandomEngine.hpp`（新設、`RAND`/`ANY`/`Value::asString()`の配列→文字列ランダム選択が共有する`yaya_rng::engine()`）、`yaya_core/src/VM.cpp`（`SRAND`が`yaya_rng::engine().seed(...)`を呼ぶよう修正）、`yaya_core/src/Value.cpp`（array→string変換も共有エンジンを使用）。`OurinTests/YayaEmily4RegressionTests.swift`新設：`emily4OnFirstBootProducesExactGoldenTalk`（Emily4実辞書一式をロードし`OnFirstBoot`のgolden文字列完全一致を検証）、`emily4AllDictionariesLoadWithoutParseFailure`（33件全辞書のロード成功を回帰確認）、`emily4RandomTalkIsReproducibleWithFixedSeed`（`SRAND`固定シードで雑談配列選択が再現可能なことを確認）。本番の`collectDicEntries`（`USL/ShioriLoader.swift`）をテストからも再利用し、`yaya.txt`のinclude/dic解決を本番と同一手順で検証 |

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
| surfaces*.txt 全読み込み（2026-06-27修正） | `Animation/SerikoParser.swift`, `Ghost/GhostManager+Animation.swift` |
| **`surfacetable.txt` の体系的処理**（2026-06-30） | `Animation/SurfaceTableParser.swift` 新設（`SurfaceTable`/`SurfaceGroup`/`SurfaceEntry` データモデル + `SurfaceTableParser.parse`）。`group,NAME { scope,N .. id,NAME }` 構文・`__disabled`/`__parts` マーカー・`option,DisableNoDefineSurfaces` を解釈。`Animation/SerikoParser.swift`（`SurfaceDefinitionLoader.loadSurfaceTable` 追加、surfacetable.txt を surfaces*.txt バンドルから分離）。`Ghost/GhostManager.swift:225`（`surfaceTable` プロパティ）、`Ghost/GhostManager+Surface.swift`（`loadImage` で未定義サーフェス描画スキップ）。テスト `SurfaceTableParserTests.swift`。※サーフィステストダイアログ UI（`\![open,surfacetest]`）は別課題 |

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
| **`\f[anchor*]` 装飾サブコマンド群の受理**（`anchorfontcolor`/`anchornotselectfontcolor` は文字色へ反映。style/brush/pen/method/visited 系14種は受理＋debug ログでサイレント無視を解消） | `Ourin/Ghost/GhostManager.swift`（`\f` switch） |
| **DevTools モック UI の裁定**（External Events Harness を実配線: 実サーバステータス・実 TCP/HTTP 送信・応答表示・全サーバ再起動。Headline/Balloon プレビュー・Signpost・Resource Overlay・Plugin Enabled トグルは「Preview only」注記） | `Ourin/ContentView.swift`、`ExternalServer/ServerMetrics.swift`（`requestCount` 公開） |
| **NAR 複合 install 種別の記載訂正**（AUDITS_TODO の「不足」記載は誤りで、実装済みだったことを確認） | `Ourin/NarInstall/Paths.swift:219-236`（calendar/skin・calendar/plugin・calendar 旧互換・language） |

---

## English

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
| **HTTP response line ending fixed `\r` → `\r\n`** (RFC 7230 §3 compliant) | `ExternalServer/SstpHttpServer.swift:112-118`, `149-154` (success/MCP paths now `\r\n`; error path already was) |
| **External SSTP NOTIFY ValueNotify script replayed to balloon** | `SSTP/SSTPDispatcher.swift:236-247` (removed `method != .notify` guard; NOTIFY ValueNotify replayed via `runNotifyScript`). `SHIORIEvents/EventBridge.swift:221-240` (added `playScriptOnGhostsResolving(notify:)`) |
| **SSTP parser tolerates bare `\n`** (LF-only normalization for de facto tools) | `SSTP/SSTPParser.swift:7-10` (normalizes CR-less LF to CRLF before splitting). Test `ExternalServerTests.swift` (`parserToleratesBareLFLineEndings`) |

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
| **`\__t` (TeachBox) / `\__q` (choice queue) / `\__c` (CommunicateBox) meta-tags implemented** | `Ghost/GhostManager.swift` (`case "__t"`/`"__c"`), `didEmit` `case .choiceQueue`. Tests `SakuraScriptEngineTests.swift` (`metaTagTeachBox`/`metaTagCommunicateBox`/`choiceQueueCommand`/`choiceQueueRangeSyntaxBindsDisplayText`/`choiceQueueRangeTextNotShownInBalloon`/`choiceQueueScriptFormKeepsTitle`/`choiceQueueMultipleRangesProduceMultipleChoices`) |
| **`\__q` range-based display-text binding (`\__q[ID,...]text\__q`)** | `SakuraScript/SakuraScriptEngine.swift` (`mergeChoiceQueueRanges` post-process + `.choiceQueue(title:id:references:)` token). `Ghost/GhostManager.swift` (`case .choiceQueue` produces a titled choice). ID semantics identical to `\q` (`script:`/`On*`/references). ※Rich labels (images, `\__l` and other script elements) are flattened to plain text |
| `surfaces***.txt` full read + filename-order merge (fixed 2026-06-27) | `Animation/SerikoParser.swift`, `Ghost/GhostManager+Animation.swift` |
| **`%lastghostname` / `%lastobjectname` (install-time) supported** | `SakuraScript/EnvironmentExpander.swift` (static `lastInstalledGhostName`/`lastInstalledObjectName` + expansion). Also fixed Pattern 2 unconditional return so bare `%key` reaches Pattern 3. Set in `Ghost/GhostManager+System.swift:1515-1516` (before OnInstallComplete). Test `EnvironmentExpanderTests.swift` |

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
| Event ID coverage (only 14 undefined out of UKADOC 252) | `SHIORIEvents/EventID.swift` (404 events) |
| **OnMouseClick Reference4-6 fulfilled** (hit name/button/device type) | `SHIORIEvents/InputMonitor.swift:373-413` (R4=region, R5=button, R6="mouse"). UKADOC list_shiori_event compliant |
| **`EventBridge.start(enableAutoEvents:)` consolidated on real ghost load** | `Ghost/GhostManager.swift:643-646` (after OnBoot, `!isRunningUnderTests`), `2719-2737` (`startEventBridgeIfNeeded` restart-with-auto-events) |
| **WebSocket/archive 14 events implemented** | `SHIORIEvents/EventID.swift` (14 cases added). Dispatch: `Web/GhostManager+WebSocket.swift` (OnExecuteWebSocket Open/Receive/Close/Error/Send/State), `Ghost/GhostManager+System.swift` (OnExecuteHTTPStreaming, OnCompress/ExtractArchiveComplete/Failure), `Ghost/GhostManager+Display.swift` (OnMusicPlay/OnMusicPlayEx/OnSoundLoop/OnSoundStop/OnVideoPlayEx). Migrated existing `notifyCustom` strings to typed `notify(.X)`. Test `EventIDAuditTests.swift` |
| **Event Reference spec table-driven (foundation)** | New `SHIORIEvents/EventReferenceSpec.swift` (`EventReferenceTable.allSpecs` centralizes ~80 major events' Reference0..N semantic labels, category, and `notifyReturnIgnored`). `SHIORIEvents/EventBridge.swift` (`ShioriDispatcher.notifyReturnIgnored` now derived from `EventReferenceTable.notifyReturnIgnoredIDs`, replacing the hardcoded Set). Test `EventReferenceTableTests.swift` (exact match with legacy 38-item set, no duplicate IDs, major-event Reference verification). ※Migrating all 216 inline dispatch sites to the table is incremental |

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
| **`SRAND` now actually seeds the RNG (was a no-op stub) + new real-Emily4-ghost regression tests** (2026-07-01) | `yaya_core/src/RandomEngine.hpp` (new; the shared `yaya_rng::engine()` used by `RAND`/`ANY`/`Value::asString()`'s array→string random selection), `yaya_core/src/VM.cpp` (`SRAND` now calls `yaya_rng::engine().seed(...)`), `yaya_core/src/Value.cpp` (array→string conversion also uses the shared engine). New `OurinTests/YayaEmily4RegressionTests.swift`: `emily4OnFirstBootProducesExactGoldenTalk` (loads the real Emily4 dictionary set and asserts an exact golden match for `OnFirstBoot`), `emily4AllDictionariesLoadWithoutParseFailure` (regression-checks all 33 dictionaries load cleanly), `emily4RandomTalkIsReproducibleWithFixedSeed` (confirms a fixed `SRAND` seed reproduces the same random-talk-array selection). Reuses the production `collectDicEntries` (`USL/ShioriLoader.swift`) from the test so `yaya.txt` include/dic resolution matches production exactly |

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
| surfaces*.txt full read (fixed 2026-06-27) | `Animation/SerikoParser.swift`, `Ghost/GhostManager+Animation.swift` |
| **`surfacetable.txt` systematic processing** (2026-06-30) | New `Animation/SurfaceTableParser.swift` (`SurfaceTable`/`SurfaceGroup`/`SurfaceEntry` data model + `SurfaceTableParser.parse`). Parses `group,NAME { scope,N .. id,NAME }` syntax, `__disabled`/`__parts` markers, and `option,DisableNoDefineSurfaces`. `Animation/SerikoParser.swift` (added `SurfaceDefinitionLoader.loadSurfaceTable`, separating surfacetable.txt from the surfaces*.txt bundle). `Ghost/GhostManager.swift:225` (`surfaceTable` property), `Ghost/GhostManager+Surface.swift` (`loadImage` skips undefined surfaces). Test `SurfaceTableParserTests.swift`. ※Surface-test dialog UI (`\![open,surfacetest]`) is a separate task |

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
| **`\f[anchor*]` decoration subcommands accepted** (`anchorfontcolor`/`anchornotselectfontcolor` reflected into text color; the other 14 style/brush/pen/method/visited variants accepted + debug-logged, ending silent ignoring) | `Ourin/Ghost/GhostManager.swift` (`\f` switch) |
| **DevTools mock UI adjudication** (External Events Harness wired to real APIs: live server status, real TCP/HTTP sends with response display, restart-all-servers; Headline/Balloon preview, Signpost, Resource Overlay, and Plugin Enabled toggle marked "Preview only") | `Ourin/ContentView.swift`, `ExternalServer/ServerMetrics.swift` (public `requestCount`) |
| **Corrected NAR composite-install documentation** (the "missing" claim in AUDITS_TODO was wrong; already implemented) | `Ourin/NarInstall/Paths.swift:219-236` (calendar/skin, calendar/plugin, legacy calendar, language) |

---

*本ファイルは監査レポート（GLM/CODEX/CLAUDE/AGY）の完了項目を集約したものです。未完項目は `AUDITS_TODO.md` を参照してください。*

*This file consolidates completed items from audit reports (GLM/CODEX/CLAUDE/AGY). For pending items, see `AUDITS_TODO.md`.*
