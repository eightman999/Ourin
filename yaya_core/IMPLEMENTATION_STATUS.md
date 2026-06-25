# YAYA Core Implementation Status

## Status Legend

- **implemented** — works and matches YAYA reference behavior for common cases
- **partial** — parses/executes but with known correctness gaps or restrictions
- **stub** — present for compatibility but returns a safe default (no real behavior)
- **unsupported** — intentionally not available on macOS / not yet implemented

## Overview

`yaya_core` is a C++ helper process that parses and executes YAYA ghost
dictionaries on macOS, communicating with the Swift host (`YayaAdapter`) via
JSON-line IPC. It is **not** a 100% faithful reimplementation of the Windows
`yaya-shiori` reference; this document records what actually works versus what
is a compatibility shim.

Previous versions of this document claimed "100% function coverage" and "Emily4
fully supported". That overstated reality: many listed functions were stubs, and
several parsed constructs lacked faithful runtime semantics. This revision
corrects the record.

## Loading & Configuration

| Capability | Status | Notes |
| --- | --- | --- |
| `dic, file.dic` | implemented | |
| `dic, file.dic, encoding` (per-dic encoding) | implemented | Phase 1: per-dic encoding honored end-to-end |
| `include, file` | implemented | recursive, with cycle prevention |
| `charset, X` / `charset.*` directives | implemented | `charset.dic` selects the dictionary encoding |
| `dicdir, path` | implemented | Phase 1: expands directory, honors `_loading_order.txt` |
| `_loading_order.txt` (order + encoding) | implemented | real yaya-dic format: `dic, filename, encoding` and `dicif, filename, encoding` (load-if-exists); legacy `flag,filepath` / bare `filepath` also tolerated |
| Duplicate dic suppression | implemented | first-occurrence wins |
| `yaya.txt` absent → load all `.dic` | implemented | lexical fallback |

## Encoding Model

| Capability | Status | Notes |
| --- | --- | --- |
| UTF-8 (with/without BOM) | implemented | BOM stripped |
| CP932 / Shift_JIS via iconv | implemented | auto-fallback when declared but content is valid UTF-8 |
| Auto detection | implemented | UTF-8 validity check, else CP932 conversion |
| Per-dic encoding override | implemented | Phase 1/2 |

## Parser / AST

| Construct | Status | Notes |
| --- | --- | --- |
| Function definitions (`name { }`) | implemented | dotted names, `: type` annotations recorded |
| `if` / `elseif` / `else` | implemented | |
| `while` | implemented | |
| `for` (C-style) | implemented | |
| `foreach` | implemented | |
| `switch expr { ... }` | implemented | index-based selection; supports `--`-separated block literals and one-per-line forms |
| `case expr { when .. { } others { } }` | implemented | Phase 3/4: dedicated AST, expr evaluated once, first-match semantics |
| Standalone `when` (labeled blocks) | partial | parses as passthrough; no implicit switch dispatch |
| Block literal `{ a -- b -- c }` | implemented | `--` lexed as operator after values; switch + block supported |
| Labeled blocks `{{LABEL .. }}LABEL` | partial | tolerated via brace/label recovery; not a first-class node |
| Array literals `(a, b, c)` | implemented | |
| Dotted identifiers (`SHIORI3FW.Status`) | implemented | |
| `reference[i]`, `_argv` | implemented | |
| `_in_` / `!_in_` | implemented | |
| UTF-8 / Japanese identifiers | implemented | |
| Compound assignments (`+=` etc., `,=`) | implemented | |
| Array element assignment (`a[i] = ..`) | partial | stored against the array variable (compound form is approximate) |
| Prefix `&` (reference operator) | partial | parsed; treated as identity (no true by-reference) |

### Parser Reliability Note

The parser uses "progress guarantee" recovery (forced token advance on
no-progress) plus safety counters to avoid infinite loops. This means essentially
every dictionary file *loads* without timeout, but tolerant skipping can produce
incomplete ASTs for advanced edge cases. Emily4 currently loads 33/33 configured
dictionaries without parse failure (regression baseline after Phases 1/3/4).

## Runtime / VM

| Capability | Status | Notes |
| --- | --- | --- |
| Variable storage / scopes | implemented | |
| Expression evaluation | implemented | |
| Function calls (user + built-in) | implemented | |
| `return` / `break` / `continue` | implemented | |
| `case/when` first-match + `others` | implemented | Phase 4: non-selected bodies do not run |
| Overload function dispatch | implemented | Phase 5: default = all same-name declarations concatenate in declaration order; `nonoverload` disables accumulation — the latest declaration replaces earlier ones (last definition wins) |
| `array` / `sequential` / `void` type modifiers | implemented | Phase 5: multi-word modifiers (e.g. `nonoverload array`) supported |
| Function declaration metadata | implemented | Phase 5: `FUNCDECL_READ/WRITE/ERASE`, `GETFUNCINFO`, `UNDEFFUNC` |
| Dynamic dictionaries (`DICLOAD`/`DICUNLOAD`/`APPEND_RUNTIME_DIC`) | implemented | Phase 6: per-source ownership, load/unload at runtime |
| Persistence (`SAVEVAR`/`RESTOREVAR`) | implemented | Phase 7: anchored under ghost root; temp vars registered via `REGISTERTEMPVAR` are excluded |
| Settings (`GETSETTING`/`SETSETTING`/`GETDELIM`/`SETDELIM`/`DUMPVAR`) | implemented | Phase 7 |
| SHIORI `request`/`load`/`unload` framework dispatch | implemented | full SHIORI response header parsing |

## Built-in Functions — Audit Summary

> Detailed per-function status lives in `FUNCTION_REFERENCE.md`.

- **Type conversion / string / math / array / bitwise / hex-binary**: implemented
- **Type checking** (`ISINTSTR`, `ISREALSTR`): implemented
- **File I/O** (`FOPEN`…`FDEL`, `FCOPY`…): implemented **with security restriction** (relative paths only; no absolute / no `..`)
- **System** (`GETTIME`, `EXECUTE`, `EXECUTE_WAIT`, `SLEEP`, `GETENV`): implemented
- **Variable/function mgmt** (`ISVAR`, `ISFUNC`, `EVAL`, `GETFUNCLIST`, …): implemented
- **Regular expressions** (`RE_*`): implemented (std::regex; Phase 10 completed `RE_ASEARCH`/`RE_ASEARCHEX`)
- **Dynamic dictionaries** (`DICLOAD`, `DICUNLOAD`, `UNDEFFUNC`, `APPEND_RUNTIME_DIC`): implemented (Phase 5/6)
- **Persistence** (`SAVEVAR`, `RESTOREVAR`): implemented (Phase 7, anchored under ghost root)
- **SAORI/Plugin** (`LOADLIB`, `UNLOADLIB`, `REQUESTLIB`): implemented (Phase 8: Result + valueex parsing, `CHARSETLIB`, `FUNCTIONLOAD/EX/SAORI` wrappers)
- **Settings** (`GETSETTING`, `SETSETTING`, `GETDELIM`, `SETDELIM`, `DUMPVAR`): implemented (Phase 7)
- **Diagnostics** (`GETERRORLOG`, `GETCALLSTACK`, `GETFUNCINFO`, `GETLASTERROR`/`SETLASTERROR`): implemented (Phase 5/7/10)
- **Encoding utils** (`CHARSETTEXTTOID`, `CHARSETIDTOTEXT`, `CHARSETLIB/EX`, `ZEN2HAN`, `HAN2ZEN`): implemented
- **Global defines** (`IS/SET/UNDEF/PROCESSGLOBALDEFINE`): implemented (Phase 10)
- **Directory ops** (`MKDIR`, `RMDIR`, `FENUM`): **stub**

## SHIORI / UKADOC Header Compatibility

| Area | Status | Notes |
| --- | --- | --- |
| Request headers (Sender, SenderType, SecurityLevel, SecurityOrigin, ID, Status, BaseID, Reference*) | implemented | Phase 9: caller headers pass through without duplication |
| `X-SSTP-PassThru-*` headers | implemented | Phase 9: forwarded both directions |
| Response headers (Value, ValueNotify, Reference*, Marker, MarkerSend, SecurityLevel, ErrorLevel, BalloonOffset, Age) | implemented | parsed generically; returned to Swift |
| GET vs NOTIFY semantics | implemented | NOTIFY-only events ignore Value; ValueNotify still forwarded |

## Known Limitations

- **By-reference semantics**: `&` is parsed but treated as pass-by-value (`E.Swap`/`E.Qsort` in-place effects are not honored).
- **Standalone `when` dispatch**: inside labeled blocks, `when` runs unconditionally (no implicit state switch). The `when` function attribute is recorded but does not add implicit dispatch.
- **Directory ops**: `MKDIR`/`RMDIR`/`FENUM` remain stubs (use host file ops via FOPEN-style relative sandbox if needed).
- **SAORI valueex as variables**: extras are exposed via `valueex`/`valueex0..15` builtins rather than implicit variables (framework scripts manage their own copy).

## Integration

- `yaya_core` builds via CMake (`./build.sh`); universal binary (arm64 + x86_64).
- Integrated into the app bundle as an auxiliary executable.
- IPC: JSON lines on stdin/stdout; `host_op` requests (file, execute, plugin/SAORI) handled by `YayaAdapter`.
- SAORI load/unload/request routed through `SaoriManager`; multi-value response mapping is partial.

## Success Criteria — Honest Assessment

- yaya_core compiles: yes
- Simple YAYA dictionaries parse and execute: yes
- IPC with Swift YayaAdapter works: yes
- All `yaya-shiori-500` functions *present*: yes (but many are stubs — see above)
- Emily4 loads all configured dictionaries: yes (33/33 without parse failure)
- Emily4 event responses are correct for common events: **partial** (advanced constructs and stubbed helpers still limit full fidelity)
