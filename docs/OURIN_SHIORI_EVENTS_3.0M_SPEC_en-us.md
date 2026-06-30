# Ourin — **SHIORI Events 3.0M (macOS)** 仕様書（UKADOC互換 / ToC付き）

**Status:** Translation Pending  
**Original:** [OURIN_SHIORI_EVENTS_3.0M_SPEC_ja-jp.md](./OURIN_SHIORI_EVENTS_3.0M_SPEC_ja-jp.md)  
**Language:** English (US)

---

## Translation Note

This document is a partial translation of the Japanese original. Sections are added here as they are implemented. For the full specification see [OURIN_SHIORI_EVENTS_3.0M_SPEC_ja-jp.md](./OURIN_SHIORI_EVENTS_3.0M_SPEC_ja-jp.md).

---

## Automatic System-Event Enablement

### Overview

Standard automatic system events — timer (`OnSecondChange`/`OnMinuteChange`/`OnHourTimeSignal`), input/mouse, sleep/wake, display change, power status, locale, appearance, session, network, gamepad, device, and speech — are enabled at **real ghost-load completion** as the single centralized activation point.

Relevant source files:
- `Ourin/Ghost/GhostManager.swift` — `startEventBridgeIfNeeded(enableAutoEvents:)`
- `Ourin/SHIORIEvents/EventBridge.swift` — `start(enableAutoEvents:)` and the internal NOTIFY queue

### Activation Sequence

```
GhostManager.start()
  ↓ YAYA dictionary load complete
  ↓ (before OnBoot GET is issued)
startEventBridgeIfNeeded(enableAutoEvents: !GhostManager.isRunningUnderTests)
  → EventBridge.shared.start(enableAutoEvents: true)   // false under tests
     → TimerEmitter / InputMonitor / SleepObserver /
        DisplayObserver / SpaceObserver / PowerObserver /
        LocaleObserver / AppearanceObserver / SessionObserver /
        NetworkObserver / GamepadObserver / DeviceObserver /
        SpeechObserver — all started
     → pendingNotifies flushed (queued NOTIFYs delivered immediately)
```

### NOTIFY Queue Behavior Before Enablement

While `autoEventsEnabled = false`, any call to `broadcastNotify` or `broadcastNotifyCustom` appends the event to the internal `pendingNotifies` queue without delivering it. When auto events are enabled, the queue is **flushed** and all pending NOTIFYs are delivered to registered ghost sessions in order.

| State | NOTIFY handling |
|---|---|
| `autoEventsEnabled = false` (before enablement) | Appended to `pendingNotifies` queue; not delivered yet |
| `autoEventsEnabled = true` (after enablement) | Delivered immediately. Queue is flushed first if non-empty |

### Suppression Under Unit Tests

`GhostManager.isRunningUnderTests` detects test execution by checking for the environment variables `XCTestConfigurationFilePath` or `XCTestBundlePath`. When running under tests, `EventBridge.start(enableAutoEvents: false)` is called, so system observers (timer, input monitor, etc.) are not started.

### Difference from Previous Behavior

Previously the default was `enableAutoEvents = false`, which meant automatic system events could remain queue-only unless the name-input dialog path in `GhostManager+Display` ran. The current implementation makes **real ghost-load completion the sole activation point**, ensuring automatic events are enabled regardless of which UI path the user follows.

---

**Translation Status:** ⏳ Partial (automatic-event-enablement section added 2026-06-28)  
**Last Updated:** 2026-06-28
