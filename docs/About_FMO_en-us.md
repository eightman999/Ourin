# About the FMO Feature

This document explains the FMO (Forged Memory Object) implementation in Ourin.

## Overview

Ourin's FMO is **not** a full Windows FileMapping API compatibility layer. Instead, it provides **semantic compatibility** using POSIX shared memory. The goal is to let external tools query the list of running ghosts along with their names, paths, shells, balloons, and surfaces.

## Shared Memory Names

| Resource | Name |
|---|---|
| Shared memory | `/ourin_fmo` |
| Semaphore (mutex) | `/ourin_fmo_mutex` |

## FMO Record Format

An SSP-compatible format is used:

```
(id).(key)\x01(value)\r\n
```

- `\x01` is ASCII SOH (Start of Heading, U+0001)
- Line endings are CRLF (`\r\n`)
- `id` is a zero-based ghost index

### Fields

| Key | Description | Example |
|---|---|---|
| `name` | Ghost's sakura name | `Emily4` |
| `keroname` | Kero's name | `Teddy` |
| `path` | Ghost directory path | `/Users/.../ghost/emily4` |
| `shell` | Current shell name | `master` |
| `balloon` | Current balloon name | `default` |
| `sakura.surface` | Current sakura surface ID | `0` |
| `kero.surface` | Current kero surface ID | `10` |
| `hwnd` | Window handle (dummy value) | `0` |

### Example Output

```
0.name\x01Emily4\r\n
0.keroname\x01Teddy\r\n
0.path\x01/Users/user/Library/.../ghost/emily4\r\n
0.shell\x01master\r\n
0.balloon\x01default\r\n
0.sakura.surface\x010\r\n
0.kero.surface\x0110\r\n
0.hwnd\x010\r\n
```

## Differences from Windows

### hwnd is a Dummy Value
`hwnd` corresponds to a Windows window handle but has no meaning on macOS. It always returns `0`.

### Path Format
Paths use the native macOS format (POSIX paths), not Windows backslash separators or drive letter notation.

### Shared Memory Lifetime
- Windows: Named FileMapping is automatically deleted when all handles are closed.
- Ourin: POSIX shared memory retains its name while the process is alive. On normal shutdown, `shm_unlink` / `sem_unlink` are called to remove it.
- Shared memory left behind after a crash is safely overwritten on the next launch.

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

## Main Classes

### `FmoManager`
- Overall FMO management class
- `buildSnapshot(records:)`: Generates SSP-style record format string (static)
- `writeSnapshot(records:)`: Writes snapshot to shared memory
- `isAnotherInstanceRunning()`: Checks for another instance via shared memory existence
- `cleanup()`: Releases shared memory and semaphore on normal shutdown

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
