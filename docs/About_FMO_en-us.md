# About the FMO Feature

This document explains the implementation policy for reproducing FMO (Forged Memory Object), used in Windows games and ghosts, on macOS.

## Objective
- Share a 64KB data area between processes using named shared memory.
- Perform exclusive control using named semaphores.
- Implement a launch check compliant with the ninix specification.

## ninix Specification Compliance

This implementation complies with the FMO specification of ninix/ninix-kagari.

### Launch Check Method
In a POSIX environment, it is determined whether another baseware is running by checking if `shm_open('/ninix', O_RDWR, 0)` succeeds.

- Success → Another baseware is already running.
- Failure (errno == ENOENT) → Not running.
- Other errors → Insufficient permissions, etc.

### Resource Names to Use
For compatibility with ninix, the following names are used:

- Shared memory name: `/ninix`
- Semaphore name: `/ninix_mutex`

### FMO Content
Data is stored in the shared memory with the following structure:

```c
struct shm_t {
    uint32_t size;      // Data size (first 4 bytes)
    sem_t sem;          // Semaphore (POSIX environment)
    char buf[PATH_MAX]; // Path to the directory containing the UNIX socket
};
```

In ninix, the FMO does not hold the baseware's information itself, but rather the directory path where the UNIX socket for retrieving the baseware's information is located. The path ends with a `/` (e.g., `/home/user/.ninix/sock/`).

## Main Classes

### `FmoMutex`
- A Mutex class that wraps a named semaphore.
- Performs exclusive control with `lock()` and `unlock()`.
- The `createNew` parameter allows switching between new creation mode and existing open mode.
- Only the creator executes `sem_unlink` during `cleanup()`.

### `FmoSharedMemory`
- A wrapper for handling POSIX shared memory from Swift.
- Adopts an ephemeral operation where `shm_unlink` is called after `shm_open`, and the memory is automatically deleted on the final close.
- Writes the data size in the first 4 bytes and a NUL terminator at the end.
- The `createNew` parameter allows switching between new creation mode and existing open mode.
- Only the creator executes `shm_unlink` during `cleanup()` (however, in ephemeral mode, it is already unlinked immediately after creation).

### `FmoManager`
- Initializes the above two together and is used at application launch.
- The `isAnotherInstanceRunning()` static method allows checking if another baseware is running.

## Usage Example

### Launch Check and Initialization
```swift
// 1. First, check if another baseware is running
if FmoManager.isAnotherInstanceRunning(sharedName: "/ninix") {
    NSLog("Another baseware instance is already running")
    exit(1)
}

// 2. If not running, create FMO resources
do {
    let manager = try FmoManager(mutexName: "/ninix_mutex", sharedName: "/ninix")
    // Use...
} catch {
    NSLog("FMO initialization failed: \(error)")
}
```

### Reading and Writing Data
```swift
try manager.memory.write(data, mutex: manager.mutex)
let received = try manager.memory.read(mutex: manager.mutex)
```

### Cleanup
When the application terminates, call `cleanup()` to release the shared memory and semaphore:

```swift
manager.cleanup()
```

## Implementation Flow

1.  **Launch Check**: Check for the existence of other instances with `FmoManager.isAnotherInstanceRunning()`.
2.  **FMO Creation**: If no other instance exists, initialize with `FmoManager(mutexName:sharedName:)`.
3.  **Data Sharing**: Read and write data to shared memory while protecting it with a mutex.
4.  **Cleanup**: Release resources with `cleanup()` on exit.

## Error Handling

- `FmoError.alreadyRunning`: The semaphore or shared memory already exists (another instance is running).
- `FmoError.systemError(String)`: System error (insufficient permissions, lack of resources, etc.).

By performing the launch check first, unnecessary `alreadyRunning` errors can be avoided.

## Technical Details

### C Bridge Functions
The following bridge functions are implemented (`FmoBridge.c/h`) to call POSIX APIs from Swift:

#### Shared Memory Operations
- `fmo_open_shared()`: Create new shared memory.
- `fmo_open_existing_shared()`: Open existing shared memory.
- `fmo_map()`: Memory mapping.
- `fmo_munmap()`: Unmap memory.
- `fmo_shm_unlink()`: Delete shared memory.

#### Semaphore Operations
- `fmo_sem_open()`: Open/create a semaphore.
- `fmo_sem_wait()`: Acquire a lock.
- `fmo_sem_post()`: Release a lock.
- `fmo_sem_close()`: Close a semaphore.
- `fmo_sem_unlink()`: Delete a semaphore.

#### Launch Check
- `fmo_check_running()`: Launch check based on the ninix specification.
  - Attempts to open existing shared memory with `shm_open(name, O_RDWR, 0)`.
  - Return value: 1=running, 0=not running, -1=error.

### Notes

- **32/64bit Incompatibility**: FMO cannot be exchanged between 32-bit and 64-bit processes.
- **Permissions**: Access to shared memory and semaphores may be restricted in a sandboxed environment.
- **Resource Names**: `/ninix` and `/ninix_mutex` are used for ninix compatibility, but can be changed if necessary.
- **Ephemeral Operation**: The shared memory is unlinked immediately after creation (`shm_unlink`) and is automatically deleted when all processes close it.

## Implementation Status

**Last Updated:** 2025-10-20

### Implementation in Ourin

- [x] **Fully Implemented**: The FMO system is fully implemented and verified.
- [x] **Launch Check**: ninix specification compliant launch check using `FmoManager.isAnotherInstanceRunning()`.
- [x] **Shared Memory Management**: Management of POSIX shared memory by `FmoSharedMemory`.
- [x] **Exclusive Control**: Implementation of named semaphores with `FmoMutex`.
- [x] **C Bridge**: A set of bridge functions for the POSIX API (`FmoBridge.c/h`).
- [x] **Ephemeral Operation**: Automatic deletion feature for shared memory.
- [x] **Error Handling**: Appropriate error handling with `FmoError`.

### Implemented Features

1.  **POSIX Shared Memory**
    -   Creation/opening of shared memory with `shm_open()`.
    -   Memory mapping with `mmap()`.
    -   Automatic deletion with `shm_unlink()`.

2.  **Named Semaphores**
    -   Creation/opening of semaphores with `sem_open()`.
    -   Exclusive control with `sem_wait()`/`sem_post()`.
    -   Deletion with `sem_unlink()`.

3.  **ninix Compatible Launch Check**
    -   Existence check for `/ninix` shared memory.
    -   Attempt to open existing memory in `O_RDWR` mode.
    -   Error determination based on errno.

4.  **Swift Interface**
    -   `FmoManager`: Overall management class.
    -   `FmoSharedMemory`: Shared memory wrapper.
    -   `FmoMutex`: Semaphore wrapper.
    -   `FmoError`: Error type definition.

### Implementation Files

- `Ourin/FMO/FmoManager.swift`: FMO management class
- `Ourin/FMO/FmoSharedMemory.swift`: Shared memory wrapper
- `Ourin/FMO/FmoMutex.swift`: Mutex wrapper
- `Ourin/FMO/FmoError.swift`: Error definition
- `Ourin/FMO/FmoBridge.c`: C bridge implementation
- `Ourin/FMO/FmoBridge.h`: C bridge header

### Operation Check

- ✅ Single instance launch control
- ✅ Error detection when launching multiple instances
- ✅ Reading from and writing to shared memory
- ✅ Exclusive control with semaphores
- ✅ Resource release on process termination
