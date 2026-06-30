# Ourin における SERIKO 実装

## スコープ

Ourin は現在、SERIKO を 2 層で実装しています：

- `AnimationEngine.swift` のレガシー実行パス
- 新しいパーサー/エグゼキューターパス：
  - `Ourin/Animation/SerikoParser.swift`
  - `Ourin/Animation/SerikoExecutor.swift`
  - `Ourin/Ghost/GhostManager+Animation.swift` 統合

## パーサー (`SerikoParser`)

`SerikoParser.parseSurfaces(_:)` は `surfaces.txt` を読み込んで以下を抽出します：

- `surfaceN { ... }` スコープブロック
- `animation<ID>.interval,<value>`
- `animation<ID>.option,<value>`
- `animation<ID>.pattern<idx>,...`

コアモデル型：

- `SerikoInterval` (`always`, `sometimes`, `rarely`, `random`, `runonce`, `yen-e`, `talk`, `bind`, `never`)
- `SerikoMethod` (`overlay`, `overlayfast`, `base`, `move`, `reduce`, `replace`, `start`, `alternativestart`, `stop`, `asis`)
- `SerikoPattern`
- `AnimationDefinition`

注：

- レガシー数値パターン形式は `overlay` として扱われます。
- 不明な値は `.unknown(...)` で保持されます。

## エグゼキューター (`SerikoExecutor`)

`SerikoExecutor` はステートフルアニメーションスケジューラーです：

- `register(animations:)` は定義を保存します
- `executeAnimation(id:)` はアニメーションを即座に開始します
- `startLoop()` は経過時間とインターバル規則に基づいてアクティブなアニメーションを進めます
- `pauseAnimation`, `resumeAnimation`, `offsetAnimation`, `stopAnimation`, `stopAllAnimations`

インターバルトリガー：

- 確率的：`sometimes`, `rarely`, `random`
- ワンショット：`runonce`
- イベント駆動：`yenE`, `talk`, `bind` トリガー API 経由

コールバック：

- `onMethodInvoked`
- `onPatternExecuted`
- `onAnimationFinished`

## ゴースト統合

`GhostManager+Animation.swift` はエグゼキューターコールバックをレンダリング処理に配線します：

- `overlay` / `overlayFast` -> `handleSurfaceOverlay`
- `base` -> `handleAnimAddBase`
- `move` -> `handleAnimAddMove`
- `replace` -> `handleSurfaceOverlay(..., .replace)`
- `start` / `alternativeStart` -> ネストされたエグゼキューター開始
- `stop` -> エグゼキューター停止

実行時フロー：

1. `loadAnimationsForCurrentSurface()` が `surfaces.txt` をロードします
2. パースされたアニメーションが `SerikoExecutor` に登録されます
3. `playAnimation(...)` はまずエグゼキューターを試します
4. エグゼキューターに一致する定義がない場合、レガシー `AnimationEngine` にフォールバックします

ループは `GhostManager+Animation` のタイマーが `serikoExecutor.startLoop()` を呼び出して駆動されます。

## SakuraScript リンケージ

現在のリンケージはコマンドレベルで `GhostManager` ハンドラーを通じて行われます：

- `\i[ID]` / `\i[ID,wait]`
- `\![anim,clear|pause|resume|offset|add|stop,...]`

`waitForAnimation(id:)` は同期動作向けに存在し、アニメーションフローで使用されます。

## テストカバレッジ

- `OurinTests/SerikoParserTests.swift`
  - パーサー正確性
  - 実シェル `surfaces.txt` パース
- `OurinTests/SerikoExecutorTests.swift`
  - 起動/進行/オフセット
  - runonce 完了
  - インターバルトリガー動作

## 現在のステータス

**ステータス**: パーサー完了、エグゼキューター統合済み / 更新日：2026-06-15

### 実装済みコンポーネント

#### ✅ **SerikoParser.swift** (完全)
以下を含む完全な SERIKO/2.0 パーサー：
- すべてのインターバルタイプ (always, sometimes, rarely, random, runonce, yen-e, talk, bind, never)
- すべてのメソッドタイプ (overlay, overlayfast, base, move, isReducing, replace, start, alternativestart, stop, asis)
- パターンパースとサーフェス定義
- surfaces.txt パース

#### ✅ **SerikoExecutor.swift** (接続済み)
以下を含む完全に機能するアニメーション実行エンジン：
- アニメーション状態管理
- executeAnimation()、startLoop() メソッド
- すべての execute メソッド (overlay, base, move, reduce, replace, start, stop など)
- 一時停止/再開/オフセット機能
- コールバックシステム (onMethodInvoked, onPatternExecuted, onAnimationFinished)
- ✅ GhostManager へのコールバック配線 (`GhostManager+Animation.swift`)

#### ✅ **GhostManager+Animation.swift** (統合済み)
- SerikoExecutor コールバック接続済み
- タイマー駆動ループ (`serikoExecutor.startLoop()`) と `\![anim,*]` ルーティング実装済み

### 統合のギャップ
- ✅ **SerikoExecutor コールバック接続済み** - GhostManager アニメーションハンドラー経由で配線
- ✅ **SakuraScript アニメーションコマンドルーティング済み** - \![anim,*] パスでアニメーション処理を制御
- ⚠️ **高度な着せ替え動作のカバレッジ** - 機能パスは存在しますが、より広いゴースト行列検証は進行中

### ブロック中の問題
- 現在のトラッカーでアクティブな SERIKO ブロッカーはありません。

### 必要な統合

詳細な統合手順については、INTEGRATION_ROADMAP.md の**フェーズ 3** を参照してください：

1. **SerikoExecutor を GhostManager に配線** (タスク 3.1)：
   - GhostManager+Animation.swift 内：
     ```swift
     serikoExecutor.onMethodInvoked = { [weak self] method in
         self?.handleSerikoMethod(method)
     }
     
     serikoExecutor.onPatternExecuted = { [weak self] pattern in
         self?.handleSerikoPattern(pattern)
     }
     
     serikoExecutor.onAnimationFinished = { [weak self] animationId in
         self?.handleAnimationFinished(animationId)
     }
     ```
   - サーフェス/レンダリングを更新するハンドラーメソッドを実装

2. **SakuraScript アニメーションコマンドを実装** (タスク 3.2)：
   - SakuraScriptEngine.swift 内：
     ```swift
     private func handleAnimCommand(arguments: [String]) {
         let command = arguments[0]
         switch command {
         case "clear":
             serikoExecutor.stopAnimation(id: animId)
         case "pause":
             serikoExecutor.pauseAnimation(id: animId)
         // ... など
         }
     }
     ```
   - \__w[animation,ID] のウェイトハンドラーを実装

3. **テスト** (タスク 3.3)：
   - アニメーションを持つゴーストをロード
   - SakuraScript 経由でトリガー
   - 再生が機能することを確認
   - 一時停止/再開/オフセットをテスト

### 成功基準
- [x] GhostManager コールバック接続済み
- [x] アニメーションコマンド実行
- [x] 一時停止/再開/オフセット動作
- [x] 重大な SERIKO ブロッカー解決済み
- [ ] 完全なマルチゴースト画面上行列検証

---

## 現在の制限

- 高度なオプション互換性はゴーストデータ形状によって異なります。
- `animation<ID>.option` 内のすべての SERIKO オプションがまだランタイムで適用されていません。
- 高度な SakuraScript アニメーション待機パターンとの統合は部分的なままです。
- レガシーと新しいパスはコンパチビリティのため共存します。動作はコマンド/データ形状によって異なる場合があります。
