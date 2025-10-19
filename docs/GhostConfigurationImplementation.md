# Ghost Configuration System Implementation

## Overview

Implemented a comprehensive system to load and apply ghost configuration from `descript.txt` files. This allows ghosts to set environment variables and properties during startup and loading, following the ukagaka specification.

## Implementation Summary

### 1. GhostConfiguration Structure (`Ourin/Ghost/GhostConfiguration.swift`)

Created a comprehensive structure to hold all `descript.txt` values:

**Basic Information:**
- `charset`, `type`, `name`
- `sakura.name`, `kero.name`, `char*.name`
- `id`, `title`

**Author Information:**
- `craftman`, `craftmanw`, `craftmanurl`
- `homeurl`

**SHIORI Configuration:**
- `shiori` (DLL filename)
- `shiori.version`, `shiori.cache`, `shiori.encoding`, `shiori.forceencoding`
- `shiori.escape_unknown`

**Surface Configuration:**
- `sakura.seriko.defaultsurface`, `kero.seriko.defaultsurface`
- `char*.seriko.defaultsurface`
- `balloon.defaultsurface`

**Position Configuration:**
- `seriko.alignmenttodesktop` (top/bottom/free)
- Scope-specific alignments: `sakura.seriko.alignmenttodesktop`, `kero.seriko.alignmenttodesktop`, `char*.seriko.alignmenttodesktop`
- Base positions: `sakura.defaultx/y`, `kero.defaultx/y`, `char*.defaultx/y`
- Display positions: `sakura.defaultleft/top`, `kero.defaultleft/top`, `char*.defaultleft/top`

**SSTP Configuration:**
- `sstp.allowunspecifiedsend`, `sstp.allowcommunicate`, `sstp.alwaystranslate`

**Balloon Configuration:**
- `balloon`, `default.balloon.path`
- `recommended.balloon`, `recommended.balloon.path`
- `balloon.dontmove`, `balloon.syncscale`

**UI Configuration:**
- `icon`, `icon.minimize`
- `mousecursor`, `mousecursor.text`, `mousecursor.wait`, `mousecursor.hand`, `mousecursor.grip`, `mousecursor.arrow`
- `menu.font.name`, `menu.font.height`

**Behavior Settings:**
- `name.allowoverride`
- `don't need onmousemove`, `don't need bind`, `don't need seriko talk`

**AI Graph Configuration:**
- `shiori.logo.file`, `shiori.logo.x`, `shiori.logo.y`, `shiori.logo.align`

**Installation:**
- `install.accept`, `readme`, `readme.charset`

### 2. Ghost Integration (`Ourin/Property/GhostPropertyProvider.swift`)

Extended the `Ghost` struct to include configuration:
- Added `configuration: GhostConfiguration?` property
- Added `init(from config: GhostConfiguration, path: String, username: String?)`  initializer

### 3. GhostManager Integration (`Ourin/Ghost/GhostManager.swift`)

**Loading Configuration:**
- Added `ghostConfig: GhostConfiguration?` property
- Load configuration from `descript.txt` during `start()`
- Log configuration details for debugging

**Applying Configuration:**
- Added `applyGhostConfiguration(_:ghostRoot:)` method
- Applies homeurl to ResourceManager
- Applies default surface positions (sakura/kero/char*.defaultx/y)
- Applies display positions based on alignment settings
- Respects `seriko.alignmenttodesktop` when applying positions
- Stores positions in ResourceManager for persistence

### 4. Comprehensive Test Suite (`OurinTests/GhostConfigurationTests.swift`)

Created extensive tests covering:
- Basic parsing (required/optional fields)
- Surface configuration
- Position configuration (including alignments)
- Character-specific positions (char2, char3, etc.)
- SSTP configuration
- Balloon configuration
- UI configuration
- Behavior settings
- SHIORI configuration
- Installation configuration
- AI graph configuration
- Emily4 real-world test case
- Ghost struct integration

## Usage

### Automatic Loading

Configuration is automatically loaded when a ghost starts:

```swift
let ghostRoot = ghostURL.appendingPathComponent("ghost/master", isDirectory: true)
if let config = GhostConfiguration.load(from: ghostRoot) {
    self.ghostConfig = config
    applyGhostConfiguration(config, ghostRoot: ghostRoot)
}
```

### Manual Loading

```swift
// Load from a ghost directory
let config = GhostConfiguration.load(from: ghostRootURL)

// Parse from a dictionary
let dict = ["name": "MyGhost", "sakura.name": "Sakura"]
let config = GhostConfiguration.parse(from: dict)

// Create programmatically
let config = GhostConfiguration(
    name: "TestGhost",
    sakuraName: "Sakura",
    keroName: "Kero"
)
```

### Creating Ghost from Configuration

```swift
let ghost = Ghost(from: config, path: "/path/to/ghost")
```

## Configuration Priority

1. **Position Settings:**
   - `seriko.alignmenttodesktop` sets global default (top/bottom/free)
   - `sakura.seriko.alignmenttodesktop` overrides for sakura
   - `kero.seriko.alignmenttodesktop` overrides for kero
   - `char*.seriko.alignmenttodesktop` overrides for additional characters
   - Display positions (`defaultleft/top`) only apply when alignment is `free`

2. **Runtime vs descript.txt:**
   - Configuration values are loaded at startup
   - Runtime values from ResourceManager take precedence for user-modified settings
   - Configuration provides sensible defaults

## Supported Encoding

- UTF-8 (preferred)
- Shift_JIS/CP932 (fallback for compatibility)

## Example descript.txt

```
charset,Shift_JIS
type,ghost
name,Emily/Phase4.5
sakura.name,Emily
kero.name,Teddy
balloon,emily4
id,Emily/Phase4.5
char2.seriko.defaultsurface,200
name.allowoverride,0
craftmanurl,http://ssp.shillest.net/
craftman,[SSPBT/GL03B]Emily Development Team
sstp.allowunspecifiedsend,1
icon,icon.ico
shiori,yaya.dll
shiori.version,SHIORI/3.0
```

## Future Enhancements

Potential additions identified in the specification:

1. **MAKOTO Support:**
   - `makoto` DLL specification

2. **Advanced Position Control:**
   - Shell-specific position overrides
   - Runtime position persistence

3. **Cursor Management:**
   - Loading and applying custom cursor files
   - Scope-specific cursor settings

4. **Tooltip Configuration:**
   - `currentghost.seriko.tooltip.*` properties

5. **History Tracking:**
   - Most recently used ghosts/balloons/shells
   - Usage statistics

## References

- UKADOC descript.txt specification: https://ssp.shillest.net/ukadoc/manual/descript_ghost.html
- SSP Property System specification
- Ourin Property System documentation: `docs/PropertySystem.md`

## Files Modified

- **New:** `Ourin/Ghost/GhostConfiguration.swift`
- **New:** `OurinTests/GhostConfigurationTests.swift`
- **Modified:** `Ourin/Property/GhostPropertyProvider.swift`
- **Modified:** `Ourin/Ghost/GhostManager.swift`
- **Fixed:** `OurinTests/NarInstallTests.swift` (added missing Foundation import)
- **Fixed:** `OurinTests/ShioriLoaderTests.swift` (replaced deprecated `#fail` with `Issue.record`)

## Build Status

✅ Build successful
✅ All code compiles without errors
✅ Comprehensive test suite created (18 tests covering all configuration aspects)

## Technical Details

### Parsing Strategy

The implementation uses a two-phase parsing approach:

1. **File Reading:** Uses the existing `DescriptorLoader` pattern for encoding detection (UTF-8 first, then Shift_JIS fallback)

2. **Value Parsing:** `GhostConfiguration.parse(from:)` processes the dictionary:
   - Required fields validated (name must exist)
   - Optional fields with sensible defaults
   - Type conversion with safety (Int parsing, enum matching)
   - `char*` entries parsed via regex pattern matching

### Character Pattern Parsing

Additional characters (char2, char3, etc.) are parsed using regex:

```swift
let charPattern = "^char(\\d+)\\.(.+)$"
// Matches: char2.name, char3.defaultx, etc.
```

### Error Handling

- Returns `nil` if required fields are missing
- Gracefully handles invalid values (falls back to defaults)
- Logs warnings for malformed configuration
- Uses Swift optionals for non-critical fields

### Performance

- Parsing is done once at ghost startup
- Configuration is cached in memory
- No performance impact on runtime operations

## Integration with Existing Systems

- **PropertyManager:** Can use configuration values for property queries
- **ResourceManager:** Receives initial values from configuration, stores runtime changes
- **GhostPropertyProvider:** Can expose configuration via property system
- **SERIKO Engine:** Uses surface defaults from configuration
- **SSTP Server:** Respects SSTP permission settings
- **Balloon System:** Uses balloon preferences from configuration
