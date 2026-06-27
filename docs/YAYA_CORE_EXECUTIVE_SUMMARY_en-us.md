# YAYA Core Module - Executive Summary

**Date**: 2025-10-16  
**Project**: Ourin (桜鈴) - macOS Native Ukagaka Baseware  
**Issue**: Investigation of yaya_core module status and implementation planning

> **2026-06-27 status correction:** this is a historical executive summary.
> The current `yaya_core` is no longer IPC-only: it includes a parser, VM,
> dictionary loader, encoding handling, and broad built-in coverage. It remains
> partially compatible rather than complete. See
> [`../yaya_core/IMPLEMENTATION_STATUS.md`](../yaya_core/IMPLEMENTATION_STATUS.md)
> and [`AUDIT_CODEX_2026-06-27.md`](AUDIT_CODEX_2026-06-27.md).

---

## TL;DR

**Historical note:** at the time of this investigation, `yaya_core` only had the
IPC framework implemented. That statement is now obsolete; current status is
partial compatibility with a working parser/VM and known remaining gaps.

**Recommended approach**: Continue with **C++ implementation** (Phase 1-2), optional migration to Swift in Phase 3+.

**Estimated effort**: 3 weeks for MVP, 2-3 weeks for extended features.

---

## Investigation Results

### What Exists ✅

```
yaya_core/
├── CMakeLists.txt              ✅ Universal Binary (arm64 + x86_64)
├── src/
│   ├── main.cpp                ✅ JSON line-based IPC (stdin/stdout)
│   ├── YayaCore.cpp            ✅ Command dispatcher (load/request/unload)
│   ├── DictionaryManager.cpp   🟡 Implemented, with compatibility limits
│   ├── Parser.cpp / Lexer.cpp  🟡 Implemented, with advanced syntax limits
│   └── VM.cpp                  🟡 Implemented, with remaining stub built-ins

Ourin/Yaya/
└── YayaAdapter.swift           ✅ Swift IPC client (complete)

docs/
└── OURIN_YAYA_ADAPTER_SPEC_1.0M.md  ✅ IPC protocol specification
```

### Remaining Compatibility Gaps

| Component | Priority | Effort |
|-----------|----------|--------|
| By-reference semantics (`&`) | High | TBD |
| Standalone `when` / labeled block dispatch | High | TBD |
| Remaining stub built-ins (`MKDIR`, `RMDIR`, `FENUM`, Windows shims) | Medium | TBD |
| Real ghost output regression matrix | High | TBD |
| Full SSP/YAYA reference behavior parity | Long-term | TBD |

---

## Implementation Roadmap

### Phase 1: MVP (3 weeks)

**Goal**: Run Emily4 ghost successfully

**Week 1**: Parser Foundation
- [ ] Lexer (tokenizer) implementation
- [ ] UTF-8/CP932 file loading
- [ ] Basic Parser (expressions, statements)

**Week 2**: VM Implementation
- [ ] Variable store
- [ ] Function registry
- [ ] Expression evaluator
- [ ] Basic built-in functions (RAND, STRLEN, etc.)

**Week 3**: SHIORI Integration
- [ ] SHIORI/3.0M adapter
- [ ] Error handling
- [ ] Testing with Emily4 ghost
- [ ] Documentation

**Success Criteria**:
- ✅ Emily4 ghost boots
- ✅ OnBoot event works
- ✅ Basic dialogue functions
- ✅ Runs on Intel + Apple Silicon

### Phase 2: Extended Features (2-3 weeks)

- [ ] Arrays and dictionaries
- [ ] Loop structures (while/foreach)
- [ ] Regular expressions
- [ ] Performance optimizations
- [ ] Comprehensive test suite

### Phase 3: Quality & Optimization (ongoing)

- [ ] Memory leak validation (Asan/Valgrind)
- [ ] Performance profiling
- [ ] Multi-ghost compatibility
- [ ] (Optional) Swift VM migration

---

## Technical Decisions

### Language: C++ (Recommended)

**Rationale**:
1. **Leverage existing code**: 
   - IPC framework already in C++
   - Official YAYA is C++ (can reference architecture)
   
2. **Performance**:
   - Dictionary parsing needs speed (50+ files, MB of text)
   - VM execution critical path (thousands of ops per event)
   
3. **Universal Binary**:
   - CMake already configured for arm64/x86_64
   
4. **Future flexibility**:
   - IPC isolation allows later Swift migration
   - No impact on Swift codebase (YayaAdapter.swift)

**Alternative**: Swift
- Pros: Xcode integration, memory safety, modern concurrency
- Cons: Less reference material, harder performance tuning
- Decision: Defer to Phase 3+

### Dependencies

| Library | Purpose | License | Status |
|---------|---------|---------|--------|
| nlohmann/json | JSON IPC | MIT | ✅ Already used |
| ICU | Encoding conversion | Unicode | ✅ macOS system library |
| std::regex | Regex support | - | ✅ C++11 stdlib |
| Google Test | Unit testing | BSD-3 | 📦 To be added |

**No additional dependencies required** beyond C++17 stdlib + macOS system libraries.

### Architecture

```
Ourin.app (Swift)
    ↓ Process + JSON IPC
yaya_core (C++ executable)
    ├─ main.cpp (IPC server)
    ├─ YayaCore (dispatcher)
    ├─ DictionaryManager
    │   ├─ Lexer (tokenization)
    │   ├─ Parser (AST construction)
    │   └─ VM (execution)
    │       ├─ VariableStore
    │       ├─ FunctionRegistry
    │       └─ BuiltinFunctions
    └─ ShioriAdapter (SHIORI/3.0M)
```

---

## Reference Materials

### Existing Documentation (Repository)

- `docs/OURIN_YAYA_ADAPTER_SPEC_1.0M.md` - IPC protocol spec
- `docs/OURIN_USL_1.0M_SPEC.md` - SHIORI loader spec
- `emily4/ghost/master/*.dic` - 50+ real YAYA dictionary files (test cases)

### External Resources

- **Official YAYA**: https://github.com/YAYA-shiori/yaya-shiori (BSD-3-Clause)
- **YAYA Docs**: https://emily.shillest.net/ayaya/
- **Ukagaka Wiki**: https://ssp.shillest.net/ukadoc/
- **yaya-rs**: https://github.com/apxxxxxxe/yaya-rs (Rust implementation)

### New Documentation (Created Today)

1. **YAYA_CORE_INVESTIGATION_REPORT.md** (Japanese) - Investigation results
2. **YAYA_CORE_IMPLEMENTATION_PLAN.md** (Japanese) - Detailed roadmap
3. **YAYA_CORE_TECHNICAL_SPEC.md** (Japanese) - Language specification
4. **yaya_core/README.md** (English) - Quick start guide

---

## Risk Analysis

### Technical Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| YAYA spec ambiguity | High | Reference official implementation, test with real ghosts |
| Performance issues | Medium | Profile early, optimize iteratively |
| Encoding problems | Medium | Use ICU, comprehensive test coverage |
| Memory leaks | Medium | Asan/Valgrind, smart pointers |

### Schedule Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope creep | Medium | Strict MVP definition, defer features to Phase 2 |
| Technical blockers | Medium | Reference official YAYA code |
| Testing gaps | Low | Emily4 as primary test case |

---

## Success Metrics

### Phase 1 (MVP)

- [ ] Loads and parses 50+ Emily4 dictionary files (< 500ms)
- [ ] Executes OnBoot event (< 50ms latency)
- [ ] Generates valid SakuraScript responses
- [ ] Runs on both Intel and Apple Silicon Macs
- [ ] Supports UTF-8 and CP932 encodings

### Phase 2 (Extended)

- [ ] Passes comprehensive test suite (100+ tests)
- [ ] Works with 3+ different ghosts
- [ ] Performance benchmarks met (see technical spec)
- [ ] Memory usage < 100MB per ghost

---

## Next Actions

### Immediate (This Week)

1. ✅ Complete investigation and documentation
2. ⏭️ Set up development environment
3. ⏭️ Begin Lexer implementation

### Short Term (Next 3 Weeks)

- [ ] Implement Phase 1 (MVP)
- [ ] Test with Emily4 ghost
- [ ] Document any Windows YAYA compatibility issues

### Medium Term (Next 6 Weeks)

- [ ] Complete Phase 2 (extended features)
- [ ] Test with multiple ghosts
- [ ] Performance profiling and optimization

---

## Conclusion

The YAYA Core module **exists in scaffold form** but requires significant implementation work. The recommended approach is:

1. **Continue with C++** for Phase 1-2 (leveraging existing IPC framework)
2. **Reference official YAYA** while optimizing for macOS
3. **Maximize Swift assets** (no changes needed to YayaAdapter.swift)
4. **Target Universal Binary** (Intel + Apple Silicon)
5. **Consider Swift migration** in Phase 3+ (optional)

**Estimated Timeline**: MVP in 3 weeks, full feature set in 5-6 weeks.

---

**Author**: GitHub Copilot  
**Project**: Ourin (eightman999/Ourin)  
**Date**: 2025-10-16
