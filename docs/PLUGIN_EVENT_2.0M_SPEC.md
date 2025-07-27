
# PLUGIN Event — **2.0M（macOS）** 仕様書（UKADOC互換）
**Status:** Draft / Ourin (macOS 10.15+ / Universal 2: arm64+x86_64)  
**Updated:** 2025-07-27 (JST)  
**互換方針:** UKADOC「PLUGIN Eventリスト」のイベント **ID・意味・Reference順**を踏襲し、**OS 依存値のみ macOS ネイティブ**へ置換。  
**文字コード:** 既定 **UTF‑8**（SJIS/CP932 受理→内部 UTF‑8 正規化）。`version` 応答の `Charset:` 指定があれば切り替え可。  
**改行:** `LF` 推奨（`CRLF` 受理）。

---

## 目次
- [1. 本仕様の目的](#1-本仕様の目的)
- [2. 通信・符号化・改行](#2-通信符号化改行)
- [3. macOS置換（M‑Diff）](#3-macos置換m-diff)
- [4. イベント一覧（完全）](#4-イベント一覧完全)
  - [4.1 version](#41-version)
  - [4.2 installedplugin [NOTIFY]](#42-installedplugin-notify)
  - [4.3 installedghostname [NOTIFY]](#43-installedghostname-notify)
  - [4.4 installedballoonname [NOTIFY]](#44-installedballoonname-notify)
  - [4.5 ghostpathlist [NOTIFY]](#45-ghostpathlist-notify)
  - [4.6 balloonpathlist [NOTIFY]](#46-balloonpathlist-notify)
  - [4.7 headlinepathlist [NOTIFY]](#47-headlinepathlist-notify)
  - [4.8 pluginpathlist [NOTIFY]](#48-pluginpathlist-notify)
  - [4.9 OnSecondChange](#49-onsecondchange)
  - [4.10 OnOtherGhostTalk](#410-onotherghosttalk)
  - [4.11 OnGhostBoot](#411-onghostboot)
  - [4.12 OnGhostExit [NOTIFY]](#412-onghostexit-notify)
  - [4.13 OnGhostInfoUpdate [NOTIFY]](#413-onghostinfoupdate-notify)
  - [4.14 OnMenuExec](#414-onmenuexec)
  - [4.15 OnInstallComplete](#415-oninstallcomplete)
  - [4.16 OnChoiceSelect(Ex)/OnAnchorSelect(Ex)/\q 任意名](#416-onchoiceselectexonanchorselectexq-任意名)
  - [4.17 ![raiseplugin] / ![notifyplugin] 任意名](#417-raiseplugin--notifyplugin-任意名)
- [5. セキュリティとサンドボックス](#5-セキュリティとサンドボックス)
- [6. スレッド/順序/タイムアウト](#6-スレッド順序タイムアウト)
- [7. 例: フレーム](#7-例-フレーム)
- [8. 付録: 用語](#8-付録-用語)

---

## 1. 本仕様の目的
- Windows 前提の要素（`HWND`/パス等）を **macOS ネイティブ値**へ置換しつつ、**イベント語彙と意味を完全互換**で提供する。

## 2. 通信・符号化・改行
- リクエスト/レスポンスの書式は PLUGIN/2.0 に準拠。  
- **既定文字コードは UTF‑8**。互換のため **SJIS/CP932 入力も受理**し内部で UTF‑8 に正規化。  
- 改行は `LF` 推奨（`CRLF` 受理）。

## 3. macOS置換（M‑Diff）
- **ウィンドウ識別**：`HWND` は **`CGWindowID`（32bit, Window Server のウィンドウ番号）**に置換。アプリ内の `NSWindow.windowNumber`（window server 番号）から変換可。  
  - 列挙や他プロセス窓の照会は `CGWindowListCopyWindowInfo` と `kCGWindowNumber` を用いる。  
- **パス**：Windows 形式は **POSIX/`file://` URL** に置換。相対はゴースト/プラグインの基点から解決。  
- **通知種別**：UKADOC で `[NOTIFY]` 明記のものは常に NOTIFY、無印は状況に応じ GET/NOTIFY を踏襲。

---

## 4. イベント一覧（完全）

### 4.1 `version`
- **タイミング**：プラグインのロード直後。  
- **応答**：`Value` にバージョン文字列、任意で `Charset: <encoding>` を付加（以降の通信に適用）。  
- **M‑Diff**：既定は UTF‑8（互換で SJIS も受理）。

### 4.2 `installedplugin` **[NOTIFY]**
- **意味**：インストール済プラグインの列挙。  
- **Ref***：バイト値1区切りで「プラグイン名,プラグインID」。  
- **M‑Diff**：なし（語彙互換）。

### 4.3 `installedghostname` **[NOTIFY]**
- **意味**：インストール済ゴースト名の列挙。  
- **Ref0/1/2**：各種名のバイト1区切りリスト。  
- **M‑Diff**：なし。

### 4.4 `installedballoonname` **[NOTIFY]**
- **Ref0**：バルーン名のバイト1区切りリスト。

### 4.5 `ghostpathlist` **[NOTIFY]**
- **Ref***：読み込んでいる **ゴーストフォルダのフルパス**。  
- **M‑Diff**：**POSIX 絶対パス**または `file://` URL。

### 4.6 `balloonpathlist` **[NOTIFY]**
- **Ref0**：読み込んでいる **バルーンフォルダのフルパス**（POSIX/`file://`）。

### 4.7 `headlinepathlist` **[NOTIFY]**
- **Ref***：読み込んでいる **ヘッドラインフォルダのフルパス**。

### 4.8 `pluginpathlist` **[NOTIFY]**
- **Ref***：読み込んでいる **プラグインフォルダのフルパス**。

### 4.9 `OnSecondChange`
- **意味**：秒間隔の通知。  
- **間隔**：`descript.txt` の `secondchangeinterval` に従う。  
- **M‑Diff**：タイマーは `DispatchSourceTimer` 等で実装。

### 4.10 `OnOtherGhostTalk`
- **Ref0**：ゴースト名。  
- **Ref1**：本体側名。  
- **Ref2**：原因列挙（`break/communicate/sstp-send/owned/remote/notranslate/plugin-script/plugin-event` のカンマ区切り）。  
- **Ref3**：話したイベントID。  
- **Ref4**：話した内容のスクリプト。  
- **Ref5**：バイト1区切りで、ゴーストへ渡された Reference 群。  
- **M‑Diff**：なし。

### 4.11 `OnGhostBoot`
- **Ref0**：**起動したゴーストの各キャラクタウィンドウの `CGWindowID` 列**（未構築は `0`）。  
- **Ref1..4**：ゴースト名／現在シェル名／ゴーストID（Owned SSTP 同等）／フルパス（POSIX）。

### 4.12 `OnGhostExit` **[NOTIFY]**
- **Ref0**：終了したゴーストの **`CGWindowID` 列**。  
- **Ref1..4**：ゴースト名／現在シェル名／ID／フルパス（POSIX）。

### 4.13 `OnGhostInfoUpdate` **[NOTIFY]**
- **Ref0**：変更があったゴーストの **`CGWindowID` 列**。  
- **Ref1..4**：同上。

### 4.14 `OnMenuExec`
- **意味**：オーナードローメニューからプラグインが実行された。  
- **Ref0**：呼び出し元ゴーストの **`CGWindowID` 列**。  
- **Ref1..4**：ゴースト名／シェル名／ID／フルパス（POSIX）。

### 4.15 `OnInstallComplete`
- **Ref0**：インストールタイプ（バイト1区切り）。  
- **Ref1**：インストールされたものの名前（バイト1区切り）。  
- **Ref2**：インストールされたものの **フルパス**（POSIX）。

### 4.16 `OnChoiceSelect(Ex)` / `OnAnchorSelect(Ex)` / `\q` 等に指定された任意名
- **意味**：選択肢/アンカー選択時の **SHIORI Event 横流し**。  
- **Ref***：発生した SHIORI Event の Reference 群（そのまま）。

### 4.17 `\![raiseplugin]` / `\![notifyplugin]` に指定された任意名
- **意味**：当該コマンドの実行でプラグインに通知（`notifyplugin` は [NOTIFY]）。  
- **Ref***：指定された任意引数。

---

## 5. セキュリティとサンドボックス
- フルパスはユーザ領域の **Application Support/Ourin** を既定。サンドボックス時はコンテナ配下へ。  
- 外部入力のパスは `file://` に正規化し、必要時 **security‑scoped URL** を使用。

## 6. スレッド/順序/タイムアウト
- Ourin は **プラグイン単位で直列配送**（同一プラグインの同時呼び出しなし）。  
- 既定 **タイムアウト 3 秒**（推奨値）。応答無では次イベントへ。  
- [NOTIFY] へのスクリプト返却は **無視**（UKADOC準拠）。

## 7. 例: フレーム

```
# OnGhostBoot の例（2.0M）
GET PLUGIN/2.0
ID: OnGhostBoot
Sender: Ourin
Reference0: 12345,67890         # CGWindowID 列（未構築は 0）
Reference1: 里々さん
Reference2: default.shell
Reference3: ourin-ghost-uuid
Reference4: /Users/you/Library/Application Support/Ourin/Ghosts/Satori

###

PLUGIN/2.0 200 OK
Value: OK
```

## 8. 付録: 用語
- **CGWindowID**：Window Server のウィンドウ番号（`NSWindow.windowNumber` から取得可、列挙は CGWindowList）。  
- **POSIX パス**：macOS の絶対パス。必要に応じ `file://` URL で表現。
