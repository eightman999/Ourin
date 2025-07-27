# PROPERTY/1.0M — Ourin（macOS）プロパティシステム仕様書
**Status:** Draft / 2025-07-27  
**Target:** Ourin（ベースウェア, macOS 10.15+ / Universal 2）  
**互換方針:** SSP「プロパティシステム」の**語彙・挙動互換**（1.0 相当）。本書は macOS 向け置換（“M 拡張”）のみ定義。  
**文字コード:** 内部 UTF‑8。ただし**SJIS(CP932) 入力は受理→UTF‑8 正規化**（返却は UTF‑8）。

---

## 目次
- [1. 概要](#1-概要)
- [2. アクセス手段（互換）](#2-アクセス手段互換)
- [3. 値の表記と座標・単位](#3-値の表記と座標単位)
  - [3.1 座標系の定義（M 仕様）](#31-座標系の定義m-仕様)
  - [3.2 例：座標変換の疑似コード](#32-例座標変換の疑似コード)
- [4. プロパティ語彙（macOS マッピング）](#4-プロパティ語彙macos-マッピング)
  - [4.1 system.*](#41-system)
  - [4.2 baseware.*](#42-baseware)
  - [4.3 ghostlist/activeghostlist/currentghost.*](#43-ghostlistactiveghostlistcurrentghost)
  - [4.4 balloonlist/headlinelist/pluginlist/history/rateofuselist](#44-balloonlistheadlinelistpluginlisthistoryrateofuselist)
- [5. 書込可能フラグ（SET 有効）一覧](#5-書込可能フラグset-有効一覧)
- [6. セキュリティとサンドボックス](#6-セキュリティとサンドボックス)
- [7. 互換性と差分](#7-互換性と差分)
- [付録A: Rosetta 検出サンプル（Swift/C）](#付録a-rosetta-検出サンプルswiftc)
- [付録B: 実装ヒント（CPU/メモリ/OS 情報）](#付録b-実装ヒントcpumemoryos-情報)
- [付録C: 参考情報](#付録c-参考情報)

---

## 1. 概要
- Ourin 上で**ゴースト側から**ベースウェアの内部状態やインストール資産へ**読み取り／一部書き込み**を行う仕組み。  
- 既存 UKADOC のプロパティ語彙・取得方法を踏襲。Windows 固有の値は**同義の macOS 情報**に置換。

## 2. アクセス手段（互換）
- **環境変数展開**：`%property[プロパティ名]`  
  例: `%property[baseware.name] ver %property[baseware.version]`
- **取得**：`\![get,property,イベント名,プロパティ名,...]`  
- **設定**：`\![set,property,プロパティ名,値]`（[SET 有効]項目のみ）

> 互換上の注意：複数指定時は Reference0 から順番に返す。値は UTF‑8。

## 3. 値の表記と座標・単位
- **文字列は UTF‑8**。SJIS 入力は CP932 → UTF‑8 に正規化し処理。  
- **パスは POSIX 形式**（`/` 区切り）。
- **座標／サイズの単位**：**ピクセル相当の “論理ピクセル（pt）”**。Retina 等の拡縮は Ourin 内で吸収し、**1 論理 px = 1pt**として返却。  
  必要に応じ `backingScaleFactor` を用いて実デバイスピクセルへ変換可能。

### 3.1 座標系の定義（M 仕様）
- **原点：仮想デスクトップの左上 (0,0)**。  
  macOS のグローバル座標は**左下原点**（デフォルト）だが、SSP 互換のため**左上原点**に変換して返す。  
- マルチディスプレイ時は `NSScreen.screens` の **frame の合成矩形**を仮想デスクトップとみなし、その左上を (0,0) とする。

### 3.2 例：座標変換の疑似コード
```swift
// Cocoaのグローバル座標(左下原点) -> 互換座標(左上原点) への変換
func compatibleCursorPositionString() -> String {
    let union = NSScreen.screens.reduce(.null) { $0.union($1.frame) } // グローバル座標
    let p = NSEvent.mouseLocation // グローバル座標・左下原点・単位pt
    let x = p.x - union.minX
    let y = union.maxY - p.y      // Y反転して左上原点へ
    return "\(Int(x)),\(Int(y))"
}
```

---

## 4. プロパティ語彙（macOS マッピング）

### 4.1 `system.*`
- `system.year/month/day/hour/minute/second/millisecond/dayofweek`  
  → ローカルタイムの整数。  
- `system.cursor.pos`  
  → 現在マウス座標 `"X,Y"`（上記 **左上原点**・単位 pt）。  
- `system.os.(id)`  
  - `type` = `"macOS"` 固定。  
  - `name` = `"macOS <major.minor[.patch]>"`（`ProcessInfo.operatingSystemVersion` 由来）。  
  - `version` = **Darwin カーネル版**（`sysctl kern.osrelease`）。  
  - `build` = **ビルド番号**（`sysctl kern.osversion`）。  
  - `parenttype` / `parentname` = Rosetta 2 翻訳実行時のみ、`"Rosetta 2"` / `"macOS <version>"`。
- `system.cpu.(id)`  
  - `load`：%（移動平均可）。  
  - `num`：論理コア数（`hw.ncpu`）。  
  - `vendor` / `name`：`machdep.cpu.brand_string` など。Apple Silicon は `vendor="Apple"` を想定。  
  - `clock`：`hw.cpufrequency`。  
  - `features`：`hw.optional.*` / `machdep.cpu.features` の可読化文字列。  
- `system.memory.(id)`  
  - `load`：%（Ourin 内部で計算）。  
  - `phyt`：総物理メモリ (MB) = `hw.memsize`。  
  - `phya`：空き (MB) = `vm_stat`/`host_statistics` の値から推算（実装例は付録B）。

### 4.2 `baseware.*`
- `baseware.name` = `"Ourin"`、`baseware.version`：SemVer 文字列。

### 4.3 `ghostlist/activeghostlist/currentghost.*`
- **語彙は UKADOC 同名キーを踏襲**（`汎用プロパティ名` 群を含む）。  
- `... .path` は **POSIX パス**で返す。  
- `currentghost.balloon.scope(ID).validwidth/validheight/lines` 等の描画寸法は **論理 px**。

### 4.4 `balloonlist/headlinelist/pluginlist/history/rateofuselist`
- 語彙・取得挙動は同名互換。`index(ID)` / `count` 等も踏襲。

---

## 5. 書込可能フラグ（SET 有効）一覧
> **注意**：ここに列挙のないキーは **既定で読み取り専用**。

| キー（ワイルドカード表記） | SET | 設定値の例 | 備考 |
|---|:--:|---|---|
| `currentghost.shelllist(<name-or-path>).menu` | ✓ | `hidden` / 空文字 | オーナードローメニューからの非表示/表示切り替え |
| `currentghost.seriko.cursor.scope(ID).mouse????list(<hit>).path` | ✓ | `頭.cur` / 空文字 | `mouseuplist/mousedownlist/mousehoverlist/mousewheellist` のいずれか。空で定義削除 |
| `currentghost.seriko.cursor.scope(ID).mouse????list.index(ID2).path` | ✓ | `xxx.cur` | 上記の index 指定版 |
| `currentghost.seriko.tooltip.scope(ID).textlist(<hit>).text` | ✓ | 任意文字列 / 空文字 | ツールチップ文字列。空で定義削除 |
| `currentghost.seriko.tooltip.scope(ID).textlist.index(ID2).text` | ✓ | 任意文字列 | index 指定版 |

> 実装では **存在しないキーへの SET** を無視（もしくは警告ログ）し、副作用を発生させないこと。

---

## 6. セキュリティとサンドボックス
- **外部入力（SSTP/HEADLINE/PLUGIN/SHIORI）由来の SET** はレベル分離し、必要に応じ**無視**する。  
- 値にパスを含む場合は **ベースウェア管理下のセーフパス**に制限。

## 7. 互換性と差分
- Windows 固有の `system.os.*` の具体値は macOS 相当へ置換。  
- 座標系は**左上原点**で返す（macOS 内部から変換）。  
- 返却の文字コードは UTF‑8 固定。

---

## 付録A: Rosetta 検出サンプル（Swift/C）
**Swift**（`sysctl.proc_translated` を利用）:
```swift
import Foundation

public func isRunningUnderRosetta() -> Bool {
    var flag: Int32 = 0
    var size = MemoryLayout<Int32>.size
    let rc = sysctlbyname("sysctl.proc_translated", &flag, &size, nil, 0)
    return rc == 0 && flag == 1
}
```
**C**
```c
#include <stdbool.h>
#include <sys/sysctl.h>

bool ourin_is_rosetta(void) {
    int flag = 0;
    size_t size = sizeof(flag);
    if (sysctlbyname("sysctl.proc_translated", &flag, &size, NULL, 0) != 0) return false;
    return flag == 1;
}
```

## 付録B: 実装ヒント（CPU/Memory/OS 情報）
- OS 名（`name`）: `ProcessInfo.processInfo.operatingSystemVersion` → `"macOS X.Y[.Z]"` を合成。  
- Darwin 版（`version`）: `sysctlbyname("kern.osrelease", ...)`。  
- ビルド（`build`）: `sysctlbyname("kern.osversion", ...)`。  
- CPU：`hw.ncpu`, `machdep.cpu.brand_string`, `machdep.cpu.features`, `hw.cpufrequency`。  
- Memory：`hw.memsize`。`vm_stat` or `host_statistics` を参照し `phya` を推算（例：`free + inactive` ページ）。

## 付録C: 参考情報
- プロパティ語彙・SET 可否の例（UKADOC）  
  - `currentghost.shelllist(...).menu` の SET 例  
  - `currentghost.seriko.cursor... .path` / `... .text` は [SET有効]  
- 座標系・Retina  
  - Cocoa の既定は左下原点、`NSEvent.mouseLocation` は**スクリーン座標**  
  - `NSWindow.setFrameTopLeftPoint`、`NSView.viewDidChangeBackingProperties()`、`backingScaleFactor`
