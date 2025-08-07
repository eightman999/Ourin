import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

// MARK: - Backend Protocol
/// Common interface for different SHIORI backends.
protocol ShioriBackend {
    func request(_ text: String) -> String?
    func unload()
}

// MARK: - YAYA Backend
/// Backend for YAYA ghosts, communicating with a helper process.
final class YayaBackend: ShioriBackend {
    private let yayaAdapter: YayaAdapter

    init?(ghostURL: URL, descript: [String:String]) {
        let descriptURL = ghostURL.appendingPathComponent("ghost/master/descript.txt")
        let parsedDescript = YayaBackend.parseDescript(url: descriptURL)

        var dicFiles: [String] = []
        if let mainDic = parsedDescript["yaya.dic"] {
            dicFiles.append(mainDic)
        }
        var i = 2
        while let dicN = parsedDescript["yaya.dic\(i)"] {
            dicFiles.append(dicN)
            i += 1
        }
        if dicFiles.isEmpty {
            //NSLog("[Ourin.YayaBackend] No yaya.dic files found in descript.txt")
            return nil
        }

        guard let adapter = YayaAdapter() else {
            //NSLog("[Ourin.YayaBackend] Failed to initialize YayaAdapter (is yaya_core missing?)")
            return nil
        }

        let ghostMasterURL = ghostURL.appendingPathComponent("ghost/master")
        let ok = adapter.load(ghostRoot: ghostMasterURL, dics: dicFiles, encoding: "utf-8")
        if !ok {
            //NSLog("[Ourin.YayaBackend] YayaAdapter.load failed")
            return nil
        }

        self.yayaAdapter = adapter
        //NSLog("[Ourin.YayaBackend] YAYA backend initialized successfully for \(ghostURL.lastPathComponent)")
    }

    func request(_ text: String) -> String? {
        guard let parsed = YayaBackend.parseRequest(text) else {
            return "SHIORI/3.0 400 Bad Request\r\n\r\n"
        }

        guard let yayaResponse = yayaAdapter.request(method: parsed.method, id: parsed.id, headers: parsed.headers, refs: parsed.refs) else {
            return "SHIORI/3.0 500 Internal Server Error\r\n\r\n"
        }

        return YayaBackend.buildResponse(from: yayaResponse)
    }

    func unload() {
        yayaAdapter.unload()
    }
}

// MARK: - YayaBackend Helpers
private extension YayaBackend {
    static func parseDescript(url: URL) -> [String: String] {
        guard let contents = (try? String(contentsOf: url, encoding: .shiftJIS)) ?? (try? String(contentsOf: url, encoding: .utf8)) else {
            return [:]
        }
        var dict: [String: String] = [:]
        let lines = contents.components(separatedBy: .newlines)
        for line in lines {
            if line.starts(with: "//") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            if let separatorIndex = line.firstIndex(of: ",") {
                let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[separatorIndex...]).dropFirst().trimmingCharacters(in: .whitespaces)
                dict[key] = value
            }
        }
        return dict
    }

    static func parseRequest(_ text: String) -> (method: String, id: String, headers: [String: String], refs: [String])? {
        let lines = text.components(separatedBy: "\r\n")
        guard lines.count >= 2, let firstLine = lines.first else { return nil }
        let parts = firstLine.components(separatedBy: .whitespaces)
        guard parts.count >= 2 else { return nil }
        let method = parts[0]
        var headers: [String: String] = [:]
        var refs: [String] = []
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let separatorIndex = line.firstIndex(of: ":") {
                let key = String(line[..<separatorIndex])
                let value = String(line[separatorIndex...]).dropFirst().trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        guard let id = headers["ID"] else { return nil }
        var i = 0
        while let ref = headers["Reference\(i)"] {
            refs.append(ref)
            i += 1
        }
        return (method, id, headers, refs)
    }

    static func buildResponse(from yayaResponse: YayaResponse) -> String {
        let status = yayaResponse.status
        var statusText = "OK"
        switch status {
        case 204: statusText = "No Content"
        case 400: statusText = "Bad Request"
        case 500: statusText = "Internal Server Error"
        default: break
        }
        var responseString = "SHIORI/3.0 \(status) \(statusText)\r\n"
        if let headers = yayaResponse.headers {
            for (key, value) in headers {
                responseString += "\(key): \(value)\r\n"
            }
        }
        if let value = yayaResponse.value {
            responseString += "Value: \(value)\r\n"
        }
        responseString += "\r\n"
        return responseString
    }
}

// MARK: - Dylib Backend
/// Backend for traditional SHIORI ghosts loaded from .dylib files.
final class DylibBackend: ShioriBackend {
    private var handle: UnsafeMutableRawPointer?
    private var loadFn: ShioriLoad?
    private var requestFn: ShioriRequest?
    private var unloadFn: ShioriUnload?
    private var freeFn: ShioriFree?

    /// Path of loaded module
    public let moduleURL: URL

    init(url: URL) throws {
        guard let h = dlopen(url.path, RTLD_NOW) else {
            throw NSError(domain: "USL.DylibBackend", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: dlerror())])
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

    func request(_ text: String) -> String? {
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

    func unload() {
        if let u = unloadFn { u() }
        if let h = handle { dlclose(h); handle = nil }
        loadFn = nil
        requestFn = nil
        unloadFn = nil
        freeFn = nil
    }
}


/// Function pointer types for SHIORI C-ABI
private typealias ShioriLoad = @convention(c) (UnsafePointer<CChar>?) -> Bool
private typealias ShioriRequest = @convention(c) (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int>?) -> Bool
private typealias ShioriUnload = @convention(c) () -> Void
private typealias ShioriFree = @convention(c) (UnsafeMutablePointer<UInt8>?) -> Void

/// Dynamic loader for SHIORI modules following USL spec
public final class ShioriLoader {
    private let backend: ShioriBackend

    /// Path of loaded module, if available.
    public var moduleURL: URL? {
        if let dylib = backend as? DylibBackend {
            return dylib.moduleURL
        }
        return nil
    }

    private init(backend: ShioriBackend) {
        self.backend = backend
    }

    deinit { unload() }

    /// Attempt to load module by name searching typical USL paths
    public convenience init?(module name: String, base: URL) {
        let shioriName = (name as NSString).lastPathComponent.lowercased()
        let backend: ShioriBackend?

        if shioriName == "yaya.dll" {
            // It's YAYA. Instantiate the YayaBackend.
            // The descript dictionary will be loaded inside YayaBackend's initializer.
            // For now, we pass an empty dictionary as a placeholder.
            backend = YayaBackend(ghostURL: base, descript: [:])
        } else {
            // It's a traditional dylib.
            let paths = ShioriLoader.searchPaths(base: base)
            guard let url = ShioriLoader.find(name: name, in: paths) else {
                // Module not found
                return nil
            }
            backend = try? DylibBackend(url: url)
        }

        if let finalBackend = backend {
            self.init(backend: finalBackend)
        } else {
            // Backend initialization failed
            return nil
        }
    }

    /// Send SHIORI request and return raw response string
    public func request(_ text: String) -> String? {
        return backend.request(text)
    }

    /// Unload module if loaded
    public func unload() {
        backend.unload()
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
