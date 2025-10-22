# Ourin (桜鈴) ドキュメント索引

このディレクトリには、Ourin の全仕様書とドキュメントが含まれています。

## 📖 閲覧方法

- **マークダウン版**: このディレクトリの `.md` ファイルを直接閲覧
- **HTML版**: `html/` ディレクトリの HTML ファイルを閲覧（[索引ページ](html/index.html)から選択可能）

## 🎯 入門・概要

- [ONBOARDING.md](ONBOARDING.md) - Ourin の概要と始め方

## 📚 コア仕様書（macOS 差分版）

これらの仕様書には、現在の実装状況が追記されています。

### SHIORI システム
- [SHIORI/3.0M 仕様](SHIORI_3.0M_SPEC.md) 🟡 **部分実装** - SHIORI プロトコルの macOS ネイティブ実装仕様
  - YAYA バックエンドで実装済み
  - C ABI での Bundle/Plugin ロードは未実装

### SSTP プロトコル
- [SSTP/1.xM 仕様](SSTP_1.xM_SPEC.md) 🟢 **実装済み** - SSTP プロトコルの macOS 差分仕様
  - TCP/HTTP/XPC サーバ実装済み
  - 基本的な SEND/NOTIFY/COMMUNICATE/EXECUTE メソッド対応

### プラグインシステム
- [PLUGIN/2.0M 仕様](SPEC_PLUGIN_2.0M.md) 🟡 **部分実装** - プラグインシステムの macOS 差分仕様
  - プラグイン検出とロード機構は実装済み
  - 完全な PLUGIN/2.0M プロトコルは未実装

### NAR インストール
- [NAR INSTALL/1.0M 仕様](NAR_INSTALL_1.0M_SPEC.md) 🟢 **実装済み** - NAR パッケージインストールの仕様
  - ダブルクリック/D&D インストール対応
  - 基本的な展開とエラー処理実装済み

## ⚙️ システム実装仕様

### FMO（共有メモリ）
- [FMO について](About_FMO.md) 🟢 **完全実装** - プロセス間共有メモリの実装
  - POSIX 共有メモリとセマフォで完全実装
  - ninix 仕様準拠の起動判定

### YAYA システム
- [YAYA Adapter 仕様 1.0M](OURIN_YAYA_ADAPTER_SPEC_1.0M.md) 🟢 **完全実装** - YAYA ゴーストの実行アダプタ
  - ヘルパープロセスとの IPC 実装済み
  - `yaya.txt` および `.dic` ファイルの解析対応
  - SHIORI/3.0M ブリッジ実装済み

### USL（ローダー）
- [USL 仕様 1.0M](OURIN_USL_1.0M_SPEC.md) 🟢 **実装済み** - Universal SHIORI Loader
  - YAYA バックエンド選択機構実装済み

### イベントシステム
- [SHIORI Events 3.0M 仕様](OURIN_SHIORI_EVENTS_3.0M_SPEC.md) 🟡 **部分実装** - システムイベントと SHIORI の連携
  - 主要イベント（時間、OS 状態、ネットワーク、入力、D&D）実装済み
  - 一部イベント（ヘッドライン、メール BIFF、音声認識など）未実装

- [Plugin Event 2.0M 仕様](PLUGIN_EVENT_2.0M_SPEC.md) 🟡 **部分実装** - プラグインイベントシステム
  - 基盤となるディスパッチャ実装済み
  - 個別イベントハンドラは未実装

## 🎨 表示・UI 仕様

- [BALLOON/1.0M 仕様](BALLOON_1.0M_SPEC.md) - バルーン（吹き出し）システムの仕様
- [SakuraScript 完全仕様 1.0M](SAKURASCRIPT_FULL_1.0M_PATCHED.md) - SakuraScript の完全なコマンドリファレンス
- [SakuraScript 対応コマンド一覧](SAKURASCRIPT_COMMANDS_SUPPORTED.md) - 実装済み・未実装のコマンド一覧

## 🔧 開発者向け資料

- [DevTools UI モックアップ（日本語版）](DevToolsUIMockup_JA.md) - 開発者ツール UI の設計案
- [DevTools UI モックアップ（英語版）](DevToolsUIMockup.md) - Developer Tools UI mockup
- [Swift 連携ガイド](connect_swift.md) - Swift との連携方法
- [Property System 実装](PropertySystem.md) - プロパティシステムの実装詳細
- [Ghost Configuration Implementation](GhostConfigurationImplementation.md) - ゴースト設定の実装

## 📖 詳細仕様

### SHIORI 関連
- [SHIORI Events 3.0M 仕様](SHIORI_EVENTS_3.0M_SPEC.md) - SHIORI イベントの詳細仕様
- [SHIORI Events FULL 1.0M](SHIORI_EVENTS_FULL_1.0M_PATCHED.md) - SHIORI イベントの完全版
- [SHIORI Resource 3.0M 仕様](SHIORI_RESOURCE_3.0M_SPEC.md) - SHIORI リソース管理の仕様
- [SHIORI External 3.0M 仕様](SHIORI_EXTERNAL_3.0M_SPEC.md) - 外部 SHIORI 連携の仕様

### プロパティシステム
- [PROPERTY/1.0M 仕様](PROPERTY_1.0M_SPEC.md) - プロパティシステムの仕様
- [PROPERTY/1.0M 完全版](PROPERTY_1.0M_SPEC_FULL.md) - プロパティシステムの完全仕様
- [PROPERTY Resource 3.0M 仕様](PROPERTY_Resource_3.0M_SPEC.md) - プロパティリソースの仕様

### プラグイン
- [Plugin Event 2.0M 完全版](PLUGIN_EVENT_2.0M_SPEC_FULL.md) - プラグインイベントの完全仕様

### その他のシステム
- [HEADLINE/2.0M 仕様](HEADLINE_2.0M_SPEC.md) - ヘッドラインシステムの仕様
- [WEB/1.0M 仕様](WEB_1.0M_SPEC.md) - Web 機能の仕様
- [SSTP ホストモジュール（日本語）](SSTP_Host_Modules_JA.md) - SSTP ホストモジュールの説明

## 📖 YAYA Core ドキュメント

YAYA Core は別リポジトリで開発されていますが、参考資料がこのディレクトリに含まれています。

- [YAYA Core エグゼクティブサマリー](YAYA_CORE_EXECUTIVE_SUMMARY.md) - YAYA Core の概要と方針
- [YAYA Core 技術仕様](YAYA_CORE_TECHNICAL_SPEC.md) - YAYA Core の技術詳細
- [YAYA Core アーキテクチャ](YAYA_CORE_ARCHITECTURE.md) - YAYA Core の設計とアーキテクチャ
- [YAYA Core 実装計画](YAYA_CORE_IMPLEMENTATION_PLAN.md) - YAYA Core の実装計画
- [YAYA Core 調査報告](YAYA_CORE_INVESTIGATION_REPORT.md) - YAYA Core の調査報告
- [YAYA Core インデックス](YAYA_CORE_INDEX.md) - YAYA Core ドキュメントの索引

## 📋 UI モックアップ

- [Right Click Menu モックアップ](RightClickMenuMockup.md) - 右クリックメニューの設計案

## 🎨 実装状況の凡例

仕様書内の実装状況セクションでは、以下の記号を使用しています：

- 🟢 **完全実装** - 機能が完全に実装され、動作確認済み
- 🟡 **部分実装** - 基本機能は実装済みだが、一部機能が未実装
- 🔵 **計画中** - 仕様は確定しているが未実装
- `[x]` - 実装済み
- `[ ]` - 未実装
- `✅` - 動作確認済み

## 📝 ドキュメント更新履歴

- **2025-10-20**: 実装状況セクションを各仕様書に追加、HTML 版を生成
- **2025-07-28**: 初版ドキュメント作成

## 🔗 関連リンク

- [GitHub リポジトリ](https://github.com/eightman999/Ourin)
- [プロジェクト README](../README.md)
- [HTML 版ドキュメント索引](html/index.html)

## 📄 ライセンス

ドキュメントは Ourin プロジェクトのライセンスに従います（CC BY-NC-SA 4.0）。
