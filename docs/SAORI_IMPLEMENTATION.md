# SAORI Implementation in Ourin

## Scope

Ourin implements SAORI/1.0 host-side support under `Ourin/SaoriHost/` and bridges it to YAYA runtime calls.

Main files:

- `SaoriLoader.swift`
- `SaoriProtocol.swift`
- `SaoriRegistry.swift`
- `SaoriManager.swift`
- `YayaAdapter.swift` (bridge)
- `yaya_core/src/VM.cpp`, `yaya_core/src/YayaCore.cpp` (plugin operations)

## Module loading (`SaoriLoader`)

`SaoriLoader` handles dynamic loading with `dlopen/dlsym/dlclose`:

- Resolves symbol variants:
  - `request` / `saori_request`
  - `load` / `saori_load`
  - `unload` / `saori_unload`
- Calls `load(directory)` when available
- Sends binary request payload to `request(...)`
- Decodes response with configured charset (UTF-8 fallback)

Error cases are surfaced via `SaoriLoaderError`.

## Protocol handling (`SaoriProtocol`)

`SaoriProtocol` provides:

- SAORI request parser
- SAORI response parser/builder
- Charset conversion helpers

Supported encodings:

- UTF-8
- Shift-JIS family aliases (`sjis`, `cp932`, `windows-31j`, ...)
- EUC-JP
- ISO-2022-JP

## Discovery and cache (`SaoriRegistry`)

`SaoriRegistry` manages:

- Search paths
- `.saori` discovery under ghost roots
- Module name normalization (`foo`, `foo.dylib`, `libfoo.dylib`, ...)
- Loader cache and unload lifecycle

Default search locations include app resources and user Application Support.

## Unified API (`SaoriManager`)

`SaoriManager` provides a single entrypoint:

- Discover/load/unload modules
- Send request text with charset
- Process plugin operations:
  - `saori_load`
  - `saori_unload`
  - `saori_request`

## YAYA bridge path

Runtime chain:

1. YAYA script calls `LOADLIB` / `UNLOADLIB` / `REQUESTLIB`
2. `VM.cpp` forwards to `pluginOperation(...)`
3. `YayaCore.cpp` emits host operation JSON (`host_op`)
4. `YayaAdapter.swift` receives `host_op=plugin`
5. `YayaAdapter.handlePluginOperation(...)` delegates to `SaoriManager`
6. Result JSON is returned back to `yaya_core`

`YayaAdapter` also exposes helper `handleSaoriRequest(...)`.

## Tests and samples

Tests:

- `OurinTests/SaoriProtocolTests.swift`
- `OurinTests/SaoriRegistryTests.swift`

Samples:

- `Samples/SimpleSaori/CppSimpleSaori`
- `Samples/SimpleSaori/SwiftSimpleSaori`

Both sample modules implement `load/unload/request`.

## Current Status / 現在のステータス

**Status**: Integration Complete (Core Path) / 統合完了（コアパス） / 2026-03-15

Core SAORI components are now integrated with the YAYA runtime through VM → YayaCore → YayaAdapter → SaoriManager.

主要なSAORIコンポーネントは、VM → YayaCore → YayaAdapter → SaoriManager 経路でYAYAランタイムへ統合されました。

### Implemented Components / 実装済みコンポーネント
- ✅ **SaoriLoader.swift** - macOS native .dylib loading with dlopen/dlsym
- ✅ **SaoriProtocol.swift** - SAORI/1.0 request/response parsing
- ✅ **SaoriRegistry.swift** - Module discovery and caching
- ✅ **SaoriManager.swift** - Unified API for SAORI operations
- ✅ **Test files** - SaoriProtocolTests.swift, SaoriRegistryTests.swift

### Integration Status / 統合ステータス
- ✅ **VM.cpp** - LOADLIB/UNLOADLIB/REQUESTLIB call pluginOperation bridge
- ✅ **YayaCore.cpp** - pluginOperation routed via handlePluginOperation with validation
- ✅ **YayaAdapter.swift** - handlePluginOperation / handleSaoriRequest delegate to SaoriManager
- ✅ **Operational path** - YAYA scripts can load/request/unload SAORI modules

### Blocking Issues / ブロック中の問題
- ✅ **ID-001**: Resolved
- ✅ **ID-002**: Resolved

### Integration Record / 統合実施記録

Phase 1 integration work is complete and tracked in code/tests:

フェーズ1の統合作業は完了し、コードとテストで追跡されています：

1. ✅ **VM.cpp bridge path** (Task 1.1 complete)
2. ✅ **YayaCore plugin operation routing** (Task 1.2 complete)
3. ✅ **YayaAdapter SAORI bridge wiring** (Task 1.3 complete)
4. ✅ **Sample + smoke coverage** (Tasks 1.4-1.5 complete)

### Success Criteria / 成功基準
- [x] LOADLIB successfully loads .dylib module
- [x] REQUESTLIB sends request and receives response
- [x] UNLOADLIB unloads module
- [x] Integration smoke tests pass
- [x] No SAORI blockers remain (ID-001, ID-002 resolved)

---

## Current limitations / 現在の制限

- SAORI module ABI variance is handled by common symbol aliases only.
- Response memory ownership depends on module behavior; modules should follow SAORI conventions.
- Extended SAORI security policies are not fully formalized yet (future hardening item).
- End-to-end ghost behavior validation is still ongoing for broader real-ghost coverage.
