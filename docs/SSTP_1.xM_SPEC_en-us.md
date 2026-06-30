# SSTP/1.xM — macOS Differential Specification (Draft)

**Status:** Draft
**Updated:** 2026-06-28
**Audience:** Ourin (Sakurarin) / baseware implementors and client developers
**Scope:** Defines macOS-native (Network.framework + XPC) differences required for safe operation while maintaining the vocabulary and behavior of UKADOC **SSTP/1.x**.
**Non-goals:** Binary compatibility with Windows WM_COPYDATA. Only vocabulary and behavioral compatibility.

---

## Table of Contents
- [1. Policy and Non-goals](#1-policy-and-non-goals)
- [2. Terminology](#2-terminology)
- [3. Compatibility Policy (unchanged from upstream)](#3-compatibility-policy-unchanged-from-upstream)
- [4. macOS Differences (replacements/additions)](#4-macos-differences-replacementsadditions)
- [5. Character Encoding Policy](#5-character-encoding-policy)
- [6. Header Differences (accepted/not applicable)](#6-header-differences-acceptednot-applicable)
- [7. Status Codes](#7-status-codes)
- [8. SSTP over HTTP (compatibility)](#8-sstp-over-http-compatibility)
- [9. Examples (SEND/NOTIFY/EXECUTE)](#9-examples-sendnotifyexecute)
- [10. Reference Implementation Parameters (recommended defaults)](#10-reference-implementation-parameters-recommended-defaults)
- [11. Implementation Status](#11-implementation-status)
- [12. Conformance Checklist](#12-conformance-checklist)
- [13. Appendix A: Minimum XPC DirectSSTP Interface](#13-appendix-a-minimum-xpc-directsstp-interface)

---

## 1. Policy and Non-goals
- **Wire format (method/headers/CRLF termination) conforms to SSTP/1.x.** Interpretation of `SEND/NOTIFY/COMMUNICATE/EXECUTE/GIVE`, `Charset`, `Sender`, `Option`, etc. follows the original specification. **Keep-alive is not assumed; connections are closed after each exchange.**
- **Transport layer**: TCP server implemented with **Network.framework** (default port **9801/tcp**; optional port 9821 for SSP compatibility). **Default: loopback only.**
- **DirectSSTP replacement**: Windows WM_COPYDATA-based DirectSSTP is replaced on macOS with **XPC (NSXPCConnection)** as an equivalent IPC mechanism.

## 2. Terminology
- **(Socket)SSTP**: SSTP exchanged over TCP.
- **DirectSSTP**: Lightweight SSTP using OS IPC. On macOS, this is **XPC**.
- **SSTP over HTTP**: Compatibility bridge that carries SSTP request/response as the HTTP message body.

## 3. Compatibility Policy (unchanged from upstream)
- **SSTP overview and port**: SSTP is general-purpose ghost-to-ghost communication. Implementation uses 9801/tcp (SSP may also use 9821). **9801 is the primary port in active use.** Loopback-only listening is standard.
- **Syntax**: `CRLF` line endings, **blank line terminator.** **Charset header is required** (omission causes an error or implementation-defined fallback to OS default). **Responses may carry additional data.** **Request and response may carry different SSTP version numbers**, so **version-dependent interpretation is prohibited.**
- **Methods**: `NOTIFY` (event notification), `SEND` (script delivery), `COMMUNICATE` (user-input-equivalent response), `EXECUTE` (status query/control), `GIVE` (legacy spec) are all retained.

## 4. macOS Differences (replacements/additions)
### 4.1 (Socket)SSTP (TCP)
- **Implementation**: Started with `NWListener(using: .tcp, on: 9801)`. **Default: bind to 127.0.0.1/::1 only.** External exposure is opt-in via configuration.
- **Bind address**: `SstpTcpServer.makeListener(host:port:)` determines the bind target from the `host` parameter. Specific addresses such as `127.0.0.1` / `localhost` / `::1` bind to that address only using `NWParameters.requiredLocalEndpoint`. Only `0.0.0.0` / `::` / empty string listens on all interfaces. `SstpHttpServer` uses the same `makeListener` method.
- **TCP body forwarding**: After detecting the header terminator (`\r\n\r\n`), the TCP handler passes the **entire buffer including headers and body** to the SSTP stack. The previous implementation discarded the body; since `SSTPParser` reads everything after the blank line as the body, the full buffer must be forwarded.
- **Sandbox**: Under App Sandbox, the server requires **`com.apple.security.network.server`** and the client requires **`com.apple.security.network.client`**.
- **Firewall**: When the application firewall is enabled, **incoming connections must be allowed.** Signed/downloaded apps have an automatic allow setting.

### 4.2 DirectSSTP (macOS XPC version)
- **Implementation**: An **XPC service** such as `App.app/Contents/XPCServices/ukagaka.sstp.xpc`.
- **Interface**: `executeSSTP(request: Data, withReply: (Data)->Void)` (**request/response content is SSTP/1.x text**).
- **Connection**: `NSXPCConnection(serviceName:)` or `NSXPCConnection(machServiceName:)`. Set code signature requirements as needed.
- **Security**: XPC fundamentally requires **same-developer code signing**. Connections to external processes require Mach service/endpoint design.

### 4.3 Identifying the receiving ghost
- **ReceiverGhostName** is recommended. **ReceiverGhostHWnd** is **not applicable** on macOS (ignored).
  (In (Socket)SSTP, a ghost can be targeted by **name**. If not found, **404 Not Found** is returned.)

### 4.4 SSTP to SHIORI live-ghost bridge
- External SSTP requests now reach the **live loaded ghost (YAYA)** via `SSTPDispatcher` → `BridgeToSHIORI.handleResponse` → `liveGhostResolver` → `YayaAdapter`. Previously, if `SHIORI_BUNDLE_PATH` was not set, no ghost was consulted.
- `BridgeToSHIORI.handleResponse` resolves in order: (1) registered test resource, (2) native SHIORI bundle via `ShioriHost`, (3) live ghost via `liveGhostResolver`.
- `liveGhostResolver` is a closure of type `(String, String, [String], [String: String]) -> BridgeShioriResponse?` registered by `AppDelegate` at startup.
- **SHIORI method mapping**:

  | SSTP method | SHIORI method | Reason |
  |---|---|---|
  | `NOTIFY` | `NOTIFY SHIORI/3.0` | Notification; no return value expected (UKADOC SHIORI method spec) |
  | `SEND` | `GET SHIORI/3.0` | Script return value expected |
  | `COMMUNICATE` | `GET SHIORI/3.0` | Script return value expected |
  | `EXECUTE` | `GET SHIORI/3.0` | Script return value expected |
  | `GIVE` | `GET SHIORI/3.0` | Script return value expected |

- **ReferenceN preservation**: `mapShioriResponse` copies every `Reference0` through `ReferenceN` from the SHIORI response into the SSTP response headers. Per UKADOC, all `ReferenceN` headers are forwarded to the SSTP caller unchanged.
- **Multi-line value safety**: Ghost responses may contain Value fields with embedded newlines (e.g. Sakura Script). `BridgeShioriResponse` keeps the response structured internally. `serializeWire` strips CR/LF from all header values before building the wire string, preventing header injection and script truncation. Sakura Script newlines are represented by the `\n` token, so stripping bare newlines from the wire is display-safe. Synchronous IPC timeout: **2 seconds**.

## 5. Character Encoding Policy
- Default is **UTF-8**.
- For compatibility, `Shift_JIS`/`Windows-31J`/`CP932`/`SJIS` and similar labels are **accepted as the same family (CP932 ≈ Windows-31J)**. WHATWG Encoding treats `shift_jis` and `windows-31j` as the **same decoder**.

## 6. Header Differences (accepted/not applicable)
- **Preserved**: `Sender`, `SecurityLevel` (local/external), `SecurityOrigin`, `Option` (`nodescript`/`notranslate`/`nobreak`), `ID` (Owned SSTP), `X-SSTP-PassThru-*`.
- **Not applicable**: `HWnd` (DirectSSTP-specific) → macOS uses XPC, so it is **ignored**. `ReceiverGhostHWnd` likewise.
- **SEND-specific**: `Option: notify` is implemented (equivalent to SSP 2.6.76 behavior).

## 7. Status Codes
- **200 OK** (with return value) / **204 No Content** (no return value) / **210 Break** (executed but break) / **400** / **404** / **408** / **409** / **413** / **420** / **500** / **501** / **503** / **505** / **512** are all maintained.

## 8. SSTP over HTTP (compatibility)
- **Endpoint**: `POST http://localhost:9801/api/sstp/v1`, `Content-Type: text/plain`, **Content-Length required**.
- **Response**: HTTP always returns **200 OK** (body is the SSTP response). **Origin other than localhost is treated as external** unconditionally.

## 9. Examples (SEND/NOTIFY/EXECUTE)

### 9.1 SEND (minimal)
```
SEND SSTP/1.0
Charset: UTF-8
Sender: Ourin
Script: \h\s0Hello

```

**Response**
```
SSTP/1.4 200 OK
Charset: UTF-8
Script: \h\s0Received!

```

### 9.2 NOTIFY (event notification only)
```
NOTIFY SSTP/1.0
Charset: UTF-8
Sender: Media Player
Event: OnMusicPlay
Reference0: Wings of Freedom
Reference1: Linked Horizon

```

### 9.3 EXECUTE (information query)
```
EXECUTE SSTP/1.1
Charset: UTF-8
Sender: Ourin
Command: GetName

```

## 10. Reference Implementation Parameters (recommended defaults)
- **Port**: 9801/tcp (optionally also 9821).
- **Bind**: 127.0.0.1 / ::1 (external exposure is opt-in).
- **Charset**: Default UTF-8; SJIS-family labels accepted as CP932.

## 11. Implementation Status

**Updated:** 2026-06-28

### 11.1 Ourin host-side implementation

- [x] **TCP SSTP server**: Implemented in `SstpTcpServer.swift` using Network.framework
- [x] **HTTP SSTP server**: Implemented in `SstpHttpServer.swift`
- [x] **XPC DirectSSTP**: Implemented in `XpcDirectServer.swift` and `DirectSSTPXPC.swift`
- [x] **SSTP parser**: Implemented in `SSTPParser.swift` (order-preserving header support)
- [x] **SSTP dispatcher**: Implemented in `SSTPDispatcher.swift` — all methods and major option headers
- [x] **SSTP↔SHIORI live ghost bridge**: Implemented in `BridgeToSHIORI.swift` via `liveGhostResolver` routing to the running ghost (YAYA)
- [x] **Character encoding**: Default UTF-8; Shift_JIS/CP932 acceptance implemented
- [x] **Unified management**: TCP/HTTP/XPC unified in `OurinExternalServer.swift`
- [x] **Full SSTP/1.x protocol**: All methods and major option headers implemented

### 11.2 Implemented features

1. **SocketSSTP (TCP)**
   - TCP server implementation via Network.framework
   - Listening on port 9801
   - Loopback-only reception via `requiredLocalEndpoint` (127.0.0.1/::1); `0.0.0.0`/`::` listens on all interfaces
   - All SEND/NOTIFY/COMMUNICATE/EXECUTE/GIVE/INSTALL methods handled
   - Full request buffer (header + body) forwarded to SSTP stack (no body discarding)

2. **SSTP over HTTP**
   - HTTP server implementation (shares `SstpTcpServer.makeListener`)
   - `/api/sstp/v1` endpoint
   - Accepts requests with Content-Type: text/plain

3. **DirectSSTP (XPC)**
   - Inter-process communication via NSXPCConnection
   - `OurinSSTPXPC` protocol implemented
   - `executeSSTP(_:withReply:)` method implemented

4. **Request processing**
   - CRLF + blank-line terminator parsing
   - `Charset` header processing
   - `SecurityLevel`/`SecurityOrigin` interpretation and `securityLocalOnly` policy
   - Ghost targeting via `ReceiverGhostName` (404 if not found)
   - All `Option` patterns (`nodescript`/`notranslate`/`nobreak`)

5. **Routing and SHIORI bridge**
   - All channels unified through `SSTPDispatcher.swift` (old `SstpRouter` removed)
   - `BridgeToSHIORI.handleResponse` returns the full SHIORI/3.0 wire response
   - Reaches YayaAdapter (live YAYA ghost) via `liveGhostResolver`
   - SSTP NOTIFY propagates as `NOTIFY SHIORI/3.0`; SEND/COMMUNICATE/EXECUTE/GIVE as `GET SHIORI/3.0`
   - `mapShioriResponse` reflects all `Reference0`..`ReferenceN` into the SSTP response

6. **Safe transport of multi-line Value**
   - `BridgeShioriResponse` struct keeps the response structured
   - `serializeWire` strips CR/LF from header values before wire serialization (prevents header injection and script truncation)
   - Synchronous IPC timeout: 2 seconds

### 11.3 External exposure configuration

- Loopback-only is the default
- Passing `0.0.0.0` / `::` as the `host` parameter enables reception on all interfaces (opt-in)

## 12. Conformance Checklist
- [x] Correct handling of CRLF and blank-line terminator (implemented)
- [x] `Charset` required (UTF-8 recommended); SJIS-family accepted as CP932 (implemented)
- [x] `SecurityLevel`/`SecurityOrigin` interpretation (implemented)
- [x] Ghost targeting via `ReceiverGhostName` (404 if not found) (implemented)
- [x] **DirectSSTP (macOS)** = **XPC** bridging `request(Data)->Data` (implemented)
- [x] **SSTP over HTTP** `/api/sstp/v1` implemented with localhost restriction (implemented)
- [x] SSTP→SHIORI method mapping (NOTIFY→`NOTIFY SHIORI/3.0`, others→`GET SHIORI/3.0`) (implemented)
- [x] All SHIORI response `ReferenceN` forwarded to SSTP response (implemented)
- [x] TCP/HTTP listeners bind via `requiredLocalEndpoint` per configured `host` (implemented)
- [x] TCP raw path forwards full request (header + body) to SSTP stack (implemented)
- [x] CR/LF stripping from multi-line Value prevents header injection (implemented)

## 13. Appendix A: Minimum XPC DirectSSTP Interface
```swift
@objc public protocol OurinSSTPXPC {
    func executeSSTP(_ request: Data, withReply reply: @escaping (Data) -> Void)
}
// Host side: connect via NSXPCConnection(serviceName: "app.ourin.sstp"),
// send the SSTP text (UTF-8) as Data in request.
```
