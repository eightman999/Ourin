# Ourin Dependencies Documentation

**Last Updated**: June 26, 2026  
**Version**: 1.1.0

---

## Overview

The Ourin project adopts a design with minimal dependencies. This document describes all dependencies, their purposes, and security considerations.

---

## Main Application (Swift/SwiftUI)

### External Dependencies

**None** - The Ourin main application has no external dependencies.

### System Frameworks

Ourin uses only Apple official frameworks:

| Framework | Version | Purpose |
|-----------|---------|---------|
| **Foundation** | macOS SDK | Basic data types, collections, filesystem access |
| **AppKit** | macOS SDK | macOS native UI (window management, menus, etc.) |
| **SwiftUI** | macOS SDK | Modern declarative UI |
| **OSLog** | macOS SDK | System logging and debug output |
| **UserNotifications** | macOS SDK | Notification functionality |
| **CoreImage** | macOS SDK | Image processing and filters |
| **Combine** | macOS SDK | Reactive programming and async handling |
| **Darwin** | macOS SDK | POSIX system calls (semaphores, shared memory, etc.) |
| **Network** | macOS SDK | Network communication (SSTP TCP server) |
| **UniformTypeIdentifiers** | macOS SDK | File type identification |
| **CoreGraphics** | macOS SDK | 2D graphics |
| **ImageIO** | macOS SDK | Image input/output |

**Security Status**: ✅ All frameworks are continuously maintained by Apple.

---

## DevTools Migrator (Optional)

### Ghidra

- **Version**: 11.x or later recommended (verified with 12.0.4 in development)
- **License**: Apache License 2.0
- **Copyright**: National Security Agency (NSA)
- **Purpose**: Decompilation and analysis of SSP-compatible Windows DLL/EXE (Migrator feature)
- **Integration**: External tool only - not bundled with Ourin
- **Security**: Downloaded and executed by user; Ourin does not execute untrusted binaries

**Links**:
- https://ghidra-sre.org/
- https://www.apache.org/licenses/LICENSE-2.0

---

## Build System (CMake)

### yaya_core (C++ YAYA Language VM)

#### Build Dependencies

| Library | Version | Purpose | License |
|---------|---------|---------|---------|
| **nlohmann/json** | 3.11.2 | JSON parsing for IPC between Swift and C++ | MIT |
| **libiconv** | System | Character encoding conversion (Shift_JIS → UTF-8) | LGPL |
| **CMake** | 3.20+ | Build system | BSD 3-Clause |

#### Build Script

Located at: `yaya_core/build.sh`

```bash
#!/bin/bash
cd yaya_core
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

**Requirements**:
- macOS 12.0+
- Xcode Command Line Tools
- CMake 3.20+
- C++17 compatible compiler

---

## Development Tools (Optional)

### Tools Used in Development Environment

| Tool | Version | Purpose | License |
|------|---------|---------|---------|
| **Xcode** | 14.0+ | Primary IDE | Proprietary |
| **Swift** | 5.7+ | Programming language | Apache License 2.0 |
| **Git** | 2.30+ | Version control | GPL v2 |

**Note**: These are development tools, not runtime dependencies.

---

## Runtime Dependencies Summary

### Always Required

✅ **macOS SDK Frameworks** - Automatically available on macOS 12.0+

### Optional

🟡 **Ghidra** - Only needed for DevTools Migrator feature
- Can be installed by user as needed
- Not bundled or auto-downloaded

🟡 **yaya_core** - Pre-built binaries included in app bundle
- C++ compilation required only if building from source
- Pre-built for macOS 12.0+

---

## Dependency Graph

```
Ourin (Main App)
├── Foundation
├── AppKit
├── SwiftUI
├── OSLog
├── UserNotifications
├── CoreImage
├── Combine
├── Darwin
├── Network
├── UniformTypeIdentifiers
├── CoreGraphics
├── ImageIO
├── ShioriHost (Internal)
├── GhostManager (Internal)
├── PluginHost (Internal)
├── ExternalServer (Internal)
│   ├── SstpTcpServer
│   ├── SstpHttpServer
│   └── XpcDirectServer
├── USL (Internal - SHIORI Loader)
├── SSTP (Internal)
├── Yaya (Internal - YAYA Adapter)
│   ├── yaya_core (C++ subprocess)
│   │   ├── nlohmann/json
│   │   └── libiconv
│   ├── SaoriHost
│   └── ShioriHost
├── SakuraScript (Internal)
├── SERIKO (Internal)
├── Property (Internal)
├── NarInstall (Internal)
└── DevTools (Internal)
    └── Migrator (uses external Ghidra)
```

---

## License Compliance

### Ourin License
- **CC BY-NC-SA 4.0** (Creative Commons Attribution-NonCommercial-ShareAlike 4.0)
- Repository: https://github.com/furin-lab/ourin

### Bundled Licenses

#### nlohmann/json
- **License**: MIT
- **Usage**: JSON serialization in yaya_core
- **Distribution**: Source included in `yaya_core/CMakeLists.txt`

#### libiconv
- **License**: LGPL
- **Usage**: Character encoding conversion (CP932 ↔ UTF-8)
- **Distribution**: System library, not bundled

#### Swift Runtime
- **License**: Apache License 2.0
- **Usage**: Swift standard library runtime
- **Distribution**: Part of macOS, not bundled

#### Ghidra (if used)
- **License**: Apache License 2.0
- **Usage**: Optional decompilation tool for DevTools Migrator
- **Distribution**: Downloaded by user, not bundled
- **Copyright**: National Security Agency

---

## Third-Party Notices

### Complete List of Notices

When distributing Ourin, include these notices:

```
This software includes components licensed under the following licenses:

1. nlohmann/json
   Copyright (c) 2013-2022 Niels Lohmann
   https://github.com/nlohmann/json
   License: MIT

2. Ghidra (optional, if used)
   Copyright (c) 2019 National Security Agency
   https://ghidra-sre.org/
   License: Apache License 2.0

3. Swift Runtime
   Copyright (c) 2014-2023 Apple Inc.
   License: Apache License 2.0
```

---

## Security Considerations

### Secure Coding Practices

1. **No External HTTP Dependencies**
   - No automatic downloads of third-party libraries
   - All dependencies are either bundled or system-provided

2. **Character Encoding Security**
   - CP932/UTF-8 conversion uses system libiconv
   - Input validation for ghost dictionaries

3. **Plugin Isolation**
   - Plugins run in separate XPC processes
   - No direct access to sensitive files

4. **File System Access**
   - Non-sandboxed but respects user permissions
   - Ghost data stored in standard user locations

5. **Network Security**
   - SSTP over TCP/HTTP (no custom protocol)
   - XPC for local inter-process communication

### Threat Model

| Threat | Mitigation |
|--------|-----------|
| Malicious ghost dictionary | Input validation, parser guards |
| Malicious plugin | XPC isolation, capability restrictions |
| Buffer overflow in yaya_core | Memory-safe Swift wrapper, bounds checking |
| Network sniffing | SSTP is application-level, users can use SSH tunnel |
| Supply chain attack | Minimal dependencies, most bundled or system-provided |

---

## Update Policy

### Swift/macOS Updates

The project targets macOS 12.0 LTS and later versions of Swift.

When macOS/Swift versions are updated:
1. Test with new version
2. Update version requirements if needed
3. Document breaking changes
4. Provide migration guide for users

### Dependency Updates

For bundled dependencies like nlohmann/json:
1. Monitor upstream for security updates
2. Test compatibility before updating
3. Document changes in CHANGELOG
4. Provide release notes to users

---

## Building Without External Dependencies

### Fully Offline Build

To build Ourin without downloading any external dependencies:

```bash
# All dependencies already in repository:
xcodebuild -project Ourin.xcodeproj -scheme Ourin build

# Or for yaya_core:
cd yaya_core
./build.sh  # Uses system CMake, nlohmann/json is local
```

**Note**: Ghidra must be installed separately if using DevTools Migrator.

---

## Performance Impact

### Dependency Impact on Performance

| Component | Impact | Notes |
|-----------|--------|-------|
| Swift Runtime | Negligible | Native compilation to machine code |
| Foundation | ~20MB | Part of macOS, shared across apps |
| AppKit/SwiftUI | ~50MB | Part of macOS, shared across apps |
| yaya_core | ~10MB | Compiled subprocess, efficient VM |
| Plugins | Variable | Optional, user-provided |

**Total Base Memory**: ~200MB (shared libraries included)  
**Ghost Runtime**: +50-100MB per active ghost

---

## Maintenance Schedule

| Item | Schedule | Responsibility |
|------|----------|-----------------|
| Swift Updates | Annually (macOS releases) | Maintainers |
| Dependency Security Checks | Quarterly | Maintainers |
| License Compliance Audit | Annually | Maintainers |
| Performance Profiling | Per release | QA Team |

---

## Related Documentation

- **Build Instructions**: See CLAUDE.md
- **License**: See LICENSE or LICENSE.txt in repo
- **Contributing**: See CONTRIBUTING.md
- **Security Policy**: See SECURITY.md

---

**Last Reviewed**: June 26, 2026  
**Review Cycle**: Annual  
**Maintainer**: Furin Lab Development Team
