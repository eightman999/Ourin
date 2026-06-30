# Ourin Implementation Plan — June 2026 Remaining Tasks (UKADOC Primary Specification Reconciliation)

**Created**: June 20, 2026  
**Target Branch**: `claude/ultracode-effort-1xxdwf`  
**Reconciled Primary Specifications**: UKADOC (via `raw.githubusercontent.com/ukatech/ukadoc/master/manual/`. `ssp.shillest.net` and `ukagakadreamteam.github.io` mirrors are 403 due to network policy). YAYA language specification, repository `docs/`.  
**Method**: Parallel precise reading of 4 categories (SakuraScript / SHIORI Events / Property+SERIKO / YAYA VM+SSTP/FMO) with static analysis comparing live UKADOC and source at `file:line` level.

> **Premise**: This plan confirms that P0–P3 findings in `AUDIT_CLAUDE` (2026-06-14; → consolidated into [AUDITS_COMPLETED.md](AUDITS_COMPLETED.md) / [AUDITS_TODO.md](AUDITS_TODO.md)) were implemented in commits `8b0acef` / `b80afac`, then re-investigates remaining gaps. Dynamic ghost live testing not performed in this environment; each `file:line` is position at static analysis time—reconfirm on start.

## Implementation Progress (2026-06-20)

- ✅ **P0 all items (Sprint 1) complete** — SHIORI choice/Balloon/Ghost switch/Install/Surface/FileDrop2 Reference fixes, SERIKO `periodic` interval, SSTP body wiring.
- ✅ **P1 all items (Sprint 2) complete**
  - YAYA `SAVEVAR`/`RESTOREVAR`・`SETDELIM`/`GETDELIM`(**Linux yaya_core build + IPC live verification**: variable save/restore, array round-trip, SPLIT delim）
  - Property `scope(N).surface.num`/`animation.num` SET side-effect reflection
  - SakuraScript WebSocket full set
  - SERIKO `interpolate`/`insert`/`alternativestop` method
- ✅ **P2-4 (YAYA VM) complete** — **Linux build + run verification**
  - `GETTYPE` to YAYA standard code (`real=2,str=3,arr=4`) + `GETTYPEEX` real
  - `FENUM` absolute path permit
  - Function type modifiers `void`/`array`/`sequential` (untyped functions backward compatible)
  - Remaining: `FUNCTIONEX` (dynamic call), anonymous functions not started
- ⏳ **P2 (Swift-centric)/P3 not started** — Listed below. Swift changes (some P0, P1-2/P1-4/P1-5) cannot be compiled/verified in this Linux environment—recommend Xcode-capable environment for start/verification. C++ (yaya_core) changes verified with real build+run.

> Note: Swift changes (part of P0, P1-2/P1-4/P1-5) are static review only (no xcodebuild in Linux). C++ (yaya_core) changes verified with real build+run.

---

## 0. Summary (Remaining Gap Distribution)

| Area | Resolved (Recent Commit) | Remaining High | Remaining Med | Remaining Low |
|---|---|---|---|---|
| YAYA VM | for/foreach・break/continue・++/--・Real type・&・SPRINTF・%()・UTF-8 strings | SAVEVAR/RESTOREVAR, SETDELIM/GETDELIM | FUNCTIONEX, GETTYPE(Real), FENUM absolute path | READFMO, TOAUTO, HMC, etc. |
| SSTP/FMO | 9821 port, FMO standard fields | Production path body discard | Owned-SSTP bypass, COMMUNICATE Surface header | — |
| SHIORI Events | Mouse series, time series, OnFileDrop2 firing, Update series | OnChoiceEnter/Select Ref error | Balloon series/Ghost series Ref, OnKeyPress, OnWindowState* | OnTranslate, etc. |
| Property/SERIKO | system.monitor/disk/theme/power/network, os.*, element composition, alias/surfacetable/append | animation.num SET, surface.num SET, periodic interval | interpolate/insert/alt series, collisionex, use_self_alpha, balloon margin apply | locale subdivision, etc. |
| SakuraScript | http/rss, archive, scaling, alpha, bind, reload series | WebSocket full set | effect/filter render, zorder/sticky force, selectmode rectangle | balloonnum meaning, doc sync |

**Overall policy**: "Form (vocabulary compatibility)" nearly complete. Remaining is **(a) existing implementation Reference/argument detail bugs**, **(b) lack of real ghost persistence/deferred fire/property write**, **(c) rendering system implementation (effect/SERIKO interpolation)**—3 streams. Prioritize (a)(b).

---

## P0 — High Impact, Low Cost (Quick Wins, Start First)

Directly affect ghost operation, but fixes are localized.

### P0-1. SHIORI Choice Event Reference Fix ★Highest Priority

**Real harm**: All ghosts using menu/choice have selections not routed to dictionary.

- **OnChoiceEnter**: `Reference0` has `pendingChoices.count` (integer). Spec: R0=choice label, R1=choice ID. `Ourin/Ghost/GhostManager+System.swift:383`
- **OnChoiceSelect**: `Reference0` has label, but spec: R0=**ID** of `\q[label,ID]`. SHIORI dictionary keys on ID, so current routing impossible. `GhostManager+System.swift:436-445`

**Fix**: Emit choice label as R0, choice ID as R1 (or ID as R0 if using ID-keyed dispatch).

### P0-2. Plugin `OnOtherGhostTalk` Ref5 Spec Mismatch

Ref5 is "single 0x01-delimited Reference" per spec, but implementation splits into multiple References.

**File**: `PluginEventDispatcher.swift:142-146`

**Fix**: Join with ListDelimiter.

### P0-3. HTTP SSTP Port (now unified to 9801)

HTTP SSTP used port 9810, spec requires 9801 (same as TCP). **Fixed in 2026-06-15**: `UnifiedSstpListener` created, multiplexing HTTP/raw SSTP on 9801 by first-line detection. 9810-only HTTP listener removed.

### P0-4. Plugin XPC Protocol (now unified)

XPC protocol double-defined: `OurinSSTPXPC.executeSSTP` vs. `OurinExternalSstpXPC.deliverSSTP`. Spec: single `executeSSTP(_:withReply:)`. **Fixed in 2026-06-15**: Removed `OurinExternalSstpXPC`, unified to common `XpcDirectServer` using shared `OurinSSTPXPC.executeSSTP(_:withReply:)`.

### P0-5. SERIKO Cursor Key Structure (now corrected)

Implementation single `cursor.scope(ID).mouselist`; spec: `mouseup/mousedown/mousehover/mousewheellist` 4-split. **Fixed in 2026-06-15**: Redesigned `serikoCursor` to `[scope:[kind:[name:path]]]`, supporting 4-kind list GET/SET.

---

## P1 — Medium Impact (Direct Ghost Use Depends On These)

### P1-1. NAR Update Real Application

**Status**: Implemented 2026-06-15.

`NarInstaller.downloadAndApply(entries:homeURLString:targetRoot:)` created. `checkGhostUpdate` enumerates update descriptors, then downloads each file and applies (`.nar`/`.zip` via `install(fromNar:)`, else relative path from homeurl to ghost root, path-traversal protected). OnUpdate.OnDownloadBegin/Complete・OnUpdateComplete fire per actual result. `delete.txt`/`refresh`/`refreshundeletemask`/bundled `balloon.directory` already existing.

### P1-2. Generic dylib Direct Load, `loadu` Entry

**Status**: Implemented 2026-06-15.

SAORI/SHIORI(DylibBackend)/Headline/Plugin each loader prefers `loadu` (UTF-8 path) over `load`. SHIORI DylibBackend unified to resolve no-suffix `load/request/unload/free` (Windows-derived) generically.

### P1-3. Plugin XPC/Process Isolation

**Status**: Implemented 2026-06-15.

`PluginXpcBackend.swift` (`OurinPluginXPC`/`PluginXpcClient`) created. When `OURIN_PLUGIN_ISOLATION_MODE=xpc` or `OURIN_PLUGIN_XPC_SERVICE` set, `PluginEventDispatcher` sends to separate process worker (default in-process). Same design as SHIORI XpcBackend.

### P1-4. Property Generic Names

**Status**: Implemented 2026-06-15.

`thumbnail / update_result / update_time / shiori.<var> / index` resolved in Ghost, `(sakura|kero|char*).bind.menu` in currentghost runtime GET/SET. `index` also in Balloon/Headline/Plugin list.

### P1-5. SHIORI Resource Cache/SET

**Status**: Implemented 2026-06-15.

`ResourceBridge` already holds 5-second TTL cache. New SET override layer (`set(key:value:)`/`clearOverride(_:)`) added, override value prioritized over SHIORI query (empty = define delete). NSLock thread-safe.

### P1-6. Balloon Advanced Rendering

**Status**: Partially implemented 2026-06-15.

Generic `ImageLoader.load` PNA (separate alpha file) composition added (`CIBlendWithMask`). `BalloonView` outline changed from single blur to 8-direction offset shadow (true outline). Remaining: Retina(@2x) asset selection.

### P1-7. Plugin `OnChoiceSelect(Ex)/OnAnchorSelect(Ex)` Wiring

**Status**: Implemented 2026-06-15.

`GhostManager.forwardEventToPlugins` created. Choice confirm (`showChoiceDialog`) and anchor click (`onBalloonClicked`) flow to `PluginEventDispatcher.onArbitraryEvent`. Remaining: `\q` (queued choice) plugin wiring.

### P1-8. SHIORI Internal Event SecurityLevel Injection

**Status**: Implemented 2026-06-15.

`EventBridge` introduces `ShioriSecurityContext` (level/origin), propagates to `notify`/`notifyCustom`/`sendNotify`/`sendNotifyCustom`/`sendGet` (default local). Non-YAYA (`BridgeToSHIORI.handle`) path also receives header (was SecurityLevel missing).

### P1-9. Large Character Display

**Status**: Implemented 2026-06-15.

`GhostManager.ensureCharacterWindow(for:)` lazy-generates scope window. `setupWindows` pre-generates scope 0/1 only; `\p[N]` (arbitrary N) generates on scope switch / surface update. Remaining: multi-ghost simultaneous run (AppDelegate holds single GhostManager—architecture change needed).

---

## P2 (Swift-Centric, Verification Recommended in Xcode Environment)

### P2-1. SakuraScript Full Command Coverage

Remaining unimplemented: `\![effect,...]`, `\![filter,...]`, dialog expansion, etc.

### P2-2. Surface Animation Side Effects

`animation.num` SET should trigger frame update. Likely needs refresh queue.

### P2-3. Menu State Persistence

Dressup/menu state should persist across reloads/switches.

---

## P3 (Low Priority, Deferred)

- Spec document consistency audit (ja-jp vs en-us, outdated markers)
- Performance profiling
- Stress testing with large character sets

---

## File References (Quick Navigation)

| Topic | File | Lines |
|---|---|---|
| Choice events fix | `Ourin/Ghost/GhostManager+System.swift` | 383, 436–445 |
| Plugin Ref5 | `PluginEventDispatcher.swift` | 142–146 |
| HTTP SSTP (fixed) | `Ourin/ExternalServer/UnifiedSstpListener.swift` | (new, 2026-06-15) |
| XPC (fixed) | `Ourin/SSTP/DirectSSTPXPC.swift` | (unified, 2026-06-15) |
| SERIKO cursor (fixed) | `Ourin/Property/GhostPropertyProvider.swift` | (redesigned, 2026-06-15) |
| NAR update (impl) | `Ourin/NarInstall/NarInstaller.swift` | (new method, 2026-06-15) |
| dylib loadu (impl) | Various loaders | (priority change, 2026-06-15) |
| Plugin XPC (impl) | `Ourin/Plugin/PluginXpcBackend.swift` | (new, 2026-06-15) |
| Property generic | `Ourin/Ghost/GhostManager.swift` | (extended, 2026-06-15) |
| Resource cache SET | `Ourin/USL/ResourceBridge.swift` | (new layer, 2026-06-15) |

---

**Status**: High-leverage P0/P1 fixes implemented; P2-3 deferred pending Xcode verification or lower priority.
