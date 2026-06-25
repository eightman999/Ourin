# YAYA dic Compatibility Implementation Plan

## Purpose

This document compares Ourin's `yaya_core` dictionary support with the practical YAYA/UKADOC compatibility target. It began as an implementation plan and now also records the Phase 0-10 completion status and remaining limitations.

The goal is not only to parse more `.dic` files, but to make real YAYA ghosts behave correctly through the full stack:

- `yaya.txt` and dictionary loading rules
- YAYA language syntax and runtime semantics
- YAYA system dictionary (`yaya_base`) expectations
- SHIORI/3.0 request and response compatibility
- Ourin Swift integration and host callbacks

## Reference Scope

### Primary References

- UKADOC top page: <https://ssp.shillest.net/ukadoc/manual/>
- UKADOC SHIORI/3.0: <https://ssp.shillest.net/ukadoc/manual/spec_shiori3.html>
- UKADOC SHIORI Event list: <https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html>
- YAYA language / SHIORI reference linked by UKADOC: <http://usada.sakura.vg/contents/shiori.html>
- YAYA system dictionary repository: <https://github.com/YAYA-shiori/yaya-dic>
- yaya-dic system dictionary manual: <https://github.com/YAYA-shiori/yaya-dic/blob/master/docs/manual_yaya_base.md>

### Local References

- `yaya_core/src/Lexer.*`
- `yaya_core/src/Parser.*`
- `yaya_core/src/AST.hpp`
- `yaya_core/src/VM.*`
- `yaya_core/src/DictionaryManager.*`
- `yaya_core/src/YayaCore.*`
- `Ourin/USL/ShioriLoader.swift`
- `Ourin/Ghost/GhostManager.swift`
- `Ourin/Yaya/YayaAdapter.swift`
- `yaya_core/PARSER_PROGRESS_UPDATE.md`
- `yaya_core/IMPLEMENTATION_STATUS.md`
- `yaya_core/FUNCTION_REFERENCE.md`

## Current State Summary

This document started as the implementation plan for YAYA dic compatibility.
Phases 0-10 have since been implemented and verified against focused regression
tests. The section below now records the implementation status as of the latest
audit rather than the original pre-work gap snapshot.

`yaya_core` supports these important basics:

- Function definitions with braced bodies
- Assignments and compound assignments
- `if` / `elseif` / `else`
- `while`, `for`, `foreach`
- `switch`, `case`, and `when` parsing/runtime paths
- String, integer, array values
- Dotted identifiers such as `SHIORI3FW.Status`
- `reference[index]` and `_argv`
- UTF-8 identifiers, including Japanese names
- `_in_` and `!_in_`
- Many YAYA built-in functions
- JSON line IPC with Swift
- Partial host callback support for SAORI/plugin operations
- `yaya.txt` parsing for `dic`, `include`, `dicdir`, `_loading_order.txt`,
  global/per-dic charset, and duplicate suppression

The project is still not a byte-for-byte clone of Windows `yaya-shiori`; known
limitations are tracked in `yaya_core/IMPLEMENTATION_STATUS.md`.

## Compatibility Gap Matrix

| Area | Expected behavior | Current behavior | Remaining note |
| --- | --- | --- | --- |
| `yaya.txt` loading | Supports `dic`, `include`, `dicdir`, `_loading_order.txt`, charset hints, ordered loading | Implemented in Swift collector with structured IPC entries | `_loading_order.txt` supports real yaya-dic `dic`/`dicif` rows plus legacy forms |
| System dictionaries | `dicdir, yaya_base` loads yaya-dic in intended order | Implemented and tested with missing `dicif` skip | Emily4 smoke result: 33/33 dictionaries loaded |
| Per-dic encoding | File-level charset may differ and should be honored | Implemented end-to-end through `dic_entries` | CP932/UTF-8 mixed dictionaries verified |
| Parser reliability | Real dictionaries parse without timeouts | Improved for block literals, labels, `switch`, `case/when`, and postfix `--` ambiguity | Known parser deviations remain in implementation status |
| `case/when` semantics | Only matching `when` body runs; `others/default` fallback works | Dedicated AST/runtime implemented | First-match and no side effects in non-selected branches verified |
| `switch` semantics | Supports real YAYA switch/block literal idioms | `--` separated and nested block forms implemented with index selection | Index semantics are intentional for the supported YAYA idiom |
| Block literals | Supports `{ ... -- ... }` and nested/labeled blocks | Implemented as array literals; variable elements no longer mutate via postfix `--` | `++` remains postfix increment, not a separator |
| Function declarations | Handles `array`, `sequential`, `nonoverload`, `when`, declaration metadata | Implemented multi-declaration registry and metadata APIs | `nonoverload` means last definition wins; standalone `when` dispatch remains limited |
| Dynamic dictionaries | `DICLOAD`, `DICUNLOAD`, `UNDEFFUNC`, runtime dic append work | Implemented with per-source ownership | Relative paths are sandboxed under `ghost/master` |
| Variable persistence | `SAVEVAR`, `RESTOREVAR`, settings, temp var management | Implemented with JSON type preservation and `REGISTERTEMPVAR` exclusion | Paths are sandboxed; dictionary values depend on `Value` support |
| SAORI | `FUNCTIONLOAD`, `FUNCTIONEX`, `SAORI` work through host | Implemented through Swift `SaoriManager` IPC; `Result` and `Value*` parsed | `valueex` exposed as builtins, not implicit variables |
| SHIORI/3.0 headers | Request/response headers match UKADOC expectations | Implemented generic pass-through with case-insensitive dedupe and `ref` overlay | Header coverage should keep growing with fixture tests |
| Regex and utility funcs | yaya-dic functions behave like real YAYA | High-impact items implemented, including `RE_ASEARCH`, `RE_ASEARCHEX`, `ISEVALUABLE`, global defines, charset IDs | Windows-only/directory shims remain compatibility stubs |

## Implementation Plan

### Phase 0: Documentation and Test Baseline

Create a clear, executable compatibility baseline before changing behavior.

Tasks:

- Update `yaya_core/IMPLEMENTATION_STATUS.md` to distinguish:
  - implemented
  - partial
  - compatibility stub
  - unsupported
- Update `yaya_core/FUNCTION_REFERENCE.md` so stub status matches source code.
- Add parser/load compatibility fixtures for:
  - simple `dic`
  - recursive `include`
  - `dicdir`
  - `_loading_order.txt`
  - `case/when`
  - `switch`
  - block literals with `--`
  - nested labeled blocks
- Add an Emily4/yaya-dic smoke test harness that reports:
  - loaded files count
  - failed files
  - parse time
  - request results for representative events

Acceptance criteria:

- A developer can run one command and see current parser/runtime compatibility.
- Documentation no longer claims full support for stubbed features.

### Phase 1: `yaya.txt`, `dicdir`, and Loading Order

Make Ourin load standard YAYA dictionary layouts directly.

Tasks:

- Extend `parseYayaConfigFile` in Swift to recognize:
  - `dicdir, path`
  - optional comments and whitespace
  - `_loading_order.txt` inside each `dicdir`
- Resolve `dicdir` entries relative to `ghost/master`.
- If `_loading_order.txt` exists:
  - read it in the directory's declared/default charset
  - ignore blank lines and comments
  - load only enabled entries in listed order
- If `_loading_order.txt` does not exist:
  - load `.dic` files in deterministic lexical order
- Represent dictionary load entries as structured data:
  - relative path
  - optional encoding
  - source config file
  - source line
- Extend the JSON IPC `load` command to pass structured dictionary metadata, while keeping current string list compatibility during transition.
- Add duplicate suppression with stable first occurrence behavior.
- Keep cycle prevention for `include`.

Acceptance criteria:

- A ghost with:

```txt
dicdir, yaya_base
```

loads yaya-dic's intended dictionary set in the intended order.

- Existing ghosts that only use `dic, file.dic` continue to load unchanged.

### Phase 2: Encoding Model

Make dictionary decoding predictable and compatible with Shift_JIS/CP932-heavy ghosts.

Tasks:

- Preserve charset declarations discovered from `yaya.txt`, included config files, and per-dic entries.
- Pass per-dictionary encoding hints to `DictionaryManager`.
- Keep current UTF-8 BOM and valid UTF-8 auto-detection safeguards.
- Decode `_loading_order.txt` with the same charset strategy.
- Add tests for:
  - UTF-8 with BOM
  - UTF-8 without BOM
  - CP932 dictionary
  - CP932 config that includes UTF-8 dictionary
  - incorrect charset declaration with valid UTF-8 content

Acceptance criteria:

- CP932 YAYA dictionaries with Japanese identifiers and strings load without mojibake.
- UTF-8 dictionaries are not accidentally converted as CP932.

### Phase 3: Parser Grammar Completion

Close the known Emily4 parser gaps and remove tolerant-but-wrong parsing.

Tasks:

- Introduce dedicated AST nodes for:
  - `CaseNode`
  - `WhenClauseNode`
  - `SwitchNode` with YAYA-specific semantics
  - `BlockLiteralNode`
  - `LabeledBlockNode`
  - `ArrayLiteralNode` / tuple literal
- Implement `case expr { when a,b { ... } others { ... } }`.
- Implement standalone `when` only where the grammar actually permits it.
- Implement block literals with `--` separators.
- Implement nested/labeled block forms such as:

```yaya
{{LABEL
    ...
}}LABEL
```

- Revisit `switch` parsing so it supports real YAYA dictionary idioms rather than only index selection.
- Remove parser "success" paths that silently skip important tokens and produce incorrect runtime behavior.
- Keep progress guarantees and parse timeout protection.

Acceptance criteria:

- All files listed as failing in `yaya_core/PARSER_PROGRESS_UPDATE.md` parse without timeout.
- Parser tests assert AST shape for `case/when`, `switch`, `--` block literals, and labeled blocks.

### Phase 4: Runtime Semantics for Advanced Constructs

Make newly parsed syntax behave correctly.

Tasks:

- Execute `case/when` by evaluating the case expression once and running only the first matching clause.
- Implement `others` / `default` fallback.
- Implement block literal evaluation rules.
- Implement array literal and tuple behavior consistently with current `Value` arrays.
- Correct array element assignment and compound assignment:
  - `arr[i] = value`
  - `arr[i] += value`
  - `arr[i] ,= value`
- Add tests for side-effect behavior so non-selected `when` bodies do not run.

Acceptance criteria:

- Runtime behavior for `case/when` matches YAYA examples and Emily4 expectations.
- Array element assignment mutates only the targeted element.

### Phase 5: Function Declaration and Dispatch Semantics

Support YAYA function declaration metadata more faithfully.

Tasks:

- Replace the simple `functions_[name] = func` registry with a function registry that can hold multiple declarations per name.
- Track:
  - source dictionary
  - declaration order
  - function type
  - attributes
  - enabled/undefined state
- Complete semantics for:
  - `array`
  - `sequential`
  - `nonoverload`
  - `when`
- Implement or complete:
  - `FUNCDECL_READ`
  - `FUNCDECL_WRITE`
  - `FUNCDECL_ERASE`
  - `GETFUNCINFO`
  - `GETFUNCLIST`
  - `ISFUNC`
  - `UNDEFFUNC`

Acceptance criteria:

- Multiple same-name functions dispatch according to declaration metadata.
- Sequential functions concatenate in correct order.
- Array functions return array values without lossy string conversion.

Implementation outcome:

- Implemented a multi-declaration function registry with source ID,
  declaration order, enabled state, and modifier flags.
- Default same-name declarations concatenate in declaration order.
- `nonoverload` disables accumulation: the latest registered declaration
  replaces earlier declarations for that name (last definition wins).
- `FUNCDECL_READ`, `FUNCDECL_WRITE`, `FUNCDECL_ERASE`, `GETFUNCINFO`,
  `GETFUNCLIST`, `ISFUNC`, `UNDEFFUNC`, and `EVAL` use the registry.
- Limitation: the `when` attribute is recorded, but standalone `when`
  dispatch does not yet model an implicit switch state.

### Phase 6: Dynamic Dictionary Operations

Implement runtime dictionary loading and unloading.

Tasks:

- Implement `DICLOAD(filename)`:
  - resolve safely under `ghost/master`
  - decode using configured charset strategy
  - parse and register functions with dictionary ownership
- Implement `DICUNLOAD(filename)`:
  - unregister functions owned only by that dictionary
  - preserve functions from other dictionaries
- Implement `APPEND_RUNTIME_DIC(code)`:
  - parse code string as a temporary runtime dictionary
  - assign synthetic source ID
- Make dynamic operations report errors through `GETLASTERROR` / `SETLASTERROR`.

Acceptance criteria:

- A dictionary can define a new event at runtime, call it, unload it, and then observe that it is gone.
- Dynamic load failures do not corrupt the existing registry.

Implementation outcome:

- `DICLOAD` and `DICUNLOAD` are implemented through `VMCallback` and
  `DictionaryManager`, with each loaded file assigned a source ID.
- `APPEND_RUNTIME_DIC` parses code strings into a synthetic runtime source.
- `DICUNLOAD` removes only declarations owned by the unloaded source.
- Runtime dictionary paths are restricted to relative paths under the ghost
  root; absolute paths and parent traversal are rejected.

### Phase 7: Variable Persistence and Settings

Implement common persistence functions needed by real ghosts.

Tasks:

- Implement `SAVEVAR(file)` and `RESTOREVAR(file)`.
- Store files under `ghost/master/var` unless a stricter existing convention is identified.
- Serialize `Value` types losslessly:
  - string
  - integer
  - real
  - array
  - dictionary if currently supported by `Value`
- Implement:
  - `GETSETTING`
  - `SETSETTING`
  - `GETDELIM`
  - `SETDELIM`
  - `DUMPVAR`
- Implement temp variable registration used by yaya-dic:
  - `REGISTERTEMPVAR` / `UNREGISTERTEMPVAR` built-ins
  - framework-level calls such as `SHIORI3FW.RegisterTempVar` can map to those
    built-ins when the yaya-dic framework is present
  - unload-time cleanup behavior

Acceptance criteria:

- User variables survive unload/reload.
- Registered temporary variables are not persisted.
- Persistence cannot escape the ghost directory.

Implementation outcome:

- `SAVEVAR` and `RESTOREVAR` persist global variables as JSON with type tags.
- Persistence paths are anchored under the ghost root and reject absolute /
  parent-traversal paths.
- `REGISTERTEMPVAR` and `UNREGISTERTEMPVAR` maintain the save-exclusion list.
- `GETSETTING`, `SETSETTING`, `GETDELIM`, `SETDELIM`, `GETLASTERROR`,
  `SETLASTERROR`, `GETERRORLOG`, `CLEARERRORLOG`, `GETCALLSTACK`, and
  `DUMPVAR` are backed by VM state.

### Phase 8: SAORI and Host Operations

Complete the bridge between YAYA and Ourin's Swift host capabilities.

Tasks:

- Finish YAYA built-ins:
  - `LOADLIB`
  - `UNLOADLIB`
  - `REQUESTLIB`
  - yaya-dic wrappers `FUNCTIONLOAD`, `FUNCTIONEX`, `SAORI`
- Route all SAORI calls through `YayaAdapter.handlePluginOperation`.
- Parse SAORI responses and set:
  - return value from `Result`
  - `valueex`
  - `valueex0`, `valueex1`, ...
  - status/error variables
- Honor SAORI charset settings:
  - `CHARSETLIB`
  - `CHARSETLIBEX`
  - request/response charset headers
- Add integration tests with a small deterministic SAORI fixture.

Acceptance criteria:

- yaya-dic SAORI helper functions work against a real or fixture SAORI module.
- Multi-value SAORI responses are visible from YAYA code.

Implementation outcome:

- `LOADLIB`, `UNLOADLIB`, and `REQUESTLIB` route through host IPC to
  `YayaAdapter` / `SaoriManager`.
- `REQUESTLIB` parses `Result` and ordered `Value0..` values; extras are
  exposed through `valueex` and `valueex0..15`.
- `FUNCTIONLOAD`, `FUNCTIONEX`, and `SAORI` are available as yaya-dic-style
  wrappers.
- `CHARSETLIB` and `CHARSETLIBEX` set the default SAORI request charset.

### Phase 9: SHIORI/3.0 and UKADOC Header Compatibility

Align request/response handling with UKADOC.

Tasks:

- Expand request header construction in `YayaCore` / `YayaAdapter` to include:
  - `Sender`
  - `SenderType`
  - `SecurityLevel`
  - `SecurityOrigin`
  - `Status`
  - `BaseID`
  - `Reference*`
  - `X-SSTP-PassThru-*`
- Preserve caller-provided headers without accidental duplication.
- Parse response headers:
  - `Value`
  - `ValueNotify`
  - `Reference*`
  - `Marker`
  - `MarkerSend`
  - `SecurityLevel`
  - `ErrorLevel`
  - `ErrorDescription`
  - `BalloonOffset`
  - `Age`
  - `X-SSTP-PassThru-*`
- Return all relevant headers to Swift.
- Confirm `GET` / `NOTIFY` behavior:
  - `GET` uses `Value`
  - `NOTIFY` ignores `Value` but may process `ValueNotify`
- Align `capability` handling with UKADOC's request/response capability notification expectations.

Acceptance criteria:

- UKADOC-documented headers can round-trip through `yaya_core`.
- Events with response `Reference*` and `ValueNotify` work.

Implementation outcome:

- Request construction includes defaults for `Charset`, `Sender`,
  `SenderType`, and `SecurityLevel`.
- Caller-provided headers are emitted once with case-insensitive
  deduplication; `ID` is not duplicated.
- Caller `Reference*` headers are preserved, then the `ref` array is overlaid
  as the final `Reference0..N` source.
- Response parsing returns generic headers to Swift, including `Value`,
  `ValueNotify`, `Reference*`, and `X-SSTP-PassThru-*`.

### Phase 10: Built-in Function Audit

Audit all built-ins against source and documentation.

Tasks:

- Classify every built-in in `FUNCTION_REFERENCE.md` as:
  - implemented
  - partial
  - stub
  - intentionally unsupported on macOS
- Complete high-impact partial/stub functions:
  - `RE_ASEARCH`
  - `RE_ASEARCHEX`
  - `ISEVALUABLE`
  - `GETERRORLOG`
  - `GETCALLSTACK`
  - `GETFUNCINFO`
  - global define functions
  - charset ID/name functions
- Keep Windows-specific functions as explicit compatibility shims where macOS cannot support them.
- Record intentional deviations in documentation.

Acceptance criteria:

- Function docs match behavior.
- Stub functions are either implemented or documented as intentionally unsupported.

Implementation outcome:

- `RE_ASEARCH` and `RE_ASEARCHEX` are implemented with `std::regex`.
- `ISEVALUABLE` now parses exactly one complete expression, so malformed input
  such as `1 +` returns `0`.
- `GETERRORLOG`, `GETCALLSTACK`, `GETFUNCINFO`, global define functions, and
  charset ID/name helpers are implemented.
- Remaining stubs are documented as directory operations or Windows-only /
  platform shims.

## Testing Strategy

### Unit Tests

- Lexer token tests for advanced punctuation and UTF-8 identifiers.
- Parser AST tests for each newly supported construct.
- VM tests for runtime semantics.
- DictionaryManager tests for ordered load/unload behavior.
- Swift tests for `yaya.txt` config parsing.

### Integration Tests

- Minimal ghost:
  - simple `OnBoot`
  - `reference[]`
  - `_argv`
  - persistence
- yaya-dic ghost:
  - `dicdir, yaya_base`
  - `request`
  - `capability`
- Emily4 compatibility:
  - load all target dictionaries
  - execute representative events
  - assert no parser timeout

### Regression Metrics

Track these metrics before and after each phase:

- Number of dictionaries discovered from config
- Number of dictionaries successfully parsed
- Parse time per dictionary
- Total load time
- Number of warnings/errors
- Representative event success rate
- Host operation success/failure counts

## Risk Management

### Parser Ambiguity

YAYA syntax is permissive and historically compatibility-driven. Add dedicated AST nodes rather than continuing to skip unknown tokens silently. Silent recovery should be limited to diagnostics mode.

### Compatibility vs Security

File, command, SAORI, and dynamic dictionary operations must remain constrained to safe paths or explicit host-mediated operations. Do not broaden file access to match Windows YAYA behavior exactly without an Ourin security decision.

### Documentation Drift

Every phase that changes behavior must update:

- implementation status
- function reference
- compatibility matrix
- tests or fixtures

## Recommended Order

1. Phase 0: baseline and docs — **done**
2. Phase 1: `dicdir` and loading order — **done**
3. Phase 2: encoding model — **done**
4. Phase 3: parser grammar completion — **done**
5. Phase 4: runtime semantics — **done**
6. Phase 5: function declaration semantics — **done**
7. Phase 6: dynamic dictionary operations — **done**
8. Phase 7: persistence/settings — **done**
9. Phase 8: SAORI host integration — **done**
10. Phase 9: SHIORI/3.0 headers — **done**
11. Phase 10: built-in audit — **done**

The highest immediate compatibility gain should come from Phases 1, 3, and 4 because they unblock yaya-dic standard loading and the known Emily4 parser failures.
