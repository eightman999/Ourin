# Ourin ドキュメント（HTML版）

このディレクトリには、Ourin（桜鈴）の全ドキュメントの HTML 版が含まれています。

## 閲覧方法

1. **索引ページから閲覧**: [index.html](index.html) を開いて、カテゴリ別に整理されたドキュメント一覧から選択
2. **直接閲覧**: 各 HTML ファイルを直接開く

## ドキュメントについて

- **言語**: 第一言語は日本語です
- **内容**: マークダウン版（`../` ディレクトリ）と同じ内容です
- **実装状況**: 各仕様書には「実装状況（Implementation Status）」セクションが追加され、現在の実装の有無や状況が記載されています
- **更新日**: 2025-10-20

## 主要ドキュメント

### コア仕様書（完全実装・部分実装）
- [SHIORI/3.0M 仕様](SHIORI_3.0M_SPEC.html) - YAYA バックエンドで実装済み
- [SSTP/1.xM 仕様](SSTP_1.xM_SPEC.html) - TCP/HTTP/XPC サーバ実装済み
- [PLUGIN/2.0M 仕様](SPEC_PLUGIN_2.0M.html) - ロード機構は実装済み
- [NAR INSTALL/1.0M 仕様](NAR_INSTALL_1.0M_SPEC.html) - 基本機能実装済み

### システム実装（完全実装）
- [FMO について](About_FMO.html) - POSIX 共有メモリで完全実装
- [YAYA Adapter 仕様](OURIN_YAYA_ADAPTER_SPEC_1.0M.html) - 完全実装済み
- [USL 仕様](OURIN_USL_1.0M_SPEC.html) - 実装済み

### イベントシステム（部分実装）
- [SHIORI Events 3.0M](OURIN_SHIORI_EVENTS_3.0M_SPEC.html) - 主要イベント実装済み
- [Plugin Event 2.0M](PLUGIN_EVENT_2.0M_SPEC.html) - 基盤実装済み

## 実装状況の凡例

各ドキュメントの実装状況セクションでは、以下の記号を使用しています：

- `[x]` - 実装済み
- `[ ]` - 未実装
- `✅` - 動作確認済み

## 生成について

これらの HTML ファイルは、マークダウン版から Python の markdown パッケージを使用して自動生成されています。

変換に使用したスタイルは、日本語フォントとコードブロックの読みやすさを重視して設計されています。

## ライセンス

Ourin プロジェクトのライセンスに従います（CC BY-NC-SA 4.0）。
