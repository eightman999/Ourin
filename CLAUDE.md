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
   - `SstpRouter` handles request routing to SHIORI system

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