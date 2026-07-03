# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ourin (桜鈴) is a macOS-native ukagaka baseware (伺かベースウェア) - a desktop companion/assistant application similar to the Windows "ukagaka" ecosystem. It implements various Japanese desktop character standards including SHIORI, SSTP, and plugin systems.

## Build & Test Commands

This is an Xcode project. Use these commands:

- **Build**: `xcodebuild -project Ourin.xcodeproj -scheme Ourin build`
- **Test**: `xcodebuild -project Ourin.xcodeproj -scheme Ourin test`
- **Run**: Open `Ourin.xcodeproj` in Xcode and run, or `xcodebuild -project Ourin.xcodeproj -scheme Ourin build && open build/Release/Ourin.app`

For running single tests, use Xcode's test navigator or:
`xcodebuild -project Ourin.xcodeproj -scheme Ourin -only-testing:OurinTests/TestClassName/testMethodName test`

## Architecture Overview

### Core Systems

1. **FMO (Forged Memory Object)** - `FMO/`
   - Cross-process shared memory system using POSIX shared memory and named semaphores
   - `FmoManager` coordinates `FmoMutex` and `FmoSharedMemory`
   - Used for single-instance enforcement and process communication

2. **SHIORI System** - `SSTP/`, `USL/`
   - Core ghost AI/response system following SHIORI 3.0M specification
   - `SSTPDispatcher` handles SSTP protocol requests
   - `ShioriLoader` manages dynamic loading of SHIORI modules

3. **Plugin Architecture** - `PluginHost/`
   - Dynamic plugin loading system supporting `.plugin` and `.bundle` files
   - `PluginRegistry` discovers and manages plugin lifecycle
   - Plugins searched in app bundle and standard locations

4. **External Server** - `ExternalServer/`
   - Multi-protocol server supporting TCP, HTTP, and XPC communication
   - `OurinExternalServer` coordinates `SstpTcpServer`, `SstpHttpServer`, `XpcDirectServer`
   - Raw SSTP from all channels is parsed by `SSTPParser` and handled by `SSTP/SSTPDispatcher` (single SSTP stack; the old `SstpRouter` was removed)

5. **Event System** - `SHIORIEvents/`, `PluginEvent/`
   - System event monitoring (sleep, display, input, network, etc.)
   - `EventBridge` coordinates system observers and dispatches to SHIORI
   - `PluginEventDispatcher` distributes events to loaded plugins

6. **NAR Package System** - `NarInstall/`
   - Handles installation of NAR (ghost package) files
   - `LocalNarInstaller` extracts and installs packages
   - Integrated with file association and drag-drop

7. **Ghost Runners** - `Yaya/`
   - `YayaAdapter` provides compatibility with YAYA ghost format
   - Handles ghost loading, execution, and unloading

### Key Integration Points

- `OurinApp.swift`: Main app entry point, coordinates all subsystems
- `ContentView.swift`: Primary SwiftUI interface
- `DevToolsView.swift`: Developer tools interface for debugging
- All major systems initialized in `AppDelegate.applicationDidFinishLaunching`

### File Organization

- `Ourin/`: Main application code
- `OurinTests/`: Unit tests using Swift Testing framework  
- `docs/`: Extensive specification documentation for all protocols
- `Samples/`: Reference implementations and examples
- Source organized by functional area (FMO, SSTP, PluginHost, etc.)

### Protocol Specifications

The `docs/` directory contains comprehensive specifications:
- SHIORI 3.0M, SSTP 1.xM, Plugin 2.0M protocols
- Ourin-specific extensions and adaptations
- Implementation guides for various subsystems

This codebase implements a complex multi-protocol system for desktop companions with extensive plugin support, cross-process communication, and compatibility with existing ukagaka ecosystem standards.

## yaya_core (C++実装)

### 概要
`yaya_core/` ディレクトリにはC++製のYAYA言語パーサーとVMが含まれています（ヘルパープロセスとして JSON line IPC で Swift 側と通信）。

### 重要パス
- `yaya_core/src/`: C++ソースファイル（Lexer/Parser/VM/DictionaryManager/YayaCore）
- `yaya_core/CMakeLists.txt`: CMake設定（nlohmann_json, iconv に依存）
- `yaya_core/build.sh`: ビルドスクリプト
- ゴーストデータ: `~/Library/Containers/furin-lab.Ourin/Data/Library/Application Support/Ourin/ghost/`

### デバッグログ
stderr出力で以下のプレフィックスを使用:
- `[Parser]`: パーサー関連
- `[VM]`: 仮想マシン実行
- `[DictionaryManager]`: 辞書ファイル読み込み

### よくあるエラー
- `Expected '{' after function name`: 関数定義の構文エラー
- `Expected '=' in assignment`: 代入文の構文エラー
- `Unexpected token '++'`: インクリメント演算子の処理

### ビルドコマンド
```bash
cd yaya_core && ./build.sh
```

## 参考リソース
- **SHIORI 3.0仕様:** https://ssp.shillest.net/ukadoc/manual/spec_shiori3.html
- **桜スクリプト:** https://ssp.shillest.net/ukadoc/manual/list_sakura_script.html
- **プロパティシステム:** https://ssp.shillest.net/ukadoc/manual/list_propertysystem.html
- **YAYA言語:** http://usada.sakura.vg/contents/shiori.html

## Multi-agent orchestration workflow

You are the technical lead and orchestrator.

Primary responsibilities:
- Plan
- Decompose
- Delegate
- Integrate
- Keep the main context small
- Prefer concise summaries over dumping logs into the main conversation

Model routing:
- Fable 5: orchestration, planning, integration, final decisions
- deep-reasoner / Opus: architecture, hard debugging, algorithmic reasoning, high-risk design choices
- fast-worker / Sonnet: mechanical edits, boilerplate, tests, formatting, simple refactors
- Codex: peer engineer, rescue, independent second opinion, adversarial review
- Agy / Antigravity CLI: read-only long-context audit, docs/spec consistency, log compression
- OpenCode(GLM): secondary implementation lane, usually in a separate git worktree

Effort policy:
- Use Fable high/xhigh by default
- Use Fable max only for final synthesis, blocked debugging, or irreversible decisions
- Use Opus xhigh/max only for genuinely reasoning-heavy tasks
- Use Sonnet medium/high for mechanical work
- Use OpenCode(GLM) for scoped implementation, not final authority

Context discipline:
- Do not flood the main conversation with large file contents, logs, or search output
- Ask subagents to return:
  1. conclusion
  2. evidence
  3. changed files, if any
  4. risks
  5. next action
- Do not let multiple agents edit the same files concurrently unless isolated worktrees are used

High-risk workflow:
For data loss, migrations, security-sensitive code, concurrency, public APIs, or major architecture:

1. Ask deep-reasoner / Opus independently
2. Ask Codex independently
3. Ask Agy to check assumptions and documentation consistency
4. Optionally ask OpenCode(GLM) for an isolated implementation attempt
5. Fable compares all outputs and chooses the minimal safe path

Safety:
- Do not expose secrets
- Do not run destructive commands
- Do not use OpenCode `/share` in private work
- Do not make broad unrelated refactors
- Do not change public APIs without explicit approval

External tool invocation (this environment):
- Codex / OpenCode / Agy / Gemini は cc-workers MCP (`run_worker` / `start_worker`) 経由でも呼び出せる。
  長時間ジョブは `start_worker` + `job_status` を使い、メイン会話にログを流さない。
- 監査・検証・敵対的レビューの定型プロンプトは worker-audit スキルを使う。
