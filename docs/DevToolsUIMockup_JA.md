# Ourin DevTools — 設定 & テスト & デバッグ UI モック（macOS）

**更新日:** 2025-07-27 (JST)
**対象:** macOS 10.15+ / Universal 2

## 目次
0. 画面マップ（ワイヤーフレーム）
1. 共通UI規約
2. ペイン別モック
   2.1 General（基本設定）
   2.2 SHIORI Resource Viewer/Overlay
   2.3 Plugin Manager / Event Injector
   2.4 External Events（SSTP/HTTP/XPC）Harness
   2.5 Headline / Balloon テスト
   2.6 Logging & Diagnostics
   2.7 Network & Listener 状態
3. テストシナリオ（プリセット）
4. アクセシビリティ/国際化
5. 収集ログとエクスポート
6. 既知の課題と未決事項

## 0. 画面マップ（ワイヤーフレーム）
```
┌──────────────────────────────────────────────────────────────┐
│  Ourin DevTools                                      [Search]│
│  ─────────────────────────────────────────────────────────── │
│  ▸ General                                                  ││
│  ▸ SHIORI Resource                                          ││
│  ▸ Plugins & Events                                         ││  ← サイドバー（source list）
│  ▸ External (SSTP/HTTP/XPC)                                 ││     セクション見出し＋項目
│  ▸ Headline / Balloon                                       ││
│  ▸ Logging & Diagnostics                                    ││
│  ▸ Network                                                  ││
│                                                              │
│  ─────────────────────────────────────────────────────────── │
│  [Toolbar:  ⟳ Reload   ▶ Run Test   ⏹ Stop   ⎘ Export  ]    │  ← 右ペイン ツールバー
│  ─────────────────────────────────────────────────────────── │
│  [Detail View / Form / Table / Live Preview / Log Console]  │
└──────────────────────────────────────────────────────────────┘
```
サイドバーは主要領域の一貫したナビゲーションに適し、検索やセクション分割と相性が良い。
メニューバーから「表示 > サイドバーを表示/非表示」を提供して、HIG に沿ったレイアウトを実現する。
横並びのコントロールは 2〜3 個までなど、macOS 標準の密度ガイドラインを踏襲する。

## 1. 共通UI規約
- 検索欄は各ペインのリストやテーブルにフィルタを適用する。
- ツールバーは Reload / Run Test / Stop / Export の少数ボタンに絞る。
- 状態バッジを右上に表示し、Success / Warning / Error をアイコンと短いツールチップで示す。
- ショートカット: **⌘R**（実行）、**⌘S**（保存/エクスポート）、**⌘F**（検索）。
- UI 操作は `Logger` (subsystem `jp.ourin.devtools`, category `ui`) に記録し、計測には `Signpost` を利用する。

## 2. ペイン別モック
### 2.1 General（基本設定）
目的: Ourin 全体の既定動作やパス、互換設定を編集する。
主なコントロール:
- 「データフォルダ」 […] (POSIX/file://)
- 文字コード既定 UTF‑8（CP932 受理トグル）
- Rosetta 検出・互換モード（読み取り専用表示）
- 自動起動・自動更新チェック
- 「保存」「既定に戻す」ボタン
バリデーションではパスの存在や書き込み権限を確認し、設定保存時に `Logger` (category:"settings") で info を記録する。

### 2.2 SHIORI Resource Viewer/Overlay
目的: Resource 値の閲覧（読み取り標準）と Ourin オーバーレイ（任意で上書き）の管理。
UI:
- 上部セグメント: All | SHIORI | Ghost | Menu | Colors | Update
- テーブル: Key / Value (read-only) / Overlay (Ourin) / Effective / Last Fetched
- 右側プレビュー: メニュー色やビットマップを表示し、ショートカット `&X` 解析結果も併記
操作:
- Reload（再取得）
- Overlay を適用（Ourin 優先）／Overlay をクリア
- 変更が UI に反映されたら Signpost `apply_resource_overlay` を記録

### 2.3 Plugin Manager / Event Injector
目的: プラグインの有効化・順序・イベント注入テストを行う。
UI:
- 左側: プラグイン一覧（Enabled、ID、Version、Path）
- 右側: Event Injector
    - Event ID（ドロップダウン）
    - ReferenceN（動的フォーム）
    - Sender、Charset
    - **▶ Send (GET)**、**⟲ Notify**、**⎘ Save as Preset**
ロギングでは送信前後で `Logger` (category:"plugin") に debug を残し、Signpost `inject_event` で所要時間を測定する。

### 2.4 External Events（SSTP/HTTP/XPC）Harness
目的: 外部イベント受信ルートの検証。
UI:
- SSTP (TCP/9801): Start/Stop / Bind: 127.0.0.1 / ステータス表示
- HTTP (POST /api/sstp/v1): Start/Stop / 受信件数・平均遅延
- XPC (machService: jp.ourin.sstp): Start / 接続中クライアント一覧
- ヘルプ表示: "SSTP の TCP サーバは Network.framework の NWListener で実装" などの注記をサブテキストに記載
ツール:
- Sample Request（NOTIFY/SEND ひな形をエディタへ）
- **Send（自己宛 SSTP）**／**Open curl（HTTP サンプル）**
- **Copy XPC Snippet**（接続クライアント用の最小コード例）

### 2.5 Headline / Balloon テスト
- Headline: URL/Path 設定、更新テスト（レスポンスを表形式で表示）
- Balloon: シェル/バルーン選択、PNG プレビュー（32bit 透過・影の有無）、スケール/DPI 確認、アンカーや選択肢レイアウトを可視化
情報量が多い画面ではサイドバーとセカンダリツールバーで段階的に表示する。

### 2.6 Logging & Diagnostics（OSLog/Signpost）
目的: 開発時の構造化ログと計測を統合表示する。
UI:
- クエリバー: Subsystem（既定 `jp.ourin.*`）／Category／Level（debug, info, error …）／Since
- テーブル: Time / Level / Category / Message / Metadata
- Signpost Timeline: 区間・インスタントを図示し凡例を表示
実装メモ: OSLogStore からログを取得し `Logger` で出力。期間内 Signpost は `OSSignposter` で記録し `OSLogEntrySignpost` を可視化する。

### 2.7 Network & Listener 状態
目的: SSTP/HTTP/XPC リスナーの稼働と統計を監視する。
- SSTP (TCP/9801): 接続数、受信/秒、エラー/秒
- HTTP (9810): 2xx/4xx/5xx、平均処理時間
- XPC: 接続アプリ ID、要求/秒
参考: Network.framework の利用は Apple 推奨 (ソケット代替)。技術選定ノート (TN3151) も併記。

## 3. テストシナリオ（プリセット）
- Ghost Boot → Menu Exec → Exit
- OnGhostBoot 注入 → Resource 再取得 → OnMenuExec → OnGhostExit
  - Signpost: `scenario_boot_menu_exit` を区間として記録
- External NOTIFY（SSTP）往復
  - NOTIFY SSTP/1.1 を 9801 自己宛送出 → 204 応答 → ログ整合性を確認
  - NWListener の接続/切断イベントを info レベルで記録
- HTTP 経由 SEND（返却スクリプト）
  - `/api/sstp/v1` に SEND を POST → 200 + Script を検証
- XPC 直送（DirectSSTP‑Mac）
  - 別プロセスから `deliverSSTP(Data)` → 200/204。接続拒否やサイズ過大時のハンドリングも確認

## 4. アクセシビリティ/国際化
- VoiceOver: テーブル列に適切なアクセシビリティラベルを付与
- キーボード: サイドバーと詳細を ⌘1/⌘2 などで切り替え
- ローカライズ: 英日ランタイム切替に対応し、長文時は行高を自動調整
- HIG 準拠: macOS 標準パターン (Sidebar/Toolbar/Menu) を活用し、ユーザーの期待通りに動作させる

## 5. 収集ログとエクスポート
`File > Export Diagnostics…` から OSLog 抽出 (期間/レベル/カテゴリ)、Signpost JSON、設定スナップショット、環境情報を ZIP 化して保存できる。
ログ実装は `Logger` に統一し、OSLog の subsystem/category で分類する。必要に応じてファイル出力層を追加する。

## 6. 既知の課題と未決事項
- 長大な Resource 列のページングや差分適用タイミング
- Signpost の運用 (カテゴリと命名規則): `ourin.resource.apply`, `ourin.plugin.inject`, `ourin.net.sstp` などに統一
- XPC の権限制御 (TeamID/コード署名の要件と UI への露出)
- Network 権限文言 (ローカルネットワーク使用理由の説明)

---
_最終更新: 2025-07-27_
