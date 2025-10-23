# YAYA Core Architecture Diagram

This document provides visual diagrams of the YAYA Core architecture.

---

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Ourin.app (Swift)                        │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │  ContentView │  │  DevToolsView│  │  Ghost Manager│         │
│  └──────┬───────┘  └──────────────┘  └──────┬───────┘         │
│         │                                     │                 │
│         └──────────────────┬──────────────────┘                 │
│                            │                                     │
│                    ┌───────▼────────┐                           │
│                    │  YayaAdapter   │ ◄── Swift IPC Client     │
│                    │   (Swift)      │                           │
│                    └───────┬────────┘                           │
└────────────────────────────┼──────────────────────────────────┘
                             │
                             │ JSON over Process I/O
                             │ (stdin/stdout, line-based)
                             │
┌────────────────────────────▼──────────────────────────────────┐
│                   yaya_core (C++ Executable)                   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │                    main.cpp                              │ │
│  │              (IPC Server - JSON Lines)                   │ │
│  └────────────────────────┬─────────────────────────────────┘ │
│                           │                                    │
│  ┌────────────────────────▼─────────────────────────────────┐ │
│  │                     YayaCore                             │ │
│  │              (Command Dispatcher)                        │ │
│  │                                                          │ │
│  │  Commands:                                               │ │
│  │    • load(ghost_root, dics[], encoding)                 │ │
│  │    • request(method, id, headers, refs[])               │ │
│  │    • unload()                                            │ │
│  └────────────────────────┬─────────────────────────────────┘ │
│                           │                                    │
│  ┌────────────────────────▼─────────────────────────────────┐ │
│  │                DictionaryManager                         │ │
│  │                                                          │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │ │
│  │  │ Loader       │  │   Parser     │  │   VM         │  │ │
│  │  │              │  │              │  │              │  │ │
│  │  │ • File I/O   │  │ • Lexer      │  │ • Execute    │  │ │
│  │  │ • UTF-8/932  │  │ • Parser     │  │ • Variables  │  │ │
│  │  │ • Validation │  │ • AST        │  │ • Functions  │  │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  │ │
│  │                                                          │ │
│  │  ┌──────────────┐  ┌──────────────┐                    │ │
│  │  │BuiltinFuncs  │  │ShioriAdapter │                    │ │
│  │  │              │  │              │                    │ │
│  │  │ • RAND()     │  │ • Request    │                    │ │
│  │  │ • STRLEN()   │  │ • Response   │                    │ │
│  │  │ • SUBSTR()   │  │ • Headers    │                    │ │
│  │  └──────────────┘  └──────────────┘                    │ │
│  └──────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Flow: Load Dictionary

```
User Action: Ghost Selection
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ YayaAdapter.swift                                           │
│   adapter.load(                                             │
│     ghostRoot: "/path/to/ghost/master",                    │
│     dics: ["aya_bootend.dic", "aya_menu.dic"],            │
│     encoding: "utf-8"                                       │
│   )                                                         │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ JSON {"cmd":"load", "ghost_root":"...", "dic":[...]}
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ yaya_core: main.cpp                                         │
│   std::getline(std::cin, line)                             │
│   YayaCore::processCommand(line)                           │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ DictionaryManager::load(dics, encoding)                     │
│                                                              │
│   FOR EACH dic_file IN dics:                                │
│     1. DictionaryLoader::readFile(path)                     │
│        ├─ Detect encoding (UTF-8/CP932)                     │
│        └─ Convert to UTF-8                                   │
│                                                              │
│     2. Lexer::tokenize(source)                              │
│        ├─ Scan characters                                    │
│        ├─ Identify tokens (keywords, operators, literals)   │
│        └─ Skip comments                                      │
│                                                              │
│     3. Parser::parse(tokens)                                │
│        ├─ Build Abstract Syntax Tree (AST)                  │
│        ├─ Validate syntax                                    │
│        └─ Extract function definitions                       │
│                                                              │
│     4. FunctionRegistry::register(functions)                │
│        └─ Store function name → AST mapping                 │
│                                                              │
│   RETURN success/failure                                     │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ JSON {"ok": true/false}
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ YayaAdapter.swift                                           │
│   return Bool (success/failure)                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Data Flow: Execute Event (GET OnBoot)

```
Event: Ghost Boot
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ YayaAdapter.swift                                           │
│   adapter.request(                                          │
│     method: "GET",                                          │
│     id: "OnBoot",                                           │
│     headers: ["Charset": "UTF-8"],                         │
│     refs: []                                                │
│   )                                                         │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ JSON {"cmd":"request", "method":"GET", "id":"OnBoot", ...}
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ yaya_core: YayaCore::processCommand()                       │
│   DictionaryManager::execute("OnBoot", [])                 │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ DictionaryManager::execute(funcName, args)                  │
│                                                              │
│   1. FunctionRegistry::find("OnBoot")                       │
│      └─ Retrieve function AST                               │
│                                                              │
│   2. VM::execute(function, args)                            │
│      ├─ Create new call frame                               │
│      ├─ Set reference[0..n] variables                       │
│      │                                                       │
│      └─ Evaluate AST nodes:                                 │
│          │                                                   │
│          ├─ Variable assignment                             │
│          │  _var = "value"                                  │
│          │  VariableStore::set("_var", "value")            │
│          │                                                   │
│          ├─ Function call                                    │
│          │  RAND(10)                                        │
│          │  BuiltinFunctions::call("RAND", [10])           │
│          │                                                   │
│          ├─ Conditional execution                           │
│          │  if condition { ... } else { ... }              │
│          │                                                   │
│          └─ String concatenation                            │
│             "\0\s[0]" + "Hello" + "\e"                      │
│             = "\0\s[0]Hello\e"                              │
│                                                              │
│   3. Return SakuraScript string                             │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ JSON {"ok": true, "status": 200, "value": "\\0\\s[0]Hello\\e"}
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ YayaAdapter.swift                                           │
│   return YayaResponse                                       │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ Ourin: SakuraScript Renderer                                │
│   Parse: \0 = Sakura scope                                  │
│          \s[0] = Surface 0                                  │
│          Hello = Text                                        │
│          \e = End                                            │
│                                                              │
│   Display in balloon                                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Component Responsibilities

### Swift Layer (Ourin.app)

```
┌─────────────────────────────────────────────────────────┐
│ YayaAdapter.swift                                       │
│                                                         │
│ Responsibilities:                                       │
│  • Launch yaya_core process                            │
│  • Manage process lifecycle                            │
│  • Encode requests to JSON                             │
│  • Decode responses from JSON                          │
│  • Handle process termination                          │
│  • Error propagation to UI                             │
│                                                         │
│ Does NOT:                                               │
│  • Parse YAYA dictionaries                             │
│  • Execute YAYA code                                    │
│  • Understand YAYA syntax                              │
└─────────────────────────────────────────────────────────┘
```

### C++ Layer (yaya_core)

```
┌─────────────────────────────────────────────────────────┐
│ main.cpp + YayaCore                                     │
│                                                         │
│ Responsibilities:                                       │
│  • Read JSON from stdin                                │
│  • Write JSON to stdout                                │
│  • Dispatch commands                                    │
│  • Top-level error handling                            │
│                                                         │
│ Does NOT:                                               │
│  • Know about Swift                                     │
│  • Access UI                                            │
│  • Manage ghost files                                   │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ DictionaryManager                                       │
│                                                         │
│ Responsibilities:                                       │
│  • Load and parse .dic files                           │
│  • Manage function registry                            │
│  • Execute YAYA functions                              │
│  • Coordinate Lexer/Parser/VM                          │
│                                                         │
│ Does NOT:                                               │
│  • Render SakuraScript                                 │
│  • Manage ghost lifecycle                              │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Lexer + Parser                                          │
│                                                         │
│ Responsibilities:                                       │
│  • Tokenize YAYA source code                           │
│  • Build Abstract Syntax Tree                          │
│  • Syntax validation                                    │
│  • Error reporting                                      │
│                                                         │
│ Does NOT:                                               │
│  • Execute code                                         │
│  • Manage variables                                     │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ VM (Virtual Machine)                                    │
│                                                         │
│ Responsibilities:                                       │
│  • Execute AST nodes                                    │
│  • Manage variables (local + global)                   │
│  • Call built-in functions                             │
│  • Handle control flow (if/while/return)               │
│  • Stack management                                     │
│                                                         │
│ Does NOT:                                               │
│  • Parse source code                                    │
│  • Load files                                           │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ BuiltinFunctions                                        │
│                                                         │
│ Responsibilities:                                       │
│  • Implement YAYA built-in functions                   │
│  • Type conversion                                      │
│  • String manipulation                                  │
│  • Random number generation                            │
│  • Array operations                                     │
│                                                         │
│ Does NOT:                                               │
│  • Parse code                                           │
│  • Manage user-defined functions                       │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ ShioriAdapter                                           │
│                                                         │
│ Responsibilities:                                       │
│  • Map SHIORI requests to YAYA functions               │
│  • Set reference[] variables                           │
│  • Format SHIORI responses                             │
│  • Handle status codes                                  │
│                                                         │
│ Does NOT:                                               │
│  • Execute YAYA code directly                          │
│  • Parse dictionaries                                   │
└─────────────────────────────────────────────────────────┘
```

---

## Implementation Status

```
Component             Status      Phase
─────────────────────────────────────────
main.cpp              ✅ Done     -
YayaCore              ✅ Done     -
YayaAdapter.swift     ✅ Done     -
DictionaryManager     ⚠️  Stub    Phase 1
Lexer                 ❌ TODO     Phase 1 Week 1
Parser                ❌ TODO     Phase 1 Week 1-2
AST                   ❌ TODO     Phase 1 Week 1-2
VM                    ❌ TODO     Phase 1 Week 2
Value                 ❌ TODO     Phase 1 Week 2
VariableStore         ❌ TODO     Phase 1 Week 2
FunctionRegistry      ❌ TODO     Phase 1 Week 2
BuiltinFunctions      ❌ TODO     Phase 1 Week 2-3
ShioriAdapter         ❌ TODO     Phase 1 Week 3
Encoding Support      ❌ TODO     Phase 1 Week 1
Error Handling        ❌ TODO     Phase 1 Week 3
Unit Tests            ❌ TODO     Phase 1 Week 1-3
─────────────────────────────────────────
Arrays/Dicts          ❌ TODO     Phase 2
Loops                 ❌ TODO     Phase 2
Regex                 ❌ TODO     Phase 2
Performance Opt       ❌ TODO     Phase 2-3
```

---

## Directory Layout

```
/home/runner/work/Ourin/Ourin/
│
├── yaya_core/                      # C++ YAYA Core Module
│   ├── CMakeLists.txt              # Build config (Universal Binary)
│   ├── README.md                   # Quick start guide
│   ├── .gitignore                  # Build artifacts exclusion
│   │
│   ├── src/                        # Source code
│   │   ├── main.cpp                # ✅ IPC entry point
│   │   ├── YayaCore.{cpp,hpp}      # ✅ Command dispatcher
│   │   ├── DictionaryManager.{cpp,hpp}  # ⚠️ Stub only
│   │   ├── Lexer.{cpp,hpp}         # ❌ TODO Phase 1
│   │   ├── Parser.{cpp,hpp}        # ❌ TODO Phase 1
│   │   ├── AST.{cpp,hpp}           # ❌ TODO Phase 1
│   │   ├── VM.{cpp,hpp}            # ❌ TODO Phase 1
│   │   ├── Value.{cpp,hpp}         # ❌ TODO Phase 1
│   │   ├── VariableStore.{cpp,hpp} # ❌ TODO Phase 1
│   │   ├── FunctionRegistry.{cpp,hpp}  # ❌ TODO Phase 1
│   │   ├── BuiltinFunctions.{cpp,hpp}  # ❌ TODO Phase 1
│   │   ├── ShioriAdapter.{cpp,hpp}     # ❌ TODO Phase 1
│   │   └── Utils.{cpp,hpp}         # ❌ TODO Phase 1
│   │
│   ├── tests/                      # ❌ TODO Phase 1
│   │   ├── lexer_test.cpp
│   │   ├── parser_test.cpp
│   │   ├── vm_test.cpp
│   │   └── integration_test.cpp
│   │
│   └── build/                      # Git-ignored build directory
│
├── Ourin/Yaya/                     # Swift Integration
│   └── YayaAdapter.swift           # ✅ Process manager + IPC client
│
├── docs/                           # Documentation
│   ├── YAYA_CORE_INVESTIGATION_REPORT.md      # 🆕 調査報告
│   ├── YAYA_CORE_IMPLEMENTATION_PLAN.md       # 🆕 実装計画
│   ├── YAYA_CORE_TECHNICAL_SPEC.md            # 🆕 技術仕様
│   ├── YAYA_CORE_EXECUTIVE_SUMMARY.md         # 🆕 エグゼクティブサマリー
│   ├── YAYA_CORE_ARCHITECTURE.md              # 🆕 This file
│   ├── OURIN_YAYA_ADAPTER_SPEC_1.0M.md        # ✅ IPC仕様
│   └── OURIN_USL_1.0M_SPEC.md                 # ✅ USL仕様
│
└── emily4/                         # Test Data
    └── ghost/master/*.dic          # 50+ YAYA dictionary files
```

---

**Document**: Architecture Diagram  
**Created**: 2025-10-16  
**Project**: Ourin (eightman999/Ourin)
