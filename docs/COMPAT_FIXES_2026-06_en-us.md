# Compatibility Fixes Report (2026-06-10)

Based on audit reports (→ consolidated into [AUDITS_COMPLETED.md](AUDITS_COMPLETED.md) / [AUDITS_TODO.md](AUDITS_TODO.md)), P0/P1 findings.  
Purpose: "Existing ghosts boot, speak naturally, basic SSTP integration works."

## Fixes Completed (P0)

### 1. YAYA Dictionary CP932 / Shift_JIS → UTF-8 Conversion

- `yaya_core/src/DictionaryManager.cpp`: iconv-based CP932→UTF-8 conversion implemented.
  - Priority: UTF-8 BOM → `yaya.txt` `charset` spec → auto-detect (UTF-8 validity check → CP932 conversion).
  - Existing UTF-8 dictionaries not broken; even if `charset` claims CP932, valid UTF-8 content read as UTF-8.
  - Conversion failure logs as `[DictionaryManager] ERROR:`; full dictionary failure only if all fail.
- Swift side: `parseYayaConfigFile` collects `charset,` lines, passes to `YayaAdapter.load(encoding:)`.
- `yaya_core/CMakeLists.txt` added iconv link.

### 2. SSTP Response Line Double Prefix

- `ExternalServer/SstpParser.swift`: version strips `SSTP/` prefix, retained ("SSTP/SSTP/1.x" fixed).
- Test: `ExternalServerTests.responseStatusLineHasSinglePrefix` etc.

### 3. SSTP SEND Script Balloon Playback

- `ExternalServer/SstpRouter.swift`:
  - SEND without Event → SHIORI bypassed, Script header played directly.
  - SEND with Event → SHIORI response script (or Script header if no response) played as balloon.
  - `Option: nodescript` suppresses balloon play only, event processing still occurs.
- `EventBridge.playScriptOnGhosts(_:ghostName:)` created (ReceiverGhostName filter support).

### 4. OnSecondChange / OnMinuteChange / OnHourTimeSignal

- `TimerEmitter.swift`: Reference0=OS continuous uptime (hour), Reference1=cutoff, Reference2=overlap, Reference4=idle seconds provided.
  - Cutoff/overlap detection not yet implemented (safe interim value 0—TODO comments).
  - Idle seconds from CGEventSource total input event elapsed.
- `EventBridge.swift`: Reference3 (talk playable = `GhostManager.canPlayTalkNow()`) per-session, cantalk=1→GET (script play), cantalk=0→NOTIFY (ignore response).

### 5. Reference Numeric Order Sort

- `EventBridge.swift` / `PluginProtocol.swift`: ReferenceN sorted numerically (dict order: Reference10 < Reference2).
- Non-Reference keys don't mix into positional args. Gaps padded with "". `InputMonitor.swift`: mouse/key params changed to UKADOC-compliant ReferenceN (Ref0=X, 1=Y, 2=wheel, 3=scope, 4=hit, 5=button, 6=device).
  - Within character window, top-left-origin local coordinates.

## Fixes Completed (P1)

### SakuraScript Tag Semantics (GhostManager.swift)

| Tag | Old (incorrect) | New |
|---|---|---|
| `\t` | 100ms pause | time-critical section (`\e` / script break until mouse events blocked) |
| `\-` | line break | end current ghost (OnClose response EOF standard) |
| `\v` | settings window | stay-on-top (frontmost) |
| `\4` / `\5` | Z-order change | move away from partner / approach contact distance horizontal |
| `\*` | choice dialog | don't timeout choice |

### Other P1 Fixes

- Reference0 format (all events): Numeric sort, dedupe
- Mouse click hit detection in character window
- Property read/write side effects (surface.num → trigger SERIKO animations)
- Choice event routing to SHIORI via ID (not label)
- Balloon property update propagation

---

## Testing Performed

- **Emily4 ghost**: Boot, basic interact (click response, menu choices)
- **Test harnesses**: Property read/write, event emission, SSTP request roundtrip
- **Live verification (Linux yaya_core)**: Dictionary load, variable persistence, SAORI request routing

---

## Known Remaining Gaps (P2-P3)

- P2: Advanced SERIKO (interpolation, collision)
- P2: Dialog commands (full implementation)
- P3: Performance optimization
- P3: Multi-ghost simultaneous run (architecture change)

---

**Status**: P0/P1 high-leverage compatibility fixes complete. Core ghost operation (boot, interact, SSTP) verified functional.
