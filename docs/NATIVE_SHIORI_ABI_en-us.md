# Native SHIORI ABI

[日本語](NATIVE_SHIORI_ABI_ja-jp.md)

Updated: 2026-10-30. This contract describes the development implementation, not support in previously published binaries.

## Selecting a macOS module

Keep the Windows `shiori` entry and explicitly select a macOS module in `descript.txt`:

```text
shiori,yaya.dll
shiori.macos,native/libyaya.dylib
```

A nonempty `shiori.macos` takes precedence during both startup and reload. Paths are relative to `ghost/master`; Windows backslash separators are accepted. Even names such as `yaya` use the explicitly selected native file, rather than a bundled helper. An empty value uses the existing `shiori` rule; a missing explicit file fails to load. The dictionary directory is the selected module's parent. The selected module must follow one of the ABI contracts below.

For automatic selection of a bundled compatibility engine or an installed SHIORI engine plugin, retain the original `shiori` without adding `shiori.macos`. See [additional engines](ADDITIONAL_SHIORI_ja-jp.md) and [SHIORI engine plugins (Japanese)](SHIORI_ENGINE_PLUGINS_ja-jp.md) for setup and limitations.

## Declaration

For macOS `.bundle` / `.plugin` modules, set `OurinShioriABI` in `Contents/Info.plist`. For standalone libraries, append `.plist` to the library filename and place that file beside it (for example, `engine.dylib.plist`).

```xml
<key>OurinShioriABI</key>
<string>ukagaka-int32</string>
```

| Value | load | request | unload |
|---|---|---|---|
| `ourin` | `bool(const char *)` | `bool(const unsigned char *, size_t, unsigned char **, size_t *)` | `void(void)` |
| `ukagaka-long` | `int32_t(void *, long)` | `void *(void *, long *)` | `int32_t(void)` |
| `ukagaka-int32` | `int32_t(void *, int32_t)` | `void *(void *, int32_t *)` | `int32_t(void)` |
| `kagari` | `int32_t(void *, long)` → instance ID | `void *(int32_t id, void *, long *)` | `int32_t(int32_t id)` |
| `aosora` | `long(void *, long)` → instance ID | `void *(long id, void *, long *)` | `int32_t(long id)` |
| `yaya` | `long(void *, long)` → instance ID | `void *(long id, void *, long *)` | `int32_t(long id)` |

The `long` in `ukagaka-long` is a 64-bit integer on macOS. `kagari` is the KAGARI POSIX export set; see [KAWARI/KAGARI engines](KAWARI_KAGARI_ENGINES_ja-jp.md). Ports that retain Windows-style 32-bit lengths must use `ukagaka-int32`. This SHIORI-specific key is separate from the `OurinModuleABI` contract used by SAORI and other modules.

Without a declaration, the loader accepts the Ourin ABI exporting `shiori_request` and the dedicated KAGARI/Aosora prefixes. YAYA's multi-instance API requires an explicit `yaya` declaration. An unprefixed `request` is rejected rather than having its signature guessed. Unknown values also cause a load error.

`aosora` uses `aosora_load` / `aosora_request` / `aosora_unload`. Instance IDs are 64-bit; zero means load failure. Input/response ownership matches `ukagaka-*`. See [optional setup and real-ghost verification (Japanese)](compatibility-corpus/aosora.md). Source-derived Aosora is not bundled in the standard release.

## Symbols and ownership

For `ourin` / `ukagaka-*`, the loader prefers `loadu`, searching `shiori_loadu`, `loadu`, `shiori_load`, then `load`. Requests use `shiori_request` / `request`; unloading uses `shiori_unloadu` / `unloadu` / `shiori_unload` / `unload`. These contracts permit missing load/unload functions. If a present load function returns failure, the module load fails.

`kagari` uses `kagari_load/request/unload`; `aosora` uses `aosora_load/request/unload`. `yaya` uses the official POSIX `multi_loadu` / `multi_request` / `multi_unload`, requiring all three. YAYA/Aosora success IDs are positive C longs. YAYA reserves zero for the legacy single VM, so zero is rejected. Requests and unloads retain their instance ID, keeping simultaneous dictionaries independent.

- `ourin`: Input remains host-owned and valid until the call returns. The host copies the response and releases it with `shiori_free`, or libc `free` if that symbol is absent.
- `ukagaka-*`: load/request inputs are NUL-terminated `malloc` buffers whose ownership transfers to the module. Lengths exclude the NUL. The request length is an input/output parameter. The module allocates the response with `malloc`; the host copies it and then calls `free`.
- `kagari` / `aosora` / `yaya` also take ownership of load/request input buffers; the host frees each response. ID and length widths follow the table above.
- Negative response lengths and responses larger than 64 MiB are rejected. This does not make arbitrary malformed native code safe.

## Dictionary directory and process

The executable library location and the directory passed to load are separate values. An explicit `shiori.macos` uses the selected module's parent as the dictionary directory. For an installed plugin, ghost startup derives the dictionary directory from `ghostRoot` and the original relative `shiori` path; it does not use the plugin's installation directory. Existing paths are resolved without regard to case. Load receives the directory as UTF-8 with a trailing `/`, including when only `load` is exported. ACP/Shift_JIS-only path loaders require a wrapper. Omitting `loadDirectory` from the standalone loader API uses the library's parent directory.

The app and XPC service share `NativeShioriModule`. Failure to connect or load under the default XPC isolation does not automatically fall back to loading in the app process. The existing adapter handles SHIORI/2.x conversion. ABI support alone does not establish compatibility with an individual engine or dictionary.

## Verification

`NativeShioriABITests` builds real C libraries for both standard ABI widths and checks GET/NOTIFY, dictionary paths, unload, failed loads, missing declarations, and the separate XPC PID. The `nativeDylibFixture*` cases in `ShioriLoaderTests` cover the existing Ourin ABI.

The YAYA C fixture returns IDs above the 32-bit range and checks independent dictionaries, continuing one after unloading the other, and rejecting instance zero, directly and through XPC. See `YayaEngineTests` and `engines/yaya/README.md` for the official engine checks.

Translation: Codex. Japanese/English content comparison: 2026-10-30. Consult the individual verification reports for execution results.
