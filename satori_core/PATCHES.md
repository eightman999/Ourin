# Local integration patches

The upstream source is kept as close to `Mc172-3` as possible. Ourin applies three POSIX compatibility patches:

- `SakuraDLLClient.cpp`: return the generated response from the POSIX request path. The upstream function otherwise reaches the end of a non-void function.
- `ssu.cpp`: return `"0"` from `_lsimg` on POSIX. The upstream branch is an empty TODO in a non-void function; `0` matches the function's existing empty/error result.
- `shiori_plugin.cpp`: resolve a configured Windows `name.dll` against macOS-native `name.dylib`, `libname.dylib`, and `.so` files under `SAORI_FALLBACK_PATH`. This mirrors the dynamic-library subset of Ourin's `SaoriRegistry` name normalization without attempting to load the Windows DLL.

`src/EncodingIconv.cpp` supplies the CP932/UTF-8 conversion functions expected by the POSIX sources. `src/main.cpp` is an Ourin-owned JSON Lines boundary and is not part of upstream SATORI; it scopes `SAORI_FALLBACK_PATH` to the current ghost's approved search directories before loading SATORI.
