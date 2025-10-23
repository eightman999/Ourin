
# SHIORI Events — **3.0M / 2.0M 互換（macOS）** 仕様書
**Status:** Draft / macOS 10.15+ / Universal 2（arm64・x86_64）  
**Updated:** 2025-07-27 (JST)  
**互換方針:** UKADOC の **SHIORI イベント語彙（3.0/3.1拡張）**を踏襲し、OS 依存の値・通知だけを **macOS ネイティブ API** へ置換。  
**文字コード:** 入出力とも UTF‑8 を標準。互換のため **CP932（SJIS）受理 → 内部で UTF‑8 正規化**。  
**改行:** `LF` 推奨（`CRLF` 受理）。

---

## 目次
- [1. 目的と範囲](#1-目的と範囲)
- [2. 基本ポリシー（互換/座標/UTType/時刻）](#2-基本ポリシー互換座標uttype時刻)
- [3. イベント分類](#3-イベント分類)
- [4. イベント別マッピング表（抜粋）](#4-イベント別マッピング表抜粋)
  - [4.1 ライフサイクル](#41-ライフサイクル)
  - [4.2 入力（キーボード/マウス）](#42-入力キーボードマウス)
  - [4.3 ドラッグ＆ドロップ](#43-ドラッグドロップ)
  - [4.4 表示/ウィンドウ/デスクトップ](#44-表示ウィンドウデスクトップ)
  - [4.5 電源/バッテリー/サーマル](#45-電源バッテリーサーマル)
  - [4.6 ロケール/外観/言語](#46-ロケール外観言語)
  - [4.7 Web/URL 連携](#47-weburl-連携)
- [5. 追加定義（**M‑Add**）](#5-追加定義madd)
- [6. パラメータ規定](#6-パラメータ規定)
- [7. サンドボックス/セキュリティ](#7-サンドボックスセキュリティ)
- [8. 互換性の注意と非対応](#8-互換性の注意と非対応)
- [9. 仕様例（リクエスト/レスポンス）](#9-仕様例リクエストレスポンス)
- [付録A: 代表 API 対応表](#付録a-代表-api-対応表)
- [付録B: テスト観点チェックリスト](#付録b-テスト観点チェックリスト)

---

## 1. 目的と範囲
- 本仕様は、Ourin（ベースウェア, macOS）で **SHIORI イベント**を発火・配送するための**対応表と動作要件**を定義する。  
- SSP/UKADOC のイベント名・意味は**語彙互換**で維持し、Windows 固有値は **macOS の等価データ**へ置換または省略（未定義）。

## 2. 基本ポリシー（互換/座標/UTType/時刻）
- **互換**：既存イベント名・解釈は UKADOC に従う。  
- **座標系**：イベントで渡すスクリーン座標は **AppKit 既定＝左下原点（pt）**。必要に応じて **トップ左基準の補助値**（`TopLeftX/Y`）を M‑Add で併送可。  
- **UTType**：ドラッグ＆ドロップやクリップボードは **NSPasteboard/UTType** を基準とする（`public.plain-text`/`public.url`/`public.file-url` 等）。  
- **時刻**：ローカル時刻を返却。ミリ秒は `Date` + `mach_absolute_time` などで補完可。

## 3. イベント分類
- **ライフサイクル**（起動/終了/切替）  
- **入力**（キーボード/マウス/ホイール）  
- **ドラッグ＆ドロップ**（テキスト/URL/ファイル）  
- **表示/ウィンドウ/デスクトップ**（画面変更/Spaces/スケール）  
- **電源/バッテリー/サーマル**  
- **ロケール/外観（テーマ）/言語**  
- **Web/URL**（x‑ukagaka‑link 等）

---

## 4. イベント別マッピング表（抜粋）

### 4.1 ライフサイクル
| SHIORI Event | macOS トリガ | 備考 |
|---|---|---|
| `OnBoot` | アプリ起動 | Ourin 起動直後 |
| `OnClose` | 終了（Terminate） | 終了前 |
| `OnGhostChanged` | ゴースト切替 | 既存語彙準拠 |
| `OnIdle`/`OnMinuteChange` | タイマー | 既存間隔通り |

### 4.2 入力（キーボード/マウス）
| Event | トリガ | パラメータ例 |
|---|---|---|
| `OnKeyDown`/`OnKeyUp`/`OnKeyPress` | `NSEvent`（key） | `keyCode`（US 仮想キー）, `characters`, `modifierFlags` |
| `OnMouseDown`/`OnMouseUp`/`OnMouseMove`/`OnMouseWheel` | `NSEvent`（mouse/scroll） | `screenX/Y`（左下原点）, `button`, `delta` |

### 4.3 ドラッグ＆ドロップ
| Event | トリガ | パラメータ |
|---|---|---|
| `OnTextDrop` | `NSDraggingDestination` + `UTType.plainText` | `Value` = テキスト |
| `OnURLDrop` | `NSPasteboard.PasteboardType.url`/`UTType.url` | `Value` = URL 文字列 |
| `OnFileDrop` | `public.file-url` | `ValueN` = ファイル URL 群（セキュリティスコープ考慮） |

### 4.4 表示/ウィンドウ/デスクトップ
| Event | トリガ | 備考 |
|---|---|---|
| `OnDisplayChange` | `NSApplication.didChangeScreenParametersNotification`/CGDisplay | 解像度/構成変更 |
| `OnResetWindowPos` | 内部 | TopLeft 補助可（M‑Add） |
| `OnDpiChanged` 相当 | `backingScaleFactor` 変化 | 画面またぎ移動時 |

### 4.5 電源/バッテリー/サーマル
| Event | トリガ | 備考 |
|---|---|---|
| `OnPowerSourceChanged` | IOKit Power Sources | AC/バッテリー |
| `OnBatteryLevel` 系 | 同上（定期照会と併用） | しきい値で発火 |
| **`OnThermalStateChanged` (M‑Add)** | `NSProcessInfo.thermalStateDidChangeNotification` | 低/中/高/重大 |

### 4.6 ロケール/外観/言語
| Event | トリガ | 備考 |
|---|---|---|
| `OnLocaleChange` | `NSLocale.currentLocaleDidChangeNotification` | 地域/表記設定 |
| **`OnAppearanceChanged` (M‑Add)** | `NSApp.effectiveAppearance` 監視 | Light/Dark |
| `OnInputSourceChanged`（任意） | TIS Input Source 監視 | 実装任意 |

### 4.7 Web/URL 連携
| Event | トリガ | 備考 |
|---|---|---|
| `OnXUkagakaLinkOpen` 等 | URL スキーム受理 | 既存語彙準拠 |

---

## 5. 追加定義（**M‑Add**）
- **`OnSpaceChanged`**：`NSWorkspace.activeSpaceDidChangeNotification` により Spaces 切替を通知。  
- **`OnAppearanceChanged`**：ダーク/ライト切替を通知。`Appearance=light|dark|highcontrast` 等のパラメータを返す。  
- **`OnThermalStateChanged`**：`State=nominal|fair|serious|critical`。

---

## 6. パラメータ規定
- **座標**：`screenX,screenY` は **左下原点の pt**。補助として `topLeftX,topLeftY` を併送可。  
- **修飾キー**：`Command|Option|Shift|Control|CapsLock|Function` などのビット名。  
- **UTType**：`public.plain-text`/`public.url`/`public.file-url` を基本。拡張は UTType 階層の同等性で判定。  
- **Encoding**：返却は UTF‑8 固定。

---

## 7. サンドボックス/セキュリティ
- **ファイル D&D**：App Sandbox 環境では **security‑scoped URL** を開始/終了で管理。  
- **外部由来イベント**（SSTP/URL スキーム）からのパス入力は**制限パス**にサニタイズ。

## 8. 互換性の注意と非対応
- Windows 固有の語彙（`HWND` 等）は**未定義**。  
- スクリーンセーバ **Start/End** は macOS 公開 API が無いため、**ディスプレイスリープ/復帰**で近似（任意有効化）。

## 9. 仕様例（リクエスト/レスポンス）
```
# OnURLDrop の例（単一）
GET SHIORI/3.0
ID: OnURLDrop
Sender: Ourin
Reference0: https://example.org/
SecurityLevel: external

###

SHIORI/3.0 200 OK
Value: \0\s[0]URLを受け取りました：%reference[0]\e
```

---

## 付録A: 代表 API 対応表
- Spaces 変更 → `NSWorkspace.activeSpaceDidChangeNotification`  
- 画面構成変更 → `NSApplication.didChangeScreenParametersNotification` / CGDisplay Reconfig  
- キー/修飾 → `NSEvent.keyCode` / `NSEvent.ModifierFlags`  
- D&D 種別 → `NSPasteboard.PasteboardType.url` / `public.plain-text` / `public.file-url`  
- Power/Battery → IOKit Power Sources（通知＋照会）  
- 外観 → `NSApplication.effectiveAppearance`

## 付録B: テスト観点チェックリスト
- [ ] URL/ファイル/テキスト D&D の判定と文字コード  
- [ ] 複数ディスプレイ/スケール変更の座標・DPI 追随  
- [ ] Sleep/Wake・AC/バッテリー切替・サーマル状態  
- [ ] ロケール変更・テーマ切替  
- [ ] セキュリティ（Sandbox の security‑scoped URL、外部入力の検証）
