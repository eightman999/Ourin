# Ourin Autonomy Tool

AIエージェントが自律的にOurinプロジェクトを改良するためのツールセット。段階的自律性（Staged Autonomy）機能を提供し、安全な自動実行と人間の承認フローをサポートします。

## 機能

### コード品質向上
- **静的解析**: Swiftコードの品質分析、複雑度測定、バグ検出
- **自動リファクタリング**: 安全なコード改善の提案と実行
- **コードフォーマット**: 一貫性のあるコードスタイルの適用

### テスト実装
- **自動テスト生成**: Swift Testingフレームワーク用の単体テスト生成
- **エッジケーステスト**: 境界値や異常系のテスト自動生成
- **非同期テスト**: async/awaitを含むテスト生成

### ドキュメント作成
- **APIドキュメント**: 関数・クラス・構造体のドキュメント生成
- **使用例**: 実用的なコード例の自動生成
- **分析レポート**: プロジェクト全体の品質レポート（Markdown/HTML）

### Git統合
- **ブランチ管理**: 作業用ブランチの自動作成
- **変更追跡**: 変更点の自動追跡とコミット
- **PR作成支援**: プルリクエスト作成の手順提供

## 安全性レベル（Safety Levels）

5段階の安全性レベルで自律性を制御します：

| レベル | 名前 | 自動実行 | 承認が必要 | 説明 |
|--------|------|----------|------------|------|
| 1 | Read-only Analysis | ✓ | - | コード分析、ドキュメント生成、メトリクス収集 |
| 2 | Safe Auto-Execution | ✓ | - | テスト生成、ドキュメント更新、安全なリファクタリング |
| 3 | Semi-Autonomous | - | ✓ | バグ修正、機能実装（レビュー付き） |
| 4 | Supervised Autonomy | - | ✓ | 主要リファクタリング、アーキテクチャ変更（厳格レビュー） |
| 5 | Critical Operations | - | ✓ | 破壊的変更、データ移行、破壊的操作 |

## インストール

```bash
cd ourin-autonomy
npm install
npm run build
```

## 使用方法

### MCPサーバーとして使用（Claude Desktop等）

Claude Desktopの設定ファイルに追加：

```json
{
  "mcpServers": {
    "ourin-autonomy": {
      "command": "node",
      "args": ["/path/to/ourin-autonomy/dist/index.js"]
    }
  }
}
```

### CLIツールとして使用

```bash
# ヘルプ表示
./ourin-autonomy --help

# コード分析
./ourin-autonomy analyze

# 特定パターンのファイルを分析
./ourin-autonomy analyze -p "Ourin/**/*.swift"

# 分析レポートを生成して保存
./ourin-autonomy analyze -o analysis-report.md

# テスト生成
./ourin-autonomy test-gen Ourin/OurinApp.swift

# エッジケースを含むテスト生成
./ourin-autonomy test-gen Ourin/OurinApp.swift --edge-cases

# ドキュメント生成
./ourin-autonomy doc-gen Ourin/OurinApp.swift

# 使用例を含むドキュメント生成
./ourin-autonomy doc-gen Ourin/OurinApp.swift --examples

# リファクタリング候補の分析
./ourin-autonomy refactor-analyze Ourin/OurinApp.swift

# 安全性レベルの設定
./ourin-autonomy safety 2

# 現在の安全性レベルを確認
./ourin-autonomy safety

# 全ての安全性レベルを表示
./ourin-autonomy safety-levels

# 保留中のタスクを表示
./ourin-autonomy tasks

# タスクを承認して実行
./ourin-autonomy approve <taskId>

# Gitブランチ作成
./ourin-autonomy branch autonomy/fix-errors

# コミット
./ourin-autonomy commit "Fix errors in codebase"

# 自動モード（分析→推奨→実行のワークフロー）
./ourin-autonomy auto
```

## MCPツール一覧

### set_safety_level
現在の安全性レベルを設定します。

### analyze_code
Swiftコードの品質分析を行います。

### generate_tests
Swiftファイル用の単体テストを生成します。

### generate_documentation
Swiftファイル用のドキュメントを生成します。

### analyze_refactoring
リファクタリングの機会を分析します。

### apply_refactoring
安全なリファクタリングを適用します。

### generate_analysis_report
包括的な分析レポートを生成します。

### get_safety_status
現在の安全性レベルとステータスを取得します。

### list_pending_tasks
保留中の自律タスクを一覧表示します。

## ワークフローの例

### 1. コード品質の改善

```bash
# ステップ1: 分析
./ourin-autonomy analyze -o report.md

# ステップ2: リファクタリング候補を確認
./ourin-autonomy refactor-analyze Ourin/OurinApp.swift

# ステップ3: 安全性レベル2に設定（安全なリファクタリングを自動実行）
./ourin-autonomy safety 2

# ステップ4: リファクタリング実行（MCPまたはCLI経由）
# 安全レベル2以下であれば自動実行されます
```

### 2. テストの自動生成

```bash
# ステップ1: テストのないファイルを特定
./ourin-autonomy analyze | grep "functions"

# ステップ2: テスト生成
./ourin-autonomy test-gen Ourin/FMO/FmoManager.swift -o OurinTests/FmoManagerTests.swift

# ステップ3: テスト実行
xcodebuild -project Ourin.xcodeproj -scheme Ourin test
```

### 3. ドキュメントの自動更新

```bash
# 全てのSwiftファイルにドキュメントを生成
for file in Ourin/**/*.swift; do
  ./ourin-autonomy doc-gen "$file" -o "docs/$(basename $file .swift).md"
done
```

### 4. 自律的ワークフロー

```bash
# 自動モードで実行（分析→推奨→タスク作成）
./ourin-autonomy auto

# 生成されたタスクを確認
./ourin-autonomy tasks

# 安全性レベルを上げて承認なしで実行
./ourin-autonomy safety 3

# タスクを承認して実行
./ourin-autonomy approve fix_errors_1234567890
```

## アーキテクチャ

```
ourin-autonomy/
├── src/
│   ├── index.ts              # MCPサーバーエントリーポイント
│   ├── cli.ts                # CLIツールエントリーポイント
│   ├── analyzers/            # コード解析器
│   │   └── swift-analyzer.ts
│   ├── generators/           # コード・テスト生成器
│   │   ├── test-generator.ts
│   │   └── doc-generator.ts
│   ├── refactoring/          # リファクタリング
│   │   └── safe-refactor.ts
│   ├── autonomy/             # 自律性管理
│   │   ├── safety-level.ts
│   │   └── task-scheduler.ts
│   └── git/                 # Git操作
│       └── manager.ts
```

## 貢献

AIエージェントによる自律的改善を支援するためのプルリクエストを歓迎します。

## ライセンス

MIT License

---

**注意**: このツールは段階的自律性を実装しています。安全性レベル3以上では人間の承認が必要です。本番環境での使用前には、変更内容を必ずレビューしてください。
