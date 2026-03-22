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

**Status**: Dispatcher Complete, SHIORI Bridge Stub / ディスパッチャー完了、SHIORIブリッジがスタブ / 2026-03-15

### Implemented Components / 実装済みコンポーネント

#### ✅ **SSTPDispatcher.swift** (Complete / 完全)
Fully functional request parser and dispatcher with:
- Parses all SSTP methods (SEND, NOTIFY, COMMUNICATE, EXECUTE, GIVE, INSTALL)
- Event resolution (Event header or method default)
- Reference extraction (Reference0..N, Sentence, Command)
- Header normalization and propagation
- Route to SHIORI bridge (but bridge is stub)

#### ✅ **SSTPResponse.swift** (Complete / 完全)
Fully functional response builder with:
- All status codes (200, 204, 210, 4xx, 5xx, 512)
- Wire format generation (toWireFormat())
- Header ordering and formatting
- Charset, Sender, Script, Data handling
- X-SSTP-PassThru preservation

### Integration Gaps / 統合のギャップ
- ❌ **BridgeToSHIORI is mocked** - routeToShiori() calls stub implementation
- ❌ **No actual SHIORI processing** - Requests never reach ShioriHost
- ❌ **No external communication** - External SSTP requests cannot be processed end-to-end

### Blocking Issues / ブロック中の問題
- **ID-003**: BridgeToSHIORI is Mocked (see BLOCKER_TRACKER.md)

### Integration Required / 必要な統合

See INTEGRATION_ROADMAP.md **Phase 2** for detailed integration steps:

INTEGRATION_ROADMAP.mdの**フェーズ2**を参照して詳細な統合手順を確認してください：

1. **Implement real BridgeToSHIORI** (Task 2.1):
   - Create proper BridgeToSHIORI class
   - Inject ShioriHost dependency
   - Implement handle() method to call ShioriHost:
     ```swift
     func handle(method: String, event: String, references: [String], headers: [String: String]) async -> [String: String] {
         // Build SHIORI request
         var shioriRequest: [String: String] = [:]
         shioriRequest["ID"] = event
         shioriRequest["Charset"] = headers["Charset"] ?? "UTF-8"
         
         // Add references
         for (index, value) in references.enumerated() {
             shioriRequest["Reference\(index)"] = value
         }
         
         // Send to SHIORI
         return try await shioriHost.request(shioriRequest)
     }
     ```
   - Convert SHIORI request/response format correctly

2. **Connect SSTPDispatcher to real bridge** (Task 2.2):
   - Update SSTPDispatcher initialization
   - Pass real BridgeToSHIORI instance
   - Remove mock/stub imports

3. **Testing** (Task 2.3):
   - Test with external SSTP sender
   - Verify all SSTP methods work
   - Verify SHIORI events fire correctly

### Success Criteria / 成功基準
- [ ] BridgeToSHIORI calls ShioriHost
- [ ] External SSTP requests processed
- [ ] All SSTP methods work (SEND, NOTIFY, COMMUNICATE, EXECUTE, GIVE, INSTALL)
- [ ] Integration tests pass
- [ ] No SSTP blockers remain (ID-003 resolved)

---

## Operational notes / 動作上の注意

- Dispatcher is intentionally stateless.
- SHIORI mapping is tolerant: non-`SHIORI/` response text is treated as script payload.
- For protocol conformance improvements, add cases in `resolveEvent`, `mapShioriResponse`, and status mapping in `SSTPResponse`.
- **BridgeToSHIORI is currently stub implementation** - Integration required for external SSTP communication / BridgeToSHIORIは現在スタブ実装 - 外部SSTP通信には統合が必要
