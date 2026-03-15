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

## Current limitations

- SAORI module ABI variance is handled by common symbol aliases only.
- Response memory ownership depends on module behavior; modules should follow SAORI conventions.
- Extended SAORI security policies are not fully formalized yet (future hardening item).
