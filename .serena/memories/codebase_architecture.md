# Codebase Architecture

## Directory Structure
```
Ourin/                     # Main application source
├── FMO/                   # Forged Memory Object (shared memory system)
├── SSTP/                  # SSTP protocol implementation
├── PluginHost/            # Plugin loading and management
├── ExternalServer/        # Multi-protocol server system
├── SHIORIEvents/          # System event monitoring
├── PluginEvent/           # Plugin event dispatching
├── NarInstall/            # NAR package installation
├── Yaya/                  # YAYA ghost compatibility
├── USL/                   # SHIORI system integration
├── DevTools/              # Developer tools interface
├── SakuraScript/          # Script parsing and execution
├── Balloon/               # UI balloon system
├── Property/              # Configuration management
├── Web/                   # Web-related functionality
├── HeadlineHost/          # Headline system
└── ResourceBridge/        # Resource management
```

## Core Systems

### 1. FMO (Forged Memory Object)
- Cross-process shared memory using POSIX shared memory
- `FmoManager` coordinates `FmoMutex` and `FmoSharedMemory`
- C bridge functions in `FmoBridge.h/.c`

### 2. SHIORI System
- Core AI/response system following SHIORI 3.0M specification
- `SSTPDispatcher` handles protocol requests
- Dynamic module loading support

### 3. Plugin Architecture
- `.plugin` and `.bundle` file support
- `PluginRegistry` manages lifecycle
- Event dispatching to plugins

### 4. External Server
- Multi-protocol: TCP, HTTP, XPC
- `SstpRouter` handles request routing
- Server coordination via `OurinExternalServer`

## Entry Points
- `main.swift` - Application bootstrap
- `OurinApp.swift` - SwiftUI App struct with AppDelegate
- `ContentView.swift` - Main application UI