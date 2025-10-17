# YAYA Core - macOS Native YAYA Interpreter

**Version**: 0.1.0 (Under Development)  
**Status**: Phase 1 - Foundation  
**Platform**: macOS (Universal Binary: arm64 + x86_64)  
**License**: BSD-3-Clause

---

## Overview

YAYA Core is a native macOS implementation of the YAYA scripting language interpreter for ukagaka/ghost desktop companions. It enables YAYA-based ghosts to run on macOS without dependency on Windows DLLs.

### Features

- ✅ **JSON-based IPC**: Line-oriented JSON communication via stdin/stdout
- ✅ **Universal Binary**: Supports both Apple Silicon (arm64) and Intel (x86_64)
- ✅ **UTF-8/CP932**: Automatic character encoding detection and conversion
- 🚧 **YAYA Language**: Full YAYA script interpretation (in progress)
- 🚧 **SHIORI/3.0M**: Complete SHIORI protocol compliance (in progress)

### Current Status

**Implemented**:
- [x] IPC framework (main.cpp, YayaCore)
- [x] JSON message parsing
- [x] Command dispatch (load/request/unload)
- [x] CMake build system with Universal Binary support

**In Progress** (Phase 1):
- [ ] Dictionary file parser (Lexer + Parser)
- [ ] YAYA Virtual Machine (VM)
- [ ] Built-in functions (RAND, STRLEN, etc.)
- [ ] SHIORI adapter

**Planned** (Phase 2+):
- [ ] Arrays and dictionaries
- [ ] Regular expressions
- [ ] SAORI plugin support
- [ ] Performance optimizations

---

## Quick Start

### Prerequisites

- macOS 13.0+ (Ventura or later)
- CMake 3.20+
- C++17 compatible compiler (Clang 14+)
- nlohmann/json library

### Building

```bash
# Install dependencies (using Homebrew)
brew install cmake nlohmann-json

# Configure and build
cd yaya_core
mkdir build && cd build
cmake ..
make

# Verify build
./yaya_core --version  # (when implemented)
```

### Testing

```bash
# Run unit tests (when implemented)
cd build
ctest --verbose

# Manual IPC test
echo '{"cmd":"load","ghost_root":"/path/to/ghost","dic":["test.dic"],"encoding":"utf-8"}' | ./yaya_core
```

---

## Architecture

```
yaya_core (Executable)
│
├── main.cpp ─────────────── Entry point (stdin/stdout IPC)
│
├── YayaCore ────────────── Command dispatcher
│   └── processCommand()
│
├── DictionaryManager ───── Dictionary loading & execution
│   ├── Lexer ──────────── Tokenization
│   ├── Parser ─────────── AST construction
│   └── VM ─────────────── Script execution
│
├── ShioriAdapter ───────── SHIORI/3.0M protocol handler
│
└── BuiltinFunctions ────── YAYA built-in functions
```

---

## IPC Protocol

### Request Format (stdin)

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

### Response Format (stdout)

**Success**:
```json
{
  "ok": true,
  "status": 200,
  "headers": {"Charset": "UTF-8"},
  "value": "\\0\\s[0]Hello from YAYA\\e"
}
```

**Error**:
```json
{
  "ok": false,
  "status": 500,
  "error": "Failed to load dictionary: File not found"
}
```

---

## Development

### Project Structure

```
yaya_core/
├── CMakeLists.txt          # Build configuration
├── README.md               # This file
├── src/
│   ├── main.cpp            # Entry point
│   ├── YayaCore.{cpp,hpp}  # Core controller
│   ├── DictionaryManager.{cpp,hpp}  # Dictionary management (stub)
│   ├── Lexer.{cpp,hpp}     # (TODO) Tokenizer
│   ├── Parser.{cpp,hpp}    # (TODO) Parser
│   ├── AST.{cpp,hpp}       # (TODO) Abstract Syntax Tree
│   ├── VM.{cpp,hpp}        # (TODO) Virtual Machine
│   ├── Value.{cpp,hpp}     # (TODO) Value type
│   ├── BuiltinFunctions.{cpp,hpp}  # (TODO) Built-in functions
│   └── ShioriAdapter.{cpp,hpp}     # (TODO) SHIORI adapter
├── tests/                  # (TODO) Unit tests
│   ├── lexer_test.cpp
│   ├── parser_test.cpp
│   └── vm_test.cpp
└── docs/                   # Documentation
    ├── IMPLEMENTATION_PLAN.md
    └── TECHNICAL_SPEC.md
```

### Code Style

- **C++ Standard**: C++17
- **Naming**: 
  - Classes: `PascalCase`
  - Functions: `camelCase()`
  - Variables: `snake_case_`
  - Constants: `UPPER_CASE`
- **Formatting**: 4 spaces, no tabs
- **Comments**: English for code, Japanese for user-facing messages

### Contributing

1. Read `docs/YAYA_CORE_IMPLEMENTATION_PLAN.md` for roadmap
2. Follow the existing code structure
3. Add unit tests for new features
4. Ensure Universal Binary compatibility (test on both Intel and Apple Silicon if possible)

---

## Integration with Ourin

YAYA Core is designed to be launched as a helper executable by the Ourin app:

```swift
// Ourin/Yaya/YayaAdapter.swift
let adapter = YayaAdapter()
adapter.load(ghostRoot: ghostURL, dics: ["aya_bootend.dic"], encoding: "utf-8")
let response = adapter.request(method: "GET", id: "OnBoot", refs: [])
```

See `Ourin/Yaya/YayaAdapter.swift` for the Swift integration layer.

---

## Reference Implementation

This implementation references the official YAYA interpreter:

- **YAYA (C++)**: https://github.com/YAYA-shiori/yaya-shiori
- **License**: BSD-3-Clause
- **Approach**: Reimplementation optimized for macOS, not a direct port

---

## Documentation

- [Implementation Plan](../docs/YAYA_CORE_IMPLEMENTATION_PLAN.md) - Detailed roadmap and architecture
- [Technical Specification](../docs/YAYA_CORE_TECHNICAL_SPEC.md) - Language specification and API reference
- [YAYA Adapter Spec](../docs/OURIN_YAYA_ADAPTER_SPEC_1.0M.md) - IPC protocol specification

---

## License

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

**Maintainer**: Ourin Project  
**Contact**: https://github.com/eightman999/Ourin

---

## Xcode Integration

### Quick Setup

1. Build yaya_core:
   ```bash
   cd yaya_core
   ./build.sh
   ```

2. In Xcode, add to Ourin target's "Copy Files" build phase:
   - Destination: "Executables"
   - File: `yaya_core/build/yaya_core`

3. The binary will be accessible via:
   ```swift
   Bundle.main.url(forAuxiliaryExecutable: "yaya_core")
   ```

### Automated Build (Optional)

Add a "Run Script" build phase before "Copy Files":

```bash
cd "${SRCROOT}/yaya_core"
if [ ! -f "build/yaya_core" ] || [ "src" -nt "build/yaya_core" ]; then
    ./build.sh
fi
```

This automatically rebuilds yaya_core when source files change.

