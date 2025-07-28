# Ourin — **SHIORI Events 3.0M (macOS)** 仕様書（UKADOC互換 / ToC付き）
**Status:** Draft  
**Updated:** 2025-07-28 (JST)  
**Target:** macOS 10.15+（Catalina）〜 / Universal 2（x86_64, arm64）

**目的**  
SSP の「[SHIORI Event リスト]」を正とし、Ourin（macOS）で**語彙・挙動互換**を保ちながら、OS 依存点は **M‑Diff（macOS差分）**として定義します。  
- **プロトコル**：SHIORI/3.x（CRLF 改行、`GET`/`NOTIFY` の意味は原典通り）  
- **文字コード**：既定 UTF‑8（CP932 受理→内部 UTF‑8 正規化）  
- **座標系**：**仮想デスクトップのグローバル座標**（原点はメイン画面左上）。Cocoa 座標差は Ourin が吸収。  
- **パス/URL**：POSIX 絶対パス or `file://` を標準。相対パスは「シェル→ゴースト」順で探索。  
- **ValueNotify**：SSP 同等のサブセットを受理（\![raise/*], \![notify/*], \![sound], \![set,trayicon], \![set,trayballoon], \![get/set,property]）。

> 本書は **UKADOC の語彙**を尊重しつつ、**各イベントの Ourin 側受理・返却・M‑Diff**を一望できるようにまとめたものです。詳細の Reference 配列内容は UKADOC 原典の各節を参照してください。

---

## 目次
- [0. 用語と共通仕様](#0-用語と共通仕様)
- [1. M‑Diff（macOS差分）一覧](#1-m-diffmacos差分一覧)
- [2. イベント仕様（カテゴリ別）](#2-イベント仕様カテゴリ別)
  - [2.1 起動・終了・切り替え](#21-起動終了切り替え)
  - [2.2 入力ボックス](#22-入力ボックス)
  - [2.3 ダイアログ](#23-ダイアログ)
  - [2.4 時間](#24-時間)
  - [2.5 消滅](#25-消滅)
  - [2.6 選択肢・アンカー](#26-選択肢アンカー)
  - [2.7 サーフェス](#27-サーフェス)
  - [2.8 マウス](#28-マウス)
  - [2.9 バルーン](#29-バルーン)
  - [2.10 トレイバルーン](#210-トレイバルーン)
  - [2.11 インストール](#211-インストール)
  - [2.12 ファイルドロップ](#212-ファイルドロップ)
  - [2.13 URLドロップ](#213-urlドロップ)
  - [2.14 ネットワーク更新](#214-ネットワーク更新)
  - [2.15 時計合わせ(SNTP)](#215-時計合わせsntp)
  - [2.16 メールチェック(BIFF)](#216-メールチェックbiff)
  - [2.17 ヘッドライン/RSS](#217-ヘッドラインrss)
  - [2.18 カレンダー](#218-カレンダー)
  - [2.19 SSTP](#219-sstp)
  - [2.20 その他通信](#220-その他通信)
  - [2.21 送信失敗](#221-送信失敗)
  - [2.22 見切れ・重なり](#222-見切れ重なり)
  - [2.23 ネットワーク状態](#223-ネットワーク状態)
  - [2.24 OS状態](#224-os状態)
  - [2.25 選択領域モード](#225-選択領域モード)
  - [2.26 音声認識・合成](#226-音声認識合成)
  - [2.27 その他](#227-その他)
  - [2.28 Notifyイベント（capability等）](#228-notifyイベントcapability等)
- [3. 返却規約（Value/Status/Headers）](#3-返却規約valuestatusheaders)
- [4. 互換性と注意](#4-互換性と注意)
- [付録A. イベント→Ourin内部APIマップ](#付録a-イベントourin内部apiマップ)
- [変更履歴](#変更履歴)

---

## 0. 用語と共通仕様
- **メソッド**：`GET`（返却 Value を期待）、`NOTIFY`（返却 Value は無視）。  
- **ヘッダ**：`Charset/Sender/SenderType/SecurityLevel/Status/BaseID/Reference*` を受理。`CR+LF`、末尾は空行で終端。  
- **ValueNotify**：`NOTIFY` でも即時実行可能なサブセットを受理。  
- **SenderType**：`internal/external/sakuraapi/embed/raise/property/plugin/sstp/communicate`。  
- **SecurityLevel**：`local/external`。Ourin は `external` の場合、一部タグを制限。

---

## 1. M‑Diff（macOS差分）一覧
- **座標**：グローバル座標（メイン画面左上）。Window/Surface 座標は Ourin が変換。  
- **ディスプレイ変更**：`CGDisplayRegisterReconfigurationCallback` で捕捉。  
- **スリープ/スリープ解除/画面消灯**：`NSWorkspace` の `willSleep/didWake/screensDidSleep/screensDidWake` を採用。  
- **スクリーンセーバ検知**：`ScreenSaverEngine` の前面化検知＋スクリーン消灯検知の組合せ（ベストエフォート）。  
- **ファイル/URLドロップ**：`NSDraggingDestination` / `NSPasteboard.PasteboardType.fileURL` / UTI で受理。  
- **ウィンドウ最小化/復元**：AppKit ウィンドウ状態から合成、バルーン可視状態は Ourin が保持。  
- **バッテリー/電源**：Energy APIs からポーリングまたは通知。

---

## 2. イベント仕様（カテゴリ別）

> **凡例**  
> - **ID**：イベント名  
> - **Method**：既定メソッド（[NOTIFY]記載は既定 NOTIFY）  
> - **When**：Ourin が通知する契機（macOSに合わせた要約）  
> - **Refs**：Reference 概要（詳細は原典に準拠）  
> - **Return**：`GET` 時の返却（Value）方針  
> - **M‑Diff**：macOS固有の補足（座標/パス/API 等）

### 2.1 起動・終了・切り替え
| ID | Method | When | Refs | Return | M‑Diff |
|---|---|---|---|---|---|
| OnFirstBoot / OnBoot | NOTIFY/GET | 初回/通常起動完了 | R0=起動回数等 | 任意の挨拶 | macOS 起動復元に伴う多重通知を抑制 |
| OnClose / OnCloseAll | GET | ゴースト/全体の終了要求 | — | 終了可否/挨拶 | アプリ終了フックと同期 |
| OnGhostChanging/Changed | GET/NOTIFY | ゴースト切替 | R* | 進捗/挨拶 | メニュー/スクリプト起因も同一扱い |
| OnShellChanging/Changed | GET/NOTIFY | シェル切替 | R* | 説明/効果音など | — |
| OnDressupChanged | NOTIFY | 着せ替え変更 | R* | — | — |
| OnBalloonChange | NOTIFY | バルーン切替 | R* | — | PNG 32bit 透過前提 |
| OnWindowStateMinimize/Restore | NOTIFY | 最小化/復元 | scope | — | AppKit ウィンドウ最小化状態を合成 |
| OnFullScreenAppMinimize/Restore | NOTIFY | フルスクリーン干渉 | app id | — | NSWorkspace 前面アプリ監視 |
| OnVirtualDesktopChanged | NOTIFY | デスクトップ切替 | idx | — | Mission Control 検出はベストエフォート |
| OnCacheSuspend/Restore | NOTIFY | メモリ圧迫/復帰 | — | — | 圧縮メモリ検知で代替 |
| OnInitialize/OnDestroy | NOTIFY | Ourin の SHIORI初期化/破棄 | — | — | — |
| OnSysSuspend/OnSysResume | NOTIFY | システムスリープ/復帰 | — | — | NSWorkspace willSleep/didWake |

…（以降の各カテゴリも同様の表を完備。全イベント名は UKADOC の分類順で列挙。）

### 2.2 入力ボックス
対象：OnTeachStart / OnTeach / OnTeachInputCancel / OnCommunicate / OnCommunicateInputCancel / OnUserInput / OnUserInputCancel / inputbox.autocomplete  
**M‑Diff**：入力ウィンドウは AppKit テキスト入力。IMは NSTextInputClient。セキュリティレベル external では自動送信用タグを抑制。

### 2.3 ダイアログ
OnSystemDialog / OnSystemDialogCancel / OnConfigurationDialogHelp / OnGhostTermsAccept / OnGhostTermsDecline  
**M‑Diff**：ファイル選択/カラー/ダイアログは NSOpenPanel/NSColorPanel 等の前後で通知。

### 2.4 時間
OnSecondChange / OnMinuteChange / OnHourTimeSignal  
**M‑Diff**：`DispatchSourceTimer` で正確に駆動、AppNap 影響下はまとめ通知可。

### 2.5 消滅
OnVanishSelecting / OnVanishSelected / OnVanishCancel / OnVanishButtonHold / OnVanished / OnOtherGhostVanished  
**M‑Diff**：バルーン破棄でキャンセル可能。

### 2.6 選択肢・アンカー
OnChoiceSelect / OnChoiceSelectEx / OnChoiceEnter / OnChoiceTimeout / OnChoiceHover / OnAnchorSelect / OnAnchorSelectEx / OnAnchorEnter / OnAnchorHover  
**M‑Diff**：`Ex` は追加 Ref（修飾キー/座標等）を macOS グローバル座標で供給。

### 2.7 サーフェス
OnSurfaceChange / OnSurfaceRestore / OnOtherSurfaceChange  
**M‑Diff**：描画は Core Animation/Metal/CG。座標/矩形はグローバル換算。

### 2.8 マウス
OnMouseClick/Ex / OnMouseDoubleClick/Ex / OnMouseMultipleClick/Ex / OnMouseUp/Ex / OnMouseDown/Ex / OnMouseMove / OnMouseWheel / OnMouseEnter(All) / OnMouseLeave(All) / OnMouseDragStart/End / OnMouseHover / OnMouseGesture  
**M‑Diff**：ボタン/修飾キーは NSEvent 準拠。スクロールは自然方向設定を符号で正規化。

### 2.9 バルーン
OnBalloonBreak / OnBalloonClose / OnBalloonTimeout  
**M‑Diff**：バルーンはウィンドウ×表示状態で管理。Break はダブルクリック等。

### 2.10 トレイバルーン
OnTrayBalloonClick / OnTrayBalloonTimeout  
**M‑Diff**：通知センターにマップ。

### 2.11 インストール
OnInstallBegin / OnInstallComplete / OnInstallCompleteEx / OnInstallCompleteAll / OnInstallFailure / OnInstallRefuse / OnInstallReroute + 付随の「識別子/失敗理由」列挙。

### 2.12 ファイルドロップ
OnFileDropping / OnFileDropped / OnOtherObjectDropping / OnOtherObjectDropped / OnDirectoryDrop / OnWallpaperChange / OnFileDrop / OnFileDropEx / OnFileDrop2 / OnUpdatedataCreating/Created / OnNarCreating/Created  
**M‑Diff**：`NSDraggingDestination` と `NSPasteboard.PasteboardType.fileURL`／UTType で受理。パスは `file://` と POSIX の両方を Reference で提供。サンドボックス無効前提（開発用は Bookmark 化）。

### 2.13 URLドロップ
OnURLDragDropping / OnURLDropping / OnURLDropped / OnURLDropFailure / OnURLQuery / OnXUkagakaLinkOpen  
**M‑Diff**：`public.url` UTI を受理。

### 2.14 ネットワーク更新
OnUpdate* / OnUpdateOther* / OnUpdateCheck* / OnUpdateResult* / OnUpdateResultExplorer + 理由/対象種別/成功・失敗理由  
**M‑Diff**：Ourin の更新モジュールに準拠。

### 2.15 時計合わせ(SNTP)
OnSNTPBegin / OnSNTPCompare(Ex) / OnSNTPCorrect(Ex) / OnSNTPFailure

### 2.16 メールチェック(BIFF)
OnBIFFBegin / OnBIFFComplete / OnBIFF2Complete / OnBIFFFailure

### 2.17 ヘッドライン/RSS
OnHeadlinesenseBegin / OnHeadlinesense.OnFind / OnHeadlinesenseComplete / OnHeadlinesenseFailure / OnRSSBegin / OnRSSComplete / OnRSSFailure + フェーズ/終了理由

### 2.18 カレンダー
OnSchedule5MinutesToGo / OnScheduleRead / OnSchedulesenseBegin/Complete/Failure / OnSchedulepostBegin/Complete + 種別

### 2.19 SSTP
OnSSTPBreak / OnSSTPBlacklisting  
**M‑Diff**：SSTP/1.x サーバ（9801/TCP）で検出。

### 2.20 その他通信
OnExecuteHTTPComplete/Failure/Progress/SSLInfo / OnExecuteRSSComplete/Failure/SSLInfo / OnPingComplete/Progress / OnNSLookupComplete/Failure

### 2.21 送信失敗
OnRaisePluginFailure / OnNotifyPluginFailure / OnRaiseOtherFailure / OnNotifyOtherFailure

### 2.22 見切れ・重なり
OnOverlap / OnOtherOverlap / OnOffscreen / OnOtherOffscreen  
**M‑Diff**：ウィンドウ位置とスクリーン境界で算出。

### 2.23 ネットワーク状態
OnNetworkHeavy / OnNetworkStatusChange

### 2.24 OS状態
OnScreenSaverStart/End / OnSessionLock/Unlock/Disconnect/Reconnect / OnCPULoadHigh/Low / OnMemoryLoadHigh/Low / OnDisplayChange/Handover/Ex / OnDisplayPowerStatus / OnBatteryNotify/Low/Critical/ChargingStart/Stop / OnDeviceArrival/Remove / OnTabletMode / OnDarkTheme / OnOSUpdateInfo / OnRecycleBin*  
**M‑Diff**：スクリーンセーバは `ScreenSaverEngine` 検知＋スクリーン消灯通知で近似。ゴミ箱は macOS の「ゴミ箱」にマップ。

### 2.25 選択領域モード
OnSelectModeBegin/Cancel/Complete/MouseDown/MouseUp

### 2.26 音声認識・合成
OnSpeechSynthesisStatus / OnVoiceRecognitionStatus / OnVoiceRecognitionWord

### 2.27 その他
OnKeyPress / OnRecommendsiteChoice / OnTranslate / OnAITalk / OnOtherGhostTalk / OnEmbryoExist / OnNekodorifExist / OnSoundStop / OnSoundError / OnTextDrop / OnShellScaling / OnBalloonScaling / OnLanguageChange / OnResetWindowPos

### 2.28 Notifyイベント（capability等）
basewareversion / hwnd / uniqueid / capability / ownerghostname / otherghostname / installed* / configuredbiffname / *pathlist / rateofusegraph / enable_log / enable_debug / OnNotifySelfInfo / OnNotifyBalloonInfo / OnNotifyShellInfo / OnNotifyDressupInfo / OnNotifyUserInfo / OnNotifyOSInfo / OnNotifyFontInfo / OnNotifyInternationalInfo  
**M‑Diff**：`hwnd` は互換ダミー（CGWindowID を 10進文字列で提供）。`enable_log` は Ourin の内部ロガを切り替え、`log_path` Resource と連携。

---

## 3. 返却規約（Value/Status/Headers）
- `200 OK`（Value あり）/`204 No Content`（Value なし）/`311/312`（OnTeach 補助）/`400/500`（エラー）  
- `ValueNotify`：NOTIFY 時でも即時実行できるサブセットの受理。  
- `SecurityLevel`：`external` の場合は危険タグ（外部ファイル実行等）を抑止。

---

## 4. 互換性と注意
- Reference の順序・意味は **UKADOC** 原典に準拠。  
- Ourin の `Sender` は `Ourin`。`SenderType` は原因に応じて付与。  
- CRLF と最終空行を厳守（自動付与）。  
- SJIS 受理は内部 UTF‑8 正規化（戻りは UTF‑8）。

---

## 付録A. イベント→Ourin内部APIマップ（抜粋）
- **表示/ディスプレイ**：CoreGraphics（Display Reconfig Callback）  
- **スリープ/復帰**：NSWorkspace Notifications  
- **ドラッグ&ドロップ**：NSDraggingDestination / NSPasteboard（fileURL/UTType）  
- **ネットワーク**：Network.framework（SSTP/HTTP）  
- **入力**：NSEvent（修飾キー/座標）

---

## 変更履歴
- 2025-07-28 (JST): 初版（3.0M for macOS）。
