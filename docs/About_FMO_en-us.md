# About the FMO Feature

This document explains the FMO (Forged Memory Object) implementation in Ourin.

## Overview

Ourin's FMO is **not** a full Windows FileMapping API compatibility layer. Instead, it provides **semantic compatibility** using POSIX shared memory. The goal is to let external tools query the list of running ghosts along with their names, paths, and surfaces. Binary/OS API compatibility with Windows tools that read FMO through Win32 APIs is out of scope. The compatibility boundary Ourin guarantees is `EXECUTE GetFMO` and the `id.key\x01value\r\n` text view.

## Shared Memory Names

| Resource | Name |
|---|---|
| Shared memory | `/ourin_fmo` |
| Semaphore (mutex) | `/ourin_fmo_mutex` |

## FMO Record Format

An SSP-compatible format is used:

```
id.key\x01value\r\n
```

- `\x01` is ASCII SOH (Start of Heading, U+0001)
- Line endings are CRLF (`\r\n`)
- `id` is a unique 32-character identifier generated when the ghost starts (also accepted for Owned SSTP matching)

### Fields

| Key | Description | Example |
|---|---|---|
| `name` | Ghost's sakura name | `Emily4` |
| `keroname` | Kero's name | `Teddy` |
| `fullname` | Full ghost name from descript metadata | `Emily/Phase4` |
| `ghostname` | Ghost name from descript/directory metadata | `emily4` |
| `path` | Ghost directory path | `/Users/.../ghost/emily4` |
| `ghostpath` | Ghost installation path | `/Users/.../ghost/emily4` |
| `sakura.surface` | Current sakura surface ID | `0` |
| `kero.surface` | Current kero surface ID | `10` |
| `hwnd` | Ourin window identifier for sakura | `1001` |
| `kerohwnd` | Ourin window identifier for kero | `1002` |
| `hwndlist` | Comma-separated window identifiers for this ghost | `1001,1002` |
| `modulestate` | Comma-separated module names and health states | `shiori:running,makoto-ghost:running` |
| `shell` | Current shell name (Ourin extension) | `master` |
| `balloon` | Current balloon name (Ourin extension) | `default` |

### Example Output

```
0123456789abcdef0123456789abcdef.name\x01Emily4\r\n
0123456789abcdef0123456789abcdef.keroname\x01Teddy\r\n
0123456789abcdef0123456789abcdef.fullname\x01Emily/Phase4\r\n
0123456789abcdef0123456789abcdef.ghostname\x01emily4\r\n
0123456789abcdef0123456789abcdef.path\x01/Users/user/Library/.../ghost/emily4\r\n
0123456789abcdef0123456789abcdef.ghostpath\x01/Users/user/Library/.../ghost/emily4\r\n
0123456789abcdef0123456789abcdef.sakura.surface\x010\r\n
0123456789abcdef0123456789abcdef.kero.surface\x0110\r\n
0123456789abcdef0123456789abcdef.hwnd\x011001\r\n
0123456789abcdef0123456789abcdef.kerohwnd\x011002\r\n
0123456789abcdef0123456789abcdef.hwndlist\x011001,1002\r\n
0123456789abcdef0123456789abcdef.modulestate\x01shiori:running,makoto-ghost:running\r\n
0123456789abcdef0123456789abcdef.shell\x01master\r\n
0123456789abcdef0123456789abcdef.balloon\x01default\r\n
```

## macOS-Specific Constraints and Differences from Windows

### FileMapping Names Are Not Compatible
Ourin does not expose the exact named FileMapping objects used by Windows/SSP. On macOS it uses POSIX shared memory `/ourin_fmo` and semaphore `/ourin_fmo_mutex`. Windows external tools cannot read this FMO directly through Win32 APIs.

### hwnd is Not a Win32 HWND
`hwnd`, `kerohwnd`, and `hwndlist` are not Windows window handles. Ourin prefers `NSWindow.windowNumber`; when that is unavailable, it generates a stable non-zero hash from the ghost/scope. These values are for identification and SSTP target resolution inside the running Ourin process and cannot be dereferenced as Win32 HWND values.

### Path Format
Paths use the native macOS format (POSIX paths), not Windows backslash separators or drive letter notation.

### Shared Memory Lifetime
- Windows: Named FileMapping is automatically deleted when all handles are closed.
- Ourin: POSIX shared memory retains its name while the process is alive. On normal shutdown, `shm_unlink` / `sem_unlink` are called to remove it.
- Shared memory left behind after a crash is safely overwritten on the next launch.

## Compatibility Views

### FMO Text View
`FmoManager.buildSnapshot(records:)` generates SSP-style `id.key\x01value\r\n` text. SSTP `EXECUTE GetFMO` and the POSIX shared memory payload both use this same text view.

### Structured View
`FmoCompatibilityView.parse(_:)` and `FmoManager.buildCompatibilityView(records:)` expose the same text as field dictionaries grouped by `id`. Tests, diagnostic UI, and macOS bridge code should use this view rather than depending on POSIX shared memory details or Windows APIs.

### POSIX Shared Memory View
In shared memory, the first 4 bytes contain a `uint32_t` UTF-8 payload length, followed by the FMO text and a trailing NUL byte. This is an Ourin macOS implementation detail, not the Windows FMO memory object format itself.

## Accessing FMO from External Apps

### Recommended: SSTP EXECUTE GetFMO
For macOS external apps, using the `GetFMO` command via the SSTP protocol is recommended.
It is safer than direct shared memory access and enforces security level checks (`local` only).

```
EXECUTE SSTP/1.4
Sender: MyApp
Command: GetFMO
SecurityLevel: local
Charset: UTF-8

```

### Direct Access: POSIX Shared Memory
Open the shared memory with `shm_open("/ourin_fmo", O_RDWR, 0)`, read the first 4 bytes as a `uint32_t` for the data size, then read the FMO records as UTF-8 text. Use the `/ourin_fmo_mutex` semaphore for mutual exclusion.

## Update Timing

The FMO is updated at the following events:

- Ghost startup (after OnBoot completes)
- Ghost shutdown
- Shell change (OnShellChanged)
- Balloon change (OnBalloonChange)
- Surface change (OnSurfaceChange)
- Explicit SHIORI / MAKOTO load, unload, and reload

## Main Classes

### `FmoManager`
- Overall FMO management class
- `buildSnapshot(records:)`: Generates SSP-style record format string (static)
- `buildCompatibilityView(records:)`: Generates a structured compatibility view from the same records (static)
- `writeSnapshot(records:)`: Writes snapshot to shared memory
- `isAnotherInstanceRunning()`: Checks for another instance via shared memory existence
- `cleanup()`: Releases shared memory and semaphore on normal shutdown

### `FmoCompatibilityView`
- Parses `id.key\x01value\r\n` FMO text into `fields` grouped by `id`
- Ignores malformed lines and returns entries sorted by `id`

### `FmoSharedMemory`
- POSIX shared memory wrapper
- Retains the shared memory name while the process is alive (no immediate unlink after creation)
- Writes data size in the first 4 bytes and a NUL terminator at the end
- Stale shared memory from crashes is safely overwritten via `O_CREAT`

### `FmoMutex`
- Named semaphore wrapper
- Stale semaphores from crashes are automatically `sem_unlink`-ed and recreated

### `FmoBridge.c / .h`
- C wrapper functions for calling POSIX APIs from Swift

## Implementation Files

- `Ourin/FMO/FmoManager.swift`: FMO management class and snapshot generation
- `Ourin/FMO/FmoSharedMemory.swift`: Shared memory wrapper
- `Ourin/FMO/FmoMutex.swift`: Mutex wrapper
- `Ourin/FMO/FmoError.swift`: Error definition
- `Ourin/FMO/FmoBridge.c`: C bridge implementation
- `Ourin/FMO/FmoBridge.h`: C bridge header
