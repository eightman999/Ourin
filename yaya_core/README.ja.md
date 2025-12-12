# YAYA Core - macOSネイティブYAYAインタープリター

**バージョン**: 0.1.0 (開発中)
**ステータス**: フェーズ1 - 基盤構築
**プラットフォーム**: macOS (ユニバーサルバイナリ: arm64 + x86_64)
**ライセンス**: BSD-3-Clause

---

## 概要

YAYA Coreは、伺か/ゴーストデスクトップコンパニオン用のYAYAスクリプト言語インタープリターのmacOSネイティブ実装です。WindowsのDLLに依存せずにYAYAベースのゴーストをmacOS上で実行できます。

### 特徴

- ✅ **JSONベースIPC**: stdin/stdoutによる行指向のJSON通信
- ✅ **ユニバーサルバイナリ**: Apple Silicon (arm64)とIntel (x86_64)の両方をサポート
- ✅ **UTF-8/CP932**: 自動文字エンコーディング検出と変換
- 🚧 **YAYA言語**: 完全なYAYAスクリプト解釈（実装中）
- 🚧 **SHIORI/3.0M**: 完全なSHIORIプロトコル準拠（実装中）

### 現在のステータス

**実装済み**:
- [x] IPCフレームワーク (main.cpp, YayaCore)
- [x] JSONメッセージパース
- [x] コマンドディスパッチ (load/request/unload)
- [x] CMakeビルドシステム（ユニバーサルバイナリ対応）
- [x] 字句解析器（Lexer）
- [x] 構文解析器（Parser）
- [x] 仮想マシン（VM）
- [x] 組み込み関数（160関数すべて実装済み）
- [x] 配列・辞書サポート
- [x] 正規表現サポート

**実装中** (フェーズ2):
- [ ] SHIORIアダプター
- [ ] SAORIプラグインサポート
- [ ] パフォーマンス最適化

**計画中** (フェーズ3以降):
- [ ] より高度な最適化
- [ ] デバッグ機能の強化

---

## クイックスタート

### 前提条件

- macOS 13.0+ (Ventura以降)
- CMake 3.20+
- C++17対応コンパイラ (Clang 14+)
- nlohmann/jsonライブラリ

### ビルド

```bash
# 依存関係のインストール（Homebrew使用）
brew install cmake nlohmann-json

# ビルド
cd yaya_core
./build.sh

# ビルドの確認
./build/yaya_core --version  # (実装時)
```

### テスト

```bash
# ユニットテスト実行（実装時）
cd build
ctest --verbose

# 手動IPCテスト
echo '{"cmd":"load","ghost_root":"/path/to/ghost","dic":["test.dic"],"encoding":"utf-8"}' | ./build/yaya_core
```

---

## アーキテクチャ

```
yaya_core (実行ファイル)
│
├── main.cpp ─────────────── エントリーポイント（stdin/stdout IPC）
│
├── YayaCore ────────────── コマンドディスパッチャー
│   └── processCommand()
│
├── DictionaryManager ───── 辞書ロード・実行管理
│   ├── Lexer ──────────── トークン化
│   ├── Parser ─────────── AST構築
│   └── VM ─────────────── スクリプト実行
│
├── ShioriAdapter ───────── SHIORI/3.0Mプロトコルハンドラー
│
└── BuiltinFunctions ────── YAYA組み込み関数（160関数）
```

---

## IPCプロトコル

### リクエスト形式 (stdin)

```json
{
  "cmd": "load",
  "ghost_root": "/path/to/ghost/master",
  "dic": ["aya_bootend.dic", "aya_menu.dic"],
  "encoding": "utf-8",
  "env": {"LANG": "ja_JP.UTF-8"}
}
```

```json
{
  "cmd": "request",
  "method": "GET",
  "id": "OnBoot",
  "headers": {"Charset": "UTF-8", "Sender": "Ourin"},
  "ref": []
}
```

```json
{
  "cmd": "unload"
}
```

### レスポンス形式 (stdout)

**成功時**:
```json
{
  "ok": true,
  "status": 200,
  "headers": {"Charset": "UTF-8"},
  "value": "\\0\\s[0]Hello from YAYA\\e"
}
```

**エラー時**:
```json
{
  "ok": false,
  "status": 500,
  "error": "Failed to load dictionary: File not found"
}
```

---

## 開発

### プロジェクト構造

```
yaya_core/
├── CMakeLists.txt          # ビルド設定
├── README.md               # 英語ドキュメント
├── README.ja.md            # 日本語ドキュメント（このファイル）
├── src/
│   ├── main.cpp            # エントリーポイント
│   ├── YayaCore.{cpp,hpp}  # コアコントローラー
│   ├── DictionaryManager.{cpp,hpp}  # 辞書管理
│   ├── Lexer.{cpp,hpp}     # トークナイザー
│   ├── Parser.{cpp,hpp}    # パーサー
│   ├── AST.{cpp,hpp}       # 抽象構文木
│   ├── VM.{cpp,hpp}        # 仮想マシン
│   ├── Value.{cpp,hpp}     # 値型
│   ├── BuiltinFunctions.{cpp,hpp}  # 組み込み関数
│   ├── MessageManager.{cpp,hpp}    # メッセージ管理
│   ├── Digest.{cpp,hpp}    # ハッシュ関数ラッパー
│   └── Base64.{cpp,hpp}    # Base64エンコーディング
├── third_party/            # サードパーティコード
│   └── yaya/               # yaya-shiori-500からの移植コード
│       ├── md5.{c,h}       # MD5実装
│       ├── sha1.{c,h}      # SHA-1実装
│       ├── crc32.{c,h}     # CRC32実装
│       └── posix_utils.{cpp,h}  # POSIXユーティリティ
├── tests/                  # （計画中）ユニットテスト
└── docs/                   # ドキュメント
```

### コーディングスタイル

- **C++標準**: C++17
- **命名規則**:
  - クラス: `PascalCase`
  - 関数: `camelCase()`
  - 変数: `snake_case_`
  - 定数: `UPPER_CASE`
- **フォーマット**: スペース4つ、タブなし
- **コメント**: コードは英語、ユーザー向けメッセージは日本語

### コントリビュート

1. `docs/YAYA_CORE_IMPLEMENTATION_PLAN.md` でロードマップを確認
2. 既存のコード構造に従う
3. 新機能にはユニットテストを追加
4. ユニバーサルバイナリ互換性を確保（可能であればIntelとApple Siliconの両方でテスト）

---

## Ourinとの統合

YAYA CoreはOurinアプリによってヘルパー実行ファイルとして起動されます：

```swift
// Ourin/Yaya/YayaAdapter.swift
let adapter = YayaAdapter()
adapter.load(ghostRoot: ghostURL, dics: ["aya_bootend.dic"], encoding: "utf-8")
let response = adapter.request(method: "GET", id: "OnBoot", refs: [])
```

詳細は `Ourin/Yaya/YayaAdapter.swift` のSwift統合レイヤーを参照してください。

---

## リファレンス実装

この実装は公式YAYAインタープリターを参考にしています：

- **YAYA (C++)**: https://github.com/YAYA-shiori/yaya-shiori
- **ライセンス**: BSD-3-Clause
- **アプローチ**: macOSに最適化された再実装（直接のポートではありません）

---

## 依存関係について

### 外部依存関係

- **nlohmann/json** (3.12.0+): JSONパーサー
  - 用途: IPC通信
  - ライセンス: MIT
  - インストール: `brew install nlohmann-json`

### バンドル済みコード

`third_party/yaya/` に含まれるコード（yaya-shiori-500より）：

- **MD5/SHA-1/CRC32**: YAYA言語の`FILEDIGEST`および`STRDIGEST`関数用
  - ⚠️ **セキュリティ警告**: これらは暗号学的に安全ではありません
  - YAYA言語仕様との互換性のためのみ使用
  - Ourinの新しいコードではセキュリティ目的で使用しないこと

詳細については親ディレクトリの [`docs/DEPENDENCIES.ja.md`](../docs/DEPENDENCIES.ja.md) を参照してください。

---

## ドキュメント

- [実装計画](../docs/YAYA_CORE_IMPLEMENTATION_PLAN.md) - 詳細なロードマップとアーキテクチャ
- [技術仕様](../docs/YAYA_CORE_TECHNICAL_SPEC.md) - 言語仕様とAPIリファレンス
- [YAYAアダプター仕様](../docs/OURIN_YAYA_ADAPTER_SPEC_1.0M.md) - IPCプロトコル仕様
- [関数リファレンス](FUNCTION_REFERENCE.md) - 実装済み160関数の完全リスト

---

## ライセンス

BSD-3-Clause License

```
Copyright (c) 2025, Ourin Project
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

---

**メンテナー**: Ourin Project
**連絡先**: https://github.com/eightman999/Ourin

---

## Xcode統合

### クイックセットアップ

1. yaya_coreをビルド:
   ```bash
   cd yaya_core
   ./build.sh
   ```

2. Xcodeで、Ourinターゲットの「Copy Files」ビルドフェーズに追加:
   - Destination: "Executables"
   - File: `yaya_core/build/yaya_core`

3. バイナリは以下の方法でアクセス可能:
   ```swift
   Bundle.main.url(forAuxiliaryExecutable: "yaya_core")
   ```

### 自動ビルド（オプション）

「Copy Files」の前に「Run Script」ビルドフェーズを追加:

```bash
cd "${SRCROOT}/yaya_core"
if [ ! -f "build/yaya_core" ] || [ "src" -nt "build/yaya_core" ]; then
    ./build.sh
fi
```

これにより、ソースファイルが変更された際に自動的にyaya_coreが再ビルドされます。

---

## トラブルシューティング

### ビルドエラー: "nlohmann/json.hpp not found"

**解決策**:
```bash
# nlohmann-jsonをインストール
brew install nlohmann-json

# Apple Silicon Macの場合、パスを設定
export CMAKE_PREFIX_PATH=/opt/homebrew

# Intel Macの場合
export CMAKE_PREFIX_PATH=/usr/local

# 再ビルド
cd yaya_core
rm -rf build
./build.sh
```

### 実行エラー: "dyld: Library not loaded"

YAYA Coreは静的リンクされているため、通常このエラーは発生しません。発生した場合は：

```bash
# ビルドを確認
otool -L build/yaya_core

# 完全に再ビルド
rm -rf build
./build.sh
```

---

## お問い合わせ

質問や問題がある場合は：

- **GitHub Issues**: https://github.com/eightman999/Ourin/issues
- **Email**: eight@eightman999.com
