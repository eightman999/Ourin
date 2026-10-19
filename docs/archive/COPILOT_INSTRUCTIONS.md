# Ourin 実装プロジェクト - Copilot自律稼働指示書

## 📋 目的

**期間:** 1-2ヶ月集中実装
**目標:** macOSネイティブ最適化されたukagaka互換ベースウェアの完成

以下の4つの主要機能を実装・完成させる：
1. **SAORI/1.0完全実装** (最優先)
2. **SSTP Dispatcher完成**
3. **SERIKO/2.0完全実装**
4. **SakuraScript拡張と文書化**

---

## 🎯 作業方針

### 優先順位
1. **互換性最優先** - 既存ゴーストが動くことを第一に考える
2. **macOSネイティブ最適化** - dyld, Metal, GCD等を活用
3. **漸進的実装** - 基本的な機能から高度な機能へ
4. **テスト駆動開発** - 各機能実装後すぐにテスト
5. **ドキュメント同期** - 実装と同時にドキュメント更新

### 開発原則
- **変更前に必ずファイルを読む** - Readツールで現在の内容を確認
- **小さな変更を積み重ねる** - 一度に大きな変更をしない
- **ビルド後に必ずテスト** - xcodebuildでビルドしてからテスト
- **エラーはログに記録** - エラー内容をファイルに保存
- **進捗を可視化** - 各タスクの完了状況を明確にする

### ファイル変更ルール
1. 変更対象ファイルを`read`ツールで確認
2. `edit`ツールで必要な部分のみ修正（全体書き換えは避ける）
3. 新規ファイルのみ`write`ツールで作成
4. 修正後は必ずビルドして動作確認

---

## ✅ タスクリスト

### フェーズ1: SAORI完全実装 (3週間)

#### SAORI-1: ネイティブSAORIモジュールローダー実装 (1週間)
- [ ] SaoriLoader.swift作成
  - [ ] dyldによる.dylibロード実装
  - [ ] dlsymによる関数シンボル解決実装
  - [ ] エラーハンドリング実装
- [ ] SaoriProtocol.swift作成
  - [ ] SAORI/1.0リクエストパーサー実装
  - [ ] SAORI/1.0レスポンスビルダー実装
  - [ ] 文字コード変換実装
- [ ] SaoriRegistry.swift作成
  - [ ] モジュール検索パス管理実装
  - [ ] .saoriディレクトリ探索実装
  - [ ] モジュールキャッシュ管理実装
- [ ] SaoriManager.swift作成
  - [ ] 統合管理インターフェース実装
  - [ ] YAYAコアとのブリッジ準備
- [ ] SaoriHostディレクトリ作成とXcodeプロジェクトに追加
- [ ] 単体テスト作成と実行
- [ ] ビルド確認

#### SAORI-2: YAYA-SAORI統合 (1週間)
- [ ] yaya_core/src/VM.cppのLOADLIB/UNLOADLIB/REQUESTLIB実装
  - [ ] スタブ実装を実際の動作に置換え
  - [ ] pluginOperationコールバック呼び出し実装
- [ ] yaya_core/src/YayaCore.cppのpluginOperation()実装
  - [ ] "saori_load"処理実装
  - [ ] "saori_unload"処理実装
  - [ ] "saori_request"処理実装
  - [ ] YayaAdapterとの通信実装
- [ ] Ourin/Yaya/YayaAdapter.swift修正
  - [ ] handleSaoriRequest()メソッド追加
  - [ ] SaoriManagerとの連携実装
- [ ] yaya_coreビルド
- [ ] Ourin全体ビルド
- [ ] 統合テスト実行

#### SAORI-3: サンプルSAORIモジュール作成 (1週間)
- [ ] Samples/SimpleSaoriディレクトリ作成
- [ ] C++版SAORIサンプル実装 (SimpleSaori.cpp)
  - [ ] request()関数実装
  - [ ] load()関数実装
  - [ ] unload()関数実装
  - [ ] CMakeLists.txt作成
- [ ] Swift版SAORIサンプル実装
  - [ ] request()関数実装
  - [ ] load()関数実装
  - [ ] unload()関数実装
  - [ ] Package.swift作成
- [ ] サンプルビルドとテスト
- [ ] README.md作成

---

### フェーズ2: SSTP Dispatcher完成 (2週間)

#### SSTP-1: Dispatcher-SHIORI完全統合 (1週間)
- [ ] Ourin/SSTP/SSTPDispatcher.swiftのスタブ実装を完全なものに置換え
  - [ ] routeToShiori()メソッド実装
  - [ ] handleNotify()メソッド実装
  - [ ] handleCommunicate()メソッド実装
  - [ ] handleExecute()メソッド実装
  - [ ] handleGive()メソッド実装
  - [ ] handleInstall()メソッド実装
- [ ] SSTPメソッド→SHIORIイベントマッピング実装
- [ ] SHIORIレスポンス→SSTPレスポンス変換実装
- [ ] SecurityLevel/SenderTypeヘッダー伝播実装
- [ ] ビルド確認

#### SSTP-2: 完全なSSTPレスポンス生成 (1週間)
- [ ] Ourin/SSTP/SSTPResponse.swift作成/拡張
  - [ ] toWireFormat()メソッド実装
  - [ ] すべてのステータスコード実装
  - [ ] ヘッダー処理実装
  - [ ] Scriptヘッダー処理実装
  - [ ] データヘッダー処理実装
- [ ] ステータスメッセージ実装
- [ ] X-SSTP-PassThruヘッダー実装
- [ ] SSTPユニットテスト作成
- [ ] 統合テスト実行

---

### フェーズ3: SERIKO完全実装 (3週間)

#### SERIKO-1: SERIKO/2.0パーサー実装 (1週間)
- [ ] Ourin/Animation/SerikoParser.swift作成
  - [ ] SerikoInterval列挙型実装
  - [ ] SerikoMethod列挙型実装
  - [ ] SerikoPattern構造体実装
  - [ ] AnimationDefinition構造体実装
  - [ ] surfaces.txtパーサー実装
  - [ ] surfaceスコープ抽出実装
  - [ ] animationエントリ抽出実装
  - [ ] patternエントリ解析実装
- [ ] パーサーテスト作成
- [ ] 実際のシェルファイルでテスト

#### SERIKO-2: SERIKOエグゼキューター実装 (1週間)
- [ ] Ourin/Animation/SerikoExecutor.swift作成
  - [ ] AnimationState構造体実装
  - [ ] activeAnimations管理実装
  - [ ] executeAnimation()メソッド実装
  - [ ] startLoop()メソッド実装
  - [ ] executePattern()メソッド実装
  - [ ] 以下のメソッド実装:
    - [ ] executeOverlay()
    - [ ] executeOverlayFast()
    - [ ] executeBase()
    - [ ] executeMove()
    - [ ] executeReduce()
    - [ ] executeReplace()
    - [ ] executeStart()
    - [ ] executeAlternativeStart()
  - [ ] stopAnimation()メソッド実装
  - [ ] stopAllAnimations()メソッド実装
  - [ ] interval別スケジューリング実装:
    - [ ] always
    - [ ] sometimes/rarely/random
    - [ ] runonce
    - [ ] yen-e
    - [ ] talk
    - [ ] bind
- [ ] SERIKOユニットテスト作成

#### SERIKO-3: SERIKO-SakuraScript統合 (1週間)
- [ ] Ourin/SakuraScript/SakuraScriptEngine.swift拡張
  - [ ] \![anim,clear,ID]実装
  - [ ] \![anim,pause,ID]実装
  - [ ] \![anim,resume,ID]実装
  - [ ] \![anim,offset,ID,x,y]実装
  - [ ] \![anim,add,...]実装
    - [ ] overlay
    - [ ] base
    - [ ] move
    - [ ] text
  - [ ] \![anim,stop,ID]実装
- [ ] \![__w[animation,ID]]実装
- [ ] SerikoExecutorとの連携
- [ ] 統合テスト実行

---

### フェーズ4: SakuraScript拡張と文書化 (2週間)

#### SAKURA-1: サポート済みコマンド完全リスト作成 (3日間)
- [ ] Ourin/SakuraScript/SakuraScriptEngine.swift解析
- [ ] 実装済みコマンドを特定
- [ ] docs/SUPPORTED_SAKURA_SCRIPT.md作成
  - [ ] スコープコマンドセクション
  - [ ] サーフェスコマンドセクション
  - [ ] バルーン/テキストコマンドセクション
  - [ ] 文字変更コマンドセクション
  - [ ] ウェイトコマンドセクション
  - [ ] 選択肢コマンドセクション
  - [ ] イベントコマンドセクション
  - [ ] サウンドコマンドセクション
  - [ ] オープンコマンドセクション
  - [ ] プロパティ操作コマンドセクション
  - [ ] 実装状況マーク付（✅/⚠️/❌）

#### SAKURA-2: 未実装コマンドの優先実装 (1週間)
- [ ] \![move]拡張実装
  - [ ] --X, --Yオプション
  - [ ] --timeオプション
  - [ ] --baseオプション
  - [ ] --base-offsetオプション
  - [ ] --move-offsetオプション
  - [ ] --option=ignore-sticky-window
- [ ] \![moveasync]拡張実装
  - [ ] cancel機能実装
- [ ] \![set,scaling]拡張実装
  - [ ] --timeオプション
  - [ ] --waitオプション
- [ ] \![set,alpha]拡張実装
  - [ ] --timeオプション
  - [ ] --waitオプション
- [ ] \![set,zorder]完全実装
  - [ ] 複雑な組み合わせ対応
- [ ] \![set,sticky-window]完全実装
  - [ ] 複雑なグループ対応
- [ ] \![bind,...]拡張実装
- [ ] テスト実行

#### SAKURA-3: ドキュメント完成 (4日間)
- [ ] docs/SERIKO_IMPLEMENTATION.md作成
- [ ] docs/SAORI_IMPLEMENTATION.md作成
- [ ] docs/SSTP_DISPATCHER_GUIDE.md作成
- [ ] docs/OURIN_EXTENSIONS.md作成
- [ ] ドキュメントレビューと修正

---

## 🔄 継続的稼働プロンプト

以下のプロンプトは、自分自身に対して継続的な作業を指示するために使用します。

### 作業開始プロンプト
```
以下の手順で自律的に作業を進めてください：

1. タスクリストの次の未完了タスクを確認
2. そのタスクの詳細な実装手順を確認
3. 必要なファイルを読み込む（readツール使用）
4. 実装を行う（editツールまたはwriteツール使用）
5. ビルドしてエラーがないか確認
6. テストを行い動作を確認
7. タスクを完了としてマーク
8. 次のタスクに進む

エラーが発生した場合は：
- エラー内容を分析
- 原因を特定
- 解決策を提案
- 解決策を実行
- 再度ビルドとテスト

現在の進捗状況を定期的に報告してください。
```

### タスク進行中プロンプト
```
現在実行中のタスク: [タスク名]

進捗:
- [ ] サブタスク1
- [ ] サブタスク2
- [ ] サブタスク3

次に実行すべきサブタスクを特定し、実行してください。
完了したらチェックを入れてください。

ファイルを変更する前に必ずreadツールで現在の内容を確認してください。
```

### フェーズ完了確認プロンプト
```
フェーズ [フェーズ名] のすべてのタスクが完了しました。

以下を行ってください：
1. ビルド全体の確認
2. 関連するユニットテストの実行
3. 統合テストの実行
4. 既存ゴーストとの互換性テスト
5. 問題があれば修正

すべてが正常に動作していることを確認したら、次のフェーズに進んでください。
```

### エラー発生時プロンプト
```
エラーが発生しました：

エラー内容: [エラーメッセージ]
発生場所: [ファイル名:行番号]
発生状況: [どの操作で発生したか]

以下の手順で対処してください：
1. エラーの原因を分析
2. 関連するドキュメントや仕様書を確認
3. 類似の問題がないかコードベースを検索
4. 解決策を2〜3個提案
5. 最も適切な解決策を実行
6. 再度ビルド
7. テストで動作確認

解決できない場合は、詳細な情報を記録して次のタスクに進んでください。
```

### 定期的進捗報告プロンプト
```
進捗状況報告：

フェーズ1 (SAORI実装): [完了%]
フェーズ2 (SSTP Dispatcher): [完了%]
フェーズ3 (SERIKO実装): [完了%]
フェーズ4 (SakuraScript): [完了%]

全体進捗: [完了%]

直近に完了したタスク:
- [タスク名] (完了時刻)

現在実行中のタスク:
- [タスク名] (開始時刻)

次のタスク:
- [タスク名] (予定開始時刻)

ブロッカーがある場合は報告してください。
```

---

## 🛠️ 開発環境設定

### 必要なツール
- Xcode 15.0+
- Swift 5.9+
- Rust 1.70+ (yaya_coreビルド用)
- Git (バージョン管理)

### ビルドコマンド
```bash
# 完全ビルド
xcodebuild -project Ourin.xcodeproj -scheme Ourin build

# テスト実行
xcodebuild -project Ourin.xcodeproj -scheme Ourin test

# yaya_coreビルド
cd yaya_core && ./build.sh

# 実行
open build/Release/Ourin.app
```

### テストコマンド
```bash
# 単体テスト
xcodebuild test -scheme Ourin -only-testing:OurinTests/SaoriHostTests

# 統合テスト
open build/Release/Ourin.app
# 実際のゴーストをインストールして動作確認
```

---

## 📊 進捗管理

### マイルストーン
- [ ] 週1終了: SAORIローダー基本実装完了
- [ ] 週2終了: SAORI-YAYA統合完了
- [ ] 週3終了: SAORIフェーズ完了
- [ ] 週4終了: SSTP Dispatcher基本実装完了
- [ ] 週5終了: SSTPフェーズ完了
- [ ] 週6終了: SERIKOパーサー完了
- [ ] 週7終了: SERIKOエグゼキューター完了
- [ ] 週8終了: SERIKOフェーズ完了
- [ ] 週9終了: SakuraScript文書化完了
- [ ] 週10終了: SakuraScript拡張完了

### 品質チェックリスト
各フェーズ完了時に確認:
- [ ] すべてのタスク完了
- [ ] ビルド成功
- [ ] ユニットテスト通過
- [ ] 統合テスト通過
- [ ] 既存ゴースト互換性確認
- [ ] メモリリークチェック
- [ ] パフォーマンスチェック
- [ ] ドキュメント更新

---

## 🚨 トラブルシューティング

### よくある問題
1. **ビルドエラー**
   - 原因: 構文エラー、型不一致、ライブラリ不足
   - 対処: エラーメッセージを確認し、該当箇所を修正

2. **ランタイムエラー**
   - 原因: nil参照、範囲外アクセス、スレッド競合
   - 対処: デバッガーで原因特定し、安全な実装に修正

3. **互換性問題**
   - 原因: 仕様の誤解釈、バージョン違い
   - 対処: 仕様書を再確認し、正しい実装に修正

### エスカレーションルール
1. 問題が30分以内で解決できない場合:
   - 似たような実装例を検索
   - 関連ドキュメントを再確認

2. 問題が1時間以内で解決できない場合:
   - 別のアプローチを試す
   - コードを簡略化して最小再現例を作成

3. 問題が半日以上解決できない場合:
   - 該当機能を一時的にスキップ
   - 問題を記録して後で再検討

---

## 📝 ログ記録

作業履歴を以下の形式で記録:

```
[日時] タスク名
  - 実行内容
  - 結果: 成功/失敗
  - 修正: [必要な場合]
  - 次のアクション
```

ログファイル: `development/IMPLEMENTATION_LOG.md`

---

## 🎯 成功基準

プロジェクト完了時に以下の基準を満たすこと:

### 機能基準
- [ ] SAORI/1.0完全実装
- [ ] SSTP Dispatcher完全実装
- [ ] SERIKO/2.0完全実装
- [ ] SakuraScript主要コマンド実装
- [ ] 既存ゴースト95%以上互換

### 品質基準
- [ ] ユニットテストカバレージ80%以上
- [ ] 統合テスト通過率100%
- [ ] メモリリークなし
- [ ] クラッシュバグなし

### ドキュメント基準
- [ ] APIドキュメント完全
- [ ] 実装ガイド作成
- [ ] サンプルコード充足
- [ ] 既存ゴースト移行ガイド

---

**最終更新:** 2025年3月15日
**ステータス:** 実行待ち
