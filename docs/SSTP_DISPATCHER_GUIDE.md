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
4. Call `BridgeToSHIORI.handle(...)`
5. Map SHIORI response fields (`Script`, `Value`, `Data`, status)
6. Emit SSTP wire response

## Header propagation

Dispatcher carries/normalizes:

- `Charset`
- `Sender`
- `SenderType`
- `SecurityLevel`
- optional `SecurityOrigin`

`X-SSTP-PassThru` is preserved in responses.

## Method-specific behavior

- `NOTIFY` returns `204` regardless of returned script body
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

## Current Status / 現在のステータス

**Status**: End-to-end integration with live ghost complete / 稼働中ゴーストとのエンドツーエンド統合完了 / 2026-08-12

### Implemented Components / 実装済みコンポーネント

#### ✅ **SSTPDispatcher.swift** (Complete / 完全)
Fully functional request parser and dispatcher with:
- Parses all SSTP methods (SEND, NOTIFY, COMMUNICATE, EXECUTE, GIVE, INSTALL)
- Event resolution (Event header or method default)
- Reference extraction (Reference0..N, Sentence, Command)
- Header normalization and propagation
- Routes to the live ghost through `BridgeToSHIORI.handleResponse`

#### ✅ **SSTPResponse.swift** (Complete / 完全)
Fully functional response builder with:
- All status codes (200, 204, 210, 4xx, 5xx, 512)
- Wire format generation (toWireFormat())
- Header ordering and formatting
- Charset, Sender, Script, Data handling
- X-SSTP-PassThru preservation

### Live bridge / 稼働中ブリッジ

`BridgeToSHIORI.handleResponse` resolves requests in this order:

1. Registered `Resource` values used by focused tests
2. A native SHIORI bundle configured by `SHIORI_BUNDLE_PATH`
3. The live ghost resolver registered by `AppDelegate`

The live resolver forwards SSTP events to the loaded YAYA ghost. If no resolver or native bundle is available, the dispatcher returns `503 Service Unavailable`; it does not synthesize a mock script.

The integration is covered by `SSTPDispatcherTests`, `ExternalServerTests`, and the native SHIORI fixture tests.

---

## Operational notes / 動作上の注意

- Dispatcher is intentionally stateless.
- SHIORI mapping is tolerant: non-`SHIORI/` response text is treated as script payload.
- For protocol conformance improvements, add cases in `resolveEvent`, `mapShioriResponse`, and status mapping in `SSTPResponse`.
