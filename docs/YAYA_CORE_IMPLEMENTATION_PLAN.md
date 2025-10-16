# YAYA Core 詳細実装計画書

**日付**: 2025-10-16  
**バージョン**: 1.0  
**ステータス**: Draft  
**対象プラットフォーム**: macOS (Universal Binary: arm64 + x86_64)

---

## 目次

1. [エグゼクティブサマリー](#1-エグゼクティブサマリー)
2. [現状分析](#2-現状分析)
3. [実装方針](#3-実装方針)
4. [アーキテクチャ設計](#4-アーキテクチャ設計)
5. [YAYA言語仕様の実装範囲](#5-yaya言語仕様の実装範囲)
6. [実装フェーズ](#6-実装フェーズ)
7. [技術選定](#7-技術選定)
8. [依存関係とリソース](#8-依存関係とリソース)
9. [リスクと対策](#9-リスクと対策)
10. [テスト戦略](#10-テスト戦略)
11. [参考資料](#11-参考資料)

---

## 1. エグゼクティブサマリー

### 目的
macOS上でYAYAゴースト（伺か/ukagakaデスクトップマスコット）をネイティブ実行するため、Windows DLLに依存しないYAYA言語インタプリタを実装する。

### 現状
- 基本的な**IPCフレームワーク**は実装済み（JSON line-based protocol）
- DictionaryManagerは**スタブ実装**のみ（実際のパース・実行機能なし）
- Swift側のアダプタ（YayaAdapter.swift）は完成

### 実装方針
**ハイブリッドアプローチ**：
- **Phase 1**: C++で高速なコアエンジンを実装（既存資産最大活用）
- **Phase 2**: 段階的にSwiftへ移行可能な設計
- 既存のオープンソースYAYA実装を参考にしつつ、macOSネイティブに最適化

---

## 2. 現状分析

### 2.1 既存実装の評価

#### ✅ 実装済み機能
```
yaya_core/
├── CMakeLists.txt          # Universal Binary対応済み
├── src/
│   ├── main.cpp           # JSON IPC実装済み
│   ├── YayaCore.cpp       # コマンドディスパッチ実装済み
│   └── DictionaryManager  # スタブのみ
```

**実装済みコマンド**:
- `load`: 辞書ファイル読み込み（スタブ）
- `request`: SHIORI GET/NOTIFY処理（スタブ）
- `unload`: 辞書アンロード（スタブ）

#### ❌ 未実装機能（重要度順）
1. **辞書パーサー** (.dicファイルの字句解析・構文解析)
2. **YAYA VM** (関数実行・変数管理・制御構造)
3. **組み込み関数** (文字列操作・配列・SHIORI固有関数)
4. **文字コード処理** (UTF-8/CP932変換)
5. **エラーハンドリング** (構文エラー・実行時エラー)

### 2.2 参照可能なリソース

#### 既存のYAYA実装
1. **YAYA (C++)**: https://github.com/YAYA-shiori/yaya-shiori
   - 公式Windows実装
   - BSD-3-Clause License（商用利用可能）
   - macOSポート可能性高い

2. **yaya-rs (Rust)**: https://github.com/apxxxxxxe/yaya-rs
   - Rustによる再実装
   - YAYA仕様の現代的な解釈

3. **Emily4サンプル**: `/emily4/ghost/master/*.dic`
   - 実際のYAYA辞書（50+ファイル）
   - テストケースとして活用可能

#### ドキュメント
- `docs/OURIN_YAYA_ADAPTER_SPEC_1.0M.md`: IPC仕様
- `docs/OURIN_USL_1.0M_SPEC.md`: SHIORIローダー仕様
- YAYA公式ドキュメント（Web）

---

## 3. 実装方針

### 3.1 言語選択：C++ vs Swift

#### ✅ 推奨：**C++ベース実装**

**理由**:
1. **既存資産の活用**
   - 公式YAYAのC++コードを参考にできる
   - 文字列処理・正規表現ライブラリが成熟
   
2. **パフォーマンス**
   - 辞書パースは高速性が求められる
   - VM実行ループは低レイテンシが必要

3. **段階的移行が可能**
   - C++で実装→後でSwiftモジュールに分離可能
   - IPCレイヤーで分離されているため影響範囲が限定的

4. **Universal Binary対応**
   - CMakeで既にarm64/x86_64対応済み

#### 将来の移行パス（オプション）
- Phase 3以降: SwiftでVM実装
- Swift Concurrency活用
- Xcode統合強化

### 3.2 実装スコープ

#### Minimum Viable Product (MVP)
基本的なYAYAゴーストを動作させるために必要な最小機能:

1. **辞書読み込み**
   - UTF-8/CP932対応
   - 基本的な構文解析（関数定義・変数）

2. **基本実行機能**
   - 関数呼び出し
   - 変数代入・参照
   - 文字列連結
   - 条件分岐（if/else）

3. **SHIORI統合**
   - `OnBoot`, `OnClose` イベント
   - GET/NOTIFYレスポンス生成

#### Extended Features（Phase 2以降）
- 配列・連想配列
- ループ構造（while/foreach）
- 正規表現
- SAORI連携
- デバッグ機能

---

## 4. アーキテクチャ設計

### 4.1 コンポーネント構成

```
yaya_core (C++実行体)
├── main.cpp              # IPC Entry Point
├── YayaCore              # メインコントローラー
├── DictionaryManager     # 辞書管理
│   ├── DictionaryLoader  # ファイル読み込み・文字コード変換
│   ├── Lexer            # 字句解析
│   └── Parser           # 構文解析
├── Runtime               # 実行エンジン
│   ├── VM                # 仮想マシン
│   ├── FunctionRegistry  # 関数テーブル
│   ├── VariableStore     # 変数ストレージ
│   └── BuiltinFunctions  # 組み込み関数
└── ShioriAdapter         # SHIORI/3.0M 変換
    ├── RequestParser     # SHIORIリクエスト解析
    └── ResponseBuilder   # SHIORIレスポンス構築
```

### 4.2 データフロー

```
Swift (YayaAdapter)
    ↓ JSON {"cmd":"load", "ghost_root":"/path", "dic":["a.dic"]}
  IPC (stdin)
    ↓
main.cpp → YayaCore::processCommand()
    ↓
DictionaryManager::load()
    ├→ DictionaryLoader::readFile()  # UTF-8/CP932自動検出
    ├→ Lexer::tokenize()              # トークン分割
    └→ Parser::parse()                # AST構築
         └→ FunctionRegistry::register()

Swift (YayaAdapter)
    ↓ JSON {"cmd":"request", "method":"GET", "id":"OnBoot"}
  IPC (stdin)
    ↓
YayaCore::processCommand()
    ↓
DictionaryManager::execute("OnBoot", [])
    ├→ FunctionRegistry::find("OnBoot")
    ├→ VM::execute(function, args)
    │   ├→ VariableStore::get/set()
    │   └→ BuiltinFunctions::call()
    └→ return "\0\s[0]Hello\e"  # SakuraScript
    ↓
  IPC (stdout)
    ↓ JSON {"ok":true, "status":200, "value":"\\0\\s[0]Hello\\e"}
Swift (YayaAdapter)
```

### 4.3 メモリ管理

- **辞書データ**: `std::shared_ptr` でライフタイム管理
- **変数ストア**: `std::unordered_map<std::string, Value>`
- **関数テーブル**: `std::map<std::string, std::shared_ptr<Function>>`
- **IPC通信**: 短命バッファ（スタック確保可能）

---

## 5. YAYA言語仕様の実装範囲

### 5.1 Phase 1: 基本機能（MVP）

#### 字句要素
```yaya
// コメント（行末まで）
/* ブロックコメント */

// 変数
_var = "value"
_num = 123

// 関数定義
OnBoot {
    "\0\s[0]Hello"
}
```

#### データ型
- **文字列**: `"..."` (SakuraScript含む)
- **整数**: `123`, `-456`
- **実数**: `3.14` (オプション)

#### 演算子
- 代入: `=`
- 算術: `+`, `-`, `*`, `/`, `%`
- 比較: `==`, `!=`, `<`, `>`, `<=`, `>=`
- 論理: `&&`, `||`, `!`
- 文字列連結: `+` (自動変換)

#### 制御構造
```yaya
// 条件分岐
if condition {
    // ...
}
else {
    // ...
}

// 三項演算子
_result = condition ? true_value : false_value
```

#### 組み込み変数（SHIORI）
- `reference[0]`, `reference[1]`, ... : SHIORIリファレンス
- `RAND(max)`: 乱数生成
- `ARRAYSIZE(arr)`: 配列サイズ

### 5.2 Phase 2: 拡張機能

#### 配列・連想配列
```yaya
_arr = ("a", "b", "c")
_dict = ("key1":"value1", "key2":"value2")
```

#### ループ
```yaya
while condition {
    // ...
}

foreach _arr; _item {
    // ...
}
```

#### 正規表現
```yaya
if _str =~ "pattern" {
    // ...
}
```

---

## 6. 実装フェーズ

### Phase 1: MVP実装 (2-3週間)

#### Week 1: パーサー基盤
- [x] プロジェクト構造確認
- [ ] 字句解析器（Lexer）実装
  - トークン定義
  - ファイル読み込み
  - UTF-8/CP932変換
- [ ] 構文解析器（Parser）基盤
  - AST定義
  - 基本的な式解析

#### Week 2: VM実装
- [ ] 変数ストア実装
- [ ] 関数レジストリ
- [ ] VM実行エンジン
  - 式評価
  - 関数呼び出し
  - 条件分岐
- [ ] 基本組み込み関数
  - 文字列操作
  - RAND()
  - reference[]

#### Week 3: SHIORI統合
- [ ] ShioriAdapter実装
  - リクエスト解析
  - レスポンス構築
- [ ] エラーハンドリング
- [ ] Emily4でテスト
- [ ] ドキュメント整備

### Phase 2: 拡張機能 (2-3週間)

- [ ] 配列・連想配列
- [ ] ループ構造
- [ ] 正規表現サポート
- [ ] パフォーマンス最適化
- [ ] 包括的テストスイート

### Phase 3: 品質向上 (継続的)

- [ ] メモリリーク検証（Valgrind/ASan）
- [ ] パフォーマンスプロファイリング
- [ ] 複数ゴーストでの動作確認
- [ ] ドキュメント完成
- [ ] (オプション) Swift VM移行検討

---

## 7. 技術選定

### 7.1 必須ライブラリ

#### 既存
- **nlohmann/json**: JSON処理（IPC通信）

#### 追加推奨
- **ICU (International Components for Unicode)**: 文字コード変換
  - UTF-8 ↔ CP932
  - macOSにプリインストール済み
  
- **std::regex** (C++11標準): 正規表現
  - Phase 2で使用
  - 追加依存なし

### 7.2 ビルドシステム

#### 現状: CMake
```cmake
# yaya_core/CMakeLists.txt
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")  # ✅
find_package(nlohmann_json REQUIRED)         # ✅
```

#### 追加設定
```cmake
# ICU検出
find_package(ICU REQUIRED COMPONENTS uc i18n)
target_link_libraries(yaya_core PRIVATE ICU::uc ICU::i18n)

# C++17機能使用
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
```

### 7.3 テストフレームワーク

- **Google Test**: C++ユニットテスト
- **統合テスト**: Emily4サンプルゴーストで実際に動作確認

---

## 8. 依存関係とリソース

### 8.1 外部依存

| 依存 | バージョン | ライセンス | 用途 |
|------|-----------|-----------|------|
| nlohmann/json | 3.x | MIT | JSON IPC |
| ICU | システム | Unicode | 文字コード変換 |
| GoogleTest | 1.14+ | BSD-3 | テスト |

### 8.2 参考実装

- **公式YAYA**: https://github.com/YAYA-shiori/yaya-shiori
  - ライセンス: BSD-3-Clause
  - 参考範囲: アーキテクチャ設計、パーサーロジック
  - 直接移植はせず、macOS最適化を優先

### 8.3 必要なリソース

- **開発環境**: macOS 13+ (Xcode 15+)
- **ビルド時間**: 約2-3分（Universal Binary）
- **実行時メモリ**: 辞書ごとに20-50MB（想定）

---

## 9. リスクと対策

### 9.1 技術リスク

| リスク | 影響度 | 対策 |
|--------|--------|------|
| YAYA仕様の曖昧さ | 高 | 公式実装を参照・エミュレータテスト |
| 文字コード問題 | 中 | ICU使用・包括的テスト |
| パフォーマンス | 中 | プロファイリング・最適化 |
| メモリリーク | 中 | Asan/Valgrind検証 |

### 9.2 スコープクリープ

**対策**:
- Phase 1はMVPに厳格に制限
- 機能追加はPhase 2以降
- Emily4が動作すればPhase 1完了

### 9.3 互換性問題

**対策**:
- 複数ゴーストでテスト
- Windows版YAYAとの差分文書化
- 非互換部分はログ警告

---

## 10. テスト戦略

### 10.1 ユニットテスト

```cpp
// 例: Lexerテスト
TEST(LexerTest, TokenizeSimpleFunction) {
    Lexer lexer("OnBoot { \"hello\" }");
    auto tokens = lexer.tokenize();
    EXPECT_EQ(tokens[0].type, TokenType::Identifier);
    EXPECT_EQ(tokens[1].type, TokenType::LeftBrace);
    // ...
}
```

### 10.2 統合テスト

1. **最小辞書テスト**
```yaya
// test_minimal.dic
OnBoot {
    "\0\s[0]Test OK\e"
}
```

2. **Emily4フルテスト**
   - 全50+辞書ファイル読み込み
   - OnBoot実行
   - 主要イベント応答確認

### 10.3 パフォーマンステスト

- **ベンチマーク**: 辞書読み込み時間 < 500ms
- **レイテンシ**: `OnBoot` 応答 < 50ms
- **メモリ**: 辞書ロード後 < 100MB

---

## 11. 参考資料

### 11.1 既存ドキュメント

- `docs/OURIN_YAYA_ADAPTER_SPEC_1.0M.md`: IPC仕様
- `docs/OURIN_USL_1.0M_SPEC.md`: SHIORIローダー
- `docs/SHIORI_3.0M_SPEC.md`: SHIORIプロトコル

### 11.2 外部リソース

- YAYA公式: https://emily.shillest.net/ayaya/
- YAYA GitHub: https://github.com/YAYA-shiori/yaya-shiori
- 伺かWiki: https://ssp.shillest.net/ukadoc/
- SHIORI仕様: https://emily.shillest.net/shiori/

### 11.3 サンプルコード

- `emily4/ghost/master/*.dic`: 実際のYAYA辞書
- `CORE_SAMPLES/`: C# SHIORI実装例
- `Ourin/Yaya/YayaAdapter.swift`: Swift IPC実装

---

## まとめ

### 推奨実装アプローチ

1. **Phase 1をC++で実装** (現状維持・既存資産活用)
2. **MVP完成後にSwift移行を検討** (将来オプション)
3. **公式YAYAを参考にしつつmacOS最適化**

### 成功基準

- ✅ Emily4ゴーストが起動する
- ✅ 基本的な対話が機能する
- ✅ Universal Binaryで動作する
- ✅ UTF-8/CP932辞書に対応する

### 次のアクション

1. このドキュメントをレビュー
2. Phase 1 Week 1の実装開始
3. 週次で進捗確認

---

**文書バージョン**: 1.0  
**最終更新**: 2025-10-16  
**著者**: GitHub Copilot (eightman999/Ourin)
