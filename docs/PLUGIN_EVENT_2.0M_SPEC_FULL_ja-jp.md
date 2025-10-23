# PLUGIN Event — **2.0M（macOS）** 仕様書（UKADOC準拠・完全版）
**Status:** Draft / Ourin (macOS 10.15+ / Universal 2: arm64+x86_64)  
**Updated:** 2025-07-27 (JST)  
**互換方針:** UKADOC「PLUGIN Eventリスト」の**イベントID／意味／Reference順**を踏襲。**OS依存値のみ macOS ネイティブ**へ置換。  
**文字コード:** 既定 **UTF‑8**（互換で CP932/SJIS 受理→内部 UTF‑8 正規化）。`version` 応答の `Charset:` 指定があれば切り替え。  
**改行:** `CRLF` を厳守（受理）。内部処理は `LF` 正規化可。  
**用語:** 「バイト値1区切り」= **0x01 (SOH)** 区切り。

---

## 目次
- [1. 本仕様の目的](#1-本仕様の目的)
- [2. 通信・符号化・改行（PLUGIN/2.0 準拠）](#2-通信符号化改行plugin20-準拠)
- [3. macOS置換（M‑Diff）](#3-macos置換m-diff)
- [4. イベント一覧（完全）](#4-イベント一覧完全)
  - [4.1 version](#41-version)
  - [4.2 installedplugin \[NOTIFY\]](#42-installedplugin-notify)
  - [4.3 installedghostname \[NOTIFY\]](#43-installedghostname-notify)
  - [4.4 installedballoonname \[NOTIFY\]](#44-installedballoonname-notify)
  - [4.5 ghostpathlist \[NOTIFY\]](#45-ghostpathlist-notify)
  - [4.6 balloonpathlist \[NOTIFY\]](#46-balloonpathlist-notify)
  - [4.7 headlinepathlist \[NOTIFY\]](#47-headlinepathlist-notify)
  - [4.8 pluginpathlist \[NOTIFY\]](#48-pluginpathlist-notify)
  - [4.9 OnSecondChange](#49-onsecondchange)
  - [4.10 OnOtherGhostTalk](#410-onotherghosttalk)
  - [4.11 OnGhostBoot](#411-onghostboot)
  - [4.12 OnGhostExit \[NOTIFY\]](#412-onghostexit-notify)
  - [4.13 OnGhostInfoUpdate \[NOTIFY\]](#413-onghostinfoupdate-notify)
  - [4.14 OnMenuExec](#414-onmenuexec)
  - [4.15 OnInstallComplete](#415-oninstallcomplete)
  - [4.16 OnChoiceSelect(Ex)/OnAnchorSelect(Ex)/\q 任意名](#416-onchoiceselectexonanchorselectexq-任意名)
  - [4.17 \![raiseplugin]/\![notifyplugin] 任意名](#417-raisepluginnotifyplugin-任意名)
- [5. 応答・戻り値ポリシー](#5-応答戻り値ポリシー)
- [6. 例: フレーミング](#6-例-フレーミング)
- [7. 変更履歴](#7-変更履歴)

---

## 1. 本仕様の目的
- Windows 固有の要素（`HWND`/パス表現）を **macOS ネイティブ**に差し替えつつ、**語彙と意味は互換**のままプラグインにイベントを通知する。

## 2. 通信・符号化・改行（PLUGIN/2.0 準拠）
- リクエスト/レスポンスは **PLUGIN/2.0** のヘッダ書式に準拠（`GET/NOTIFY PLUGIN/2.0`、`ID:`、`ReferenceN:`、`Charset:` 等）。  
- 改行は **CR+LF**。`Charset:` 指定があればそれに従う（既定: 2.0M では UTF‑8）。

## 3. macOS置換（M‑Diff）
- **ウィンドウ識別**：`HWND`（Windows固有）は **`CGWindowID` の列**に置換。Ourin の NSWindow からは `windowNumber` を参照し Window Server 番号として扱い、外部照会や検証は `CGWindowListCopyWindowInfo` の `kCGWindowNumber` を用いる。  
- **パス**：Windows パスは **POSIX 絶対パス**または **`file://` URL** に置換（相対はプラグイン/ゴースト基点から解決）。  
- **区切り**：リストは **0x01 区切り**（原典の「バイト値1区切り」）。

---

## 4. イベント一覧（完全）

### 4.1 `version`
- **時期**: プラグインのロード直後。  
- **応答**: `Value:` にプラグインのバージョン文字列。任意で `Charset: <enc>` を付けると以後のリクエストに適用。  
- **備考**: 本イベントのみ応答様式が他と異なる。

### 4.2 `installedplugin` **[NOTIFY]**
- **意味**: インストール済プラグインの列挙。  
- **Ref***: 0x01 区切り `プラグイン名,プラグインID`。

### 4.3 `installedghostname` **[NOTIFY]**
- **Ref0**: 0x01 区切りのゴースト名リスト。  
- **Ref1**: 0x01 区切りの `\0` 名リスト。  
- **Ref2**: 0x01 区切りの `\1` 名リスト。

### 4.4 `installedballoonname` **[NOTIFY]**
- **Ref0**: 0x01 区切りのバルーン名リスト。

### 4.5 `ghostpathlist` **[NOTIFY]**
- **Ref***: 読み込んでいる **ゴーストフォルダのフルパス**（**POSIX/`file://`**）。複数ある場合は `Reference1..`。

### 4.6 `balloonpathlist` **[NOTIFY]**
- **Ref0**: 読み込んでいる **バルーンフォルダのフルパス**（POSIX/`file://`）。

### 4.7 `headlinepathlist` **[NOTIFY]**
- **Ref***: 読み込んでいる **ヘッドラインフォルダのフルパス**（POSIX/`file://`）。

### 4.8 `pluginpathlist` **[NOTIFY]**
- **Ref***: 読み込んでいる **プラグインフォルダのフルパス**（POSIX/`file://`）。

### 4.9 `OnSecondChange`
- **意味**: 秒間隔の通知。  
- **間隔**: `descript.txt` の `secondchangeinterval` に従う（秒）。

### 4.10 `OnOtherGhostTalk`
- **Ref0**: ゴースト名。  
- **Ref1**: 本体側名。  
- **Ref2**: 原因列挙（`break,communicate,sstp-send,owned,remote,notranslate,plugin-script,plugin-event` の **カンマ区切り**）。  
- **Ref3**: 発話イベント ID。  
- **Ref4**: 発話スクリプト。  
- **Ref5**: 0x01 区切りで、ゴーストに渡された Reference 群。

### 4.11 `OnGhostBoot`
- **Ref0**: **起動したゴーストの各キャラクタウィンドウの `CGWindowID` 列**（未構築は `0`）。  
- **Ref1**: ゴースト名。  
- **Ref2**: 現在のシェル名。  
- **Ref3**: ゴースト ID（Owned SSTP と同等）。  
- **Ref4**: ゴーストのフルパス（POSIX/`file://`）。

### 4.12 `OnGhostExit` **[NOTIFY]**
- **Ref0**: **終了したゴーストの `CGWindowID` 列**（未構築は `0`）。  
- **Ref1..4**: 名称/シェル名/ID/フルパス（POSIX/`file://`）。

### 4.13 `OnGhostInfoUpdate` **[NOTIFY]**
- **Ref0**: **変更があったゴーストの `CGWindowID` 列**（未構築は `0`）。  
- **Ref1..4**: 名称/シェル名/ID/フルパス（POSIX/`file://`）。

### 4.14 `OnMenuExec`
- **意味**: オーナードローメニューからプラグインが実行された。  
- **Ref0**: 呼び出し元ゴーストの **`CGWindowID` 列**。  
- **Ref1..4**: 名称/シェル名/ID/フルパス（POSIX/`file://`）。

### 4.15 `OnInstallComplete`
- **Ref0**: 0x01 区切りの **インストールタイプ**。  
- **Ref1**: 0x01 区切りの **名前**。  
- **Ref2**: 0x01 区切りの **フルパス**（POSIX/`file://`）。

### 4.16 `OnChoiceSelect(Ex)` / `OnAnchorSelect(Ex)` / `\q` 任意名
- **意味**: 選択肢/アンカー選択時の **SHIORI Event 横流し**。  
- **Ref***: 発生した SHIORI Event の Reference 群（そのまま）。

### 4.17 `\![raiseplugin]` / `\![notifyplugin]` 任意名
- **意味**: さくらスクリプトの実行でプラグインに通知（`notifyplugin` は **[NOTIFY]**）。  
- **Ref***: 指定された任意引数。

---

## 5. 応答・戻り値ポリシー
- **[NOTIFY]**: スクリプト返却は **無視**。`PLUGIN/2.0 204 No Content` でよい。  
- **無印**: `GET` の場合は `PLUGIN/2.0 200 OK` で `Script:` 等を返せる（`Target/Event/Reference` 可）。

## 6. 例: フレーミング
```
GET PLUGIN/2.0
ID: OnGhostBoot
Charset: UTF-8
Sender: Ourin
Reference0: 12345,67890
Reference1: 里々さん
Reference2: default.shell
Reference3: ourin-ghost-uuid
Reference4: /Users/you/Library/Application Support/Ourin/Ghosts/Satori

###

PLUGIN/2.0 200 OK
Script: \0\s[0]OK\e
```

## 7. 変更履歴
- 2025-07-27: 初版（完全版、macOS置換つき）。
