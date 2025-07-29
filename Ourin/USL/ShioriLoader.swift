import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Function pointer types for SHIORI C-ABI
private typealias ShioriLoad = @convention(c) (UnsafePointer<CChar>?) -> Bool
private typealias ShioriRequest = @convention(c) (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int>?) -> Bool
private typealias ShioriUnload = @convention(c) () -> Void
private typealias ShioriFree = @convention(c) (UnsafeMutablePointer<UInt8>?) -> Void

/// Dynamic loader for SHIORI modules following USL spec
public final class ShioriLoader {
    private var handle: UnsafeMutableRawPointer?
    private var loadFn: ShioriLoad?
    private var requestFn: ShioriRequest?
    private var unloadFn: ShioriUnload?
    private var freeFn: ShioriFree?

    /// Path of loaded module
    public let moduleURL: URL

    private init(url: URL) throws {
        guard let h = dlopen(url.path, RTLD_NOW) else {
            throw NSError(domain: "USL", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: dlerror())])
        }
        handle = h
        func loadSymbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let sym = dlsym(h, name) else { return nil }
            return unsafeBitCast(sym, to: type)
        }
        loadFn = loadSymbol("shiori_load", as: ShioriLoad.self)
        requestFn = loadSymbol("shiori_request", as: ShioriRequest.self)
        unloadFn = loadSymbol("shiori_unload", as: ShioriUnload.self)
        freeFn = loadSymbol("shiori_free", as: ShioriFree.self)
        self.moduleURL = url

        // call load if available
        if let l = loadFn {
            _ = l(url.deletingLastPathComponent().path)
        }
    }

    deinit { unload() }

    /// Attempt to load module by name searching typical USL paths
    public convenience init?(module name: String, base: URL) {
        let paths = ShioriLoader.searchPaths(base: base)
        guard let url = ShioriLoader.find(name: name, in: paths) else { return nil }
        do { try self.init(url: url) } catch { return nil }
    }

    /// Send SHIORI request and return raw response string
    public func request(_ text: String) -> String? {
        guard let req = requestFn else { return nil }
        let bytes = Array(text.utf8)
        var outPtr: UnsafeMutablePointer<UInt8>? = nil
        var outLen: Int = 0
        let ok = bytes.withUnsafeBytes {
            req($0.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count, &outPtr, &outLen)
        }
        guard ok, let p = outPtr else { return nil }
        let data = Data(bytes: p, count: outLen)
        freeFn?(p)
        return String(data: data, encoding: .utf8)
    }

    /// Unload module if loaded
    public func unload() {
        if let u = unloadFn { u() }
        if let h = handle { dlclose(h); handle = nil }
    }
}

// MARK: - Search path & name normalization helpers
extension ShioriLoader {
    /// Default search paths defined by USL spec
    static func searchPaths(base: URL) -> [URL] {
        var arr: [URL] = []
        arr.append(base.appendingPathComponent("ghost/master"))
        arr.append(base.appendingPathComponent("ghost/master/modules"))
        if let bundle = Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent() {
            arr.append(bundle.appendingPathComponent("Frameworks"))
        }
        return arr
    }

    /// Try to locate module in given search paths
    static func find(name: String, in paths: [URL]) -> URL? {
        let variants = normalizedNames(for: name)
        let fm = FileManager.default
        for dir in paths {
            for v in variants {
                let url = dir.appendingPathComponent(v)
                if fm.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    /// Generate possible file names according to USL name normalization
    static func normalizedNames(for name: String) -> [String] {
        let base = (name as NSString).lastPathComponent
        var stem = base
        var list: [String] = [base]
        if base.hasSuffix(".dll") {
            stem = String(base.dropLast(4))
        } else if let dot = base.lastIndex(of: ".") {
            stem = String(base[..<dot])
        }
        list.append("\(stem).dylib")
        list.append("lib\(stem).dylib")
        list.append("\(stem).bundle")
        list.append("\(stem).plugin")
        list.append("\(stem).so")
        list.append("lib\(stem).so")
        return Array(NSOrderedSet(array: list)) as! [String]
    }
}
