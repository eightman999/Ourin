# Ourin DevTools UI Mockup

This document outlines a proposed "Settings, Test & Debug" interface for **Ourin** on macOS. The mockup follows Apple's Human Interface Guidelines and utilises the standard Sidebar + Toolbar layout with a detail view on the right.

## 0. Screen Map
```
┌──────────────────────────────────────────────────────────────┐
│  Ourin DevTools                                      [Search]│
│  ─────────────────────────────────────────────────────────── │
│  ▸ General                                                  ││
│  ▸ SHIORI Resource                                          ││
│  ▸ Plugins & Events                                         ││  ← Sidebar
│  ▸ External (SSTP/HTTP/XPC)                                 ││     Section + Items
│  ▸ Headline / Balloon                                       ││
│  ▸ Logging & Diagnostics                                    ││
│  ▸ Network                                                  ││
│                                                              │
│  ─────────────────────────────────────────────────────────── │
│  [Toolbar:  ⟳ Reload   ▶ Run Test   ⏹ Stop   ⎘ Export  ]    │
│  ─────────────────────────────────────────────────────────── │
│  [Detail View / Form / Table / Live Preview / Log Console]  │
└──────────────────────────────────────────────────────────────┘
```

The sidebar offers consistent navigation while the right pane hosts searchable tables and forms. Toolbar buttons are limited to reloading, running tests, stopping tasks and exporting.

## 1. Common UI Guidelines
- Search fields filter lists/tables in each pane.
- Toolbar keeps button count small, following HIG recommendations.
- Status badges appear at the top‑right (success/warning/error).
- Shortcuts: **⌘R** run, **⌘S** save/export, **⌘F** search.
- Operations log to `Logger` (subsystem `jp.ourin.devtools`, category `ui`).

## 2. Pane Mockups
### 2.1 General
Edit global defaults such as:
- Data folder path (`POSIX/file://`)
- Default encoding (UTF‑8 with optional CP932)
- Rosetta detection (read‑only)
- Auto‑start and update checks

Validation confirms path existence and write permissions. Saving emits a log entry (`settings` category).

### 2.2 SHIORI Resource Viewer/Overlay
- Segment control: All | SHIORI | Ghost | Menu | Colors | Update
- Table columns: Key, Value (read‑only), Overlay (Ourin), Effective, Last Fetched
- Right pane previews colours or bitmaps.
- Reload resources, apply or clear overlays. Applying fires a signpost `apply_resource_overlay`.

### 2.3 Plugin Manager / Event Injector
- Left list: plugins (enabled, ID, version, path)
- Right form injects events: Event ID, ReferenceN fields, Sender and Charset
- Send (GET) / Notify buttons, presets can be saved
- Logging around injection uses category `plugin`; signpost `inject_event` records duration.

### 2.4 External Events Harness
Manage SSTP/HTTP/XPC listeners.
- TCP (9801) start/stop, binding address, status
- HTTP POST `/api/sstp/v1` start/stop, stats
- XPC service `jp.ourin.sstp` start/stop, client list
- Provide sample requests for SSTP/HTTP and minimal XPC snippets.

### 2.5 Headline / Balloon Test
- Headline: configure URL/path and view the response table
- Balloon: choose shell/balloon, preview PNG with scale/DPI and anchor layout

### 2.6 Logging & Diagnostics
- Query bar: subsystem (default `jp.ourin.*`), category, level and time range
- Table shows time, level, category, message and metadata
- Signpost timeline visualises durations using `OSSignposter`

### 2.7 Network & Listener Status
- Monitor current connections and throughput for SSTP/HTTP/XPC
- Display counters such as 2xx/4xx/5xx for HTTP and average processing time

## 3. Test Scenarios
- **Ghost Boot → Menu Exec → Exit** (signpost `scenario_boot_menu_exit`)
- External NOTIFY round‑trip via TCP 9801
- HTTP `SEND` via `/api/sstp/v1`
- Direct XPC delivery including oversize handling

## 4. Accessibility & Internationalisation
- VoiceOver labels for table columns
- Keyboard shortcuts for switching sidebar/detail panes
- Runtime locale switching with line height auto‑adjust

## 5. Log Collection & Export
`File > Export Diagnostics…` bundles OSLog extraction, signposts, settings snapshots and environment info into a zip archive.

## 6. Known Issues / TBD
- Paging long resource lists and overlay timing
- Signpost naming: `ourin.resource.apply`, `ourin.plugin.inject`, `ourin.net.sstp`, etc.
- XPC permission requirements and UI exposure
- Network permission explanations

---
_Last updated: 2025‑07‑27_
