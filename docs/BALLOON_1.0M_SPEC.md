# BALLOON/1.0M — Ourin（macOS）バルーン仕様（Draft）
**Status:** Draft / macOS 10.15+ / Universal 2（arm64・x86_64）  
**Updated:** 2025-07-27 (JST)  
**互換方針:** UKADOC「バルーン設定」および周辺仕様（descript.txt / balloons*s.txt 等）の**語彙・挙動互換**を維持しつつ、ウィンドウ/描画/入力を **macOS ネイティブ API** へ置換。  
**非目標:** Windows 固有の UI・レジストリ・GDI 準拠の再現（語彙・挙動互換に限定）。

---

## 目次
- [1. 対象と範囲](#1-対象と範囲)
- [2. ファイル構成と文字コード](#2-ファイル構成と文字コード)
- [3. 画像形式・透過（SSP互換）](#3-画像形式透過ssp互換)
- [4. レンダリング（Retina/多画面）](#4-レンダリングretina多画面)
- [5. ウィンドウ特性（前面/非アクティブ/ヒットテスト）](#5-ウィンドウ特性前面非アクティブヒットテスト)
- [6. テキスト描画と装飾](#6-テキスト描画と装飾)
- [7. 入力ボックス・付随アセット](#7-入力ボックス付随アセット)
- [8. 互換オプション（Windows→mac 置換）](#8-互換オプションwindowsmac-置換)
- [9. エラーハンドリング](#9-エラーハンドリング)
- [10. 適合チェックリスト](#10-適合チェックリスト)
- [付録A. 主なキー対応（差分メモ）](#付録a-主なキー対応差分メモ)
- [付録B. 画像読込パイプライン](#付録b-画像読込パイプライン)

---

## 1. 対象と範囲
- `descript.txt` の既定＋ `balloons*s.txt/balloonk*s.txt/balloonc*s.txt` による上書きを**同等解釈**する。  
- `arrow*.png` / `online*.png` / `sstp.png` 等、**アセット名の意味**を継承。

## 2. ファイル構成と文字コード
- **UTF‑8 を標準**。`descript.txt` 等の `charset,Shift_JIS` 指定があれば **CP932 として受理**。  
- 配置はベースウェアのバルーン格納フォルダ配下（UKADOC と同様）。

## 3. 画像形式・透過（SSP互換）
- **読込対応フォーマット（互換）**：**BMP / PNG / JPEG / GIF / MAG / XBM / PI / ICO / CUR**。  
  - 既定は **Image I/O**（PNG/JPEG/GIF/BMP など一般形式）。
  - **ICO/CUR** は内蔵パーサ（本配布の最小実装参照）。
  - **MAG / PI / XBM** は **拡張デコーダ SPI** を通じて段階的に提供。  
- **32bit PNG（RGBA）による透過表示**をサポート（アルファ合成）。
- **PNA**（別ファイルアルファ）にも互換対応。

## 4. レンダリング（Retina/多画面）
- 記述座標は**論理px**。描画時に **backingScaleFactor** に応じて解像度を選択し、**高DPIでも見え方を一致**させる。  
- 画面移動やスケール変更時は `viewDidChangeBackingProperties` をフックし、画像/フォントスケールを再計算。

## 5. ウィンドウ特性（前面/非アクティブ/ヒットテスト）
- **NSPanel（nonactivating）** を基本に、**フォーカスを奪わず**前面表示（`.floating` 等の適切なレベル）。  
- クリック透過は `NSView.hitTest(_:)` をオーバーライドして**透明画素のみ背面へ通す**（全体透過は `ignoresMouseEvents=true` も可）。

## 6. テキスト描画と装飾
- フォント解決は **NSFont/CTFont**。未インストール時は代替フォント。  
- 太字/斜体/下線/打消し線/影/アウトラインは **NSAttributedString** 属性で表現。  
- 折返しは **byCharWrapping** を既定。必要に応じ Core Text で禁則・ルビ等を拡張。

## 7. 入力ボックス・付随アセット
- `communicatebox.*` は **NSTextView 相当**で再現（半透明は `use_input_alpha`）。  
- `arrow*.png` / `online*.png` / `sstp.png` / `marker.png` 等の意味・優先度を継承。

## 8. 互換オプション（Windows→mac 置換）
- `cursor.style` は矩形/下線を描画して再現。  
- `wordwrappoint.x` は Core Text のレイアウト幅に反映。  
- 推奨ゴースト（`recommended.*`）は UI に警告表示。

## 9. エラーハンドリング
- 未知キーはログ警告の上、**既定値で継続**。  
- フォント未設置・画像読込失敗は UI 通知＋代替を適用。  
- スケール変更時は**即時リレイアウト**しフリンジを抑制。

## 10. 適合チェックリスト
- [ ] `descript.txt` と `balloons*s.txt` の**上書き規則**を実装。  
- [ ] **UTF‑8 標準／CP932 受理**。  
- [ ] **PNG/JPEG/GIF/BMP** 読込（Image I/O）。  
- [ ] **ICO/CUR** 読込（内蔵パーサ）。  
- [ ] **MAG/XBM/PI** は SPI で拡張可能。  
- [ ] **32bit PNG アルファ**で正しく透過。  
- [ ] **Retina/多画面**で等価表示。  
- [ ] **非アクティブ前面**＋**透明ヒットテスト**。

---

## 付録A. 主なキー対応（差分メモ）
- `font.*`、`validrect.*`、`origin.*`、`windowposition.*`、`use_self_alpha`、`use_input_alpha`、`paint_transparent_region_black`、`overlay_outside_balloon`、`communicatebox.*`、`arrow/online/sstp/marker` … **UKADOC の語彙をそのままサポート**。

## 付録B. 画像読込パイプライン
```
Data -> (UTI推定) -> Image I/O (PNG/JPEG/GIF/BMP) 
                  -> ICO/CUR 内蔵パーサ (PNGペイロード or 32bpp BMP→RGBA)
                  -> MAG/PI/XBM: Ourin Decoder SPI（拡張）
```

---

### 参考（実装者向け補足）
- ICO/CUR は **ICONDIR + ICONDIRENTRY** が先頭にあり、各エントリは **PNG か DIB(BMP)** を含む。CUR は **hotspot(x,y)** を ICONDIRENTRY の planes/bitcount フィールド位置に持つ。32bpp BMP は BGRA を α付きとして扱い、αが全ゼロなら AND マスクで補う。  
- Retina 対応は `backingScaleFactor` と `viewDidChangeBackingProperties()` を利用。  
- 非アクティブ前面は **nonactivatingPanel**、クリック透過は **hitTest** 制御。
