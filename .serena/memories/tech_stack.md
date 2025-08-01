# Tech Stack and Build System

## Primary Technologies
- **Swift** - Main programming language for application logic
- **SwiftUI** - Primary UI framework for modern macOS interfaces
- **AppKit** - Native macOS integration and window management
- **C** - Low-level system integration (FMO bridge, POSIX shared memory)
- **Objective-C** - Legacy system integration where needed

## Build System
- **Xcode project** (`.xcodeproj`) - Native macOS build system
- **xcodebuild** - Command-line build tool
- No external package managers (npm, cargo, etc.)
- Swift Package Manager used in sample projects only

## Testing Framework
- **Swift Testing** - Modern Swift testing framework (`import Testing`)
- Test files located in `OurinTests/` directory
- UI tests in `OurinUITests/` directory

## System Integration
- **POSIX shared memory** - Inter-process communication
- **Named semaphores** - Process synchronization
- **IOKit** - Hardware/system state monitoring
- **ApplicationServices** - System-level integrations