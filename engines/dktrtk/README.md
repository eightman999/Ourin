# Optional local dktrtk / AngelScript port

`build.py` builds upstream dktrtk's real `load`, `CompileScript`, `request`, and `unload` implementations. The default historical x86_64 variant retains its unchanged 13 addon source files and **AngelScript SDK 2.30.0**. The separate native ARM64 variant uses the official **AngelScript SDK 2.38.0**, its matching versions of all 13 addon source files, and the new filesystem addon's required `datetime` dependency. Scripts still use `index.as` and the original `bool load(string)`, `string request(string)`, `bool unload()` entrypoints. SHIORI responses come from script execution. No built-in response dictionary substitutes for the interpreter.

## Local build

```sh
python3 engines/dktrtk/build.py                   # preserved x86_64 / SDK 2.30.0
python3 engines/dktrtk/build.py --arch arm64      # native Apple Silicon / SDK 2.38.0
```

Apple Clang/macOS SDK are required. The default output remains `build/engines/dktrtk/dktrtk-host`, an **x86_64 macOS executable**; Apple Silicon requires Rosetta for this historical variant. The ARM64 output is separately placed at `build/engines/dktrtk-arm64/dktrtk-host` and executes natively on Apple Silicon without Rosetta. Both target macOS 13+. The two executables are independently selectable through the existing SHIOLINK configuration.

SDK 2.30.0 cannot call the original native addons on ARM64. Building those old addons against 2.38.0 also fails because the public C++ type `asIObjectType` was replaced. The ARM64 variant uses the complete matching official addons rather than deleting registrations. The original 12 `Register...` calls remain, covering all 13 original source modules; `RegisterScriptDateTime` is added before the modern filesystem addon. The official `as_callfunc_arm64_xcode.S` supplies Apple ARM64 calling conventions. All addon operations exercised by the shared test dictionary run on both variants. New SDK language semantics and additional/updated addon declarations (for example `dictionary.delete` now returns `bool`) mean this explicit variant is not an assertion that all 2.30 source/bytecode is identical. The historical variant remains available for those dictionaries.

`--archive` and `--sdk-archive` accept offline archives; `--output` and `--cxx` select output and compiler. `UPSTREAM.json` pins both revisions and SHA-256. The upstream Visual Studio project explicitly names SDK 2.30.0. The old SDK is pinned to the exact release commit from the historical `codecat/angelscript-mirror` repository. The ARM64 SDK is the official 2.38.0 release ZIP from angelcode.com; its SHA-256 is pinned and includes all matching addons. The SDK zlib notice and any source notices are retained in `AngelScript-addon-notices.txt`, together with the SDK manual license page. No external package manager is needed. Both `--sdk-archive` offline inputs must match the selected architecture's pinned SDK archive.

**dktrtk has no project license in the pinned source. This remains an optional local build; no resulting binary is embedded, packaged, published, or licensed for redistribution here.** AngelScript's separate zlib notice is retained in the output header. A local build does not establish permission to redistribute dktrtk or its addon snapshot.

## Use without changing descript.txt

Place `SHIOLINK.ourin.ini` beside the existing module path:

```ini
[SHIOLINK]
module=dktrtk.dll
executable=/absolute/path/build/engines/dktrtk/dktrtk-host
charmode=UTF-8
```

`module` must match the original descriptor's module basename. The application selects this explicitly configured process while preserving the descriptor. The default host reads UTF-8 load/control data and changes cwd before compiling UTF-8 `index.as`. In the explicit CP932 wire mode below, the load path is received in CP932 (matching `ShiolinkAdapter`'s charmode) and strictly converted to UTF-8 before POSIX filesystem access; the script receives the UTF-8 path.

### CP932 wire, UTF-8 script source

```ini
[SHIOLINK]
module=dktrtk.dll
executable=/absolute/path/build/engines/dktrtk-arm64/dktrtk-host
arguments=["--wire-charset","CP932"]
charmode=Shift_JIS
```

This is an explicit local-port bridge: script source and script strings use UTF-8, while SHIOLINK requests/responses use CP932. The host strictly decodes request bytes to UTF-8 and updates the internal Charset header; responses declared UTF-8 are encoded to CP932 and their wire Charset becomes Shift_JIS. Japanese load paths are converted separately. Unrepresentable emoji, malformed bytes and incompatible Charset declarations fail; no lossy substitution is permitted. The transport cannot represent load paths containing characters outside CP932.

The original fixed dktrtk source selects the SDK ASCII scanner (`asEP_SCRIPT_SCANNER=0`), but contains no source-encoding contract or distributed script establishing CP932 support. [The official SDK string documentation](https://www.angelcode.com/angelscript/sdk/docs/manual/doc_strings.html) defines scanner 0 as ASCII and scanner 1 as UTF-8. Its `as_config.h` explicitly states that the optional `AS_DOUBLEBYTE_CHARSET` is not Shift-JIS compatible. A CP932 source literal containing 表/ソ (trail byte `0x5c`) was experimentally accepted with warnings and corrupted by the old scanner. The port now selects scanner 1 and validates every file-backed script section, including includes, as UTF-8 before parsing; invalid legacy source fails explicitly with a source-encoding diagnostic. This does not define CP932 source as a previously supported upstream contract, and does not rewrite a ghost's files.

`example-cp932/index.as` is a self-authored **UTF-8** script testing this bridge. Its neighbor `unsupported-cp932-source.as` deliberately contains real CP932 bytes and is a rejection fixture, not a working dictionary. Tests cover Japanese Reference values, 表/ソ, halfwidth kana and CP932 extensions ①/髙, GET/NOTIFY, Japanese load paths, state save/reload in separate processes, unrepresentable request/response emoji, and rejection of non-UTF-8 main/included source. These checks do not establish compatibility with arbitrary distributed dktrtk dictionaries.

## Port changes

The build derives a temporary `ported.cpp` from the fixed upstream `dllmain.cpp`: remove the Windows DllMain and unused Windows charset-conversion helpers; replace SetCurrentDirectory with POSIX chdir; map HGLOBAL allocation/ownership to malloc/free; change pointer-returning `false` to `nullptr` for standard C++; add compiler diagnostics on stderr. Original engine creation, addon registrations, script compilation, execution and return handling remain; the source scanner now explicitly selects and validates UTF-8, as described above. `host/posix-prefix.hpp` provides the POSIX declarations and addon includes. The host adds CRLF SHIOLINK framing, bounded input/output, EOF unload and diagnostics without changing script results. The original request allocation includes a terminal NUL; the process transport sends only the script response bytes.

SDK x86_64 inline-assembly labels receive an `L` prefix so Mach-O local labels do not split CFI ranges with current Apple Clang. The assembly instructions, branches and unwind directives are preserved. The ARM64 variant explicitly uses the SDK's documented `asEP_PROPERTY_ACCESSOR_MODE=2` backward-compatibility setting. Its string and array addons keep both `length()` and the automatically recognized `get_length`/`set_length` properties from 2.30 (modern defaults otherwise omit the latter). The addon sources are marked as altered at this conditional; no operation is removed. The SDK 2.38 compiler additionally resolves an automatically recognized property ahead of an explicit same-name method call. A narrow marked patch in `CompileFunctionCall` restores method selection only for explicit array/string `length()` calls in compatibility mode 2. It leaves property accesses and other types untouched. The shared test dictionary executes both calling styles and validates their values on both variants. All source transformations assert the expected original snippets and are covered by the archive hashes.

## Verification

The real process has been exercised with the production `ShiolinkAdapter`: Japanese/emoji through `index.as`, dictionary and array parsing, grid and sqrt, NOTIFY, OnClose, actual file-addon save/reload across two processes, UTF-8 load path and process reaping. Invalid script syntax is rejected by the real compiler. The test dictionary is explicitly supplied in `example/index.as`; no real user dictionary is modified.

Six parameterized optional `DktrtkEngineTests` cover this flow, real filesystem listing, any/ref/weakref/complex/array/dictionary operations, compiler failure, and EOF in a partial request executing the script's unload. Each built variant enables a separate set of six cases; `OURIN_DKTRTK_EXECUTABLE` restricts execution to one specified host. The standalone production-`ShiolinkAdapter` probe passed these operations plus save/reload and process reaping for both the historical x86_64/Rosetta host and native ARM64 host on Apple Silicon. These standalone process checks are distinct from the app-linked Xcode tests. These checks do not establish compatibility with every distributed dktrtk dictionary or prove every addon API.
