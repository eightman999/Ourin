import Foundation

// Function pointer types for PLUGIN/2.0M
public typealias PluginRequestFn = @convention(c) (UnsafePointer<UInt8>, Int, UnsafeMutablePointer<Int>) -> UnsafePointer<UInt8>?
public typealias PluginLoadFn = @convention(c) (UnsafePointer<CChar>) -> Int32
public typealias PluginUnloadFn = @convention(c) () -> Void

/// Single plugin bundle wrapper
public struct Plugin {
    let bundle: Bundle
    let request: PluginRequestFn
    let load: PluginLoadFn?
    let unload: PluginUnloadFn?

    public init(url: URL) throws {
        guard let bundle = Bundle(url: url) else {
            throw NSError(domain: "Plugin", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid bundle"])
        }
        self.bundle = bundle
        // force load image
        _ = bundle.principalClass
        func sym<T>(_ name: String) -> T? {
            let fp = CFBundleGetFunctionPointerForName(bundle._cfBundle, name as CFString)
            guard fp != nil else { return nil }
            return unsafeBitCast(fp, to: Optional<T>.self)
        }
        guard let req: PluginRequestFn = sym("request") else {
            throw NSError(domain: "Plugin", code: -2, userInfo: [NSLocalizedDescriptionKey: "request not found"])
        }
        self.request = req
        self.load = sym("load")
        self.unload = sym("unload")
    }

    /// Send raw wire text to plugin and return response string (UTF-8)
    public func send(_ text: String) -> String {
        var outLen: Int = 0
        var bytes = Array(text.utf8)
        let respPtr = bytes.withUnsafeMutableBytes { raw -> UnsafePointer<UInt8>? in
            return request(raw.bindMemory(to: UInt8.self).baseAddress!, bytes.count, &outLen)
        }
        guard let p = respPtr else { return "" }
        let buf = UnsafeBufferPointer(start: p, count: outLen)
        return String(decoding: buf, as: UTF8.self)
    }
}

private extension Bundle {
    var _cfBundle: CFBundle {
        CFBundleGetBundleWithIdentifier(self.bundleIdentifier! as CFString)!
    }
}
