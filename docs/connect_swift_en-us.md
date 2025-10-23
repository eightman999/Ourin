# Procedure for Handling Swift-based Plugins from yaya_core

This document outlines the procedure for loading macOS native Swift plugins (`.plugin` / `.bundle`) from `yaya_core` (a C++ helper executable) and handling SHIORI/PLUGIN protocol interactions. All content assumes UTF-8 as the default, and descriptions are standardized in English.

## 1. Overview

1.  Prepare a loadable bundle in Swift that complies with the PLUGIN/2.0M specification.
2.  Place the bundle in a default directory, such as `Ourin.app/Contents/PlugIns/`.
3.  `yaya_core` loads the plugin via the CFBundle API and calls `load`, `request`, and `unload`.
4.  The wire string returned by the PLUGIN is parsed by `yaya_core` and returned to the Swift layer as a JSON IPC response.

Although Swift plugins are implemented in Swift code, they are exported with a C ABI, allowing them to be called transparently from `yaya_core` (C++).

## 2. Swift Plugin Requirements

### 2.1 Target Settings

-   In Xcode, select **Bundle (Mach-O Type: Bundle)** and set the output extension to `.plugin`.
-   **Architectures:** Enable `arm64` / `x86_64` (Universal 2).
-   **Deployment Target:** macOS 10.15 or later.

### 2.2 Exported Functions

Expose C ABI functions from Swift code using `@_cdecl`.

```swift
@_cdecl("load")
public func pluginLoad(_ pluginDir: UnsafePointer<CChar>) -> Int32 {
    // Initialization process (e.g., parsing the bundle path if necessary)
    return 0
}

@_cdecl("request")
public func pluginRequest(_ bytes: UnsafePointer<UInt8>, _ length: Int, _ outLength: UnsafeMutablePointer<Int>) -> UnsafePointer<UInt8>? {
    let data = Data(bytes: bytes, count: length)
    guard let response = handleWire(String(decoding: data, as: UTF8.self)) else {
        outLength.pointee = 0
        return nil
    }
    let utf8 = Array(response.utf8)
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: utf8.count)
    _ = buffer.initialize(from: utf8, count: utf8.count)
    outLength.pointee = utf8.count
    return UnsafePointer(buffer)
}

@_cdecl("unload")
public func pluginUnload() {
    // Cleanup
}
@_cdecl("plugin_free")
public func pluginFree(_ pointer: UnsafeMutablePointer<UInt8>?) {
    pointer?.deallocate()
}
```

> **Note:** Lifecycle management of the buffer returned from `request` is critical. If you return a copy, also expose `plugin_free` so that `yaya_core` can deallocate it.

## 3. Plugin Placement

-   It is recommended to place the plugin in `Contents/PlugIns/` within the `Ourin.app` bundle.
-   The plugin bundle must contain at least `Contents/Info.plist`, `Contents/MacOS/<Executable>`, and `Contents/Resources/descript.txt`.
-   In `descript.txt`, specify the `filename` as `.plugin` and using UTF-8 encoding is recommended.

## 4. Loading Process in yaya_core

Link CoreFoundation in C++17 or later and use the `CFBundle` API. The following is a conceptual code snippet.

```cpp
#include <CoreFoundation/CoreFoundation.h>

struct PluginHandle {
    CFBundleRef bundle;
    using LoadFn = int32_t(*)(const char*);
    using RequestFn = const unsigned char*(*)(const unsigned char*, size_t, size_t*);
    using UnloadFn = void(*)();

    LoadFn load = nullptr;
    RequestFn request = nullptr;
    UnloadFn unload = nullptr;
};

PluginHandle loadPlugin(const std::string& path) {
    PluginHandle handle{};
    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, CFStringCreateWithCString(nullptr, path.c_str(), kCFStringEncodingUTF8), kCFURLPOSIXPathStyle, true);
    handle.bundle = CFBundleCreate(kCFAllocatorDefault, url);
    CFRelease(url);
    if (!handle.bundle || !CFBundleLoadExecutable(handle.bundle)) {
        throw std::runtime_error("Failed to load plugin bundle");
    }
    handle.request = reinterpret_cast<PluginHandle::RequestFn>(CFBundleGetFunctionPointerForName(handle.bundle, CFSTR("request")));
    handle.load = reinterpret_cast<PluginHandle::LoadFn>(CFBundleGetFunctionPointerForName(handle.bundle, CFSTR("load")));
    handle.unload = reinterpret_cast<PluginHandle::UnloadFn>(CFBundleGetFunctionPointerForName(handle.bundle, CFSTR("unload")));
    if (!handle.request) {
        throw std::runtime_error("request symbol missing");
    }
    return handle;
}
```

### 4.1 Lifecycle

1.  If `load()` exists, initialize it by passing the bundle directory (UTF-8 path).
2.  In `request()`, pass the wire string (terminated by CRLF + blank line) as a UTF-8 byte sequence.
3.  If `unload()` exists, be sure to call it during the termination process.
4.  Deallocate the bundle with `CFBundleUnloadExecutable` and `CFRelease`.

## 5. Wire ↔ JSON Conversion

-   Communication with the plugin is via a **PLUGIN/2.0M** wire string.
-   `yaya_core` receives this, extracts `status` and `Value` at the SHIORI layer, and maps them to the JSON IPC format.
-   Example: If a Swift plugin returns `PLUGIN/2.0M 200 OK`, `yaya_core` converts it to `{ "ok": true, "status": 200, ... }`.

## 6. Error Handling and Debugging

-   If symbol retrieval fails, unload immediately and return an error via JSON IPC.
-   If the return value of `request()` is `nullptr`, treat it as an error equivalent to `500`.
-   You can check the loading status with `DYLD_PRINT_LIBRARIES` or `CFBundleCopyBundleURL` in Xcode.
-   Logs should be output in JSON format and cross-referenced between the Swift side and the `yaya_core` side.

## 7. Multi-Architecture Support

-   Build both the plugin and `yaya_core` as Universal 2 to avoid inconsistencies when running under Rosetta.
-   Check the architecture with `lipo -info MyPlugin.plugin/Contents/MacOS/MyPlugin`.

## 8. Testing Strategy

1.  **Unit Tests:** Verify the input/output of `request()` on the Swift plugin side with XCTest.
2.  **Integration Tests:** Prepare a script to actually load from `yaya_core` and verify the response via JSON IPC.
3.  **Long-run:** Continuously load/unload the plugin and monitor for memory leaks with Instruments.

---

The above are the steps for safely handling Swift-based plugins from `yaya_core`. During implementation, please also refer to the specifications in `SPEC_PLUGIN_2.0M.md` and `OURIN_YAYA_ADAPTER_SPEC_1.0M.md` to ensure consistency with the wire specification and IPC.
