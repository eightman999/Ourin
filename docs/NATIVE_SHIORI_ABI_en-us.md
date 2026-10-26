# Native SHIORI ABI

[日本語](NATIVE_SHIORI_ABI_ja-jp.md)

Updated: 2026-10-25. This contract describes the development implementation, not support in previously published binaries.

## Selecting a macOS module

Keep the Windows `shiori` entry and explicitly select a macOS module in `descript.txt`:

```text
shiori,yaya.dll
shiori.macos,native/libyaya.dylib
```

A nonempty `shiori.macos` takes precedence during both startup and reload. Paths are relative to `ghost/master`; Windows backslash separators are accepted. Even names such as `yaya` use the explicitly selected native file, rather than a bundled helper. An empty value uses the existing `shiori` rule; a missing explicit file fails to load. The dictionary directory is the selected module's parent. The ABI declaration below is still required.

For automatic selection of a bundled compatibility engine, retain the original `shiori` without adding `shiori.macos`. See [additional engines](ADDITIONAL_SHIORI_ja-jp.md) for setup and limitations.

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

The `long` in `ukagaka-long` is a 64-bit integer on macOS. `kagari` is the KAGARI POSIX export set; see [KAWARI/KAGARI engines](KAWARI_KAGARI_ENGINES_ja-jp.md). Ports that retain Windows-style 32-bit lengths must use `ukagaka-int32`. This SHIORI-specific key is separate from the `OurinModuleABI` contract used by SAORI and other modules.

Without a declaration, only the existing Ourin ABI exporting `shiori_request` is accepted. An unprefixed `request` is rejected rather than having its signature guessed. Unknown declaration values also cause a load error.

`aosora` uses `aosora_load` / `aosora_request` / `aosora_unload`. Instance IDs are 64-bit; zero means load failure. Input/response ownership matches `ukagaka-*`. See [optional setup and real-ghost verification (Japanese)](compatibility-corpus/aosora.md). Source-derived Aosora is not bundled in the standard release.

## Symbols and ownership

The loader prefers `loadu`, searching `shiori_loadu`, `loadu`, `shiori_load`, then `load`. Requests use `shiori_request` / `request`; unloading uses `shiori_unloadu` / `unloadu` / `shiori_unload` / `unload`. The load and unload functions are optional. If a present load function returns failure, the entire module load fails.

- `ourin`: Input remains host-owned and valid until the call returns. The host copies the response and releases it with `shiori_free`, or libc `free` if that symbol is absent.
- `ukagaka-*`: load/request inputs are NUL-terminated `malloc` buffers whose ownership transfers to the module. Lengths exclude the NUL. The request length is an input/output parameter. The module allocates the response with `malloc`; the host copies it and then calls `free`.
- Negative response lengths and responses larger than 64 MiB are rejected. This does not make arbitrary malformed native code safe.

## Dictionary directory and process

The executable library location and the directory passed to load are separate values. Ghost startup derives the dictionary directory from `ghostRoot` and the original relative `shiori` path, passing UTF-8 with a trailing `/`. Omitting `loadDirectory` from the standalone loader API uses the library's parent directory.

The app and XPC service share `NativeShioriModule`. Failure to connect or load under the default XPC isolation does not automatically fall back to loading in the app process. The existing adapter handles SHIORI/2.x conversion. ABI support alone does not establish compatibility with an individual engine or dictionary.

## Verification

`NativeShioriABITests` builds real C libraries for both standard ABI widths and checks GET/NOTIFY, dictionary paths, unload, failed loads, missing declarations, and the separate XPC PID. The `nativeDylibFixture*` cases in `ShioriLoaderTests` cover the existing Ourin ABI.

Translation: Codex. Japanese/English content comparison: 2026-10-25. Consult the individual verification reports for execution results.

The path is UTF-8 even when only `load` is exported. ACP/Shift_JIS-only path loaders require a wrapper. KAGARI’s instance-ID POSIX API is declared with `OurinShioriABI` = `kagari`.
