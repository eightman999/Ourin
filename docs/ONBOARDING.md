# Ourin Onboarding Guide

## 1. プロジェクト概要
- **Ourin (桜鈴)** は、macOS ネイティブの ukagaka ベースウェアであり、SHIORI や SSTP などの既存規格と互換性を持つデスクトップキャラクター基盤です。【F:CLAUDE.md†L7-L8】
- リポジトリには Xcode プロジェクトと Swift/C++ で実装された多数のサブシステムが含まれ、既存の ukagaka エコシステムと連携します。【F:CLAUDE.md†L60-L80】

## 2. リポジトリ構成の俯瞰
- `Ourin/`: macOS アプリ本体。SwiftUI ベースの UI と、FMO・SHIORI・プラグインなど主要機能モジュールを含みます。【F:CLAUDE.md†L60-L72】
- `OurinTests/`: Swift 製ユニットテスト群。`xcodebuild` の `test` ターゲットで実行されます。【F:CLAUDE.md†L60-L72】
- `docs/`: SHIORI/SSTP/PLUGIN 仕様や実装ガイドを収録したドキュメント集。新機能の設計時には参照が推奨されます。【F:CLAUDE.md†L73-L79】
- `Samples/`: リファレンス実装・モックアップ等の補助資料。探索してベストプラクティスを把握してください。【F:CLAUDE.md†L67-L72】
- `yaya_core/`: YAYA 互換の C++ ランタイム。Swift プラグインとの連携は `docs/connect_swift.md` を参照します。【F:docs/connect_swift.md†L1-L134】

## 3. アプリ起動時に動作する主要サブシステム
`OurinApp.swift` の `AppDelegate.applicationDidFinishLaunching` では、下記のようにサブシステム初期化が段階的に進みます。【F:Ourin/OurinApp.swift†L30-L172】

1. **FMO 初期化**: `FmoManager` を生成し、既に別プロセスが動作していないか確認します。【F:Ourin/OurinApp.swift†L46-L55】
2. **Web ハンドラ登録**: `x-ukagaka-link` スキームを Swift 側で処理できるようにします。【F:Ourin/OurinApp.swift†L57-L58】
3. **プラグイン検出**: `PluginRegistry` が `.plugin` / `.bundle` を探索・ロードし、メタ情報を解析します。【F:Ourin/OurinApp.swift†L60-L66】【F:Ourin/PluginHost/PluginRegistry.swift†L12-L95】
4. **HEADLINE モジュール読込**: ニュースティッカー等の Headline API プラグインを登録します。【F:Ourin/OurinApp.swift†L67-L70】
5. **SHIORI イベントブリッジ起動**: `EventBridge` がシステムイベントを SHIORI/SSTP へ転送します。【F:Ourin/OurinApp.swift†L72-L75】
6. **外部 SSTP サーバ**: `OurinExternalServer` が TCP/HTTP/XPC の受け口を開き、外部クライアントとの通信を受け付けます。【F:Ourin/OurinApp.swift†L77-L80】【F:CLAUDE.md†L39-L43】
7. **プラグインイベントディスパッチャ**: ロード済みプラグインへイベント配送を開始します。【F:Ourin/OurinApp.swift†L60-L66】
8. **ゴースト選択と起動**: ユーザー設定または同梱の `emily4.nar` を `NarInstaller` で展開し、`GhostManager` がゴーストの UI を描画します。【F:Ourin/OurinApp.swift†L82-L172】【F:Ourin/Ghost/GhostManager.swift†L19-L200】

## 4. サブシステム別の理解ポイント
- **FMO (Forged Memory Object)**: POSIX 共有メモリと名前付きセマフォで 64KB の共有領域を提供し、単一インスタンス制御や他プロセスとの通信に利用します。`FmoManager` が `FmoMutex` / `FmoSharedMemory` を統合します。【F:docs/About_FMO.md†L1-L28】
- **ゴースト実行環境**: `GhostManager` が YAYA 辞書の読み込み、SakuraScript 実行、ウィンドウ描画を担当します。Surface/Scope 切り替えやバルーン文字列更新もここで行われます。【F:Ourin/Ghost/GhostManager.swift†L19-L200】
- **NAR パッケージ管理**: `NarRegistry` と `NarInstaller` が `ghost/`・`balloon/` 等のディレクトリを走査し、ユーザーが導入したパッケージを列挙・展開します。【F:Ourin/Nar/NarRegistry.swift†L3-L68】【F:Ourin/OurinApp.swift†L141-L172】
- **プラグイン連携**: `PluginRegistry` が `descript.txt` のメタデータを Shift_JIS/UTF-8 を自動判別しつつ解析し、ロード済みプラグインへイベントを送出します。Swift でプラグインを実装する場合は C ABI でのエクスポートやメモリ管理指針に留意してください。【F:Ourin/PluginHost/PluginRegistry.swift†L12-L95】【F:docs/connect_swift.md†L5-L134】
- **外部通信**: `OurinExternalServer` 以下のサーバ群が SSTP や XPC を通じて他アプリ・外部ゴーストと連携します。イベントブリッジやプラグインディスパッチャと組み合わせて、Ourin 外部との相互運用を実現します。【F:CLAUDE.md†L39-L48】

## 5. ビルド・テスト・デバッグ
- 開発は Xcode (macOS) を前提とし、`xcodebuild -project Ourin.xcodeproj -scheme Ourin build` でビルド、`xcodebuild -project Ourin.xcodeproj -scheme Ourin test` でテストを実行します。【F:CLAUDE.md†L9-L18】
- ローカル起動は Xcode から実行するか、`xcodebuild ... build && open build/Release/Ourin.app` のワンライナーを使用します。【F:CLAUDE.md†L13-L16】
- プラグイン連携の検証では、`docs/connect_swift.md` のテスト戦略（単体・結合・ロングラン）を参考にしてください。【F:docs/connect_swift.md†L126-L130】

## 6. 次に取り組むと良い学習ステップ
1. **仕様ドキュメントの熟読**: `docs/` 配下の SHIORI/SSTP/PLUGIN 仕様を読み、Ourin 固有拡張との違いを把握する。【F:CLAUDE.md†L73-L79】
2. **GhostManager の追跡**: `GhostManager` のフローを追い、YAYA 辞書読込から SakuraScript 表示までの処理を Xcode のブレークポイントで確認する。【F:Ourin/Ghost/GhostManager.swift†L52-L200】
3. **プラグイン試作**: `docs/connect_swift.md` を基に最小限の Swift プラグインを作成し、`PluginRegistry` によるロード挙動を観察する。【F:Ourin/PluginHost/PluginRegistry.swift†L19-L95】【F:docs/connect_swift.md†L5-L134】
4. **FMO デバッグ**: 共有メモリの初期化・解放シーケンスを `FmoManager` のコードと `docs/About_FMO.md` で復習し、マルチインスタンス検出ロジックを理解する。【F:Ourin/OurinApp.swift†L46-L55】【F:docs/About_FMO.md†L5-L28】

このガイドを出発点に、各モジュールの実装と周辺ドキュメントを行き来しながら理解を深めてください。新しい機能追加時は、既存のサブシステムとの連携や規格準拠を最優先で検討することを推奨します。
