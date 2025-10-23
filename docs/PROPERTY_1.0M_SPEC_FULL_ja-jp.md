# PROPERTY System — **1.0M for macOS (Ourin)** 仕様書（UKADOC準拠・完全版）
**Status:** Draft / Ourin (macOS 10.15+ / Universal 2)  
**Updated:** 2025-07-28 (JST)  
**互換方針:** UKADOC「プロパティシステム」の**語彙・意味**を尊重し、**OS 依存点のみ macOS ネイティブ（M‑Diff）**として置換。  
**対象:** ゴースト作者・SHIORI実装者・Ourin（ベースウェア）実装者。

> 参考: UKADOC のプロパティシステム本体／操作タグ（\![get,property], \![set,property]）を正とする。  
> 本仕様は **macOS差分**と**実装ガイドライン**を追加したもの。

---

## 目次
- [1. 目的と適用範囲](#1-目的と適用範囲)
- [2. 利用方法（環境変数／タグ）](#2-利用方法環境変数タグ)
- [3. M‑Diff（macOS置換点）](#3-m-diffmacos置換点)
- [4. プロパティ一覧（完全）](#4-プロパティ一覧完全)
  - [4.1 system.*](#41-system)
  - [4.2 baseware.*](#42-baseware)
  - [4.3 ghostlist.* / activeghostlist.* / currentghost.*](#43-ghostlist--activeghostlist--currentghost)
  - [4.4 currentghost.shelllist.*](#44-currentghostshelllist)
  - [4.5 currentghost.scope(*) / surface / rect / name](#45-currentghostscope--surface--rect--name)
  - [4.6 currentghost.seriko.cursor.* / tooltip.*](#46-currentghostserikocursor--tooltip)
  - [4.7 currentghost.seriko.surfacelist.*](#47-currentghostserikosurfacelist)
  - [4.8 currentghost.balloon.scope(*) 系](#48-currentghostballoonscope-系)
  - [4.9 balloonlist.* / headlinelist.* / pluginlist.*](#49-balloonlist--headlinelist--pluginlist)
  - [4.10 history.(ghost|balloon|headline|plugin).*](#410-historyghostballoonheadlineplugin)
  - [4.11 rateofuselist.*](#411-rateofuselist)
  - [4.12 汎用プロパティ名](#412-汎用プロパティ名)
- [5. 書込可能（SET有効）一覧](#5-書込可能set有効一覧)
- [6. 例：参照・取得・設定](#6-例参照取得設定)
- [7. 互換性・注意事項](#7-互換性注意事項)
- [8. 変更履歴](#8-変更履歴)

---

## 1. 目的と適用範囲
- **目的**：SSP のプロパティシステム互換の**語彙**を維持しつつ、Ourin（macOS）で**同等動作**を保証する。  
- **非目標**：Windows 固有 API 値（HWND 等）や Win32 カーソルそのものの完全再現。

## 2. 利用方法（環境変数／タグ）
- 環境変数：`%property[<name>]` で **値を埋め込み**。  
- 取得タグ：`\![get,property,<event>,<name1>,<name2>...]` で **任意イベント**を発生させ、`reference0..` に値群が入る。  
- 設定タグ：`\![set,property,<name>,<value>]` で **書き込み**（対象が[SET有効]のみ）。

## 3. M‑Diff（macOS置換点）
- **文字コード**：既定 **UTF‑8**。互換のため **CP932/Shift_JIS** を受理し内部 UTF‑8 へ正規化。  
- **パス**：`path` 系・各 `*.filename` は **POSIX 絶対パス**または **`file://` URL**を標準。相対は「シェル→ゴースト」順で探索。  
- **座標（screen/rect）**：**仮想デスクトップのグローバル座標**、**原点(0,0)はメインディスプレイ左上**。Cocoa座標との差は Ourin が吸収。  
- **カーソルファイル**：`*.mousecursor*` は surfaces.txt の `cursor` セクションと**同じ指定**。`.cur/.ani` 相当は Ourin が内部でデコード（macOS NSCursor へ変換）し、相対パスは「シェル→ゴースト」。  
- **時間**：`system.*` の時刻は OS 現地時刻。

---

## 4. プロパティ一覧（完全）

### 4.1 `system.*`
- `system.year` / `month` / `day` / `hour` / `minute` / `second` / `millisecond` / `dayofweek`  
- `system.cursor.pos` : `X,Y`（ピクセル、グローバル座標）。  
- `system.os.(type|name|version|build|parenttype|parentname)`：macOS では `type=macOS`、`name` 例: `macOS 14`、`version` は Darwin カーネル等。`parent*` は互換層がある場合のみ。  
- `system.cpu.(load|num|vendor|name|clock|features)`  
- `system.memory.(load|phyt|phya)`

### 4.2 `baseware.*`
- `baseware.version` / `baseware.name`

### 4.3 `ghostlist.*` / `activeghostlist.*` / `currentghost.*`
- `ghostlist.count`、`ghostlist(<名前/相方名/パス>).汎用プロパティ名`、`.icon`、`.index(ID)`、`.current`。  
- `activeghostlist.*`：起動中のゴーストの列挙。  
- `currentghost.汎用プロパティ名`、`currentghost.status`（Status ヘッダ互換：`talking|passive|induction|timecritical|nouserbreak|online|choosing|minimizing|opening(...)/balloon(...)`）。

### 4.4 `currentghost.shelllist.*`
- `currentghost.shelllist(<シェル名/パス>).汎用プロパティ名` / `.index(ID)` / `.current` / `.count`。

### 4.5 `currentghost.scope(*) / surface / rect / name`
- `currentghost.scope.count`：最大キャラ数。  
- `currentghost.scope(ID).surface.num`：表示サーフェスID。  
- `currentghost.scope(ID).seriko.defaultsurface`：既定サーフェス。  
- `currentghost.scope(ID).surface.x|y`：サーフェスのローカル座標。  
- `currentghost.scope(ID).x|y`：**スクリーン座標**の基準点（通常はサーフェス中央下）。  
- `currentghost.scope(ID).rect`：ウィンドウ矩形 `(left,top,right,bottom)`。  
- `currentghost.scope(ID).name`：スコープ名（0=さくら、1=相方、2+=char*）。

### 4.6 `currentghost.seriko.cursor.*` / `tooltip.*`
- `currentghost.mousecursor(.*)` / `currentghost.balloon.mousecursor(.*)`：**相対パスは「シェル→ゴースト」探索**。空文字を `SET` で**定義削除**。  
- `currentghost.seriko.cursor.scope(ID).mouse????list(<当たり判定>).(path|name)`、`.index(ID2).(path|name)`、`.count`。  
- `currentghost.seriko.tooltip.scope(ID).textlist(<当たり判定>).(text|name)`、`.index(ID2).(text|name)`、`.count`。

### 4.7 `currentghost.seriko.surfacelist.*`
- `.all`：有効なサーフェスIDの**全て**（カンマ区切り）。  
- `.defined`：surfaces.txt 内で **定義ありのもの**（カンマ区切り）。

### 4.8 `currentghost.balloon.scope(ID).*`
- `.count`（画像数）、`.num`（ID）、`.validwidth(.initial)`、`.validheight(.initial)`、`.lines(.initial)`、`.basepos.x|y`、`.char_width`。

### 4.9 `balloonlist.*` / `headlinelist.*` / `pluginlist.*`
- `<list>(<名前/パス>).汎用プロパティ名` / `.index(ID).汎用プロパティ名` / `.count`。

### 4.10 `history.(ghost|balloon|headline|plugin).*`
- それぞれ `<list>(<名前/パス>).汎用プロパティ名` / `.index(ID).汎用プロパティ名` / `.count`。

### 4.11 `rateofuselist.*`
- `(name|sakuraname|keroname|boottime|bootminute|percent)` と `index(順位).<同名>`。

### 4.12 汎用プロパティ名
- `name / sakuraname / keroname / craftmanw / craftmanurl / path / thumbnail / update_result / update_time / homeurl / username / shiori.<変数名> / index / menu / sakura.bind.menu / kero.bind.menu / char*.bind.menu`

---

## 5. 書込可能（SET有効）一覧
- **カーソル**：`currentghost.mousecursor(.*)`、`currentghost.balloon.mousecursor(.*)`、`currentghost.seriko.cursor.scope(ID).mouse????list(...).path`、`.index(ID2).path`。  
- **ツールチップ**：`currentghost.seriko.tooltip.scope(ID).textlist(...).text`、`.index(ID2).text`。  
- **シェル/着せ替えメニュー**：`currentghost.shelllist(...).menu`、`currentghost.(sakura|kero|char*).bind.menu`。

---

## 6. 例：参照・取得・設定

**参照（環境変数）**  
```
%property[baseware.name] ver. %property[baseware.version]
```

**取得（イベントで受け取り）**  
```
\![get,property,OnGetSakuraName,ghostlist(Emily/Phase4.5).keroname]
// → SHIORI側 OnGetSakuraName の reference0 に値が入る
```

**設定（メニューからシェルを非表示）**  
```
\![set,property,currentghost.shelllist(ULTIMATE FORM).menu,hidden]
```

**設定（当たり判定ヘッドのツールチップ）**  
```
\![set,property,currentghost.seriko.tooltip.scope(0).textlist(Head).text,頭をなでる]
```

---

## 7. 互換性・注意事項
- **相対パス探索**：シェル→ゴーストの順で探索。空文字 `SET` は**定義削除**。  
- **スクリーン座標**：Windows と同じく **メインディスプレイ左上(0,0)** を起点とする **仮想デスクトップ座標**に統一。Ourin 内部で Cocoa/CG の差を吸収。  
- **SJIS受理**：`get/set` 受信で CP932 を受理、内部は UTF‑8 に統一。  
- **未知要素**：将来拡張のため読み取りは透過、書込は無視＋警告ログ。

---

## 8. 変更履歴
- 2025-07-28 (JST): 初版（1.0M for macOS）。
