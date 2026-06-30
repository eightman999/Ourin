# SHIORI Events — **3.0M / 2.0M 互換（macOS）** 仕様書

**Status:** Translation Pending  
**Original:** [SHIORI_EVENTS_3.0M_SPEC_ja-jp.md](./SHIORI_EVENTS_3.0M_SPEC_ja-jp.md)  
**Language:** English (US)

---

## Translation Note

This document is a partial translation of the Japanese original. Sections are added here as they are implemented. For the full specification see [SHIORI_EVENTS_3.0M_SPEC_ja-jp.md](./SHIORI_EVENTS_3.0M_SPEC_ja-jp.md).

---

## Appendix C: Automatic System-Event Enablement

### Behavior summary

Automatic system events — timer (`OnSecondChange`/`OnMinuteChange`/`OnHourTimeSignal`), input/mouse, sleep/wake, display change, power status, locale, appearance (theme), session, network, gamepad, device, and speech — are enabled inside `EventBridge` at **real ghost-load completion** as the single centralized activation point.

Relevant source files:
- `Ourin/Ghost/GhostManager.swift` — `startEventBridgeIfNeeded(enableAutoEvents:)` and `isRunningUnderTests`
- `Ourin/SHIORIEvents/EventBridge.swift` — `start(enableAutoEvents:)` / `broadcastNotify` / `flushPendingNotifies`

### NOTIFY queue before enablement

While `autoEventsEnabled = false`, events passed to `broadcastNotify` / `broadcastNotifyCustom` are appended to the internal `pendingNotifies` queue and not delivered immediately. When enablement occurs, the queue is flushed and events are delivered to registered ghost sessions in order.

### Suppression under tests

When `GhostManager.isRunningUnderTests` is `true` (detected by the presence of the environment variables `XCTestConfigurationFilePath` or `XCTestBundlePath`), `EventBridge.start(enableAutoEvents: false)` is called and system observers — including the timer and input monitor — are not started.

---

**Translation Status:** ⏳ Partial (Appendix C added 2026-06-28)  
**Last Updated:** 2026-06-28
