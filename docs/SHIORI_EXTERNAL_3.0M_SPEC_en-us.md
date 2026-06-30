# SHIORI External Events — **3.0M-Mac Specification (UKADOC-compliant)**

**Status:** Draft / Ourin (macOS 10.15+ / Universal 2)
**Original:** [SHIORI_EXTERNAL_3.0M_SPEC_ja-jp.md](./SHIORI_EXTERNAL_3.0M_SPEC_ja-jp.md)
**Language:** English (US)
**Updated:** 2025-07-27 (JST)
**Compatibility policy:** Follows UKADOC "External SHIORI Events" for event names, semantics, and Reference ordering. Windows-dependent transport is replaced with **macOS-native** equivalents.
**Intended audience:** Ourin (baseware) implementers and external application developers.

---

## Table of Contents
- [1. Purpose and Scope](#1-purpose-and-scope)
- [2. Transport](#2-transport)
  - [2.1 Socket SSTP (TCP/9801)](#21-socket-sstp-tcp9801)
  - [2.2 SSTP-over-HTTP (extension)](#22-sstp-over-http-extension)
  - [2.3 DirectSSTP-Mac as XPC (extension)](#23-directsstp-mac-as-xpc-extension)
- [3. Character Encoding / Line Endings / Path Notation](#3-character-encoding--line-endings--path-notation)
- [4. Event Compatibility Rules](#4-event-compatibility-rules)
- [5. Frame Examples (SSTP/HTTP/XPC)](#5-frame-examples-sstphttpxpc)
- [6. Security / Sandbox](#6-security--sandbox)
- [7. Test Checklist](#7-test-checklist)
- [8. BridgeToSHIORI — SSTP to SHIORI Bridge Behavior](#8-bridgetoshiori--sstp-to-shiori-bridge-behavior)
- [9. Change History](#9-change-history)

---

## 1. Purpose and Scope
- Receive and forward "external SHIORI Events" fired by **external apps / other ghosts / plugins** to Ourin while preserving **vocabulary compatibility**.
- This page is a compatibility implementation guide based on the UKADOC catalog; individual event details are governed by the respective issuing source.

## 2. Transport

### 2.1 Socket SSTP (TCP/9801)
- **Send/Receive**: Receive **SSTP/1.x** frames (`NOTIFY SSTP/1.x` / `SEND SSTP/1.x`, etc.) on **TCP:9801**.
- **Response**: `SSTP/1.x 200 OK` / `204 No Content`, etc. (script is ignored for [NOTIFY]).
- **Compatibility**: Per the original spec — **CRLF line endings**, `Charset:` optional (defaults to UTF-8 if absent).

### 2.2 SSTP-over-HTTP (extension)
- **Method/Path**: `POST /api/sstp/v1`
- **Header**: `Content-Type: text/plain; charset=<enc>` (recommended)
- **Body**: **Raw SSTP/1.x text** (`NOTIFY ...` through `CRLFCRLF`).
- **Purpose**: Traversing firewalls/proxies and leveraging standard HTTP logging. **SSTP grammar is unchanged** to maintain compatibility.

### 2.3 DirectSSTP-Mac as XPC (extension)
- **IPC**: Received as a **Mach service** using `NSXPCListener(machServiceName: "jp.ourin.sstp")`.
- **Interface**: `deliverSSTP(request: Data, reply: (Data)->Void)` (accepts UTF-8/CP932).
- **Use case**: Fast local delivery and process isolation.

## 3. Character Encoding / Line Endings / Path Notation
- **Character encoding**: Default **UTF-8**. For compatibility, **CP932/Shift_JIS** is accepted and normalized to UTF-8 internally. `Charset:` takes priority when specified.
- **Line endings**: **CRLF** is required for received data (internal processing may normalize to LF).
- **Paths**: **POSIX absolute paths** or **`file://` URLs** are standard. Windows-format paths received are normalized by the receiver.

## 4. Event Compatibility Rules
- Events **marked [NOTIFY]** must always be sent as NOTIFY; the **returned script is ignored**.
- **Unmarked** events may use either **GET or NOTIFY** depending on context.
- Ourin **transparently passes unknown event names** to SHIORI/3.0 (preserving vocabulary).

## 5. Frame Examples (SSTP/HTTP/XPC)

### 5.1 Socket SSTP (TCP/9801, NOTIFY)
```
NOTIFY SSTP/1.1
Sender: ExternalApp
Charset: UTF-8
Event: OnRequestValues
Reference0: OtherGhost
Reference1: Profile
Reference2: LIFE

\r\n
```

### 5.2 SSTP-over-HTTP (POST)
```
POST /api/sstp/v1 HTTP/1.1
Host: 127.0.0.1
Content-Type: text/plain; charset=UTF-8
Content-Length: <len>

NOTIFY SSTP/1.1
Sender: ExternalApp
Event: OnRequestValues
...
```

### 5.3 DirectSSTP-Mac (XPC)
- Pass the **raw SSTP/1.x byte sequence** as `request`. The response is the raw byte sequence of `SSTP/1.x 200 OK ...`.

## 6. Security / Sandbox
- **Receive binding**: Default is `127.0.0.1` only (local only).
- **Path intake**: `file://` normalization and **security-scoped URL** management when needed.
- **XPC**: Strict **exported interface** on `NSXPCListener`; connection controlled by signature/identifier.

## 7. Test Checklist
- [ ] CRLF line endings, `Charset:` interpretation, and mixed CP932 acceptance
- [ ] Behavioral differences between [NOTIFY] and unmarked; return codes (200/204/400, etc.)
- [ ] Same event reaches SHIORI regardless of Socket/HTTP/XPC transport
- [ ] Local binding; automatic retry on port conflict
- [ ] Large bodies, multiple `ReferenceN`, and transparent pass-through of unknown event names

## 8. BridgeToSHIORI — SSTP to SHIORI Bridge Behavior

This section is based on the implementation in `BridgeToSHIORI.swift` and `EventBridge.swift`.

### 8.1 Method Preservation

- SSTP NOTIFY frames (`NOTIFY SSTP/1.x`) are forwarded to SHIORI as `NOTIFY SHIORI/3.0`. GET frames are forwarded as `GET SHIORI/3.0`.
- NOTIFY is never converted to GET (`EventBridge.sendNotify` always passes `method: "NOTIFY"`).

### 8.2 handle vs. handleResponse

The SSTP dispatcher (`SSTPDispatcher`) uses `BridgeToSHIORI.handleResponse` to receive the full SHIORI/3.0 wire response string, preserving all headers including `ReferenceN`, `Value`, `ValueNotify`, and `Status`.
Other internal callers such as `GhostManager`, `ResourceBridge`, and `WebHandler` use `BridgeToSHIORI.handle`, which returns only the `Value` (script string).

### 8.3 ReceiverGhostName Routing

When the SSTP frame contains a `ReceiverGhostName` header, the bridge routes the request only to the session matching that ghost. When the header is absent, the request is sent to the primary (first registered) ghost.

### 8.4 Resource Event Handling

When a `Resource` event arrives via SSTP, `references[0]` is used as the resource name and the request is forwarded as a SHIORI GET with `ID: Resource` / `Reference0: <name>`. The return value is treated as a short text value (the 3.0 mapping of the UKADOC SHIORI/2.5-origin Resource).

### 8.5 Bridge to the Live Ghost

When no native SHIORI bundle is configured, the bridge forwards the request to the actually loaded ghost (YAYA, etc.) via the `liveGhostResolver` closure. If no matching ghost exists, an empty response is returned.

## 9. Change History
- 2026-06-28: Added §8 "BridgeToSHIORI — SSTP to SHIORI Bridge Behavior" (behavior description aligned with implementation).
- 2025-07-27: Initial version (3.0M-Mac).
