# Ourin /  桜鈴

![Ourin Logo](logo/ourin_512x.png)

Macネイティブの伺かベースウェア

---

## 📄 License / ライセンス

[![License: CC BY-NC-SA 4.0](https://img.shields.io/badge/License-BY--NC--SA%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by-nc-sa/4.0/)

This project is licensed under the
[Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/).

このプロジェクトは
[クリエイティブ・コモンズ 表示-非営利-継承 4.0 国際ライセンス（CC BY-NC-SA 4.0）](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.ja)
のもとで提供されています。

---

### ✅ You are free to / 許可されていること

- **Share / 共有**: 複製・再配布できます  
- **Adapt / 改変**: リミックス・改変・派生利用ができます

As long as you follow these terms:  
以下の条件を守る限りにおいて：

- **Attribution / 表示**: 適切なクレジットの表示が必要です  
- **NonCommercial / 非営利**: 営利目的での利用は禁止されています  
- **ShareAlike / 継承**: 改変後も同一ライセンスでの公開が必要です

---

### 💼 Commercial Use / 商用利用について

If you wish to use this work for **commercial purposes**,  
please contact one of the copyright holders below.

この作品を**商用利用したい場合**は、以下の著作権者にご連絡ください。

#### 📧 Contact / 連絡先

- **eightman**： [eight@eightman999.com](mailto:eight@eightman999.com)  
- **風鈴ラボ / Furin Lab**： [contact@furinlab.com](mailto:contact@furinlab.com)

---

## 🔗 License Link / ライセンスリンク

- [Full License Text (EN)](https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode)  
- [ライセンス全文（日本語訳）](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.ja)

---

### 📦 Components and Exceptions / コンポーネント別ライセンス

- Ourin baseware: CC BY-NC-SA 4.0  
  Ourin ベースウェア: CC BY-NC-SA 4.0
- Integrated YAYA Core: CC BY-NC-SA 4.0  
  同梱 YAYA Core: CC BY-NC-SA 4.0
- Default ghost (Emily/Phase4.5): CC BY-NC 4.0  
  既定ゴースト（Emily/Phase4.5）: CC BY-NC 4.0

For the full texts, open the app and navigate to About → "ライセンスを表示…".
各文面はアプリ内の About → 「ライセンスを表示…」から参照できます。

---

## 🚀 開発環境のセットアップ / Development Setup

### 必要な環境 / Requirements

- **macOS**: 13.0 (Ventura) 以上 / macOS 13.0 (Ventura) or later
- **Xcode**: 16.4 以上 / Xcode 16.4 or later
- **CMake**: 3.20 以上 / CMake 3.20 or later
- **Homebrew**: パッケージ管理用 / For package management

### 依存関係のインストール / Installing Dependencies

#### 1. Homebrew経由でのインストール / Install via Homebrew

```bash
# CMakeとnlohmann-jsonライブラリをインストール
# Install CMake and nlohmann-json library
brew install cmake nlohmann-json
```

#### 2. Xcode Command Line Toolsの確認 / Verify Xcode Command Line Tools

```bash
xcode-select --install
```

### ビルド手順 / Build Instructions

#### メインアプリケーション / Main Application

```bash
# Xcodeプロジェクトを開く / Open Xcode project
open Ourin.xcodeproj

# またはコマンドラインでビルド / Or build from command line
xcodebuild -project Ourin.xcodeproj -scheme Ourin build
```

#### YAYA Coreのビルド / Building YAYA Core

YAYA Core（C++製のYAYAインタープリター）は自動的にビルドされますが、
手動でビルドする場合は以下のコマンドを実行してください。

The YAYA Core (C++ YAYA interpreter) is built automatically, but you can build it manually:

```bash
cd yaya_core
./build.sh
```

詳細については `yaya_core/README.md` を参照してください。
For details, see `yaya_core/README.md`.

### テストの実行 / Running Tests

```bash
# すべてのテストを実行 / Run all tests
xcodebuild -project Ourin.xcodeproj -scheme Ourin test

# 特定のテストのみ実行 / Run specific test
xcodebuild -project Ourin.xcodeproj -scheme Ourin \
  -only-testing:OurinTests/TestClassName/testMethodName test
```

---

## 📚 依存関係について / About Dependencies

### メインアプリケーション / Main Application

Ourinのメインアプリケーションは**外部依存関係を持ちません**。
Appleのシステムフレームワーク（Foundation、AppKit、SwiftUIなど）のみを使用しています。

The main Ourin application has **no external dependencies**.
It only uses Apple's system frameworks (Foundation, AppKit, SwiftUI, etc.).

### YAYA Core

YAYA CoreはC++で実装されており、以下の依存関係があります：

YAYA Core is implemented in C++ and has the following dependencies:

- **nlohmann/json** (3.12.0+): JSONパーサー（IPC通信用） / JSON parser (for IPC communication)
- **バンドル済みコード / Bundled code**: MD5、SHA-1、CRC32実装（YAYA互換性のため） / MD5, SHA-1, CRC32 implementations (for YAYA compatibility)

詳細については [`docs/DEPENDENCIES.ja.md`](docs/DEPENDENCIES.ja.md) を参照してください。
For details, see [`docs/DEPENDENCIES.ja.md`](docs/DEPENDENCIES.ja.md).

---

## 📖 ドキュメント / Documentation

- [CLAUDE.md](CLAUDE.md) - Claude Codeのための開発ガイド / Development guide for Claude Code
- [docs/](docs/) - 技術仕様書とプロトコルドキュメント / Technical specifications and protocol documentation
- [yaya_core/README.md](yaya_core/README.md) - YAYA Coreの詳細ドキュメント / YAYA Core detailed documentation

---

## 🔒 セキュリティについて / Security

セキュリティに関する懸念事項や脆弱性を発見した場合は、
公開のissueではなく、直接開発者にご連絡ください。

If you discover any security concerns or vulnerabilities,
please contact the developers directly rather than opening a public issue.

📧 [eight@eightman999.com](mailto:eight@eightman999.com)
