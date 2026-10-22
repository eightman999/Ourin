# Ourin /  桜鈴

![Ourin Logo](logo/ourin_512x.png)

Macネイティブの伺かベースウェア

## 全体構造

Ourinは、伺かのベースウェアとして次の層を分離して実装しています。

```text
Ghost / Shell / Balloon
          │
GhostManager ── GhostShioriRuntime ──┬─ YayaAdapter ── yaya_core
          │                           ├─ SatoriAdapter ── satori_core
          │                           └─ Native SHIORI ── ShioriLoader
          │
     SHIORI 3.0 / SSTP / Web / XPC
          │
       SAORI / PLUGIN（SaoriHost）
```

SHIORIの要求・応答は`GhostShioriRuntime`に集約し、ベースウェアのイベント配送とSSTPブリッジは実装言語に依存しません。YAYAは既存の`yaya_core`を継続利用し、里々は`SatoriAdapter`経由で独立した`satori_core`へ接続します。SAORIはukatech/csaoriの境界（入力の文字コード、戻り値、モジュールのロード・アンロード）に合わせて`SaoriHost`へ整理します。

仕様上の基準は[UKADOC SHIORI/3.0](https://ssp.shillest.net/ukadoc/manual/spec_shiori3.html)、[SSTP](https://ssp.shillest.net/)、[AYAYA](https://emily.shillest.net/ayaya/)です。

---

## 📄 License / ライセンス

[![Source code: Apache-2.0](https://img.shields.io/badge/source-Apache--2.0-blue.svg)](LICENSES/Apache-2.0.txt)
[![Documentation: CC BY-SA 4.0](https://img.shields.io/badge/docs-CC%20BY--SA%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)

- Original Ourin source code: [Apache License 2.0](LICENSES/Apache-2.0.txt)
- Original project documentation: [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
- Ourin独自ソースコード: [Apache License 2.0](LICENSES/Apache-2.0.txt)
- Ourin独自ドキュメント: [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/deed.ja)

Third-party components and bundled content retain their original licenses.
第三者コンポーネントおよび同梱コンテンツは、元のライセンスを維持します。

### 📦 Components and Exceptions / コンポーネント別ライセンス

- Integrated YAYA Core: BSD-3-Clause ([YAYA-shiori/yaya-shiori](https://github.com/YAYA-shiori/yaya-shiori) に準拠)
  同梱 YAYA Core: BSD-3-Clause（上流ライセンスと改変部分の表示を維持）
- Satori runtime: BSD-2-Clause ([ukatech/satoriya-shiori](https://github.com/ukatech/satoriya-shiori) を参照）
  里々ランタイムは固定版SATORIを`satori_core` helperとして同梱します。
- SAORI host boundary: modified BSD + ukagaka exception ([ukatech/csaori](https://github.com/ukatech/csaori) に準拠)
  SAORIホストの実装・互換性監査ではcsaoriの入力/出力構造と文字コード規則を基準にします。
- Default ghost (Rin): same license as Ourin; art is a placeholder  
  既定ゴースト（Rin）: Ourin本体と同じライセンス。立ち絵は仮絵
- Migrator (DevTools): uses **Ghidra** (Apache 2.0) as an external tool — not bundled  
  Migrator（DevTools）: **Ghidra**（Apache 2.0）を外部ツールとして利用（同梱なし）

For the full texts, open the app and navigate to About → "ライセンスを表示…".
各文面はアプリ内の About → 「ライセンスを表示…」から参照できます。

The detailed scope and precedence rules are documented in [LICENSE](LICENSE).
適用範囲と優先順位の詳細は [LICENSE](LICENSE) を参照してください。

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

#### 里々 Core / Satori Core

`satori_core`は固定版SATORIをUniversal 2でビルドし、`SatoriAdapter`とUTF-8 JSON Linesで通信します。手動ビルドは`cd satori_core && ./build.sh`です。上流のtag/commit、ライセンス、ローカルpatchは`satori_core/UPSTREAM.md`と`PATCHES.md`に記録しています。

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

詳細については [`docs/DEPENDENCIES_ja-jp.md`](docs/DEPENDENCIES_ja-jp.md) を参照してください。
For details, see [`docs/DEPENDENCIES_en-us.md`](docs/DEPENDENCIES_en-us.md).

### Satori / SAORI

里々の仕様・実装参照は[ukatech/satoriya-shiori](https://github.com/ukatech/satoriya-shiori)を、SAORI/PLUGINのホスト境界は[ukatech/csaori](https://github.com/ukatech/csaori)を一次参照とします。上流コードを取り込む場合は、リビジョンとライセンスファイルを同時に固定します。

### Migrator (DevTools) / Ghidra

Ourin Migrator は SSP 互換 Windows DLL/EXE の解析に **Ghidra** を使用します。
Ghidra は同梱されず、ユーザーが別途インストールした `analyzeHeadless` を外部プロセスとして呼び出します。

The Ourin Migrator uses **Ghidra** to analyze SSP-compatible Windows DLLs/EXEs.
Ghidra is not bundled; Ourin invokes the user-installed `analyzeHeadless` as a separate process.

- **Ghidra**: Apache License 2.0（NSA） / Apache License 2.0 (NSA)
- 公式サイト / Official: https://ghidra-sre.org/

通常起動時は Ghidra や Java に依存しません（DevTools の Migrator 機能を使用する場合のみ）。
Normal operation does not depend on Ghidra or Java (only when using the DevTools Migrator feature).

---

## 🔌 外部 SSTP と Claude Code 連携 / External SSTP & Claude Code Integration

### 受信口 / Endpoints

| 経路 / Transport | 既定 / Default | 宛先 / Address |
|---|---|---|
| HTTP SSTP | 無効 / off | `POST http://127.0.0.1:9801/api/sstp/v1`（本文は生の SSTP / raw SSTP body） |
| 生 SSTP / raw TCP | 無効 / off | `127.0.0.1:9801`（同一ポートで多重化 / multiplexed） |
| Distributed IPC | 有効 / on | 通知 `jp.ourin.sstp.request`（`id`, `request`）→ `jp.ourin.sstp.response`（`id`, `response`） |
| XPC | 有効 / on | mach service `jp.ourin.sstp` |

- HTTP／TCP は設定の `OurinExternalSSTPAllowHTTP` / `OurinExternalSSTPAllowTCP` で有効化し、Ourin を再起動する。待受は `127.0.0.1` のみ。
  Enable with these preference keys and restart Ourin; listeners bind to `127.0.0.1` only.
- 設定は `~/Library/Preferences/furin-lab.Ourin.plist` から読まれる。`defaults write furin-lab.Ourin …` はコンテナ側の plist に書くことがあるため、フルパスを指定する。
  Ourin reads `~/Library/Preferences/furin-lab.Ourin.plist`; `defaults write furin-lab.Ourin …` may write the container plist instead, so pass the full path:
  ```bash
  defaults write "$HOME/Library/Preferences/furin-lab.Ourin.plist" OurinExternalSSTPAllowHTTP -bool true
  ```
- `Origin` ヘッダ付きの HTTP 要求はブラウザ由来として `SecurityLevel: external` になり、外部セキュリティレベルを許可していなければ `420 Refuse`。ローカルのツールは `Origin` を付けずに送る。
  Requests with an `Origin` header are treated as browser-originated (`external`) and refused with `420` unless external security level is allowed; local tools should omit `Origin`.

### Claude Code からの実況 / Narration from Claude Code

Claude Code の mod（`ghost-narrator`、リポジトリ外）は作業の出来事を次の形で送る。SSP 互換の `SEND` なので SSP でも動く。
The Claude Code mod `ghost-narrator` (outside this repository) sends work events as SSP-compatible `SEND` requests:

```
SEND SSTP/1.4
Sender: Claude Code
Charset: UTF-8
Event: OnClaudeCode
Reference0: <kind>
Reference1: <detail>
Script: <fallback script>\e
```

- `Reference0`: `start` / `prompt` / `edit` / `run` / `pass` / `fail` / `denied` / `done` / `aborted` / `say`
- `Reference1`: コマンド・ファイル名などの詳細 / detail such as the command or file name
- ゴーストが `OnClaudeCode` を処理すればその台詞、処理しなければ `Script` を再生する。ゴースト辞書で `Reference0` ごとに反応を書ける。
  If the ghost handles `OnClaudeCode` its own script plays; otherwise the `Script` fallback plays.
- デスクトップアプリの Claude Code では、`done` / `fail` / `denied` / `aborted` の台詞にセッションへ戻る選択肢が付く。
  In the Claude desktop app, `done` / `fail` / `denied` / `aborted` lines carry a choice that jumps back to the session:
  `\q[セッションを開く,script:\![open,browser,claude://code/continue?session=local_…]]`

### 互換性の修正 / Compatibility fixes

- オフセット付き element／overlay が上下鏡映される問題（顔パーツが下半身に出る）を修正 / Offset element/overlay parts were mirrored vertically.
- HTTP SSTP が CRLF ヘッダを分割できず常に `411` を返していた問題、および `SecurityOrigin` 挿入で最終ヘッダが連結される問題を修正 / HTTP SSTP always returned `411`; injected security headers were concatenated onto the last header.
- 保存位置が画面外でも復元していた問題を修正（可視領域へクランプ）/ Saved window positions are clamped into the visible screen.
- `\![move]` を UKADOC どおりの座標系に変更（`--base` 既定は `screen`＝モニタ左上原点、+Y は下向き、`--move-offset` は移動窓上の点）/ `\![move]` now follows UKADOC coordinates.
- `EXECUTE GetName`・`currentghost.*` が起動中のゴースト（descript.txt の `name`）を返すよう修正 / `GetName` and `currentghost.*` now reflect the running ghost.

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
