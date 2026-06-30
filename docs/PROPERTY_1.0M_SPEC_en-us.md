# PROPERTY/1.0M — Ourin (macOS) Property System Specification

**Status:** Draft / 2025-07-27
**Original:** [PROPERTY_1.0M_SPEC_ja-jp.md](./PROPERTY_1.0M_SPEC_ja-jp.md)
**Language:** English (US)
**Compatibility policy:** Vocabulary and behavioral compatibility with SSP "property system" (equivalent to 1.0). This document defines only macOS-specific replacements ("M extensions").
**Character encoding:** Internal UTF-8. SJIS (CP932) input is accepted and normalized to UTF-8 on ingress; responses are always UTF-8.

---

## Table of Contents
- [1. Overview](#1-overview)
- [2. Access Methods (Compatible)](#2-access-methods-compatible)
- [3. Value Notation, Coordinates, and Units](#3-value-notation-coordinates-and-units)
  - [3.1 Coordinate System Definition (M Spec)](#31-coordinate-system-definition-m-spec)
  - [3.2 Example: Coordinate Conversion Pseudocode](#32-example-coordinate-conversion-pseudocode)
- [4. Property Vocabulary (macOS Mapping)](#4-property-vocabulary-macos-mapping)
  - [4.1 system.*](#41-system)
  - [4.2 baseware.*](#42-baseware)
  - [4.3 ghostlist/activeghostlist/currentghost.*](#43-ghostlistactiveghostlistcurrentghost)
  - [4.4 balloonlist/headlinelist/pluginlist/history/rateofuselist](#44-balloonlistheadlinelistpluginlisthistoryrateofuselist)
  - [4.5 Standard Namespace Aliases (sakura/kero/ghost/shell)](#45-standard-namespace-aliases-sakurakeroghostshell)
- [5. Writable Properties (SET-enabled)](#5-writable-properties-set-enabled)
- [6. Security and Sandbox](#6-security-and-sandbox)
- [7. Compatibility and Differences](#7-compatibility-and-differences)
- [Appendix A: Rosetta Detection Sample (Swift/C)](#appendix-a-rosetta-detection-sample-swiftc)
- [Appendix B: Implementation Hints (CPU/Memory/OS Info)](#appendix-b-implementation-hints-cpumemoryos-info)
- [Appendix C: References](#appendix-c-references)

---

## 1. Overview
- Provides a mechanism for **ghost scripts** to **read and partially write** the baseware's internal state and installed assets on Ourin.
- Follows the existing UKADOC property vocabulary and access methods. Windows-specific values are replaced with **equivalent macOS information**.

## 2. Access Methods (Compatible)
- **Environment variable expansion**: `%property[property-name]`
  Example: `%property[baseware.name] ver %property[baseware.version]`
- **Get**: `\![get,property,EventName,PropertyKey,...]`
- **Set**: `\![set,property,PropertyKey,Value]` (SET-enabled keys only)

> Compatibility note: when multiple keys are specified, values are returned in order from Reference0. Values are UTF-8.

## 3. Value Notation, Coordinates, and Units
- **Strings are UTF-8**. SJIS input is normalized from CP932 to UTF-8 before processing.
- **Paths use POSIX format** (`/` separator).
- **Coordinate/size units**: **logical pixels (pt)**. Retina scaling is absorbed internally by Ourin; values are returned as **1 logical px = 1 pt**.
  When needed, use `backingScaleFactor` to convert to physical device pixels.

### 3.1 Coordinate System Definition (M Spec)
- **Origin: top-left (0,0) of the virtual desktop.**
  macOS global coordinates use a **bottom-left origin** by default, but Ourin converts to **top-left origin** for SSP compatibility.
- In multi-monitor setups, the union rectangle of all `NSScreen.screens` frames is treated as the virtual desktop, and its top-left corner is (0,0).

### 3.2 Example: Coordinate Conversion Pseudocode
```swift
// Cocoa global coordinate (bottom-left origin) -> compatible coordinate (top-left origin)
func compatibleCursorPositionString() -> String {
    let union = NSScreen.screens.reduce(.null) { $0.union($1.frame) } // global coordinate
    let p = NSEvent.mouseLocation // global coordinate, bottom-left origin, unit: pt
    let x = p.x - union.minX
    let y = union.maxY - p.y      // Y-flip to top-left origin
    return "\(Int(x)),\(Int(y))"
}
```

---

## 4. Property Vocabulary (macOS Mapping)

### 4.1 `system.*`
- `system.year/month/day/hour/minute/second/millisecond/dayofweek`
  → Integer in local time.
- `system.cursor.pos`
  → Current mouse coordinate `"X,Y"` (top-left origin as above, unit: pt).
- `system.os.(id)`
  - `type` = `"macOS"` (fixed).
  - `name` = `"macOS <major.minor[.patch]>"` (from `ProcessInfo.operatingSystemVersion`).
  - `version` = **Darwin kernel version** (`sysctl kern.osrelease`).
  - `build` = **Build number** (`sysctl kern.osversion`).
  - `parenttype` / `parentname` = Only when running under Rosetta 2: `"Rosetta 2"` / `"macOS <version>"`.
- `system.cpu.(id)`
  - `load`: % (moving average possible).
  - `num`: Logical core count (`hw.ncpu`).
  - `vendor` / `name`: `machdep.cpu.brand_string` etc. Apple Silicon assumes `vendor="Apple"`.
  - `clock`: `hw.cpufrequency`.
  - `features`: Readable string from `hw.optional.*` / `machdep.cpu.features`.
- `system.memory.(id)`
  - `load`: % (calculated internally by Ourin).
  - `phyt`: Total physical memory (MB) = `hw.memsize`.
  - `phya`: Available (MB) = estimated from `vm_stat`/`host_statistics` (see Appendix B).

### 4.2 `baseware.*`
- `baseware.name` = `"Ourin"`, `baseware.version`: SemVer string.

### 4.3 `ghostlist/activeghostlist/currentghost.*`
- **Vocabulary follows the UKADOC same-name keys** (including "common property name" group).
- `... .path` returns a **POSIX path**.
- Drawing dimensions such as `currentghost.balloon.scope(ID).validwidth/validheight/lines` are in **logical px**.

### 4.4 `balloonlist/headlinelist/pluginlist/history/rateofuselist`
- Vocabulary and retrieval behavior are compatible with same-name keys. `index(ID)` / `count` etc. are also followed.

### 4.5 Standard Namespace Aliases (sakura/kero/ghost/shell)

Four SSP-compatible shorthand namespaces are registered as `AliasPropertyProvider` instances
during `PropertyManager` initialization (in `registerDefaultProviders`, `PropertyManager.swift`).

| Alias namespace | Delegation target (expanded prefix) |
|---|---|
| `sakura.*` | `currentghost.scope(0).*` |
| `kero.*` | `currentghost.scope(1).*` |
| `ghost.*` | `currentghost.*` |
| `shell.*` | `currentghost.shelllist.current.*` |

**Behavioral details:**

- GET (e.g. `%property[sakura.surface.num]`): The alias provider expands the key and delegates to
  `PropertyManager.shared.get("currentghost.scope(0).surface.num")`. Behavior is identical to direct access.
- SET (e.g. `\![set,property,kero.surface.num,10]`): Likewise, after key expansion, delegates to
  `PropertyManager.shared.set("currentghost.scope(1).surface.num", value: "10")`.
  Succeeds only if the delegation target accepts the SET.
- When the sub-key is empty (e.g. bare `ghost`), the delegation target prefix itself (`currentghost`)
  is used as the key.
- `AliasPropertyProvider.writableProperties()` returns `[]` (writable key enumeration is not
  surfaced through aliases). Whether SET via an alias namespace succeeds depends on the actual
  target provider's implementation.
- Cache behavior: `sakura`, `kero`, `ghost`, and `shell` are not in `uncachedPrefixes`, so
  resolved values are cached. The cache is invalidated when `PropertyManager.invalidateCache()` is called.

---

## 5. Writable Properties (SET-enabled)
> **Note**: Keys not listed here are **read-only by default**.

| Key (wildcard notation) | SET | Example value | Notes |
|---|:--:|---|---|
| `currentghost.shelllist(<name-or-path>).menu` | ✓ | `hidden` / empty string | Show/hide in owned-draw menu |
| `currentghost.seriko.cursor.scope(ID).mouse????list(<hit>).path` | ✓ | `head.cur` / empty string | One of `mouseuplist/mousedownlist/mousehoverlist/mousewheellist`. Empty deletes the definition |
| `currentghost.seriko.cursor.scope(ID).mouse????list.index(ID2).path` | ✓ | `xxx.cur` | Index-specified variant of above |
| `currentghost.seriko.tooltip.scope(ID).textlist(<hit>).text` | ✓ | Any string / empty string | Tooltip text. Empty deletes the definition |
| `currentghost.seriko.tooltip.scope(ID).textlist.index(ID2).text` | ✓ | Any string | Index-specified variant |

> In the implementation, SET to **a non-existent key** must be silently ignored (or warning-logged) with no side effects.

---

## 6. Security and Sandbox
- **SET requests from external input (SSTP/HEADLINE/PLUGIN/SHIORI)** are level-separated and ignored where appropriate.
- When a value includes a path, it must be restricted to **safe paths under baseware management**.

## 7. Compatibility and Differences
- Specific values in Windows `system.os.*` are replaced with macOS equivalents.
- Coordinate system is returned with **top-left origin** (converted from macOS internal representation).
- Response character encoding is fixed to UTF-8.

---

## Appendix A: Rosetta Detection Sample (Swift/C)
**Swift** (using `sysctl.proc_translated`):
```swift
import Foundation

public func isRunningUnderRosetta() -> Bool {
    var flag: Int32 = 0
    var size = MemoryLayout<Int32>.size
    let rc = sysctlbyname("sysctl.proc_translated", &flag, &size, nil, 0)
    return rc == 0 && flag == 1
}
```
**C**
```c
#include <stdbool.h>
#include <sys/sysctl.h>

bool ourin_is_rosetta(void) {
    int flag = 0;
    size_t size = sizeof(flag);
    if (sysctlbyname("sysctl.proc_translated", &flag, &size, NULL, 0) != 0) return false;
    return flag == 1;
}
```

## Appendix B: Implementation Hints (CPU/Memory/OS Info)
- OS name (`name`): `ProcessInfo.processInfo.operatingSystemVersion` → compose as `"macOS X.Y[.Z]"`.
- Darwin version (`version`): `sysctlbyname("kern.osrelease", ...)`.
- Build (`build`): `sysctlbyname("kern.osversion", ...)`.
- CPU: `hw.ncpu`, `machdep.cpu.brand_string`, `machdep.cpu.features`, `hw.cpufrequency`.
- Memory: `hw.memsize`. Estimate `phya` from `vm_stat` or `host_statistics` (example: `free + inactive` pages).

## Appendix C: References
- Property vocabulary and SET availability examples (UKADOC)
  - SET example for `currentghost.shelllist(...).menu`
  - `currentghost.seriko.cursor... .path` / `... .text` are [SET-enabled]
- Coordinate system / Retina
  - Cocoa default is bottom-left origin; `NSEvent.mouseLocation` is in **screen coordinates**
  - `NSWindow.setFrameTopLeftPoint`, `NSView.viewDidChangeBackingProperties()`, `backingScaleFactor`
