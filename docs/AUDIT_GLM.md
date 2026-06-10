# Ourin (桜鈴) 仕様準拠監査レポート

**監査日**: 2026-06-10
**監査対象**: Ourin macOSネイティブ伺かベースウェア
**情報源**: UKADOC一次仕様、YAYA仕様、SSPリファレンス実装、ソースコード静的解析

---

## 目次

1. [A. SHIORI プロトコル](#a-shiori-プロトコル)
2. [B. SSTP プロトコル](#b-sstp-プロトコル)
3. [C. SakuraScript](#c-sakurascript)
4. [D. SHIORI イベント](#d-shiori-イベント)
5. [E. プロパティシステム](#e-プロパティシステム)
6. [F. YAYA言語VM](#f-yaya言語vm)
7. [G. プラグインシステム](#g-プラグインシステム)
8. [H. NARパッケージ](#h-narパッケージ)
9. [I. FMO](#i-fmo)
10. [J. バルーン・シェル・リソース](#j-バルーンシェルリソース)
11. [最終サマリー](#最終サマリー)

---

## A. SHIORI プロトコル

### 準拠度スコア: 7/10

### 実装済み（仕様準拠）

- **GET/NOTIFY メソッド**: `BridgeToSHIORI.swift:130` で SHIORI/3.0 GET/NOTIFY リクエストを構築。SHIORI/2.6 フォールバック付き（`ShioriHost.request()`）
- **Charset処理**: `EncodingAdapter.swift` で Shift_JIS/windows-31j/cp932 デコード対応。`EncodingNormalizer.swift` で UTF-8優先→Shift-JISフォールバック
- **ヘッダーフィールド**: SecurityLevel, Sender, ID, Reference0..31, Option, IfGhost, Entry, BaseID, Marker, X-SSTP-PassThru-* 等を網羅的に処理（`SSTPDispatcher.swift:658-743`）
- **SHIORI 2.x互換**: `ShioriHost` が 3.0→2.6 プロトコル交渉を実装
- **エラーレスポンス**: 200/204/210/400/404/408/409/413/420/500/501/503/505/512 の完全なステータスコードマップ（`SSTPResponse.swift`）
- **SHIORIレスポンスパース**: `mapShioriResponse()` で Script, Value, ValueNotify, Data, Status, Surface, Balloon, Icon, ScriptOption, BaseID, Marker, ErrorLevel, BalloonOffset, Reference, Age 等を解析

### 実装済み（要修正）

- **SstpRouter と SSTPDispatcher の二重ルータ**: `SstpRouter.swift`（外部サーバー用）と `SSTPDispatcher.swift`（内部用）が独立実装
  - Reference上限不一致: SSTPDispatcher=32, SstpRouter=16
  - 修正箇所: `SstpRouter.swift` — Reference15→31へ拡張
- **SstpRouter GIVE が SHIORI にルーティングされない**: `SstpRouter.swift:115-117` で GIVE を即座に 204 返却
  - 根拠: UKADOC SSTP GIVE仕様 — データ送信としてSHIORI `OnChoiceSelect` へルーティングが期待される
  - 修正案: `handleGive()` で SHIORI へ通知後にレスポンスを返す
- **HTTPレスポンス行末**: `SstpHttpServer.swift:100-106` で `\r` のみ（`\r\n` であるべき）
  - 根拠: HTTP/1.1 RFC 7230 §3
  - 修正箇所: `SstpHttpServer.swift:100-106`
  - 修正案: `"\r"` → `"\r\n"`

### 未実装（重要度: 高/中/低）

- **出力Charset再エンコード** [中]: レスポンスは常にUTF-8。リクエストのCharsetに合わせた再エンコードなし — 実用的には問題ないが仕様上の不一致
- **SSTPListener のテスト** [低]: `SSTPListener.swift`（TCP:9801）にテストなし

### 互換性リスク

- **外部SSTP GIVE**: 外部クライアントからのGIVEリクエストがSHIORIに届かない — SSTP対応アプリとの連携に影響
- **Reference上限差**: 外部SSTP経由で16個以上のReferenceが必要なイベントが制限される

---

## B. SSTP プロトコル

### 準拠度スコア: 8/10

### 実装済み（仕様準拠）

- **全メソッド**: SEND (`SSTPDispatcher.swift:routeToShiori`), NOTIFY (`handleNotify`), COMMUNICATE (`handleCommunicate`), EXECUTE (`handleExecute`), GIVE (`handleGive`), INSTALL (`handleInstall`)
- **TCP (port 9801)**: `SstpTcpServer.swift` — localhost only、UTF-8/SJIS フォールバック
- **HTTP (port 9810)**: `SstpHttpServer.swift` — POST `/api/sstp/v1`
- **XPC**: `XpcDirectServer.swift` — Mach service `jp.ourin.sstp`
- **Distributed IPC**: `OurinExternalServer.swift` — DistributedNotificationCenter 使用
- **セキュリティレベル**: local/external 二段階。デフォルトでexternal拒否（420 Refuse）
- **SSTPバージョン**: SSTP/1.* 対応（`isSupportedVersion()`）、デフォルト1.4
- **EXECUTE拡張コマンド**: getname, getghostname, getnames, getfmo, getshellname, getballoonname, getversion, quiet, restore, setproperty, getproperty, setcookie, getcookie, moveasync, dumpsurface, settrayicon, settrayballoon 等
- **SSTP Options**: notify, nodescript, nobreak, notranslate の完全処理
- **PassThruヘッダー**: `X-SSTP-PassThru*` の収集・エコーバック

### 実装済み（要修正）

- **HTTP CRLF行末**: 前述の `\r` → `\r\n` 問題（`SstpHttpServer.swift:100-106`）
- **HTTP Body読み取り**: 大きなボディがチャンク分割される場合、バッファリングが不十分な可能性（`SstpHttpServer.swift:93`）

### 未実装（重要度: 低）

- **Direct SSTP (WM_COPYDATA)**: Windows専用機能 — プラットフォーム差異として分類
- **ポート9821（セカンダリ）**: 未対応 [低]

### 互換性リスク

- **TCP/HTTP はデフォルト無効**: `enableTCP: false`, `enableHTTP: false` — 外部SSTPクライアントは明示的な有効化が必要
- XPCとDistributed IPCはデフォルト有効 — macOSネイティブのSSTP連携は動作

---

## C. SakuraScript

### 準拠度スコア: 7/10

### 実装済み（仕様準拠）

- **パーサー**: `SakuraScriptEngine.swift` — 単一パス再帰下降パーサー、30種類のToken型を生成
- **スコープ**: `\0`/`\h`, `\1`/`\u`, `\p[N]` — 完全実装 (`Engine.swift:211-229`)
- **サーフィス**: `\s[N]`, `\s[-1]` — 完全実装 (`Engine.swift:230-242`)
- **アニメーション**: `\i[N]`, `\i[N,wait]`, `\![anim,*]` — 完全実装 (`GhostManager.swift:1817-1869`)
- **テキスト制御**: `\n`, `\e` — 完全実装
- **ウェイト**: `\wN`, `\_w[ms]`, `\__w[ms]`, `\t`, `\x`, `\x[noclear]` — 完全実装
- **選択肢**: `\q[title,ID]`, `\z`, `\*`, `\_a[ID]...\_a`, `\__q[ID]` — 完全実装
- **サウンド**: `\8[file]`, `\_v[file]`, `\![sound,*]` — 完全実装
- **イベント**: `\![raise]`, `\![notify]`, `\![embed]`, `\![timerraise*]`, `\![raiseother]`, `\![raiseplugin]` 等 — 完全実装
- **Open/Close**: `\![open,*]`, `\![close,*]` — 全ダイアログタイプ実装
- **Set/Reset**: `\![set,*]`, `\![reset,*]` — 大部分実装
- **Lock/Unlock**: `\![lock,repaint]`, `\![unlock,repaint]`, balloon repaint/move — 実装
- **環境変数**: `%month`〜`%second`, `%username`, `%selfname`, `%keroname`, `%screenwidth/height`, `%exh`, `%et`, `%wronghour`, `%ms`〜`%mz`, `%property[...]` — 完全実装 (`EnvironmentExpander.swift`)
- **エスケープシーケンス**: `\\`, `\%`, `\]`, `\[`, 引用符内 `""` — 正しく処理
- **SERIKO**: `SerikoParser.swift` (458行) + `SerikoExecutor.swift` (318行) — 10メソッド、9インターバル完全対応

### 実装済み（要修正）

- **`\v` の誤マッピング** [高]:
  - 現在: `.openPreferences`（設定ダイアログを開く）
  - 仕様: "stay on top" トグル（`\![set,windowstate,stayontop]` と同等）
  - 修正箇所: `SakuraScriptEngine.swift:408`
  - 修正案: Token を `.command("v", [])` に変更し、GhostManager側で windowstate 処理

- **`\6`/`\7` の誤マッピング** [中]:
  - 現在: `\6` → `.openURL`, `\7` → `.openEmail`
  - 仕様: `\6` = SNTP時刻修正実行, `\7` = SNTP時刻確認開始
  - 緩和: GhostManager 側で実行時に SNTP 機能へ再マップしているが、トークン名が誤解を招く
  - 修正箇所: `SakuraScriptEngine.swift:410-415`

- **`\a` の意味論的矛盾** [低]:
  - 現在: `.anchor` マーカー
  - UKADOC旧仕様: ランダムトーク（OnAITalk）
  - 注: SSP自体も `\a` を anchor として扱うため、デファクト準拠

- **`\_!...\_!`/`\_?...\_?` クロージングタグ検出** [中]:
  - `SakuraScriptEngine.swift:493` でクロージングタグを `\__!`/`\__?` として構築
  - UKADOC仕様では `\_!`/`\_?` が正しい可能性
  - テストも `\__!` を使用しており、両方の検証が必要

### 未実装（重要度: 高/中/低）

- **`\j[ID]` (ジャンプ)** [高]: URL/ファイルへのジャンプ — 多くのゴーストが使用
- **`\__t` (TeachBox)** [中]: 旧形式のTeachBoxオープン — `\![open,teachbox]` で代替可能
- **`\__c` (CommunicateBox)** [中]: 旧形式のCommunicateBoxオープン — `\![open,communicatebox]` で代替可能
- **`\f[...]` フォント描画** [中]: 20+のフォントコマンドがパース済みだが実行時効果なし（GhostManager に `"f"` ハンドラなし）
  - 影響: 太字/斜体/下線/文字色/フォント変更が反映されない
- **`\b[N]` バルーン切替実行** [中]: パース済みだがマルチバルーン未対応
- **`\C` (append mode) 実行** [低]: パース済みだが実行なし
- **`\n[half]`/`\n[percent]`** [低]: `.newlineVariation` としてパースされるが、通常改行と同じ扱い
- **`\c[char/line,N]` テキストクリア** [低]: パース済みだが実行なし
- **`\_n` (no-wrap)** [低]: パース済みだが実行なし
- **`\__v[...]` 音声合成** [低]: macOSにSSP音声APIなし — プラットフォーム差異
- **`\m[umsg,wparam,lparam]`** [低]: Windowsメッセージ送信 — プラットフォーム差異
- **`\![sound,cdplay]`** [低]: CD再生 — プラットフォーム差異

### 互換性リスク

- **`\j[ID]` 未実装**: `\j[http://...]` や `\j[file:///...]` を使用するゴーストでジャンプが無視される
- **フォントコマンド無効**: 文字色や太字を駆使するゴーストで表示が単調になる
- **`\v` 誤動作**: `\v` を always-on-top 用に使うゴーストで設定画面が開く

---

## D. SHIORI イベント

### 準拠度スコア: 5/10

### 実装済み（仕様準拠）

- **EventID レジストリ**: `EventID.swift` に 287 個のイベントID定義
- **アクティブディスパッチャ**: 15個のObserverで約85イベントを実際に発火
- **起動・終了系**: `OnBoot`, `OnFirstBoot`, `OnSecondBoot`, `OnClose`, `OnInitialize` — `GhostManager.swift:2338-2378`
- **時間系**: `OnSecondChange`, `OnMinuteChange`, `OnHourTimeSignal`, `OnIdle` — `TimerEmitter.swift`
- **スリープ/復帰**: `OnSysSuspend`/`OnSleep`, `OnSysResume`/`OnWake`, `OnScreenSaverStart`/`End` — `SleepObserver.swift`
- **セッション**: `OnSessionLock`/`Unlock`, `OnScreenLock`/`Unlock` — `SessionObserver.swift`
- **マウス**: `OnMouseClick/DoubleClick/MultipleClick`, `OnMouseDown/Up/Move/Wheel`, `OnMouseEnter/Leave/Hover`, `OnMouseDragStart/DragEnd`, `OnMouseGesture` — `InputMonitor.swift`
- **ゲームパッド**: `OnGamepadConnected/Disconnected/ButtonDown/Up/AxisMove` — `GamepadObserver.swift`
- **ネットワーク**: `OnNetworkStatusChange`, `OnNetworkOnline/Offline/Heavy` — `NetworkObserver.swift`
- **ディスプレイ**: `OnDisplayChange` — `DisplayObserver.swift`
- **スペース**: `OnSpaceChanged`, `OnVirtualDesktopChanged` — `SpaceObserver.swift`
- **電源**: `OnPowerSourceChanged`, `OnThermalStateChanged` — `PowerObserver.swift`
- **デバイス**: `OnDeviceArrival/Remove` — `DeviceObserver.swift`
- **ロケール/外観**: `OnLocaleChange`, `OnLanguageChange`, `OnAppearanceChanged` — 各Observer
- **ドラッグ＆ドロップ**: `OnFileDrop/Dropped/Dropping`, `OnURLDrop/Dropped/Dropping`, `OnTextDrop` — `DragDropView.swift`
- **サーフィス/シェル**: `OnSurfaceChange/Restore`, `OnShellChanging/Changed` — `GhostManager+Surface.swift`
- **バルーン**: `OnBalloonBreak/Close/Timeout/Change` — `GhostManager+Balloon.swift`
- **更新**: `OnUpdateBegin/Ready/Complete/Failure`, `OnUpdateOtherBegin/Ready/Complete`, `OnUpdateCheckComplete/Failure` — `GhostManager+System.swift`
- **選択肢**: `OnChoiceSelect/SelectEx/Hover/Enter` — `GhostManager+System.swift`
- **アンカー**: `OnAnchorSelect/SelectEx` — `GhostManager+Balloon.swift`
- **SSTP**: `OnSSTPBreak`, `OnSSTPBlacklisting` — `SSTPDispatcher.swift`

### 実装済み（要修正）

- **マウスイベント Reference パラメータ名非準拠** [重大]:
  - 現在: `screenX`, `screenY`, `modifiers`, `button`, `buttonNumber` 等の説明的名前
  - 仕様: `Reference0`=charID, `Reference1`=X, `Reference2`=Y, `Reference3`=scope, `Reference4`=region, `Reference5`=button, `Reference6`=device
  - 根拠: UKADOC `list_shiori_event.html`
  - 修正箇所: `InputMonitor.swift:185-202`
  - 修正案: パラメータ辞書のキーを `Reference0`..`Reference6` に変更
  - 影響: `\reference[0]` で座標を取得するYAYA辞書が動作しない

- **タイマーイベント Reference 欠落** [高]:
  - `OnSecondChange`/`OnMinuteChange`/`OnHourTimeSignal`/`OnIdle` 全てが `params: [:]` で発火
  - 仕様: `Reference0`=uptime(h), `Reference1`=画面外フラグ, `Reference2`=重なりフラグ, `Reference3`=再生可能, `Reference4`=アイドル秒
  - 修正箇所: `TimerEmitter.swift:50-65`
  - 修正案: 各タイマーイベントに Reference0..4 を設定

- **電源/ネットワーク/負荷イベント Reference 名非準拠** [高]:
  - 現在: `Source`, `State`, `Status`, `Load` 等の説明的名前
  - 仕様: `Reference0` のみ
  - 修正箇所: `PowerObserver.swift`, `NetworkObserver.swift`, `SystemLoadObserver.swift`

- **OnSleep/OnWake 二重発火** [中]:
  - `OnSysSuspend`+`OnSleep` が同時発火。UKADOCでは別概念
  - 修正箇所: `SleepObserver.swift:17-24`

### 未実装（重要度: 高/中/低）

- **OnGhostChanging/OnGhostChanged** [高]: ゴースト切替時のイベント未発火
- **OnGhostCalling/OnGhostCalled/OnGhostCallComplete** [高]: ゴースト呼び出しの完全なイベントチェーン未実装
- **OnOtherGhostTalk** [高]: 他ゴーストのトーク監視未実装
- **OnUserInput/OnUserInputCancel** [高]: InputBox系イベント — UIは存在するが OnCommunicate にルーティング
- **OnTeach/OnTeachStart/OnTeachInputCancel** [中]: TeachBox系イベント
- **OnOverlap/OnOtherOverlap** [中]: 重なり検出
- **OnOffscreen/OnOtherOffscreen** [中]: 画面外検出
- **OnVanishSelecting/Selected/Cancel/Vanished** [中]: 消失フローイベント
- **OnChoiceTimeout** [中]: 選択肢タイムアウトイベント（部分的実装）
- **OnBatteryLow/Critical/ChargingStart/Stop/Notify** [中]: 詳細バッテリーイベント
- **OnDisplayChangeEx/Handover/PowerStatus** [低]: 拡張ディスプレイイベント
- **OnInstallBegin/Complete/Failure** [低]: NARインストール中のイベント未発火
- **OnSchedule*** [低]: カレンダー系イベント
- **OnBIFFBegin/Complete/Failure** [低]: メールチェック系イベント
- **OnSNTPBegin/Compare/Correct/Failure** [低]: SNTP系イベント
- **OnSelectMode*** [低]: 選択モード系イベント
- **OnSoundStop/Loop/Error** [低]: サウンド状態イベント
- **OnDarkTheme** [低]: EventID定義済みだがOnAppearanceChangedで代替（独自拡張）
- **OnRecycleBinEmpty** [低]: ゴミ箱イベント
- **OnOSUpdateInfo** [低]: OS更新情報

### 互換性リスク

- **マウスReference非準拠**: 座標ベースの処理を行うゴースト（当たり判定連動等）が動作しない
- **タイマーReference欠落**: OnSecondChangeでuptimeやidle秒を使うゴーストで分岐が壊れる
- **ゴースト切替イベント未発火**: `OnGhostChanging`/`OnGhostChanged` に依存するゴーストの切り替え後スクリプトが表示されない
- **OnUserInput未実装**: InputBoxを使用するゴーストで入力結果が処理されない

---

## E. プロパティシステム

### 準拠度スコア: 8/10

### 実装済み（仕様準拠）

- **名前空間**: `system.*`, `baseware.*`, `ghostlist.*`, `activeghostlist.*`, `currentghost.*`, `balloonlist.*`, `currentghost.balloon.*`, `headlinelist.*`, `pluginlist.*`, `history.*`, `rateofuselist.*` — 全主要名前空間対応
- **`\p[]` 参照**: `EnvironmentExpander.swift:177-179` で `%property[...]` 展開、再帰解決と循環検出（深度制限16）
- **読み取り専用/読み書き区別**: `writableProperties()` で書き込み可能プロパティを明示
- **書き込み可能プロパティ**: `currentghost.shelllist(name).menu`, `currentghost.mousecursor.*`, `currentghost.balloon.mousecursor.*`, SERIKO tooltip/cursor
- **プロバイダーアーキテクチャ**: `PropertyProvider` プロトコル → 9個のプロバイダー実装
  - `SystemPropertyProvider`: date/time, OS info, CPU, memory
  - `BasewarePropertyProvider`: name, version
  - `GhostPropertyProvider`: ghostlist, activeghostlist, currentghost
  - `BalloonPropertyProvider`: balloonlist, currentghost.balloon
  - `HeadlinePropertyProvider`, `PluginPropertyProvider`, `HistoryPropertyProvider`, `RateOfUsePropertyProvider`
- **ResourceManager**: `sakura.defaultleft/top`, `kero.defaultleft/top`, `charN.defaultleft/top`, balloon位置, `username`, `homeurl` の永続化

### 実装済み（要修正）

- **CPU負荷計算バグ** [高]:
  - `SystemPropertyProvider.cpuLoad()`: `(deltaUser + deltaSystem + deltaIdle + deltaNice) / total * 100` —常に100%を返す
  - 正しくは: `(deltaUser + deltaSystem + deltaNice) / total * 100`（idleを除外）
  - 修正箇所: `PropertyManager.swift` 内 `cpuLoad()`
  - 影響: `system.cpu.load` が常に100%を返す

- **History/RateOfUse データが空** [中]:
  - プロバイダーは初期化されるが実際の使用履歴データが収集・永続化されない
  - `history.*` / `rateofuselist.*` が常に count=0 を返す

### 未実装（重要度: 低）

- `currentghost.favorites.*` — お気に入りプロパティ
- `currentghost.material.*` — マテリアルプロパティ
- `system.os.build` — ビルド番号
- `system.monitor.*` — マルチモニター詳細
- `system.disk.*` — ディスク情報
- `system.power.*` — 詳細電源情報
- `system.network.*` — ネットワーク情報
- `system.theme.*` — テーマ情報

### 互換性リスク

- CPU負荷が100%固定のため、負荷に応じた挙動変更を行うゴーストが誤動作
- History/RateOfUse が空のため、使用率グラフ系の機能が動作しない

---

## F. YAYA言語VM

### 準拠度スコア: 4/10

### 実装済み（仕様準拠）

- **プロセスアーキテクチャ**: Swift → JSON IPC → C++ yaya_core 別プロセス（`YayaAdapter.swift` + `yaya_core/`）
- **Lexer**: YAYA構文の完全なトークン化 — コメント(`//`,`--`,`#`,`/* */`)、文字列(ダブル/シングル/ヒアドキュメント)、16進数、UTF-8識別子、演算子 — `Lexer.cpp` (590行)
- **Parser**: 再帰下降パーサー — 関数定義、if/elseif/else、while、switch/case/when、三項演算子、配列アクセス/スライス、代入(単純/複合)、後置++/-- — `Parser.cpp` (1,433行)
- **VM**: ツリーウォーキングインタプリタ — 14ノード型、グローバル/ローカルスコープ(`_`プレフィクス)、再帰深度制限1000、実行タイムアウト120秒 — `VM.cpp` (2,439行)
- **組み込み関数**: 約100+関数登録
  - 文字列: STRLEN, STRSTR, SUBSTR, REPLACE, ERASE, INSERT, CHR, CHRCODE, TOUPPER, TOLOWER, CUTSPACE
  - 数学: FLOOR, CEIL, ROUND, SQRT, POW, LOG, LOG10, SIN, COS, TAN, ASIN, ACOS, ATAN, SINH, COSH, TANH, SRAND
  - 配列: ARRAYSIZE, IARRAY, SPLIT, ASEARCH, ASORT, ARRAYDEDUP, ANY
  - 型変換: TOINT, TOSTR, GETTYPE, CVINT, CVSTR, TOAUTO
  - ファイルI/O: FOPEN, FCLOSE, FREAD, FWRITE, FSEEK, FTELL, FSIZE, FENUM, FCOPY, FMOVE, FDEL, MKDIR, RMDIR
  - 正規表現: RE_SEARCH, RE_MATCH, RE_GREP, RE_REPLACE, RE_SPLIT
  - エンコーディング: STRENCODE, STRDECODE, Base64, STRDIGEST(md5/sha1/crc32)
  - ビット演算: BITWISE_AND/OR/XOR/NOT/SHIFT
  - SAORI: LOADLIB, UNLOADLIB, REQUESTLIB（IPC経由でSwiftホストにコールバック）
- **辞書ファイル読み込み**: .dic ファイル → Lexer → Parser → VM へのAST登録 — `DictionaryManager.cpp` (209行)
- **SHIORI統合**: reference[] 配列の設定、イベントIDからの関数呼び出し、SHIORI3FW フレームワークモード対応
- **文字列補間**: `%(_varname)` 構文、SSP変数の保持（Swift側展開用）

### 実装済み（要修正）

- **for/foreach ループが実行時に壊れている** [致命的]:
  - Parser は for/foreach を `WhileNode(condition=LiteralNode("1"))` に変換
  - 初期化子、条件チェック、インクリメントが**破棄**される
  - 結果: 無限ループ（120秒タイムアウトで停止）
  - 修正箇所: `Parser.cpp` の for/foreach 処理
  - 修正案: WhileNode に初期化子・条件・インクリメントを保持する ForNode/ForEachNode を追加

- **break/continue が動作しない** [致命的]:
  - VM の `executeNode` で Break/Continue ノードが `Value()` を返すだけ
  - While ループハンドラに break/continue 信号の try/catch なし
  - 修正箇所: `VM.cpp` の Break/Continue/While 処理
  - 修正案: 例外ベースの制御フロー（BreakSignal/ContinueSignal）を実装

- **浮動小数点なし** [高]:
  - Value 型が整数のみ。SQRT, POW, SIN, COS 等が整数に切り捨て
  - 影響: 実数演算を使用するゴーストで不正確な計算結果

- **Shift-JIS エンコーディング未対応** [高]:
  - `DictionaryManager::load()` で `(void)encoding` — UTF-8のみ
  - 影響: Shift-JIS の .dic ファイルを読むゴーストが文字化け

### 未実装（重要度: 高/中/低）

- **浮動小数点数リテラル/型** [高]: 整数のみ
- **ZEN2HAN/HAN2ZEN** [中]: スタブ（入力をそのまま返す）
- **SAVEVAR/RESTOREVAR** [中]: スタブ — 変数の永続化なし
- **STRFORM フォーマット指定子** [低]: 単純結合のみ（%d/%s 未対応）
- **DICLOAD/DICUNLOAD** [中]: スタブ
- **READFMO** [低]: スタブ
- **辞書型（Dictionary）操作** [低]: 型定義のみで組み込み関数なし
- **自動テスト** [高]: C++コードにテストなし

### 互換性リスク

- **for/foreach 使用ゴースト**: 無限ループ → タイムアウト → 応答なし。影響範囲が極めて大きい
- **break/continue 使用ゴースト**: ループ脱出不可 → 同上
- **浮動小数点計算**: 統計・確率計算を使用するゴーストで不正確な結果
- **Shift-JIS 辞書**: 日本語ゴーストの大部分が Shift-JIS の .dic を使用 → 文字化けで読み込み失敗の可能性

---

## G. プラグインシステム

### 準拠度スコア: 7/10

### 実装済み（仕様準拠）

- **PLUGIN/2.0M プロトコル**: `PluginProtocol.swift` — GET/NOTIFY メソッド、CRLF区切りヘッダーパース、ビルダー
- **プラグインライフサイクル**: `Plugin.swift` — CFBundle からの `request`/`load`/`unload` C関数ポインタ解決
- **プラグイン検出**: `PluginRegistry.swift` — `PlugIns/` ディレクトリと Application Support からスキャン、`descript.txt` パース
- **イベントディスパッチ**: `PluginEventDispatcher.swift` — OnSecondChange（タイマー）、OnGhostBoot, OnMenuExec, OnInstallComplete, OnGhostExit, OnGhostInfoUpdate, OnOtherGhostTalk
- **SAORI互換**: `SaoriProtocol.swift` + `SaoriLoader.swift` + `SaoriRegistry.swift` + `SaoriManager.swift`
  - SAORI/1.0 プロトコル（EXECUTE/GET）
  - dlopen による動的ロード、`request`/`saori_request` シンボル解決
  - UTF-8/Shift-JIS/EUC-JP/ISO-2022-JP エンコーディング対応
- **ターゲット解決**: `OurinPluginEventBridge.swift` — random, lastinstalled, id/name/filename マッチング
- **ターゲットフィルタリング**: self/ghost/baseware/ourin

### 実装済み（要修正）

- **Plugin.force-load クラッシュリスク** [高]:
  - `Plugin.swift` で `bundleIdentifier!` を force-unwrap — IDなしバンドルでクラッシュ
  - 修正箇所: `Plugin.swift` の `_cfBundle` 計算プロパティ
  - 修正案: オプショナルバインディングに変更

- **PluginEventDispatcher タイムアウトがログのみ** [中]:
  - 3秒警告をログ出力するが実際のキャンセルなし — ハングしたプラグインがシリアルキューを無期限ブロック

### 未実装（重要度: 低）

- `OnBalloonChange/Changing` イベント — プラグイン向け
- `OnHeadlineSense*` イベント — プラグイン向け
- プラグインアンインストール/無効化管理
- プラグイン優先度/実行順序

### 互換性リスク

- バンドルIDなしの古いプラグインでロード時クラッシュの可能性
- プラグインがハングした場合の回復不可能

---

## H. NARパッケージ

### 準拠度スコア: 7/10

### 実装済み（仕様準拠）

- **NAR形式解析**: PK ヘッダー + 拡張子検証 — `NarInstaller.swift`
- **ZIP展開**: `/usr/bin/ditto` 使用 — `ZipUtil.swift`
- **install.txt パース**: `InstallTxtParser.swift` — charset/type/directory/accept/extras 解析
- **文字コード検出**: UTF-8/Shift-JIS 自動判定 — `TextEncodingDetector`
- **タイプルーティング**: ghost/balloon/shell/plugin/package → 対応ディレクトリ — `Paths.swift`
- **Zip Slip保護**: パストラバーサル防止 — `ZipUtil.swift`
- **delete.txt サポート**: レガシーファイル削除
- **Windows パス正規化**: バックスラッシュ → スラッシュ変換
- **無視ファイル**: desktop.ini, .DS_Store, __MACOSX 等
- **シンボリックリンクスキップ**: セキュリティ対策
- **更新記述子パース**: updates2.dau, updates.txt — `UpdateDescriptorParser`
- **ドラッグ＆ドロップUI**: `NarInstallView.swift`
- **パッケージレジストリ**: `NarRegistry.swift` — ファイルシステムベースの発見

### 実装済み（要修正）

- **シェルインストールパス不一致** [高]:
  - 現在: `{base}/shell/{directory}/` にインストール
  - 仕様: ゴーストディレクトリ内 `{ghost}/shell/{shellname}/`
  - 根拠: UKADOC `dev_nar.html` — accept フィールドで対象ゴーストを特定
  - 修正箇所: `Paths.swift` の `installTarget(forType: "shell")`
  - 影響: シェルNARが正しいゴーストに関連付けられない

- **NarRegistry.installedShells(for:) が ghost パラメータを無視** [中]:
  - 全グローバルシェルを返す — ゴースト別のシェルリストが不正確

### 未実装（重要度: 高/中/低）

- **descript.txt バリデーション** [中]: install.txtのみ解析、インストール内容の検証なし
- **アンインストール** [低]: 機能なし
- **NAR作成** [低]: `createnar` コマンド対応なし
- **デジタル署名検証** [低]: なし
- **差分更新適用** [低]: URL解析のみで実際のダウンロード/適用なし
- **accept プロンプト UI** [低]: 衝突時にエラーで停止

### 互換性リスク

- シェル付きNARが正しい場所にインストールされず、ゴーストとシェルの関連付けが壊れる

---

## I. FMO

### 準拠度スコア: 3/10

### 実装済み（仕様準拠）

- **POSIX共有メモリ**: `FmoSharedMemory.swift` — 64KB割り当て、mmap(MAP_SHARED)
- **名前付きセマフォ**: `FmoMutex.swift` — 排他制御
- **単一起動検出**: ninix互換 `/ninix` チェック — `FmoManager.isAnotherInstanceRunning()`
- **C ブリッジ**: `FmoBridge.c/h` — shm_open, mmap, sem_open 等のPOSIX API ラッパー

### 実装済み（要修正）

- **FMOデータ形式がSSP非互換** [致命的]:
  - 現在: 4バイト長プレフィクス + 生データ blob（独自形式）
  - 仕様: SSP/ninix FMO形式 — 複数ゴーストエントリ（hwnd, name, keroname, sakuraname 等）
  - 根拠: ninix FMO仕様、SSPのFMO実装
  - 修正案: SSP互換FMO構造体（エントリ配列）を実装

- **エフェメラルモードが発見と矛盾** [高]:
  - `shm_unlink` を作成直後に呼び出し — 名前による新規接続が不可
  - `fmo_check_running` は名前でオープンを試みる — 競合状態

### 未実装（重要度: 高/中/低）

- **FMO エントリ登録/列挙** [高]: ゴーストのFMO登録なし
- **複数ゴースト管理** [高]: マルチゴースト非対応
- **UNIX ソケットパス共有** [中]: SSTP通信用パスの共有なし
- **ゴースト間通信パス** [高]: FMO経由のプロセス間SSTPなし

### 互換性リスク

- FMOベースのゴースト間通信が完全に動作しない — 複数ゴースト起動時の連携が不可
- ninix/SSPとのFMO互換性なし

---

## J. バルーン・シェル・リソース

### 準拠度スコア: 4/10

### 実装済み（仕様準拠）

- **descript.txt パース**: `DescriptorLoader.swift` — UTF-8/Shift-JIS、balloons*.txt オーバーレイ
- **画像ローダー**: `ImageLoader.swift` — Image I/O (PNG/JPEG/GIF/BMP) + ICO/CUR デコーダー
- **ICO/CUR デコーダー**: `ICO.swift` — PNG ペイロード、32bpp BMP with AND mask alpha
- **ResourceBridge**: `ResourceBridge.swift` — 5秒TTLキャッシュ、型付きアクセサ（bool/int/point/color/url）
- **オーナー描画メニュー**: 80+ メニューボタンキー、キャプション/ショートカット/可視性パース
- **SERIKO パーサー**: `SerikoParser.swift` — surfaces.txt アニメーション定義の完全パース

### 実装済み（要修正）

- **ICO スコアリングの CUR バグ** [低]:
  - `isCursor == true` の場合 `bpp_or_hotspotY` を bpp として使用 — 実際はホットスポットY座標
  - 修正箇所: `ICO.swift` のスコア計算

### 未実装（重要度: 高/中/低）

- **バルーンレンダリング** [致命的]: バルーンウィンドウ、テキストレイアウト、矢印/オンライン/SSTPインジケーターの描画なし
- **surfaces.txt バルーン定義パース** [高]: バルーンの surfaces.txt（テキスト領域、矢印位置等）のパーサーなし
- **バルーンポジショニング** [高]: windowposition.*/origin.* 未実装
- **テキスト装飾** [高]: NSAttributedString によるフォント/スタイル適用なし
- **CommunicateBox** [中]: 入力ボックスUI未実装
- **透明ピクセルクリックスルー** [中]: ヒットテスト未実装
- **Retina スケーリング** [低]: スケール対応レンダリングなし
- **MAG/PI/XBM デコーダー** [低]: 将来対応予定

### 互換性リスク

- **バルーン描画なし**: ゴーストの会話が視覚的に表示されない — ベースウェアとして致命的
- **テキストスタイル未適用**: `\f[...]` コマンドの効果が一切反映されない

---

## 最終サマリー

### 1. 全体準拠度スコア

| カテゴリ | スコア | 重み | 加重スコア |
|----------|--------|------|-----------|
| A. SHIORI プロトコル | 7/10 | ×2 | 14 |
| B. SSTP プロトコル | 8/10 | ×1 | 8 |
| C. SakuraScript | 7/10 | ×2 | 14 |
| D. SHIORI イベント | 5/10 | ×1 | 5 |
| E. プロパティシステム | 8/10 | ×1 | 8 |
| F. YAYA言語VM | 4/10 | ×1 | 4 |
| G. プラグインシステム | 7/10 | ×1 | 7 |
| H. NARパッケージ | 7/10 | ×1 | 7 |
| I. FMO | 3/10 | ×1 | 3 |
| J. バルーン/シェル/リソース | 4/10 | ×1 | 4 |
| **合計** | | **12** | **74** |

**全体準拠度スコア: 6.2/10**（加重平均: 74/120）

### 2. クリティカルな互換性問題 Top 10

| # | 問題 | カテゴリ | 影響を受けるゴースト |
|---|------|---------|-------------------|
| 1 | **YAYA for/foreach ループが無限ループ** | F | for/foreach を使用する全YAYAゴースト |
| 2 | **YAYA break/continue が動作しない** | F | ループ制御を使用するYAYAゴースト |
| 3 | **バルーンレンダリング未実装** | J | 全ゴースト（会話表示不可） |
| 4 | **FMO がSSP非互換形式** | I | 複数ゴースト同時起動時の連携全般 |
| 5 | **マウスイベントReference非準拠** | D | 座標ベース処理を行うゴースト |
| 6 | **タイマーイベントReference欠落** | D | OnSecondChange uptime/idle を使うゴースト |
| 7 | **YAYA Shift-JIS エンコーディング未対応** | F | Shift-JIS .dic を使用する日本語ゴースト |
| 8 | **`\j[ID]` ジャンプ未実装** | C | URL/ファイルジャンプを使用するゴースト |
| 9 | **OnGhostChanging/OnGhostChanged 未発火** | D | ゴースト切替スクリプトを使用するゴースト |
| 10 | **`\v` の誤マッピング** | C | `\v` を always-on-top 用に使うゴースト |

### 3. 推奨修正優先順位

| 優先度 | 修正項目 | 影響度 | 修正コスト | カテゴリ |
|--------|---------|--------|-----------|---------|
| **P0** | for/foreach ループの実行修正 | 致命的 | 大 | F |
| **P0** | break/continue の実装 | 致命的 | 中 | F |
| **P0** | バルーンレンダリング基盤 | 致命的 | 極大 | J |
| **P1** | マウスイベント Reference パラメータ名修正 | 高 | 小 | D |
| **P1** | タイマーイベント Reference 追加 | 高 | 小 | D |
| **P1** | FMO SSP互換形式への移行 | 高 | 大 | I |
| **P1** | YAYA Shift-JIS エンコーディング対応 | 高 | 中 | F |
| **P2** | `\v` マッピング修正 | 中 | 極小 | C |
| **P2** | `\j[ID]` ジャンプ実装 | 中 | 中 | C |
| **P2** | OnGhostChanging/OnGhostChanged 発火 | 中 | 中 | D |
| **P2** | シェルNARインストールパス修正 | 中 | 小 | H |
| **P2** | 浮動小数点サポート | 中 | 大 | F |
| **P3** | SstpRouter GIVE SHIORIルーティング | 低 | 小 | B |
| **P3** | HTTP CRLF 行末修正 | 低 | 極小 | B |
| **P3** | SstpRouter Reference 上限拡張 | 低 | 極小 | B |
| **P3** | `\f[...]` フォント描画実装 | 低 | 大 | C |
| **P3** | Plugin force-unwrap 修正 | 低 | 極小 | G |
| **P3** | CPU負荷計算バグ修正 | 低 | 極小 | E |
| **P3** | テストカバレッジ向上 | 低 | 大 | 全般 |

### 4. SSPとの主要な仕様解釈の差異

| 項目 | SSPの挙動 | Ourinの挙動 | 分類 |
|------|----------|------------|------|
| FMO データ形式 | SSP互換構造化エントリ（hwnd/name/keroname等） | 4バイト長プレフィクス + 生blob | **非互換** |
| 出力Charset | リクエストCharsetに再エンコード | 常にUTF-8 | プラットフォーム差異 |
| Direct SSTP | WM_COPYDATA | XPC / Distributed IPC | プラットフォーム差異 |
| プロセスモデル | DLLインプロセスロード | 別プロセス (yaya_core) IPC | プラットフォーム差異 |
| タイマーReference | uptime/画面外/重なり/再生可能/アイドル秒 | 空 `[:]` | **非互換** |
| マウスReference | Reference0..6 形式 | 説明的名前 (screenX等) | **非互換** |
| SSTP TCPデフォルト | ポート9801でリッスン | デフォルト無効 | 設計差異 |
| マルチゴースト | FMO + プロセス間SSTP | FMO非互換 + プロセス間通信未実装 | **非互換** |
| バルーンテキスト | フル描画（フォント/色/マーカー/画像） | 描画未実装 | **未実装** |
| `\v` | always-on-top トグル | openPreferences（設定画面） | **バグ** |
| `\a` | anchor マーカー | anchor マーカー（SSPデファクトに準拠） | 準拠 |
| OnDarkTheme | 発火あり | 未発火（OnAppearanceChanged で代替） | 独自拡張 |
| サーフィス描画 | DirectDraw/GDI | Metal | プラットフォーム差異 |

---

*監査終了。本レポートはソースコード静的解析とUKADOC仕様との照合に基づいています。動的テスト（実際のゴースト読み込み・実行）は含まれていません。*
