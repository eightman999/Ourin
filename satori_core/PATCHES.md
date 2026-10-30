# Local integration patches

The upstream source is kept as close to `Mc172-3` as possible. Ourin applies three POSIX compatibility patches:

- `SakuraDLLClient.cpp`: return the generated response from the POSIX request path. The upstream function otherwise reaches the end of a non-void function.
- `ssu.cpp`: return `"0"` from `_lsimg` on POSIX. The upstream branch is an empty TODO in a non-void function; `0` matches the function's existing empty/error result.
- `shiori_plugin.cpp`: resolve a configured Windows `name.dll` against macOS-native `name.dylib`, `libname.dylib`, and `.so` files under `SAORI_FALLBACK_PATH`. This mirrors the dynamic-library subset of Ourin's `SaoriRegistry` name normalization without attempting to load the Windows DLL.

`src/EncodingIconv.cpp` supplies the CP932/UTF-8 conversion functions expected by the POSIX sources. `src/main.cpp` is an Ourin-owned JSON Lines boundary and is not part of upstream SATORI; it scopes `SAORI_FALLBACK_PATH` to the current ghost's approved search directories before loading SATORI.

The JSONL boundary also duplicates its protocol output descriptor before redirecting ordinary stdout to stderr. Upstream conditional candidate selection writes `selecting` and CP932 dictionary candidates to `std::cout`; these diagnostics must not corrupt JSON responses or trigger helper recovery. Only serialized response lines use the reserved descriptor, with partial-write and EINTR handling.

The encoding boundary matches upstream `_/charset.cpp`: `UTF8toSJIS` consumes a leading UTF-8 BOM, and `CUnicodeF::utf16be_to_sjis` substitutes a space for characters unavailable in CP932. This prevents one valid but unrepresentable dictionary character from aborting the entire load. Malformed UTF-8, surrogate code points, truncated sequences, and invalid CP932 remain errors. This is CP932 compatibility, not lossless Unicode dictionary support. A leading BOM is an encoding signature ([Unicode FAQ](https://unicode.org/faq/utf_bom.html)); embedded U+FEFF is not silently removed.

`main.cpp` duplicates the JSON output descriptor before routing native stdout to stderr. Upstream `Family.h::select_all` emits conditional-selection diagnostics on `std::cout`; these no longer corrupt JSON Lines. Native SAORI stdout follows the same boundary.

Run `python3 -m unittest discover -s satori_core/tests -p 'test_encoding.py' -v` from the repository root after building. The Ourin-authored fixtures check BOM handling, upstream substitution, invalid input rejection, real conditional conversation, diagnostic separation, and unchanged source dictionary bytes.
