# SSTP Dispatcher Guide

## Overview

`Ourin/SSTP/SSTPDispatcher.swift` accepts parsed `SSTPRequest` and routes it to SHIORI bridge logic.

Supported methods:

- `SEND`
- `NOTIFY`
- `COMMUNICATE`
- `EXECUTE`
- `GIVE`
- `INSTALL`

Unsupported methods return `400`.

## Dispatch flow

Primary entry:

- `SSTPDispatcher.dispatch(request:)`

Core route function:

- `routeToShiori(request:method:)`

Flow:

1. Resolve event name (`Event` header override or method default)
2. Extract references (`Reference0..N`, plus `Sentence`/`Command` special handling)
3. Build SHIORI headers
4. Call `BridgeToSHIORI.handleResponse(...)` — returns a full SHIORI/3.0 wire response
5. Map SHIORI response fields (`Script`, `Value`, `ValueNotify`, `Data`, `ReferenceN`, status, etc.)
6. Emit SSTP wire response

### SHIORI bridge routing (live ghost support)

`routeToShiori` calls `BridgeToSHIORI.handleResponse`. Unlike the old `handle` call (which returned only the value string), `handleResponse` returns the complete SHIORI/3.0 wire response so that `mapShioriResponse` can preserve `ReferenceN`, `ValueNotify`, `Status`, and other headers.

`BridgeToSHIORI.handleResponse` resolves in this order:

1. **Test/registered resource** (`Resource` event only) — stub values for unit tests
2. **Native SHIORI bundle** (set via `SHIORI_BUNDLE_PATH` environment variable) — via `ShioriHost`
3. **Live ghost** (`liveGhostResolver`) — closure registered by `AppDelegate` at startup, pointing to `YayaAdapter` or equivalent

When `liveGhostResolver` is set, external SSTP requests reach the actually loaded YAYA ghost. Previously, if `SHIORI_BUNDLE_PATH` was not set, no ghost was ever consulted.

#### SHIORI method mapping

| SSTP method | SHIORI method | Reason |
|---|---|---|
| `NOTIFY` | `NOTIFY SHIORI/3.0` | Notification; no return value expected (UKADOC SHIORI method spec) |
| `SEND` | `GET SHIORI/3.0` | Script return value expected |
| `COMMUNICATE` | `GET SHIORI/3.0` | Script return value expected |
| `EXECUTE` | `GET SHIORI/3.0` | Script return value expected |
| `GIVE` | `GET SHIORI/3.0` | Script return value expected |

## Header propagation

Dispatcher carries/normalizes:

- `Charset`
- `Sender`
- `SenderType`
- `SecurityLevel`
- optional `SecurityOrigin`

`X-SSTP-PassThru` is preserved in responses.

## Method-specific behavior

- `NOTIFY` returns `200` if the SHIORI response includes `ValueNotify`, otherwise `204`
- `EXECUTE` validates `Command` header and returns `400` if missing
- `COMMUNICATE` injects `Sentence` into references
- `GIVE` defaults to `OnChoiceSelect`
- `INSTALL` defaults to `OnInstall`

## Response model (`SSTPResponse`)

`Ourin/SSTP/SSTPResponse.swift` centralizes response formatting:

- Status line with default status messages
- Ordered key output (`Charset`, `Sender`, `Script`, `Data`, `X-SSTP-PassThru`, others)
- `toWireFormat()` outputs CRLF-separated wire string

Supported status messages include:

- `200`, `204`, `210`
- `4xx` common validation/security errors
- `5xx` server capability errors
- `512 Invisible`

## Testing

- `OurinTests/SSTPDispatcherTests.swift`
- `OurinTests/SSTPResponseTests.swift`

Tests validate routing, mapping, propagation, and wire formatting.

## ReferenceN preservation

`mapShioriResponse` copies every `Reference0` through `ReferenceN` from the SHIORI response into the SSTP response headers. The previous implementation extracted only `Reference0`. Per UKADOC, all `ReferenceN` headers from the SHIORI response must be forwarded to the SSTP caller unchanged.

## Current Status

**Status**: End-to-end integration with live ghost complete / 2026-06-28

### Implemented Components

#### ✅ **SSTPDispatcher.swift** (Complete)
Fully functional request parser and dispatcher with:
- Parses all SSTP methods (SEND, NOTIFY, COMMUNICATE, EXECUTE, GIVE, INSTALL)
- Event resolution (Event header or method default)
- Reference extraction (Reference0..N, Sentence, Command)
- Header normalization and propagation
- Routes to live ghost via `BridgeToSHIORI.handleResponse`

#### ✅ **BridgeToSHIORI.swift** (Complete)
Live ghost bridge implementation:
- `handleResponse` — returns the full SHIORI/3.0 wire response (for SSTP dispatcher)
- `handle` — returns the value string only (for GhostManager / ResourceBridge / internal callers)
- `liveGhostResolver` — closure registered by `AppDelegate` at startup pointing to `YayaAdapter`
- `BridgeShioriResponse` struct keeps the response structured internally (prevents CR/LF in Value from causing header injection or script truncation)
- `serializeWire` strips CR/LF from all header values before serializing to wire format
- Synchronous IPC timeout: **2 seconds**

#### ✅ **SSTPResponse.swift** (Complete)
Fully functional response builder with:
- All status codes (200, 204, 210, 4xx, 5xx, 512)
- Wire format generation (toWireFormat())
- Header ordering and formatting
- Charset, Sender, Script, Data handling
- X-SSTP-PassThru preservation

---

## Operational notes

- Dispatcher is intentionally stateless.
- SHIORI mapping is tolerant: non-`SHIORI/` response text is treated as script payload.
- If `liveGhostResolver` is nil (no ghost loaded), `BridgeToSHIORI.handleResponse` returns an empty string and the dispatcher emits `503 Service Unavailable`.
- Multi-line ghost values (e.g. Sakura Script containing newlines) are kept in `BridgeShioriResponse` until `serializeWire` strips raw CR/LF. Sakura Script newlines are represented by the `\n` token, so stripping bare newlines from the wire is display-safe.
