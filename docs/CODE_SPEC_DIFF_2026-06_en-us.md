# Code and Specification Difference Report (2026-06-14, updated 2026-06-15)

> 2026-06-15 update: Resolved §1 items #5 (HTTP port), #6 (XPC naming), #7 (SERIKO cursor) — details in §5. Corrected §2 NAR description to reality (delete.txt/refresh/update descriptor fetch implemented, update application wiring pending). Additionally implemented in §2: P1 generic property names, dylib `loadu` entry, Plugin XPC separation, SHIORI SecurityLevel injection (🔧).

Comparison of specifications in `docs/` (ja-jp preferred) against implementations in `Ourin/` and `yaya_core/` across SHIORI / SSTP / SakuraScript·SERIKO / Property / FMO etc. / Plugin (6 domains).

Legend: ✅=verified in actual code / 🔧=fixed in this commit / 📝=not addressed (plan needed) / 📄=documentation debt (code correct)

---

## 0. Structural Trends

1. **"Specification older than implementation" reversal common**. `TODO/todo.md` (2025-10-21), `IMPLEMENTATION_STATUS_SUMMARY` (2026-03), spec "not implemented" remarks incorrectly mark implemented features as "not implemented". Post-2026-06-COMPAT_FIXES documents not followed.
2. **ja-jp version translation stub in some specs** (`SHIORI_RESOURCE_3.0M_ja-jp`, `SAKURASCRIPT_COMMANDS_SUPPORTED_ja-jp` etc.). Authoritative en-us side.
3. **Most gaps are "documentation debt" not code bugs**.

---

## 1. Implementation Bugs, Concrete Inconsistencies

| # | Priority | Difference | Evidence | Status |
|---|---|---|---|---|
| 1 | P1 | **CPU usage constantly ≈100%**. `(user+system+idle+nice)/total*100` includes idle in numerator (=total/total). Correct: exclude idle | `Ourin/Property/PropertyManager.swift:292` | 🔧 Fixed |
| 2 | P1 | **Memory property key name mismatch**. Implementation `system.memory.physical/.available` ⇔ spec `.phyt/.phya` | `PropertyManager.swift:251-252` / `PROPERTY_1.0M_SPEC_ja-jp.md:86-88` | 🔧 Added phyt/phya as official keys (English alias maintained) |
| 3 | P1 | **Plugin `OnOtherGhostTalk` Ref5 spec deviation**. Ref5 "single 0x01-delimited Reference" vs. implementation splits into multiple References | `PluginEventDispatcher.swift:142-146` / `PLUGIN_EVENT_2.0M_SPEC_FULL_ja-jp.md:88-94` | 🔧 Join with ListDelimiter |
| 4 | P1 | **Plugin version response discarded**. Spec: apply response Value and optional `Charset:` to subsequent communication. Implementation: `let _ = plugin.send(req)` (log only) | `PluginEventDispatcher.swift:64-72` / `PLUGIN_EVENT_2.0M_SPEC_ja-jp.md §4.1` | 🔧 Parse response, retain negotiated Charset per plugin, reflect in send |
| 5 | P1 | **HTTP SSTP port 9810** (spec: TCP 9801) | `SstpHttpServer.swift` / `SstpTcpServer.swift` / `SSTP_1.xM_SPEC_ja-jp.md:71` | 🔧 **Fixed (2026-06-15)**. `UnifiedSstpListener` created, single 9801 port multiplexes HTTP/raw SSTP by first-line check. 9810-only HTTP listener removed |
| 6 | P1 | **XPC protocol double-define, method name mismatch**. `OurinSSTPXPC.executeSSTP` vs. `OurinExternalSstpXPC.deliverSSTP`. Spec: `executeSSTP(_:withReply:)` single | `Ourin/SSTP/DirectSSTPXPC.swift` / `Ourin/ExternalServer/XpcDirectServer.swift` | 🔧 **Fixed (2026-06-15)**. Removed `OurinExternalSstpXPC`, unified `XpcDirectServer` to shared `OurinSSTPXPC.executeSSTP(_:withReply:)` |
| 7 | P0/P1 | **SERIKO cursor key structure mismatch**. Implementation single `cursor.scope(ID).mouselist`, spec `mouseup/mousedown/mousehover/mousewheellist` 4-split | `GhostPropertyProvider.swift` / `PROPERTY_1.0M_SPEC_ja-jp.md:109` | 🔧 **Fixed (2026-06-15)**. Redesigned `serikoCursor` to `[scope:[kind:[name:path]]]`, supporting 4-kind list GET/SET |

---

## 2. Not Implemented, Partial Implementation (Feature Extension Plan)

- 🔧 **NAR update real application → Addressed (2026-06-15)**. `NarInstaller.downloadAndApply(entries:homeURLString:targetRoot:)` created; `checkGhostUpdate` enumerates update descriptor, then downloads each file (`.nar`/`.zip` via `install(fromNar:)`, else homeurl-relative path to ghost root, path-traversal protected). OnUpdate.OnDownloadBegin/Complete, OnUpdateComplete fire per actual result. `delete.txt`/`refresh`/`refreshundeletemask`/bundled `balloon.directory` already existing.
- 🔧 **Generic dylib direct load, `loadu` entry → Addressed (2026-06-15)**. SAORI/SHIORI(DylibBackend)/Headline/Plugin loaders prefer `loadu` (UTF-8 path) over `load`. SHIORI DylibBackend unified to resolve no-suffix `load/request/unload/free` (Windows-derived) generically.
- 🔧 **Plugin XPC/process separation → Addressed (2026-06-15)**. `PluginXpcBackend.swift` (`OurinPluginXPC`/`PluginXpcClient`) created. When `OURIN_PLUGIN_ISOLATION_MODE=xpc` or `OURIN_PLUGIN_XPC_SERVICE` set, `PluginEventDispatcher` sends to separate process worker (default in-process). SHIORI XpcBackend same design.
- 🔧 **Property generic names → Addressed (2026-06-15)**: `thumbnail / update_result / update_time / shiori.<var> / index` resolved in Ghost, `(sakura|kero|char*).bind.menu` in currentghost runtime GET/SET. `index` in Balloon/Headline/Plugin list too.
- 🔧 **SHIORI Resource cache/SET → Addressed (2026-06-15)**. `ResourceBridge` already holds 5-sec TTL cache. New SET override layer (`set(key:value:)`/`clearOverride(_:)`) added; override value prioritized over SHIORI query (empty = define delete). NSLock thread-safe.
- 🔧 **Balloon advanced rendering → Partially addressed (2026-06-15)**. Generic `ImageLoader.load` PNA (separate alpha file) composition added (`CIBlendWithMask`). `BalloonView` outline improved from single blur to 8-direction offset shadow (true outline). Remaining: Retina(@2x) asset selection.
- 🔧 **Plugin `OnChoiceSelect(Ex)/OnAnchorSelect(Ex)` → Wired (2026-06-15)**. `GhostManager.forwardEventToPlugins` created; choice confirm (`showChoiceDialog`) and anchor click (`onBalloonClicked`) flow to `PluginEventDispatcher.onArbitraryEvent`. Remaining: `\q` (queued choice) plugin wiring.
- 🔧 **SHIORI internal event SecurityLevel injection → Addressed (2026-06-15)**. `EventBridge` introduces `ShioriSecurityContext` (level/origin), propagates to `notify`/`notifyCustom`/`sendNotify`/`sendNotifyCustom`/`sendGet` (default local). Non-YAYA (`BridgeToSHIORI.handle`) path also receives header (was SecurityLevel missing).
- 🔧 **Large Character display → Addressed (2026-06-15)**. `GhostManager.ensureCharacterWindow(for:)` lazy-generates scope window. `setupWindows` pre-generates scope 0/1; `\p[N]` (arbitrary N) generates on scope switch/surface update. Remaining: multi-ghost simultaneous run (AppDelegate holds single GhostManager—arch change needed).

---

## 3. Documentation Debt (Code Correct)

- `SHIORI_RESOURCE_3.0M_ja-jp.md` is translation stub; actual content is en-us side
- `SAKURASCRIPT_COMMANDS_SUPPORTED_ja-jp.md` implementation status is outdated; code supports more than doc claims
- `TODO.md` (2025-10-21) lists tasks as "not done" that are now complete

---

## 4. Spec Alignment Status by Domain

### SHIORI / SSTP
- ✅ Core event routing (ON* events → SHIORI)
- ✅ Response script parsing
- ✅ Reference0..N header passing
- 🔧 Choice event Reference fix (2026-06-15)
- 🔧 HTTP/SSTP port unification (2026-06-15)
- 📝 `COMMUNICATE` Surface header (low priority)

### SakuraScript
- ✅ Core command parsing
- ✅ Control flow (\t, \e, \w, etc.)
- ✅ Text formatting (\f[...])
- 🔧 Dialog/balloon/menu commands (partial)
- 📝 Advanced effect/filter rendering (low priority)

### SERIKO Animation
- ✅ Parser for SERIKO/2.0
- ✅ Surface/overlay execution
- 🔧 Cursor structure (2026-06-15)
- 📝 Complex interpolation/collision detection (med priority)

### Property System
- ✅ Core read/write
- 🔧 Generic property names (2026-06-15)
- 🔧 CPU/memory calculation fix (2026-06-15)
- 📝 Advanced system properties (os.*, theme, power, etc.—low priority)

### YAYA VM
- ✅ Function definitions, control flow
- ✅ Variable persistence (SAVEVAR/RESTOREVAR)
- 🔧 Built-in function coverage (partial)
- 📝 Real type operations, advanced regex

---

## Summary

**Code quality**: Most "differences" are documentation updates needed, not code bugs. P0-P1 high-leverage items now addressed (2026-06-15 commit). Remaining gaps are P2 (code detail) and P3 (spec doc consistency).

**Next actions**:
1. Verify fixes in real ghost execution (Emily4 or similar)
2. Update spec docs to reflect 2026-06-15 changes
3. Address P2 feature gaps as needed for real ghost compatibility
