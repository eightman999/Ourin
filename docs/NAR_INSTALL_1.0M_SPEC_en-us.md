# Ourin — **NAR Double-Click Installer** Specification (NAR-INSTALL/1.0M, macOS)

**Status:** Draft
**Updated:** 2026-06-28
**Target:** macOS 10.15+ (Catalina and later), Universal 2 (arm64 / x86_64)

> Purpose: When the user double-clicks a **`.nar`** file (a ZIP archive) or opens it with Ourin via "Open With", the app receives the file and extracts **ghost / balloon / shell / plugin / package / calendar / language** content to the appropriate directory according to the vocabulary defined in `install.txt`. This specification follows SSP conventions (drag-and-drop / double-click) while mandating **UTF-8 as the default encoding**, **CP932 acceptance**, and **Zip Slip prevention**.

---

## Table of Contents
- [0. Terminology and Prerequisites](#0-terminology-and-prerequisites)
- [1. Scope and Non-Goals](#1-scope-and-non-goals)
- [2. Dependencies and References](#2-dependencies-and-references)
- [3. File Association (UTI/Document Types)](#3-file-association-utidocument-types)
- [4. Open Handler](#4-open-handler)
- [5. Archive Validation and Encoding Detection](#5-archive-validation-and-encoding-detection)
- [6. install.txt Vocabulary](#6-installtxt-vocabulary)
- [7. Extraction Policy (Safe Unzip and Placement)](#7-extraction-policy-safe-unzip-and-placement)
- [8. Conflict and Update (accept/delete/homeurl)](#8-conflict-and-update-acceptdeletehomeurl)
- [9. Logging and Failure UX](#9-logging-and-failure-ux)
- [10. Security (Zip Slip / Quarantine)](#10-security-zip-slip--quarantine)
- [11. Compatibility Notes (Windows/Case/Line-ending Differences)](#11-compatibility-notes-windowscaseline-ending-differences)
- [Appendix A. Info.plist Example](#appendix-a-infoplist-example)
- [Appendix B. Success/Failure Flow](#appendix-b-successfailure-flow)
- [Appendix C. Sample Structure](#appendix-c-sample-structure)
- [Implementation Status](#implementation-status)
- [Changelog](#changelog)

---

## 0. Terminology and Prerequisites
- **.nar**: Ukagaka distribution package. **The actual format is ZIP.**
- **install.txt**: The **install manifest** placed at the top level of the archive (`type`/`directory`/`*.directory` and other fields).
- **Ourin base directory**: `~/Documents/Ourin/` (falls back to `~/Library/Application Support/Ourin/` when Documents is unavailable).
- **Character encoding**: **UTF-8 default**, **CP932 accepted** (internally normalized to UTF-8).

## 1. Scope and Non-Goals
- **In scope**: Installation triggered by Finder **double-click**, "Open With", or **drag-and-drop** onto an Ourin window.
- **Non-goals**: Binary-level Windows compatibility reproduction or full Install UI replication. The focus is **protocol (install.txt vocabulary) compatibility**.

## 2. Dependencies and References
- **Apple UTI/Document Types**: `.nar` exported as a **custom UTI** conforming to **`public.zip-archive``. Associated via `CFBundleDocumentTypes`; the app implements an **open handler**.
- **NSApplicationDelegate**: URL/path received via `application(_:openFiles:)` / `application(_:open:)`.
- **Ukadoc**: Conforms to operational conventions for **install.txt / distribution / network updates** (`updates2.dau`/`delete.txt`/drag-and-drop/double-click).

## 3. File Association (UTI/Document Types)
- Declare `jp.ourin.nar` in **UTExportedTypeDeclarations** with `UTTypeConformsTo = public.zip-archive` and extension `nar`.
- Set `LSItemContentTypes = jp.ourin.nar` in **CFBundleDocumentTypes** (Role: Viewer or Editor).
- Priority in case of conflict is controlled by **LSHandlerRank**.

## 4. Open Handler
- Implement both `NSApplicationDelegate.application(_:openFiles:)` (multiple files) and `application(_:open:)` (URL) so the handler is called whether the app is already running or launches fresh. Bridge AppKit delegate even in SwiftUI configurations.

## 5. Archive Validation and Encoding Detection
- Verify **zip compatibility** by MIME/UTType and also check the leading record.
- `install.txt` is read **preferring UTF-8**. On failure, retry with **CP932** and normalize internally to UTF-8. BOM and CRLF are accepted.
- When a `charset` declaration is present on the first non-comment line (either `charset,<value>` or `charset:<value>` syntax), that encoding is used preferentially before falling back to auto-detection.

## 6. install.txt Vocabulary

- **Required**: `type,<kind>` / `directory,<install-name>` (`directory` may be omitted for `supplement` and `package`)
- **Optional**: `accept,<identifier>`, `*.directory,<bundled-name>` (e.g., `balloon.directory,MyBalloon`), `*.source.directory`, etc.
- **Recommended**: Place `charset,UTF-8` **at the top** of the file.

### 6.1 Accepted type Values and Install Destinations

| type value | Accepted spelling variants | Install destination (`<base>` = `~/Documents/Ourin`) |
|------------|---------------------------|------------------------------------------------------|
| `ghost` | — | `<base>/ghost/<directory>` |
| `balloon` | — | `<base>/balloon/<directory>` |
| `shell` | — | `<base>/ghost/<accept>/shell/<directory>` |
| `plugin` | — | `<base>/plugin/<directory>` |
| `headline` | — | `<base>/headline/<directory>` |
| `package` | — | `<base>/package/<directory>` |
| `supplement` | — | `<base>/ghost/<accept>/` (directory is optional) |
| `calendar/skin` | `calendar skin`, `calendarskin` | `<base>/calendar/skin/<directory>` |
| `calendar/plugin` | `calendar plugin`, `calendarplugin` | `<base>/calendar/plugin/<directory>` |
| `calendar` | — (legacy form without skin/plugin distinction) | `<base>/calendar/<directory>` |
| `language` | — | `<base>/language/<directory>` |

`calendar/skin` and `calendar/plugin` are accepted regardless of case, spaces, or slashes (`InstallTxtParser.swift` → `OurinPaths.installTarget()`). The legacy `calendar` form (no sub-type distinction) is retained for backward compatibility. `language` corresponds to the language type in the UKADOC install.txt specification.

`shell` and `supplement` require the `accept` field to specify the target ghost's directory name. If `accept` is absent, an `installTxtMissingKey("accept")` error is raised.

### 6.2 refreshundeletemask Field

```
refreshundeletemask,pattern1:pattern2:...
```

- The UKADOC-specified delimiter is a **colon (`:`)**. This is the primary separator.
- For compatibility with existing data, **commas (`,`)** are also accepted as delimiters (`InstallTxtParser.swift:106`).
- Values are parsed into the `refreshUndeleteMask: [String]` array as a set of regex patterns.
- Used in combination with `refresh,1`. When `refresh,1` is specified, paths matching any mask entry are excluded from pre-install deletion.

Example:
```
refresh,1
refreshundeletemask,savedata:*.sav:userconfig.txt
```

The above is parsed as three colon-delimited elements: `savedata`, `*.sav`, and `userconfig.txt`.

## 7. Extraction Policy (Safe Unzip and Placement)
- **Safely extract** to a temporary directory → interpret `install.txt` → copy to the **install destination**.
- **Excluded**: `__MACOSX/`, `.DS_Store`, and `Thumbs.db` are automatically excluded.
- **Case sensitivity**: File names are handled **strictly**, with warnings on duplicate collisions.

## 8. Conflict and Update (accept/delete/homeurl)
- If the existing `{directory}` is present: overwrite-update if `accept` matches; suggest a rename if it differs.
- If `delete.txt` is present, remove unnecessary assets. Update distribution follows `homeurl` + `updates2.dau`.

## 9. Logging and Failure UX
- Log major phases (validation/parsing/extraction/post-processing) via `OSLog`.
- Representative errors: `InstallTxtMissing`, `UnsupportedType`, `ZipSlipDetected`, `NameConflict`, `DecodeFailed(sjis)`.

## 10. Security (Zip Slip / Quarantine)
- **Zip Slip**: Normalize paths before extraction and **reject** any write outside the target directory via `..`, absolute paths, or symbolic links.
- Quarantine attributes from downloaded files are treated as a normal flow since the action is **user-initiated** (double-click/drop).

## 11. Compatibility Notes (Windows/Case/Line-ending Differences)
- Existing Windows distributions may arrive with **Shift_JIS** encoding and `\\` path separators. Ourin **accepts the input** and normalizes internally to UTF-8 / UNIX paths.
- Both CRLF and LF line endings are accepted.

---

## Appendix A. Info.plist Example
```xml
<!-- Info.plist excerpt: UTI and Document Types -->
<key>UTExportedTypeDeclarations</key>
<array>
  <dict>
    <key>UTTypeIdentifier</key><string>jp.ourin.nar</string>
    <key>UTTypeDescription</key><string>Ukagaka NAR</string>
    <key>UTTypeConformsTo</key>
    <array><string>public.zip-archive</string></array>
    <key>UTTypeTagSpecification</key>
    <dict>
      <key>public.filename-extension</key><array><string>nar</string></array>
      <key>public.mime-type</key><string>application/x-ukagaka-nar</string>
    </dict>
  </dict>
</array>

<key>CFBundleDocumentTypes</key>
<array>
  <dict>
    <key>CFBundleTypeName</key><string>Ukagaka NAR</string>
    <key>LSItemContentTypes</key>
    <array><string>jp.ourin.nar</string></array>
    <key>CFBundleTypeRole</key><string>Viewer</string>
  </dict>
</array>
```

## Appendix B. Success/Failure Flow
```
Finder(.nar) → Launch Services → Ourin(app open)
 → open handler
   → validate(zip) OK? → read install.txt → parse {type,directory,...}
   → resolve install path
   → safeExtract → copy/merge → post steps(readme/terms, switch)
   → success toast

Failure cases:
  - no install.txt → error: InstallTxtMissing
  - unsupported type → error: UnsupportedType
  - zip slip → error: ZipSlipDetected
  - directory conflict → user prompt(rename/overwrite)
```

## Appendix C. Sample Structure
```
OURIN_NAR_INSTALL_1_0M/
  NAR_INSTALL_1.0M_SPEC.md
  NAR_INSTALL_1.0M_PLAN.md
  sample/
    Sources/OurinNarInstallerSample/
      AppDelegate.swift
      SampleNarInstaller.swift
      InstallTxtParser.swift
      ZipUtil.swift
      Paths.swift
    Info.plist (example)
```

---

## Implementation Status

**Last Updated:** 2026-06-28

### Implemented in Ourin

- [x] **NAR file association**: UTI declaration and association for `.nar` in Info.plist
- [x] **Double-click/D&D handling**: openFiles handler in AppDelegate
- [x] **ZIP extraction**: Implemented in `ZipUtil.swift`
- [x] **install.txt parsing**: Implemented in `InstallTxtParser.swift`
- [x] **Encoding auto-detection**: UTF-8 and CP932 auto-detection implemented
- [x] **Zip Slip prevention**: Implemented in `ZipUtil.secureCopyTree()`
- [x] **Type-based install**: `OurinPaths.installTarget()` resolves install destinations for ghost/balloon/shell/supplement/plugin/headline/package/calendar/calendar/skin/calendar/plugin/language
- [x] **Basic error handling**: Install error detection and reporting implemented
- [ ] **Conflict UI**: Full UI for accept/delete/homeurl is not yet complete
- [ ] **Update feature**: updates2.dau processing is not yet implemented
- [ ] **Deletion feature**: delete.txt processing is not yet implemented

### Implemented Features

1. **Package Reception**
   - Double-click from Finder
   - Drag-and-drop onto the Ourin window
   - Launch via "Open With This Application"

2. **Extraction and Validation**
   - ZIP header validation (PK magic number)
   - Safe extraction to a temporary directory
   - install.txt presence check

3. **install.txt Parsing**
   - `type` field parsing (ghost, balloon, shell, supplement, plugin, headline, package, calendar/skin, calendar/plugin, calendar, language)
   - `directory` and `*.directory` parsing
   - `refreshundeletemask` field: colon-delimited per UKADOC; commas also accepted for compatibility
   - UTF-8/CP932 auto-detection and decoding

4. **Safe Placement**
   - Zip Slip attack prevention (no escaping to parent directories)
   - Placement under `~/Documents/Ourin/`
   - Type-based directory routing (ghost, balloon, shell, supplement, plugin, headline, package, calendar/skin, calendar/plugin, calendar, language)

5. **Error Handling**
   - NAR format error (NotZip)
   - install.txt missing (InstallTxtNotFound)
   - Decode error (InstallTxtDecodeFailed)
   - Unsupported type (UnsupportedType)
   - Zip Slip detected (ZipSlipDetected)
   - Directory conflict (DirectoryConflict)

### Not Yet Implemented

1. **Conflict Resolution UI**
   - Overwrite confirmation dialog via the `accept` field
   - Rename/overwrite choices presented to the user

2. **Network Updates**
   - `updates2.dau` processing
   - Automatic update check

3. **Deletion**
   - `delete.txt` processing
   - File removal on uninstall

4. **Advanced Features**
   - README/terms of use display
   - Automatic switch after install
   - `homeurl` processing

### Source File Locations

- `Ourin/NarInstall/LocalNarInstaller.swift`: Installer main body
- `Ourin/NarInstall/InstallTxtParser.swift`: install.txt parsing
- `Ourin/NarInstall/ZipUtil.swift`: ZIP extraction utility
- `Ourin/NarInstall/Paths.swift`: Path resolution (OurinPaths)
- `Ourin/NarInstall/NarInstallViewModel.swift`: UI ViewModel
- `Ourin/NarInstall/NarInstallView.swift`: SwiftUI install screen

---

## Changelog
- 2026-06-28: Added §6.1 type accepted-values table (calendar/skin, calendar/plugin, calendar, language). Added §6.2 refreshundeletemask field delimiter specification (colon primary, comma compatible). Updated implementation status type list. Expanded from placeholder to full specification.
- 2025-10-20: Implementation status section added (Japanese original).
- 2025-07-28: Initial revision (NAR-INSTALL/1.0M).
