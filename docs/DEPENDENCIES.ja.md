# Ourin 依存関係ドキュメント

**最終更新**: 2025年12月11日
**バージョン**: 0.0.1.21

---

## 概要

Ourinプロジェクトは、依存関係を最小限に抑えた設計を採用しています。このドキュメントでは、すべての依存関係、その用途、セキュリティに関する考慮事項について説明します。

---

## メインアプリケーション (Swift/SwiftUI)

### 外部依存関係

**なし** - Ourinのメインアプリケーションは外部依存関係を持ちません。

### システムフレームワーク

Ourinは以下のApple公式フレームワークのみを使用しています：

| フレームワーク | バージョン | 用途 |
|--------------|-----------|------|
| **Foundation** | macOS SDK | 基本的なデータ型、コレクション、ファイルシステムアクセス |
| **AppKit** | macOS SDK | macOSネイティブUI（ウィンドウ管理、メニューなど） |
| **SwiftUI** | macOS SDK | モダンな宣言的UI |
| **OSLog** | macOS SDK | システムログ・デバッグ出力 |
| **UserNotifications** | macOS SDK | 通知機能 |
| **CoreImage** | macOS SDK | 画像処理・フィルター |
| **Combine** | macOS SDK | リアクティブプログラミング・非同期処理 |
| **Darwin** | macOS SDK | POSIXシステムコール（セマフォ、共有メモリなど） |
| **Network** | macOS SDK | ネットワーク通信（SSTP TCPサーバー） |
| **UniformTypeIdentifiers** | macOS SDK | ファイルタイプ識別 |
| **CoreGraphics** | macOS SDK | 2D描画 |
| **ImageIO** | macOS SDK | 画像入出力 |

**セキュリティステータス**: ✅ すべてのフレームワークはAppleにより継続的にメンテナンスされています。

---

## YAYA Core (C++実装)

### 外部依存関係

#### 1. nlohmann/json

- **バージョン**: 3.12.0以上推奨
- **ライセンス**: MIT License
- **用途**: JSON形式でのプロセス間通信（IPC）
- **リポジトリ**: https://github.com/nlohmann/json
- **インストール方法**:
  ```bash
  brew install nlohmann-json
  ```

**セキュリティステータス**: ✅ 最新バージョン（3.12.0、2025年4月リリース）に既知の重大な脆弱性はありません。

**既知の過去の脆弱性**:
- バージョン2.0.10以前: ヒープベースのバッファオーバーフロー脆弱性（CBOR解析時）
- **対策**: バージョン3.12.0を使用することで回避済み

### バンドル済みサードパーティコード

以下のコードは `yaya_core/third_party/yaya/` に含まれています（yaya-shiori-500からの移植）：

#### 1. MD5実装 (md5.c/md5.h)

- **用途**: YAYAの`FILEDIGEST`および`STRDIGEST`関数（MD5モード）
- **ライセンス**: BSD-3-Clause（YAYA projectより）
- **セキュリティ警告**: ⚠️ MD5は暗号学的に破られています（2004年以降）
  - **重要**: この実装は**セキュリティ目的では使用していません**
  - YAYA言語仕様との互換性のためのみ提供
  - 認証・署名検証・パスワードハッシュなどには使用禁止

#### 2. SHA-1実装 (sha1.c/sha1.h)

- **用途**: YAYAの`FILEDIGEST`および`STRDIGEST`関数（SHA-1モード）
- **ライセンス**: BSD-3-Clause（YAYA projectより）
- **セキュリティ警告**: ⚠️ SHA-1は非推奨です（2017年以降）
  - **重要**: この実装は**セキュリティ目的では使用していません**
  - YAYA言語仕様との互換性のためのみ提供
  - 認証・署名検証などには使用禁止

#### 3. CRC32実装 (crc32.c/crc32.h)

- **用途**: YAYAの`FILEDIGEST`および`STRDIGEST`関数（CRC32モード）
- **ライセンス**: BSD-3-Clause（YAYA projectより）
- **用途制限**: チェックサムのみ（暗号学的ハッシュではありません）

#### 4. POSIX Utilities (posix_utils.cpp/posix_utils.h)

- **用途**: POSIX APIラッパー（ファイル操作、エンコーディング変換など）
- **ライセンス**: BSD-3-Clause（YAYA projectより）

---

## ビルドツール依存関係

### 必須ツール

| ツール | 最小バージョン | 用途 |
|-------|--------------|------|
| **Xcode** | 16.4+ | Swiftコンパイル・アプリビルド |
| **CMake** | 3.20+ | YAYA Coreビルドシステム |
| **make** | GNU Make | CMakeからの呼び出し |
| **Clang** | 14+ (Xcode付属) | C++17コンパイル |

### インストール方法

```bash
# Xcode Command Line Tools
xcode-select --install

# CMake（Homebrew経由）
brew install cmake

# nlohmann-json
brew install nlohmann-json
```

---

## 最小システム要件

### 現在の設定

- **最小macOSバージョン**: 11.0 (Big Sur)
- **推奨macOSバージョン**: 13.0 (Ventura) 以上

### セキュリティに関する注意

⚠️ **重要**: macOS 11.0 (Big Sur)は2023年9月にサポート終了しており、セキュリティアップデートを受信していません。

**推奨事項**: 今後のリリースでは最小バージョンをmacOS 13.0 (Ventura)に引き上げることを検討してください。

---

## CI/CD依存関係

GitHub Actionsワークフロー (`.github/workflows/macOS.yml`)で使用されているツール：

| ツール | バージョン | 用途 |
|-------|-----------|------|
| `actions/checkout` | v4 | リポジトリチェックアウト |
| `maxim-lobanov/setup-xcode` | v1 | Xcode選択 |
| `actions/cache` | v4 | SwiftPMキャッシュ |
| `xcbeautify` | latest | ビルドログの整形 |

---

## セキュリティベストプラクティス

### ✅ 実施済み

1. **最小依存関係**: 外部依存関係は1つのみ（nlohmann/json）
2. **公式フレームワーク**: Appleの公式フレームワークのみ使用
3. **定期監査**: 依存関係の定期的なレビュー

### ⚠️ 検討事項

1. **バージョン固定**: `CMakeLists.txt`でnlohmann/jsonのバージョンを固定
   ```cmake
   find_package(nlohmann_json 3.12.0 REQUIRED)
   ```

2. **最小macOSバージョンの更新**:
   - 現在: macOS 11.0 (サポート終了)
   - 推奨: macOS 13.0+ (セキュリティサポート継続中)

3. **ハッシュ関数の文書化**:
   - MD5/SHA-1はYAYA互換性のみ
   - 新規コードでは使用禁止を明示

---

## 依存関係の更新方法

### nlohmann/jsonの更新

```bash
# Homebrewで最新版に更新
brew upgrade nlohmann-json

# バージョン確認
brew info nlohmann-json

# YAYA Coreを再ビルド
cd yaya_core
rm -rf build
./build.sh
```

### Xcodeの更新

```bash
# 最新のXcodeをApp Storeからインストール後
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

---

## トラブルシューティング

### nlohmann/jsonが見つからない

```bash
# パッケージが正しくインストールされているか確認
brew list nlohmann-json

# CMakeのパッケージ検索パスを確認
cmake --find-package -DNAME=nlohmann_json -DCOMPILER_ID=GNU -DLANGUAGE=CXX -DMODE=EXIST

# 再インストール
brew uninstall nlohmann-json
brew install nlohmann-json
```

### ビルドエラー: "nlohmann/json.hpp not found"

**原因**: Homebrewのインストールパスが認識されていない

**解決策**:
```bash
# Intel Mac
export CMAKE_PREFIX_PATH=/usr/local

# Apple Silicon Mac
export CMAKE_PREFIX_PATH=/opt/homebrew

# 環境変数を設定してから再ビルド
cd yaya_core
rm -rf build
./build.sh
```

---

## 参考リンク

### 公式ドキュメント

- [nlohmann/json GitHub](https://github.com/nlohmann/json)
- [nlohmann/json ドキュメント](https://json.nlohmann.me/)
- [Apple Developer - Frameworks](https://developer.apple.com/documentation/technologies)

### セキュリティ情報

- [macOS セキュリティアップデート](https://support.apple.com/ja-jp/HT201222)
- [nlohmann/json Security Policy](https://github.com/nlohmann/json/security/policy)

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|---------|
| 2025-12-11 | 1.0.0 | 初版作成 - 依存関係の完全な文書化 |

---

## お問い合わせ

依存関係やセキュリティに関する質問は以下までお問い合わせください：

📧 eight@eightman999.com
🌐 https://github.com/eightman999/Ourin
