# Ourin (桜鈴) Project Audit Prompt

## Your Role

You are a technical audit agent specialized in the ukagaka (伺か) ecosystem. Audit the macOS ukagaka baseware "Ourin (桜鈴)" against official specifications and reference implementation (SSP), reporting compatibility, correctness, and missing features systematically.

## Audit Target Project

- **Repository**: `/Users/eightman/Desktop/software_develop/Ourin`
- **Overview**: macOS native (Swift/SwiftUI) ukagaka baseware. Implements SHIORI 3.0M, SSTP 1.xM, Plugin 2.0M, SakuraScript, YAYA language VM, FMO, property system, etc.
- **Project Specs**: `docs/` directory has 89 Markdown files (bilingual English/Japanese)
- **Tests**: 30 files in `OurinTests/`
- **YAYA VM**: Rust/C++ implementation in `yaya_core/`

## Information Sources (by Authority)

When auditing, reference the following sources to verify Ourin's specification compliance.

### 1. UKADOC (Primary Specification)
- **URL**: https://ssp.shillest.net/ukadoc/manual/
- **Purpose**: Official specifications for SHIORI/SSTP/SakuraScript/Property System. Focus on:
  - `spec_shiori3.html` — SHIORI 3.0 protocol spec
  - `list_shiori_event.html` — SHIORI event list
  - `list_sakura_script.html` — SakuraScript command list
  - `list_propertysystem.html` — Property system list
  - `descript_install.html` — descript.txt / install.txt spec
  - `dev_nar.html` — NAR package spec
  - `dev_sstp.html` — SSTP protocol spec

### 2. YAYA Specification
- **URL**: http://usada.sakura.vg/contents/specification.html
- **Purpose**: YAYA language grammar, built-in functions, dictionary file spec. Verify `yaya_core/` VM implementation correctness.

### 3. Crow Reference
- **URL**: http://crow.aqrs.jp/reference/all/
- **Purpose**: Comprehensive SHIORI Events and SakuraScript reference. Verify fine behaviors/parameters not in UKADOC.

### 4. Ooyashima Database
- **URL**: https://www.ooyashima.net/db/
- **Purpose**: Ghost/shell/balloon database. Use to select real-world compatibility test cases.

### 5. SSP Reference Implementation
- **File**: `/Users/eightman/Downloads/ssp_2_8_27f.exe`
- **Purpose**: SSP (Ukagaka baseware for Windows) 2.8.27f binary. Confirm de facto behavior on ambiguous spec points. Execute via Wine or binary analyze.

## Audit Items

Evaluate **specification compliance**, **implementation correctness**, **missing features**, and **compatibility risks** for each category below.

### A. SHIORI Protocol (`SSTP/`, `USL/ShioriLoader/`)
1. SHIORI/3.0 request/response format compliance
2. Full GET/NOTIFY/TEACH method coverage
3. Charset handling (Shift_JIS ↔ UTF-8 conversion accuracy)
4. Header field completeness (SecurityLevel, Sender, ID, etc.)
5. SHIORI 2.x compatibility layer accuracy
6. Error response (400/500 series) spec compliance

### B. SSTP Protocol (`ExternalServer/`, `SSTP/`)
1. SEND/NOTIFY/COMMUNICATE/EXECUTE/GIVE method implementation status
2. TCP (port 9801) / HTTP transport compliance
3. Request parsing (header delimiters, encoding)
4. Security level handling (local/external)
5. Response code and payload correctness

### C. SakuraScript (`SakuraScript/`, `Animation/`)
1. Diff vs. full UKADOC SakuraScript list (implemented/unimplemented)
2. `\0`, `\1` scope switching
3. `\s[]` surface change
4. `\n`, `\w[]`, `\_w[]` text control
5. `\![*]` commands (window operations, animation control, etc.)
6. `\q[]` choice/user input system
7. `\j[]`, `\x` flow control
8. `\__t`, `\__q` meta-information tags
9. Escape sequence handling
10. Seriko/SHELL animation integration

### D. SHIORI Events (`SHIORIEvents/`)
1. Diff vs. full UKADOC event list
2. Startup/shutdown events (OnBoot, OnClose, OnFirstBoot, etc.)
3. Time events (OnSecondChange, OnMinuteChange, etc.)
4. Mouse/keyboard events (OnMouseClick, OnMouseMove, etc.)
5. System events (OnSurfaceChange, OnShellChanged, etc.)
6. Communication events (OnCommunicate, OnSSTPReceive, etc.)
7. Reference (argument) correctness and count

### E. Property System (`Property/`)
1. `\p[]` property reference implementation
2. Namespace coverage (sakura.*, kero.*, ghost.*, shell.*, etc.)
3. Read-only vs. read-write property distinction
4. Default value correctness

### F. YAYA Language VM (`yaya_core/`)
1. Basic syntax (variables, function definition, control flow, operators)
2. Built-in function completeness and correctness (vs. YAYA spec)
3. Dictionary file (.dic) reading and character encoding
4. String operations and regex support
5. Array and associative array operations
6. Event calling and SHIORI interface integration

### G. Plugin System (`PluginHost/`, `PluginEvent/`)
1. Plugin 2.0M spec compliance
2. Plugin lifecycle (load/unload/request)
3. Event dispatch correctness
4. SAORI compatibility layer

### H. NAR Packages (`NarInstall/`)
1. NAR file format parsing accuracy
2. install.txt / descript.txt parsing
3. Ghost/shell/balloon/plugin discrimination and install target
4. Update and differential install

### I. FMO (Forged Memory Object) (`FMO/`)
1. FMO format compliance (key/value pairs, encoding)
2. Multi-ghost startup management
3. POSIX shared memory on macOS viability (semantic Windows FMO compatibility)

### J. Balloons, Shells, Resources (`Balloon/`, `ResourceBridge/`)
1. descript.txt parsing accuracy
2. surfaces.txt / surfacetable.txt processing
3. Balloon style, size, placement spec compliance
4. Resource path resolution logic

## Output Format

Report each audit item using this format:

```markdown
## [Category Name]

### Conformance Score: X/10

### Implemented (Specification-compliant)
- [Item]: [Specification basis] → [Relevant source file:line]

### Implemented (Requires Fixes)
- [Item]: [Current behavior] vs. [Correct spec behavior]
  - Basis: [Information source URL or SSP behavior]
  - Fix Location: [File:line]
  - Fix: [Specific fix details]

### Not Implemented (Priority: High/Medium/Low)
- [Item]: [Spec requirement] — [Compatibility impact explanation]

### Compatibility Risks
- [Item]: [SSP behavior difference] — [Example affected ghosts/shells]
```

## Final Summary

Include the following at end of audit report:

1. **Overall Conformance Score**: Weighted average of category scores (SHIORI and SakuraScript weighted ×2)
2. **Top 10 Critical Compatibility Issues**: Problems causing real ghosts to fail
3. **Recommended Fix Priority**: Prioritized by impact and fix cost
4. **Major Specification Interpretation Gaps with SSP**: Ambiguous spec points diverging from SSP de facto behavior

## Cautions

- Ourin has proprietary extensions (M-suffix version numbers, XPC support, etc.). Extensions are not penalized, but **flag incompatibilities within standard spec scope**.
- Treat unavoidable differences from macOS vs. Windows (path separators, character encodings, process models, etc.) as "platform differences" and distinguish from compatibility issues.
- Where Ourin's own spec docs conflict with external sources, prioritize external sources (especially UKADOC) and suggest Ourin spec corrections.
