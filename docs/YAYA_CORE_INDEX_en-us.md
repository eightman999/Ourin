# YAYA Core Documentation Index

**Last Updated**: 2026-06-27
**Status**: Historical investigation document; superseded by current implementation status

> **Status correction:** this document records the 2025 pre-implementation
> investigation state. The current `yaya_core` contains a C++ parser/VM,
> dictionary loading, CP932/UTF-8 handling, SHIORI IPC, and broad built-in
> function coverage. It is still partial rather than 100% faithful. Use
> [`../yaya_core/IMPLEMENTATION_STATUS.md`](../yaya_core/IMPLEMENTATION_STATUS.md)
> and [`AUDITS_COMPLETED.md`](AUDITS_COMPLETED.md) / [`AUDITS_TODO.md`](AUDITS_TODO.md) for current status.

---

## 📋 Quick Navigation

### For Decision Makers
- **[Executive Summary](YAYA_CORE_EXECUTIVE_SUMMARY.md)** (English, 7 min read)
  - TL;DR of findings and recommendations
  - Timeline and budget overview
  - Key technical decisions

### For Project Managers
- **[Investigation Report](YAYA_CORE_INVESTIGATION_REPORT.md)** (日本語, 10 min read)
  - Current status analysis
  - Risk assessment
  - Resource requirements

- **[Implementation Plan](YAYA_CORE_IMPLEMENTATION_PLAN.md)** (日本語, 15 min read)
  - 3-phase roadmap with detailed breakdown
  - Week-by-week tasks
  - Success criteria

### For Developers
- **[Technical Specification](YAYA_CORE_TECHNICAL_SPEC.md)** (日本語, 25 min read)
  - Complete YAYA language specification
  - API definitions
  - Code examples and test cases

- **[Architecture Diagrams](YAYA_CORE_ARCHITECTURE.md)** (English, 10 min read)
  - Visual system overview
  - Component responsibilities
  - Data flow illustrations

- **[Developer Quick Start](../yaya_core/README.md)** (English, 5 min read)
  - Build instructions
  - IPC protocol reference
  - Testing guide

### Related Specifications
- **[YAYA Adapter Spec](OURIN_YAYA_ADAPTER_SPEC_1.0M.md)** (日本語)
  - IPC protocol specification
  - Message format definitions

- **[USL Spec](OURIN_USL_1.0M_SPEC.md)** (日本語)
  - Universal SHIORI Loader specification
  - Module loading requirements

---

## 📊 Documentation Overview

| Document | Language | Size | Target Audience | Purpose |
|----------|----------|------|-----------------|---------|
| Executive Summary | EN | 7 KB | Stakeholders | Decision making |
| Investigation Report | JA | 8 KB | PM / Tech Lead | Status & risks |
| Implementation Plan | JA | 9 KB | PM / Developers | Roadmap |
| Technical Spec | JA | 15 KB | Developers | Implementation |
| Architecture | EN | 20 KB | Developers | System design |
| Quick Start | EN | 7 KB | Developers | Getting started |

**Total**: ~66 KB of comprehensive documentation

---

## 🔍 Investigation Summary

### What We Found

**Historical note:** at the time of this 2025 investigation, the yaya_core module
only had the IPC communication layer implemented. That is no longer accurate:
the repository now contains a parser, VM, dictionary loader, encoding support,
and broad built-in function coverage. Remaining limitations are tracked in
`yaya_core/IMPLEMENTATION_STATUS.md`.

### Current Status Matrix

| Component | Status | Details |
|-----------|--------|---------|
| IPC Framework | ✅ Complete | JSON line-based stdin/stdout |
| Command Dispatch | ✅ Complete | load/request/unload |
| Swift Integration | ✅ Complete | YayaAdapter.swift |
| Build System | ✅ Complete | CMake, Universal Binary |
| Dictionary Parser | 🟡 Partial | Implemented with known compatibility limits |
| YAYA VM | 🟡 Partial | Implemented; by-reference and standalone `when` remain partial |
| Built-in Functions | 🟡 Partial | Broad coverage; some functions remain stubs |
| SHIORI Adapter | ✅ Implemented | Integrated through Swift host/JSON-line IPC |

---

## 🎯 Key Recommendations

### Recommended Approach

**Continue with C++ for Phase 1-2, consider Swift migration in Phase 3+**

**Why C++?**
1. Existing IPC framework already in C++
2. Can reference official YAYA implementation (BSD-3-Clause)
3. Better performance for parser/VM
4. CMake already configured for Universal Binary
5. Process isolation allows future Swift migration

**Why not Swift immediately?**
1. Less reference material available
2. Parser/VM libraries less mature
3. Performance tuning more challenging
4. Can always migrate later (IPC isolation)

### Implementation Timeline

```
Phase 1: MVP (3 weeks)
├─ Week 1: Lexer + file loading + UTF-8/CP932 support
├─ Week 2: Parser + VM + basic built-in functions
└─ Week 3: SHIORI integration + Emily4 testing

Phase 2: Extended Features (2-3 weeks)
├─ Arrays and dictionaries
├─ Loop structures (while/foreach)
├─ Regular expressions
└─ Performance optimization

Phase 3: Quality & Optimization (ongoing)
├─ Memory leak validation
├─ Performance profiling
├─ Multi-ghost compatibility
└─ (Optional) Swift VM migration
```

### Success Criteria

**Phase 1 MVP is complete when**:
- ✅ Emily4 ghost boots successfully
- ✅ OnBoot event executes and returns SakuraScript
- ✅ Basic dialogue works (user can interact)
- ✅ Runs on both Intel and Apple Silicon Macs
- ✅ Supports UTF-8 and CP932 dictionary files

---

## 🏗️ Architecture Quick Reference

### System Layers

```
┌──────────────────────────────────┐
│   Ourin.app (Swift)              │
│   - UI Layer                     │
│   - YayaAdapter (IPC Client)     │
└──────────┬───────────────────────┘
           │ JSON over Process I/O
┌──────────▼───────────────────────┐
│   yaya_core (C++ Executable)     │
│   - IPC Server                   │
│   - Dictionary Manager           │
│   - Lexer/Parser/VM              │
│   - SHIORI Adapter               │
└──────────────────────────────────┘
```

### Component Responsibilities

**Swift Layer** (No changes needed):
- Launch yaya_core process
- Manage process lifecycle
- JSON encoding/decoding
- Error propagation to UI

**C++ Layer** (Implementation needed):
- Load and parse .dic files
- Execute YAYA scripts
- Manage variables and functions
- Generate SHIORI responses

---

## 📦 Dependencies

### Required Libraries

| Library | Purpose | License | Status |
|---------|---------|---------|--------|
| nlohmann/json | JSON IPC | MIT | ✅ Already used |
| ICU | Character encoding | Unicode | ✅ macOS system |
| std::regex | Regular expressions | - | ✅ C++11 stdlib |
| Google Test | Unit testing | BSD-3 | 📦 To be added |

**No additional dependencies** beyond what's already in the project or macOS.

---

## 🧪 Testing Strategy

### Test Resources Available

- **Emily4 Ghost**: 50+ dictionary files in `emily4/ghost/master/`
- **CORE_SAMPLES**: Reference implementations
- **Official YAYA**: Can compare outputs

### Testing Approach

1. **Unit Tests**: Each component (Lexer, Parser, VM, etc.)
2. **Integration Tests**: Load actual dictionary files
3. **System Tests**: Full Emily4 ghost execution
4. **Compatibility Tests**: Multiple ghosts, both architectures

---

## 📚 Reference Materials

### In Repository
- `emily4/ghost/master/*.dic` - Real YAYA dictionaries (50+ files)
- `CORE_SAMPLES/` - C# SHIORI implementation (reference)
- `Ourin/Yaya/YayaAdapter.swift` - Swift integration (complete)

### External Resources
- [Official YAYA](https://github.com/YAYA-shiori/yaya-shiori) - C++ implementation (BSD-3)
- [YAYA Documentation](https://emily.shillest.net/ayaya/) - Language reference
- [Ukagaka Wiki](https://ssp.shillest.net/ukadoc/) - Protocol specs
- [yaya-rs](https://github.com/apxxxxxxe/yaya-rs) - Rust implementation (reference)

---

## 🚀 Getting Started

### For Developers Ready to Implement

1. **Read in this order**:
   - [Quick Start](../yaya_core/README.md) - Build and test current state
   - [Architecture](YAYA_CORE_ARCHITECTURE.md) - Understand system design
   - [Technical Spec](YAYA_CORE_TECHNICAL_SPEC.md) - Detailed implementation guide
   - [Implementation Plan](YAYA_CORE_IMPLEMENTATION_PLAN.md) - Week-by-week tasks

2. **Set up environment**:
   ```bash
   brew install cmake nlohmann-json
   cd yaya_core
   mkdir build && cd build
   cmake ..
   make
   ```

3. **Start with Phase 1, Week 1**:
   - Implement Lexer (tokenizer)
   - Add UTF-8/CP932 file loading
   - Write unit tests

### For Reviewers

1. **Start with**: [Executive Summary](YAYA_CORE_EXECUTIVE_SUMMARY.md)
2. **Then read**: [Investigation Report](YAYA_CORE_INVESTIGATION_REPORT.md)
3. **Review**: [Implementation Plan](YAYA_CORE_IMPLEMENTATION_PLAN.md)

---

## 📞 Questions & Feedback

### Common Questions

**Q: Can we just use the Windows YAYA DLL?**  
A: No, Windows DLLs cannot run natively on macOS. We need a native reimplementation.

**Q: Why not Swift from the start?**  
A: C++ allows us to reference the official YAYA codebase and has better performance for parsers/VMs. We can migrate to Swift in Phase 3 if desired.

**Q: How compatible will this be with Windows YAYA?**  
A: We aim for behavioral compatibility (same input → same output) but not binary compatibility. Some Windows-specific features may not be supported.

**Q: What about existing ghosts?**  
A: Emily4 is our primary test case. If it works with Emily4, it should work with most YAYA ghosts.

**Q: How long until we can use it?**  
A: Phase 1 MVP should be complete in 3 weeks, providing basic functionality.

---

## 🗂️ Document Change Log

### 2025-10-16 - Initial Release
- Created complete documentation suite
- Investigation report
- Implementation plan (3 phases)
- Technical specification
- Architecture diagrams
- Executive summary
- This index file

---

## 📄 License

All documentation: CC BY-NC-SA 4.0  
Code (yaya_core): BSD-3-Clause (YAYA compatible)

---

**Project**: Ourin (桜鈴) - macOS Native Ukagaka Baseware  
**Repository**: https://github.com/eightman999/Ourin  
**Documentation Path**: `/docs/`

**Prepared by**: GitHub Copilot  
**Date**: 2025-10-16
