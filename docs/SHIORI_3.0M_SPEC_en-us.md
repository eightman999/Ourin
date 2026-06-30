# SHIORI/3.0M — macOS Native Differential Specification (Draft)

**Status:** Draft
**Original:** [SHIORI_3.0M_SPEC_ja-jp.md](./SHIORI_3.0M_SPEC_ja-jp.md)
**Language:** English (US)
**Updated:** 2025-07-27
**Audience:** Ourin (Rin) baseware implementers and SHIORI authors
**Scope:** Maintains vocabulary/behavior compatibility with UKADOC **SHIORI/3.0** while replacing Windows DLL dependencies (GlobalAlloc, etc.) with **macOS Bundle (.bundle/.plugin) + C ABI**.
**Non-goal:** Binary compatibility with Windows DLL (vocabulary and behavior compatibility only).

---

## Table of Contents
- [1. Purpose and Policy](#1-purpose-and-policy)
- [2. Terminology](#2-terminology)
- [3. Compatible (Unchanged)](#3-compatible-unchanged)
- [4. macOS Differences (Replacements)](#4-macos-differences-replacements)
- [5. Character Encoding Policy](#5-character-encoding-policy)
- [6. Request/Response (Wire Specification)](#6-requestresponse-wire-specification)
- [7. 2.x (2.0/2.5) Compatibility](#7-2x-2025-compatibility)
- [8. Examples (OnBoot/OnCommunicate)](#8-examples-onbootoncommunicate)
- [9. Minimal Implementation (C ABI and Template)](#9-minimal-implementation-c-abi-and-template)
- [10. Ourin Host Implementation Notes](#10-ourin-host-implementation-notes)
- [11. Implementation Status](#11-implementation-status)
- [12. Conformance Checklist](#12-conformance-checklist)
- [13. References (Normative/Informative)](#13-references-normativeinformative)

---

## 1. Purpose and Policy
- **SHIORI/3.0 vocabulary and behavior** (`GET/NOTIFY`, `ID`, `Reference*`, `Charset`, `SecurityLevel/Origin`, etc.) are **adopted as-is**.
- The implementation (Windows DLL conventions) is **reinterpreted** as **macOS Bundle + C ABI**. **XPC isolation** is an optional recommendation.

## 2. Terminology
- **3.0M**: Identifier for this macOS differential specification.
- **Host**: Baseware such as Ourin.
- **Module**: SHIORI implementation body (`.bundle`/`.plugin`).
- **Wire**: SHIORI message using CRLF line endings with blank line terminator (SHIORI/3.0 syntax).

## 3. Compatible (Unchanged)
- **Methods**: `GET` (expects a return value), `NOTIFY` (does not expect a return value).
- **Wire syntax**: CRLF line endings, **blank-line terminated**, header ordering (`Charset` near the top).
- **Key headers**: `ID`, `Reference0..N`, `Sender`, `SenderType`, `SecurityLevel`, `SecurityOrigin`, `BaseID`, `Status`, and others.
- **Response**: `SHIORI/3.0 200/204/...` with `Value` (and optional extensions such as `ValueNotify`).

## 4. macOS Differences (Replacements)
### 4.1 Implementation (DLL → Bundle) and Exports
- Distribution: `.bundle` (or `.plugin`). **Universal 2** (`arm64`/`x86_64`) recommended.
- Exports (**C ABI**):
  ```c
  bool shiori_load(const char* dir_utf8);
  void shiori_unload(void);
  bool shiori_request(const unsigned char* req, size_t req_len,
                      unsigned char** res, size_t* res_len);
  void shiori_free(unsigned char* p);
  ```
- **Loading/Resolution**: Resolved from CFBundle by **function name** (`CFBundleGetFunctionPointerForName`).
- **Memory management**: The return value **must be freed by the caller (host) via shiori_free**. Mixing global allocators is not permitted.

### 4.2 Execution Container (Optional)
- Minimum is **in-process loading**.
- For analysis or stability, isolate to an **XPC service** and bridge via `Data -> Data`.

## 5. Character Encoding Policy
- **Default is UTF-8**.
- For compatibility, `Shift_JIS / Windows-31J / CP932 / SJIS` labels are accepted as **equivalent** (treated as CP932).
- The response `Charset` should match the request charset.

## 6. Request/Response (Wire Specification)
- **First line**: `GET SHIORI/3.0` or `NOTIFY SHIORI/3.0`.
- **Terminator**: CRLF + CRLF. **Do not assume null termination**.
- **Example (minimal)**:
  ```
  GET SHIORI/3.0
  Charset: UTF-8
  ID: OnBoot

  ```
  **Response**
  ```
  SHIORI/3.0 200 OK
  Charset: UTF-8
  Value: \h\s0Hello from 3.0M

  ```

## 7. 2.x (2.0/2.5) Compatibility
- Only **vocabulary/behavior compatibility** is provided. **Binary compatibility is not provided**.
- **SHIORI Resource** (from 2.5) is organized in 3.0 onwards as **roughly equivalent to a normal Event**. Return values are treated as **short text**.
- 2.x-style queries are mapped to **3.0 `ID`/`Reference*`** where possible.

## 8. Examples (OnBoot/OnCommunicate)
**OnBoot (startup)**
```
GET SHIORI/3.0
Charset: UTF-8
Sender: Ourin
ID: OnBoot

```
**OnCommunicate (dialogue)**
```
GET SHIORI/3.0
Charset: UTF-8
Sender: Ourin
ID: OnCommunicate
Reference0: Hello

```

## 9. Minimal Implementation (C ABI and Template)
**Header**
```c
// shiori.h (3.0M)
#pragma once
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif
bool shiori_load(const char* dir_utf8);
void shiori_unload(void);
bool shiori_request(const unsigned char* req, size_t req_len,
                    unsigned char** res, size_t* res_len);
void shiori_free(unsigned char* p);
#ifdef __cplusplus
} // extern "C"
#endif
```

**Implementation (ultra-minimal)**
```c
// shiori.c (3.0M minimal)
#include "shiori.h"
#include <string.h>
#include <stdlib.h>

bool shiori_load(const char* dir_utf8){ (void)dir_utf8; return true; }
void shiori_unload(void){}

static unsigned char* duputf8(const char* s, size_t* out){
  size_t n = strlen(s);
  unsigned char* p = (unsigned char*)malloc(n);
  if(!p) return NULL; memcpy(p, s, n); *out = n; return p;
}

bool shiori_request(const unsigned char* req, size_t len,
                    unsigned char** res, size_t* res_len){
  (void)len;
  const char *ok =
    "SHIORI/3.0 200 OK\r\n"
    "Charset: UTF-8\r\n"
    "Value: \\h\\s0Hello from 3.0M\r\n"
    "\r\n";
  *res = duputf8(ok, res_len);
  return *res != NULL;
}

void shiori_free(unsigned char* p){ free(p); }
```

## 10. Ourin Host Implementation Notes
- Load via `CFBundle`, calling `shiori_load` → `shiori_request` → `shiori_unload` (on exit).
- When using **XPC isolation**, bridge via a fixed `request(Data)->Data` interface.
- **macOS 10.15+ / 64-bit only**, **Universal 2** distribution as the baseline.

## 10.1 BridgeToSHIORI — Event Pipeline Implementation

`BridgeToSHIORI.swift` is the bridge layer that converts internal host events into SHIORI/3.0 wire format and forwards them to a native SHIORI bundle or the live loaded ghost (YAYA, etc.).

### Method Selection

| Caller | Method | Wire first line |
|---|---|---|
| `sendGet` / `sendGetCustom` | `GET` | `GET SHIORI/3.0` |
| `sendNotify` / `sendNotifyCustom` | `NOTIFY` | `NOTIFY SHIORI/3.0` |

- NOTIFY is never coerced into GET. `EventBridge.sendNotify` always passes `method: "NOTIFY"`, and `BridgeToSHIORI.handle` forwards that value unchanged to `ShioriHost.request` (see `BridgeToSHIORI.swift:250`: `let verb = method.uppercased() == "NOTIFY" ? "NOTIFY" : "GET"`).
- Timer events (`OnSecondChange`, etc.) dynamically switch between GET and NOTIFY based on the `cantalk` flag (`EventBridge.swift:443–451`).

### handle vs. handleResponse

`BridgeToSHIORI` exposes two public methods.

- **`handle(event:references:headers:method:) -> String`**
  Returns only the `Value` (script string) from the response. Used by callers such as `GhostManager`, `ResourceBridge`, and `WebHandler` that consume the result directly as a script value.

- **`handleResponse(event:references:headers:method:) -> String`**
  Returns the full SHIORI/3.0 wire response string (`SHIORI/3.0 200 OK\r\n...`).
  Used exclusively on the SSTP dispatcher path so that `SSTPDispatcher.mapShioriResponse` can parse all headers including `ReferenceN`, `Value`, `ValueNotify`, and `Status`.

### Bridge to Live Ghost (liveGhostResolver)

When no native SHIORI bundle is configured (`SHIORI_BUNDLE_PATH` environment variable is absent), `handle` / `handleResponse` call the `liveGhostResolver` closure.
This closure is set by AppDelegate at startup and routes the request to the actually loaded ghost (YAYA, etc.).
If no matching ghost exists or cannot respond, the resolver returns `nil` (`handle` returns an empty string).

Priority: **registered Resource value (test) → native SHIORI bundle → liveGhostResolver (live ghost)**

### Resource Event Normalization

When the event name is `Resource`, `references[0]` is treated as the resource name.
Internally it is sent as a standard SHIORI `GET` (`ID: Resource` / `Reference0: <name>`), and the return value is treated as a short text value (3.0 mapping of the SHIORI/2.5-origin Resource).

### ReceiverGhostName Routing

When the SSTP frame contains a `ReceiverGhostName` header, `liveGhostResolver` routes the request only to the session matching that ghost name. If the header is absent, the request goes to the primary ghost.

### Wire Serialization and Header Sanitization

When `handleResponse` serializes a structured live-ghost response to a wire string, it strips CR/LF from all header values and the `Value` field.
Because SakuraScript newlines are represented as `\n` tokens, removing raw newlines has no visible impact on script rendering.

## 11. Implementation Status

**Updated:** 2025-10-20

### 11.1 Ourin Host-Side Implementation

- [x] **CFBundle loading**: Implemented in `ShioriLoader.swift`
- [x] **YAYA backend**: YAYA ghost support implemented in `YayaBackend` and `YayaAdapter.swift`
- [x] **Character encoding**: UTF-8 default; Shift_JIS/CP932 acceptance implemented
- [x] **Request/Response processing**: Basic wire protocol processing with CRLF + blank-line termination implemented
- [ ] **Bundle/Plugin-format SHIORI**: Direct C ABI loading not implemented (YAYA only at present)
- [x] **XPC isolated execution**: Implemented (`XpcBackend` in `ShioriLoader.swift` bridges `OurinShioriXPC` via `Data->Data`. Updated 2026-06-15)
- [ ] **shiori_free memory management**: Not applicable until C ABI is implemented

### 11.2 Implemented Features

1. **YAYA ghost support**
   - Parsing and loading of `yaya.txt`
   - Recursive loading of `dic` files
   - Request/response processing
   - Basic events: `OnBoot`, `OnCommunicate`, etc.

2. **Character encoding**
   - UTF-8 as default
   - Automatic detection and conversion of Shift_JIS/CP932

3. **Event system**
   - System event monitoring and forwarding to SHIORI
   - Event dispatching via `EventBridge`

### 11.3 Unimplemented Features

1. **Bundle/Plugin loading via C ABI**
   - Implementation of `shiori_load`, `shiori_request`, `shiori_unload`, `shiori_free`
   - Function pointer resolution from CFBundle

2. ~~**XPC service isolation**~~ → Implemented (`XpcBackend`). Supports separate-process execution and sandbox isolation.

3. **SHIORI/2.x compatibility**
   - 2.x protocol support (not supported due to binary IPC convention differences; consolidated to 3.0)

## 12. Conformance Checklist
- [x] `GET/NOTIFY SHIORI/3.0` round-trips with CRLF + blank-line termination (implemented via YAYA backend)
- [x] Missing `Charset` defaults to UTF-8; SJIS-family labels accepted as CP932
- [x] `Value`/`ValueNotify` and other extensions implemented as needed (basic implementation done)
- [ ] Implementation as `.bundle/.plugin` (Universal 2) + **C ABI** (not yet implemented)
- [ ] Return-value release via **shiori_free** (not yet implemented)

## 13. References (Normative/Informative)
- SHIORI/3.0 (UKADOC)
- SHIORI Event list / notes
- DLL common specification (basis for Windows GlobalAlloc conventions; replaced in 3.0M)
- Apple: CFBundle (function pointer resolution by name) / NSXPCConnection (isolated execution)
- macOS 10.15+; 32-bit not supported
