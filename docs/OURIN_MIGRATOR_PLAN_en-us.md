# Ourin Migrator Plan

Ourin Migrator is implemented as a DevTools feature that reads SSP/Windows-derived assets without breaking them, and progressively transforms and assists them into a form usable by Ourin.

## Purpose

- Analyze SSP-compatible assets under `/Users/eightman/Documents/Ourin`
- Treat Windows `.dll` / `.exe` as migration targets rather than executing them in Ourin itself
- Maintain existing SSP-compatible metadata such as `descript.txt`
- Obtain pseudo C code, imports, exports, strings, and resources via Ghidra headless analysis
- Generate `ourin.json` to connect with Ourin builtin replacements and macOS plugin implementations
- For unknown DLLs, generate `.plugin` scaffold and implementation TODO report rather than fully automatic conversion

## Basic Policy

DLL/EXE files will not be loaded in Ourin itself. On normal startup, only `descript.txt`, `ourin.json`, macOS native plugin, and builtin replacement are used.

Ghidra will not be bundled with Ourin. The DevTools side will invoke the user-specified `analyzeHeadless` as an external process.

Original SSP-compatible file structure will be maintained, and only additional information for Ourin will be placed in `ourin.json` or under the `ourin/` directory.

When distributing and storing ported plugins, place `install.txt`, `descript.txt`, and `message.*.txt` in the root of the package directory, where the Ourin host will interpret them. The generated macOS `.plugin` will limit its responsibilities to compatibility with the original DLL's `load` / `loadu` / `request` / `unload` / `unloadu` and minimal `descript.txt` fallback. Display text and language selection will not be hardcoded into the `.plugin`; they will be delegated to `message.*.txt` in principle.

```text
plugin/shared_value/
  descript.txt
  install.txt
  message.japanese.txt
  message.english.txt
  shared_value.dll
  ourin.json
  ourin/
    analysis/
      report.md
      imports.json
      exports.json
      strings.txt
      resources.txt
      decompiled.c
    macos/
      shared_value.plugin/
```

For distribution, the standard macOS package directory format is as follows:

```text
plugin/shared_value_mac/
  install.txt
  descript.txt
  message.japanese.txt
  message.english.txt
  shared_value.plugin/
  Sources/
    SharedValuePlugin.c
  OriginalDocs/
    ReadMe.txt
```

`OriginalDocs/` is for preservation and reference of the original distribution and is not normal runtime input.

## Implementation Location

```text
Ourin/DevTools/Migrator/
  OurinMigratorView.swift
  LegacyAssetScanner.swift
  LegacyBinaryAnalyzer.swift
  GhidraHeadlessRunner.swift
  MigrationReport.swift
  OurinManifest.swift
  PluginScaffolder.swift
  Resources/
    DecompileAll.java
```

Use existing compatibility processing in:

```text
Ourin/Compat/LegacyDescriptor.swift
Ourin/Compat/SSPCompat.swift
Ourin/Calendar/CalendarRegistry.swift
Ourin/PluginHost/PluginRegistry.swift
```

## Target Directories

Initial scan targets are as follows:

```text
/Users/eightman/Documents/Ourin/plugin
/Users/eightman/Documents/Ourin/calendar/plugin
/Users/eightman/Documents/Ourin/headline
/Users/eightman/Documents/Ourin/data
```

Detection targets:

```text
*.dll
*.DLL
*.exe
*.EXE
descript.txt
ourin.json
```

## Display Information

The DevTools list displays the following:

```text
Name
Kind: plugin / calendar-plugin / headline / tool / unknown
Binary: PE32 / PE32+ / unknown
Filename
ID
Status: metadata-only / analyzed / mapped / scaffolded
Recommendation
```

Basic UI form:

```text
Ourin Migrator
  [Scan Documents/Ourin]
  [Ghidra Path: ...]
  [Analyze Selected]
  [Generate ourin.json]
  [Create Plugin Scaffold]

Name | Kind | Binary | Status | Action
```

Detail pane:

```text
descript.txt summary
imports
exports
strings preview
resources preview
migration recommendation
generated files
```

## Ghidra Analysis

Ghidra default candidate:

```text
/Users/eightman/Downloads/ghidra_12.0.4_PUBLIC/support/analyzeHeadless
```

Analysis runs as an external process via `Process`. Project workspace is created in a temporary directory, and artifacts are saved to `ourin/analysis/` in each target folder.

Generated files:

```text
ourin/analysis/decompiled.c
ourin/analysis/imports.json
ourin/analysis/exports.json
ourin/analysis/strings.txt
ourin/analysis/resources.txt
ourin/analysis/report.md
```

Since Ghidra analysis takes time, DevTools will enable progress display and cancellation.

## ourin.json

`ourin.json` represents the correspondence relationship between the original DLL/EXE and Ourin implementation.

Example:

```json
{
  "format": "ourin-migration-1",
  "source": {
    "filename": "shared_value.dll",
    "kind": "pe32-dll",
    "sspPluginId": "ABED14AF-F34B-4ff2-95B7-30ED37D5802D"
  },
  "mode": "native-replacement",
  "implementation": "builtin:shared_value",
  "analysis": {
    "decompiled": "ourin/analysis/decompiled.c",
    "report": "ourin/analysis/report.md"
  }
}
```

Main `mode` options:

```text
metadata-only       Do not execute DLL/EXE, use only SSP metadata
native-replacement  Replace with Ourin builtin implementation
native-plugin       Use macOS .plugin/.bundle
scaffold            Scaffold generated, awaiting implementation
unsupported         Currently not supported
```

## Known DLL/EXE Builtin Replacement Candidates

Initially treat the following as migration targets:

```text
shared_value.dll -> builtin:shared_value
SAKNIFE.DLL      -> builtin:saknife or scaffold
SCHEDULE.dll     -> builtin:calendar_schedule or scaffold
SSPH.exe         -> builtin:ssph_compat
mcp.exe          -> builtin:mcp_compat
```

Known DLLs should not be machine-converted from pseudo C to Swift; instead, implement equivalent functionality natively on the Ourin side and link it via `ourin.json`.

## .plugin Scaffold Generation

For unknown DLLs, generate a macOS plugin scaffold rather than full conversion:

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

Internal structure of `<name>.plugin`:

```text
<name>.plugin/
  Contents/
    Info.plist
    MacOS/<name>
    Resources/
      descript.txt
      ourin.json
```

Scaffold provides minimal PLUGIN/DLL compatibility entry points:

```text
load
loadu
request
unload
unloadu
plugin_free (if needed)
```

Behavior for each event ID branches within `request`. However, menu display names and message text are made readable to the Ourin host from `message.*.txt`, avoiding hardcoding into the `.plugin` side.

At the same time, `ourin/analysis/report.md` outputs implementation TODOs inferred from exports/imports/strings.

## Implementation Phases

### Phase 1: Scanning

- Detect `.dll` / `.exe` / `descript.txt` / `ourin.json` from target directories
- Classify PE32 / PE32+ / unknown via file command equivalent judgment
- Read `descript.txt` with both UTF-8 and Shift_JIS support using `LegacyDescriptor`
- Display list in DevTools

### Phase 2: Analysis

- Enable Ghidra path configuration
- Perform headless analysis on selected files
- Save pseudo C, imports, exports, strings, and resources
- Record analysis logs, success/failure, and elapsed time

### Phase 3: Report Generation

- Generate `report.md`
- Summarize binary kind, exports, imports, notable strings, and presumed functionality
- Present recommended migration mode for Ourin

### Phase 4: ourin.json Generation

- Enable writing `metadata-only` / `native-replacement` / `native-plugin` / `scaffold` / `unsupported`
- Auto-suggest builtin implementation names for known DLLs
- Confirm overwrite if existing `ourin.json` exists

### Phase 5: .plugin Scaffold Generation

- Generate `.plugin` scaffold for unknown DLLs
- Create `Info.plist`, executable file placeholder, and `Resources/ourin.json`
- Append generated items and TODOs to `report.md`

## MVP

The initial completion line is as follows:

1. Display DLL/EXE list in DevTools
2. Analyze selected files via Ghidra headless
3. Generate `ourin/analysis/decompiled.c` and `report.md`
4. Generate `ourin.json`
5. Recognize `shared_value.dll` as `builtin:shared_value`

The MVP does not aim for automatic conversion. Analysis, classification, and Ourin manifest generation are the primary objectives.

## Cautions

- Pseudo C from Ghidra is not original source, so full automatic conversion to Swift/macOS plugin will not be performed
- Untrusted binaries are handled, so they will not be executed within Ourin process
- Ghidra/Java dependencies will not be forced on regular users
- Original SSP assets will not be destroyed
- Overwriting generated files requires confirmation or backup

## License & Attribution

- **Ghidra**: This feature invokes Ghidra (developed by National Security Agency, Apache License 2.0) as an external tool. Ghidra is not bundled with Ourin.
  - https://ghidra-sre.org/
  - https://www.apache.org/licenses/LICENSE-2.0
- **DecompileAll.java**: Ourin code (CC BY-NC-SA 4.0) using Ghidra Script API. Instantiated at runtime from `GhidraScriptSource.swift`.
- **Analysis target DLL/EXE**: SSP-compatible assets follow their respective licenses. The Migrator assists with read-only analysis and conversion and does not imply permission to redistribute original assets.

Ghidra license text can be referenced from the app's About → "Show Licenses..." menu.
