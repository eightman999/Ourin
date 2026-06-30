# Property System Implementation

## Overview

The Property System allows ghost scripts to read and write baseware parameters at runtime, following the ukagaka property system specification. This provides a standardized way for ghosts to access system information, baseware details, and runtime data.

## Architecture

### Core Components

1. **PropertyProvider Protocol** (`PropertyProvider.swift`)
   - Base protocol for all property providers
   - Supports `get(key:)` for reading properties
   - Supports `set(key:value:)` for writing properties (optional)

2. **PropertyManager** (`PropertyManager.swift`)
   - Central manager that coordinates all property providers
   - Routes property requests to appropriate providers based on prefix
   - Supports `%property[...]` environment variable expansion

### Property Providers

#### SystemPropertyProvider
Provides `system.*` properties:
- Date/time: `system.year`, `system.month`, `system.day`, `system.hour`, `system.minute`, `system.second`, `system.millisecond`, `system.dayofweek`
- Cursor: `system.cursor.pos`
- OS information: `system.os.type`, `system.os.name`, `system.os.version`, `system.os.build`
- CPU information: `system.cpu.num`, `system.cpu.vendor`, `system.cpu.name`, `system.cpu.clock`, `system.cpu.features`, `system.cpu.load`
- Memory information: `system.memory.phyt`, `system.memory.phya`, `system.memory.load`

#### BasewarePropertyProvider
Provides `baseware.*` properties:
- `baseware.name` - Returns "Ourin"
- `baseware.version` - Returns application version

#### GhostPropertyProvider
Provides ghost-related properties for `ghostlist.*`, `activeghostlist.*`, and `currentghost.*`:

**Common Properties:**
- `name`, `sakuraname`, `keroname`
- `craftmanw`, `craftmanurl`
- `path`, `icon`, `homeurl`
- `username`

**ghostlist:**
- `ghostlist.count` - Number of installed ghosts
- `ghostlist.index(n).{property}` - Access ghost by index
- `ghostlist({name|sakuraname|path}).{property}` - Access ghost by identifier

**currentghost:**
- Basic properties as above
- `currentghost.status` - Ghost status
- `currentghost.shelllist.count` - Number of shells
- `currentghost.shelllist.current.{property}` - Current shell properties
- `currentghost.shelllist({name|path}).{property}` - Shell by identifier
- `currentghost.shelllist.index(n).{property}` - Shell by index
- `currentghost.scope.count` - Number of scopes
- `currentghost.scope(n).surface.num` - Surface number for scope
- `currentghost.scope(n).{x|y|rect|name}` - Scope position and info

**Shell Properties:**
- `name`, `path`, `menu` (hidden/empty)

**Scope Properties:**
- `surface.num`, `surface.x`, `surface.y`
- `x`, `y`, `rect`
- `name`, `seriko.defaultsurface`

#### BalloonPropertyProvider
Provides balloon-related properties:

**balloonlist:**
- `balloonlist.count`
- `balloonlist.index(n).{name|path|craftmanw|craftmanurl}`
- `balloonlist({name|path}).{property}`

**currentghost.balloon:**
- `balloon.scope(n).count` - Balloon image count
- `balloon.scope(n).num` - Balloon ID
- `balloon.scope(n).validwidth` - Text drawing width
- `balloon.scope(n).validheight` - Text drawing height
- `balloon.scope(n).lines` - Maximum lines
- `balloon.scope(n).basepos.{x|y}` - Text start position
- `balloon.scope(n).char_width` - Character width

#### HeadlinePropertyProvider
Provides `headlinelist.*` properties:
- `headlinelist.count`
- `headlinelist.index(n).{name|path|craftmanw|craftmanurl}`
- `headlinelist({name|path}).{property}`

#### AliasPropertyProvider
Registered four times under the standard SSP-compatible shorthand namespaces
(`registerDefaultProviders` in `PropertyManager.swift`):

| Registered prefix | Delegation target prefix |
|---|---|
| `sakura` | `currentghost.scope(0)` |
| `kero` | `currentghost.scope(1)` |
| `ghost` | `currentghost` |
| `shell` | `currentghost.shelllist.current` |

When `get(key:)` or `set(key:value:)` is called, the provider prepends the delegation target prefix
to the sub-key and re-dispatches to `PropertyManager.shared.get/set`. For example,
`sakura.surface.num` becomes `currentghost.scope(0).surface.num` before lookup.
Both GET and SET delegate to the existing providers; alias registration does not add any
independently stored state.

#### PluginPropertyProvider
Provides `pluginlist.*` properties:
- `pluginlist.count`
- `pluginlist.index(n).{name|path|id|craftmanw|craftmanurl|filename|native|executablepath|packagepath|executionstate|candispatchrequests}`
- `pluginlist({name|path|id|executablepath|packagepath}).{property}`
- `pluginlist({name|path|id|executablepath|packagepath}).message.<key>` - localized text loaded from a plugin package `message.*.txt` file, for example `message.menu.title`

`path` is the SSP-compatible original module path, `executablepath` is the macOS native `.plugin` / `.bundle` body,
and `packagepath` is the package directory containing `install.txt`. Windows DLL-derived plugins are listed as
`executionstate=metadataOnly` and `candispatchrequests=0`.

## Usage

### Environment Variable Expansion

In SakuraScript text, use `%property[key]` to embed property values:

```
%property[baseware.name] ver,%property[baseware.version]
```

This will be expanded to:
```
Ourin ver,1.0
```

### SakuraScript Tags

#### Get Property

Retrieve a property value and trigger a SHIORI event with the value:

```
\![get,property,EventName,PropertyKey]
```

Example:
```
\![get,property,OnGetSakuraName,ghostlist(Emily/Phase4.5).keroname]
```

This will trigger the `OnGetSakuraName` event with `Reference0` containing the value "Teddy".

#### Set Property

Set a writable property value:

```
\![set,property,PropertyKey,Value]
```

Example:
```
\![set,property,currentghost.shelllist(ULTIMATE FORM).menu,hidden]
```

This hides the "ULTIMATE FORM" shell from the shell change menu.

### Programmatic Access

```swift
let manager = PropertyManager()

// Get property
if let year = manager.get("system.year") {
    print("Current year: \(year)")
}

// Set property
manager.set("currentghost.shelllist(Default).menu", value: "hidden")

// Expand text with properties
let text = "Welcome to %property[baseware.name]!"
let expanded = manager.expand(text: text)
```

## Writable Properties

Currently, the following properties support write operations:

1. `currentghost.shelllist({name}).menu` - Set to "hidden" to hide shell from menu

The alias namespaces `sakura.*`, `kero.*`, `ghost.*`, and `shell.*` can also be used on
the left-hand side of a SET command. They expand to the same delegation target as for GET;
the SET succeeds or fails according to whether the resolved full key is writable.
`AliasPropertyProvider.writableProperties()` returns `[]`, so aliases do not appear in
the writable key enumeration.

## Integration Points

### GhostManager
The `GhostManager` class handles property-related SakuraScript commands:
- `\![get,property,...]` at line 408
- `\![set,property,...]` at line 421

### SakuraScriptEngine
The `SakuraScriptEngine` integrates with `PropertyManager`:
- Provides `propertyManager` property for property access
- Delegates to `EnvironmentExpander` for `%property[...]` expansion

### EnvironmentExpander
Handles `%property[key]` expansion in text:
- Line 109-111 in `EnvironmentExpander.swift`
- Delegates to `PropertyManager.get()`

## Testing

Comprehensive tests are provided in `PropertySystemTests.swift`:
- System properties (date/time, OS info)
- Baseware properties
- Ghost properties (ghostlist, currentghost)
- Property expansion
- Balloon, headline, and plugin properties
- SET functionality

Run tests with:
```bash
xcodebuild test -project Ourin.xcodeproj -scheme Ourin
```

## Future Enhancements

Potential additions for complete specification compliance:

1. **History Properties** (`history.*`)
   - `history.ghost.*`, `history.balloon.*`, etc.
   - Most recently used items tracking

2. **Rate of Use** (`rateofuselist.*`)
   - Ghost usage statistics
   - Boot time tracking
   - Usage percentage calculation

3. **Additional Writable Properties**
   - Mouse cursor customization (`currentghost.mousecursor.*`)
   - Tooltip customization (`currentghost.seriko.tooltip.*`)
   - Surface list properties (`currentghost.seriko.surfacelist.*`)

4. **Dynamic Data Integration**
   - Connect to actual runtime ghost/shell/balloon data
   - Real-time scope position tracking
   - Live balloon metrics

## References

- UKADOC Property System Specification: https://usada.sakura.vg/contents/specification.html
- SSP Property Implementation
- CROW Property Test Cases
