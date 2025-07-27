# SHIORI Resource — **3.0M‑Mac 仕様書（完全版 / UKADOC準拠）**
**Status:** Draft / Ourin (macOS 10.15+ / Universal 2)  
**Updated:** 2025-07-27 (JST)  
**互換方針:** UKADOC「[SHIORI Resourceリスト]」に載る**全要素**の**名称・意味・返値**を踏襲し、**OS 依存値のみ macOS ネイティブ（M‑Diff）**に置換。  
**対象:** Ourin（ベースウェア）および SHIORI 実装者。

> 典拠: SHIORI Resource の一次情報は UKADOC を参照。項目名や返値の意味は UKADOC が正です。  
> 本仕様は **macOS 移植差分（M‑Diff）**と**実装上の統一方針**を追加定義します。

---

## 目次
- [1. 基本規約](#1-基本規約)
- [2. M‑Diff（macOS 置換点）](#2-m-diffmacos-置換点)
- [3. 要素一覧（完全）](#3-要素一覧完全)
  - [3.1 SHIORI情報](#31-shiori情報)
  - [3.2 ゴースト情報](#32-ゴースト情報)
  - [3.3 更新情報](#33-更新情報)
  - [3.4 オーナードローメニュー画像](#34-オーナードローメニュー画像)
  - [3.5 オーナードローメニュー文字色](#35-オーナードローメニュー文字色)
  - [3.6 オーナードローメニュー項目名（caption 系）](#36-オーナードローメニュー項目名caption-系)
  - [3.7 ツールチップイベント（補足）](#37-ツールチップイベント補足)
- [4. 返答規則と既定値](#4-返答規則と既定値)
- [5. 互換性と注意点](#5-互換性と注意点)
- [6. 変更履歴](#6-変更履歴)

---

## 1. 基本規約
- **文字コード:** 既定 **UTF‑8**。互換のため **CP932/Shift_JIS** 受理→内部 UTF‑8 正規化可。  
- **改行:** CR+LF を**受理**（内部処理は LF 正規化可）。  
- **返値の型:** 文字列／数値／ブール（`0/1` 文字列）／色（R,G,B の整数）など。戻りは**さくらスクリプトでない短文**が基本。  
- **省略時:** 未対応・未設定は空文字を返す。`*.visible` は省略時 1（表示）。

## 2. M‑Diff（macOS 置換点）
- **パス（`*.filename` / `log_path` / 各URL・画像パス）:** **POSIX 絶対パス**または **`file://` URL** を標準。Windows 形式が来た場合は受信側で正規化。  
- **座標（`*.defaultleft` / `*.defaulttop` / 入力ボックス `.default*`）:** **ディスプレイ座標（ピクセル）**。Ourin 内部では Cocoa の座標系差（原点位置）の吸収を行い、SSP と等価の表示位置になるよう変換。  
- **色:** `menu.*.color.(r|g|b)` は **0–255 の整数**を推奨。  
- **列挙:** `popupmenu.type` 等の列挙値は **SSP と同義**。未知値は既定動作にフォールバック。

---

## 3. 要素一覧（完全）

### 3.1 SHIORI情報
| Key | 意味（要約） | 返値の型 | 備考 |
|---|---|---|---|
| `version` | SHIORI のバージョン情報（*プロトコル版ではない*） | 文字列 | 自動返却。 |
| `craftman` | SHIORI 作者名（7bit） | 文字列 | 自動返却。 |
| `craftmanw` | SHIORI 作者名（拡張文字可） | 文字列 | 自動返却。 |
| `name` | SHIORI 名称（ゴースト名ではない、7bit） | 文字列 | 自動返却。 |
| `log_path` | SHIORI ログファイルのフルパス | パス文字列 | Ourin は POSIX/`file://` を受理・推奨。 |

### 3.2 ゴースト情報
| Key | 意味（要約） | 返値の型 | 備考 |
|---|---|---|---|
| `homeurl` | ネットワーク更新用 URL / 位置 | URL/文字列 | `descript.txt` と併記時の優先は原典参照。 |
| `useorigin1` | 更新ファイルカウントの開始数（1:1開始/0:0開始） | `0/1` | 互換値。 |
| `username` | ユーザー表示名 | 文字列 |  |

**デフォルト位置（画像/画面）**  
| Key | 意味 | 返値 | 備考 |
|---|---|---|---|
| `sakura.defaultx` / `kero.defaultx` / `char*.defaultx` | 画像ベースX | 数値 |  |
| `sakura.defaulty` / `kero.defaulty` / `char*.defaulty` | 画像ベースY | 数値 |  |
| `sakura.defaultleft` / `kero.defaultleft` / `char*.defaultleft` | 画面X | 数値 | M‑Diff: Cocoa 座標を吸収。 |
| `sakura.defaulttop` / `kero.defaulttop` / `char*.defaulttop` | 画面Y | 数値 | 同上。 |

**入力ボックス初期位置**  
`(communicatebox|scriptbox|addressbar|teachbox|dateinput|timeinput|ipinput|sliderinput|passwordinput|inputbox).defaultleft` / `.defaulttop` … ディスプレイ座標（ピクセル）。

**おすすめ/ポータル**  
| Key | 意味 | 返値 | 形式 |
|---|---|---|---|
| `sakura.recommendsites` / `kero.recommendsites` / `char*.recommendsites` | おすすめリスト | 連結文字列 | `項目名`[0x01]`url`[0x01]`バナー画像パス`[0x01]`選択時トーク` [0x02] … |
| `sakura.portalsites` | ポータルリスト | 連結文字列 | 同上。 |
| `sakura.recommendbuttoncaption` / `kero.*` / `char*.recommendbuttoncaption` | ボタン名 | 文字列 |  |
| `updatebuttoncaption` / `vanishbuttoncaption` / `readmebuttoncaption` | ボタン名 | 文字列 |  |
| `vanishbuttonvisible` | 消滅通告ボタン表示 | `0/1` | 省略時 1。 |
| `sakura.popupmenu.visible` / `kero.*` / `char*.popupmenu.visible` | オーナードローメニュー表示 | `0/1` | |
| `sakura.popupmenu.type` / `kero.*` / `char*.popupmenu.type` | メニュー種別 | 列挙 | SSP 同義。 |
| `getaistate` | AI 状態 | 文字列 |  |
| `getaistateex` | AI 状態（複数） | 連結文字列 | 0x01 区切りなど。 |
| `legacyinterface` | 互換用フラグ | `0/1` | SSP 互換。 |

### 3.3 更新情報
| Key | 意味 | 返値 | 備考 |
|---|---|---|---|
| `other_homeurl_override` | 他 source の homeurl 上書き | 文字列 | 既定空。 |

### 3.4 オーナードローメニュー画像
| Key | 意味 | 返値 | 備考 |
|---|---|---|---|
| `menu.sidebar.bitmap.filename` | サイドバー画像 | パス文字列 | M‑Diff: POSIX/`file://`。 |
| `menu.background.bitmap.filename` | 背景画像 | パス文字列 | 同上。 |
| `menu.foreground.bitmap.filename` | 前景画像 | パス文字列 | 同上。 |

### 3.5 オーナードローメニュー文字色
| Key | 意味 | 返値 |
|---|---|---|
| `menu.background.font.color.r/g/b` | 背景用フォント色（RGB） | 整数(0–255) |
| `menu.foreground.font.color.r/g/b` | 前景用フォント色（RGB） | 整数(0–255) |
| `menu.separator.color.r/g/b` | セパレータ線色（RGB） | 整数(0–255) |
| `menu.frame.color.r/g/b` | フレーム線色（RGB） | 整数(0–255) |
| `menu.disable.font.color.r/g/b` | 無効項目フォント色（RGB） | 整数(0–255) |

### 3.6 オーナードローメニュー項目名（caption 系）
以下の **`.caption`** キーはメニューに表示するラベル。**Ourin では `X.caption` に対し `X.visible`（`0/1`）も受理**し、未指定は 1（表示）とする。

```
activaterootbutton.caption, addressbarbutton.caption, alignrootbutton.caption,
alwaysstayontopbutton.caption, alwaystrayiconvisiblebutton.caption,
balloonhistorybutton.caption, balloonrootbutton.caption, biffallbutton.caption,
biffbutton.caption, calendarbutton.caption, callghosthistorybutton.caption,
callghostrootbutton.caption, callsstpsendboxbutton.caption, char*.recommendsites.caption,
charsetbutton.caption, closeballoonbutton.caption, closebutton.caption,
collisionvisiblebutton.caption, configurationbutton.caption, configurationrootbutton.caption,
debugballoonbutton.caption, definedsurfaceonlybutton.caption, dressuprootbutton.caption,
duibutton.caption, enableballoonmovebutton.caption, firststaffbutton.caption,
ghostexplorerbutton.caption, ghosthistorybutton.caption, ghostinstallbutton.caption,
ghostrootbutton.caption, headlinesensehistorybutton.caption, headlinesenserootbutton.caption,
helpbutton.caption, hidebutton.caption, historyrootbutton.caption, inforootbutton.caption,
leavepassivebutton.caption, messengerbutton.caption, pluginhistorybutton.caption,
pluginrootbutton.caption, portalrootbutton.caption, purgeghostcachebutton.caption,
quitbutton.caption, rateofuseballoonbutton.caption, rateofusebutton.caption,
rateofuserootbutton.caption, rateofusetotalbutton.caption, readmebutton.caption,
recommendrootbutton.caption, regionenabledbutton.caption, reloadinfobutton.caption,
resetballoonpositionbutton.caption, resettodefaultbutton.caption, scriptlogbutton.caption,
shellrootbutton.caption, shellscaleotherbutton.caption, shellscalerootbutton.caption,
sntpbutton.caption, switchactivatewhentalkbutton.caption,
switchactivatewhentalkexceptupdatebutton.caption, switchautobiffbutton.caption,
switchautoheadlinesensebutton.caption, switchblacklistingbutton.caption,
switchcompatiblemodebutton.caption, switchconsolealwaysvisiblebutton.caption,
switchconsolevisiblebutton.caption, switchdeactivatebutton.caption,
switchdontactivatebutton.caption, switchdontforcealignbutton.caption,
switchduivisiblebutton.caption, switchforcealignfreebutton.caption,
switchforcealignlimitbutton.caption, switchignoreserikomovebutton.caption,
switchlocalsstpbutton.caption, switchmovetodefaultpositionbutton.caption,
switchproxybutton.caption, switchquietbutton.caption, switchreloadbutton.caption,
switchreloadtempghostbutton.caption, switchremotesstpbutton.caption, switchrootbutton.caption,
switchtalkghostbutton.caption, systeminfobutton.caption, updatebutton.caption,
updatefmobutton.caption, updateplatformbutton.caption, utilityrootbutton.caption,
vanishbutton.caption, aistatebutton.caption, dictationbutton.caption, texttospeechbutton.caption
```

**ショートカットキー**  
項目のショートカットキーは UKADOC の「ショートカットキー」節の規定に従う（キー設定で当該項目を起動）。

### 3.7 ツールチップイベント（補足）
`tooltip` / `balloon_tooltip` は **ツールチップ表示時に参照されるイベント名**。Ourin は UKADOC の推奨順に解決し、スクリプトを取得して表示する。

---

## 4. 返答規則と既定値
- 返答は**短いテキスト**（`0/1` や連結文字列含む）。  
- `*.visible` は省略時 1。  
- おすすめ/ポータルの**連結形式**は `[0x01]`（SOH）と `[0x02]`（STX）で区切る慣例に従う。

## 5. 互換性と注意点
- **SHIORI/3.0 準拠**：Resource は SHIORI/3.0 の**通常イベント扱い**だが、返値がスクリプトではない点に注意。  
- **未知キー**：Ourin は未知の Resource でも透過で処理可能（将来拡張互換）。  
- **画像パス**：`menu.*.bitmap.filename` の相対は**ゴーストルート**基準で解決。

## 6. 変更履歴
- 2025‑07‑27: 初版（3.0M‑Mac、全要素）。
