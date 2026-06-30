# Plugin Compatibility Implementation Proposal

**Created:** 2026-06-26

This document consolidates the SSP/PLUGIN compatibility approach and current implementation gaps for Ourin.

## Baseline Policy

Going forward, macOS-ported plugins adopt this responsibility separation:

```text
SomePlugin_mac/
  install.txt
  descript.txt
  message.japanese.txt
  message.english.txt
  SomePlugin.plugin/
```

- Ourin host interprets `install.txt`, `descript.txt`, `message.*.txt`.
- `.plugin` bundle concentrates on DLL `load` / `loadu` / `request` / `unload` / `unloadu` compatibility.
- Display strings and language selection default to `message.*.txt`.
- Windows DLL is not directly loaded on macOS.

## Fix 1: Update PluginScaffolder output format to `*_mac/`

**Problem**

`docs/SPEC_PLUGIN_2.0M_en-us.md` and `docs/OURIN_MIGRATOR_PLAN.md` standardized `SomePlugin_mac/`, but current `PluginScaffolder` generates legacy format `ourin/macos/<name>.plugin/`.

**Proposal**

Change `PluginScaffolder.scaffold` output to:

```text
ourin/macos/<name>_mac/
  install.txt
  descript.txt
  message.japanese.txt
  message.english.txt
  <name>.plugin/
    Contents/
      Info.plist
      MacOS/<name>
      Resources/
        descript.txt
        ourin.json
  Sources/
    <name>Plugin.c
  OriginalDocs/
    ReadMe.txt
```

**Acceptance Criteria**

- `OurinMigratorTests.scaffoldGeneratesPluginBundleStructure` updated to new structure and passes.
- If existing `descript.txt` / `install.txt` / `message.*.txt` present, copy to root and `OriginalDocs/`.
- `IMPLEMENTATION_TODO.md` not in bundle but in `<name>_mac/README.md` or `Sources/`.

## Fix 2: Prevent double-loading of same plugin ID

**Problem**

`/Users/eightman/Documents/Ourin/plugin/SAKNIFE.plugin` and `SAKNIFE_mac/SAKNIFE.plugin` can both exist, causing same `id` plugin to load twice.

**Proposal**

Add dedup to `PluginRegistry.discoverAndLoad` for loaded ID / bundle path.

Priority:

1. Native `.plugin` in package directory with `install.txt`
2. Native `.plugin` placed directly
3. Legacy metadata-only directory

With duplicates by same ID, use highest priority, skip lower, log result.

**Acceptance Criteria**

- Add test to `LegacyPluginRegistryTests`: "direct `.plugin` and `*_mac` with same ID registers only one".
- `installedplugin` and `pluginpathlist` have no duplicate IDs.

## Fix 3: Separate meaning of `PluginMeta.path`

**Current:** 2026-06-27 implemented. Added `PluginMeta.compatibilityPath` / `executablePath` / `packagePath` and `PluginCompatibilityEntry`; accessible via `pluginlist.index(n).executablepath` / `pluginlist.index(n).packagepath` / `executionstate` / `candispatchrequests`.

**Problem**

If package root `descript.txt` has legacy DLL `filename,SAKNIFE.dll`, `PluginMeta.path` becomes DLL path. But actual loaded native bundle is `SAKNIFE.plugin`, making `pluginpathlist` semantics ambiguous.

**Proposal**

Separate `PluginMeta` into compatibility and execution paths:

```swift
public let compatibilityPath: String   // descript.txt filename, DLL compatible.
public let executablePath: String      // actual load target, native .plugin / .bundle.
public let packagePath: String?        // install.txt package directory.
```

Keep legacy `path` for compatibility, treat as `compatibilityPath` alias over time.

**Acceptance Criteria**

- `pluginlist.index(n).path` remains for backwards compatibility.
- `pluginlist.index(n).executablepath` returns native `.plugin` path.
- `pluginpathlist` spec clarifies which to send. Recommend package path, else executable path.

## Fix 4: Wire `message.*.txt` to actual display

**Problem**

Ourin retains `message.*.txt` in `PluginMeta.localizedMessages`, but SAKNIFE `.plugin` still has fixed menu text internally.

**Proposal**

Short term:

- Ourin plugin menu UI / DevTools display prioritizes `PluginMeta.message(for:)`.
- Add display examples using `pluginlist(...).message.<key>`.

Medium term:

- If `.plugin` `load` receives package root path, provide helper function for plugin to read root `message.*.txt`.
- Policy: shift menu building to Ourin host, let `.plugin` only process command ID.

**Acceptance Criteria**

- Changing `SAKNIFE_mac/message.japanese.txt` `menu.empty_recycle_bin` reflects in Ourin display.
- Minimal fixed menu names in `.plugin` source.

## Fix 5: Clarify reload / rescan of `install.txt` packages

**Problem**

Plugin registry now reads package directories, but update/reload scope ambiguous: bundle or package?

**Proposal**

- Keep `packageURL` in registry internal record.
- `unloadAll()` unloads native bundle, clears package metadata.
- `discoverAndLoad()` re-evaluates per package.
- DevTools plugin list shows both `packageURL` and `executablePath`.

**Acceptance Criteria**

- After changing `SAKNIFE_mac/message.*.txt`, plugin reload updates metadata.
- UI distinguishes bundle direct vs package plugin.

## Fix 6: Standardize SAKNIFE placement to standard form

**Problem**

Currently `SAKNIFE.plugin` direct and `SAKNIFE_mac/SAKNIFE.plugin` coexist for verification.

**Proposal**

Standard is `SAKNIFE_mac/`, retire direct `/plugin/SAKNIFE.plugin` as verification or legacy artifact.

Preferred placement:

```text
/Users/eightman/Documents/Ourin/plugin/SAKNIFE_mac/
```

Archive candidate:

```text
/Users/eightman/Documents/Ourin/plugin/_legacy_native/SAKNIFE.plugin
```

**Acceptance Criteria**

- On startup, SAKNIFE registers once.
- `installedplugin` has no SAKNIFE duplicates.

## Fix 7: Sync docs and tests

**Problem**

Policy entering docs, but implementation and tests not fully tracking.

**Proposal**

- `SPEC_PLUGIN_2.0M_en-us.md` `*_mac` policy is source of truth.
- `OURIN_MIGRATOR_PLAN.md` and `PluginScaffolder` output align.
- Add tests for new `message.<key>` in PropertySystem_en-us/ja-jp.

**Acceptance Criteria**

- `xcodebuild -project Ourin.xcodeproj -scheme Ourin build` succeeds.
- Added or updated tests pass.
- Docs standard structure actually generated by Migrator.

## Recommended Implementation Order

1. Decide on direct `.plugin` handling, eliminate double-load risk.
2. Implement `PluginMeta.path` meaning separation.
3. Add dedup to `PluginRegistry` same ID priority/dedup.
4. Update `PluginScaffolder` to `*_mac/` output.
5. Wire `message.*.txt` to UI display.
6. Sync tests and docs.

## Minimum Fix Set

Focus on brittle areas first:

1. Same plugin ID double-load prevention.
2. Add `PluginMeta` `executablePath` / `packagePath`.
3. Change `PluginScaffolder` output to `*_mac/`.

This 3-point fix resolves most current policy/implementation drift.
