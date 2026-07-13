import Foundation
import Darwin

@objc protocol OurinShioriXPC {
    func ping(withReply reply: @escaping () -> Void)
    func load(_ bundlePath: String, withReply reply: @escaping (Bool, String?) -> Void)
    func execute(_ request: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func unload(withReply reply: @escaping () -> Void)
    func execute(_ request: Data, bundlePath: String, withReply reply: @escaping (Data?, String?) -> Void)
}

private typealias ShioriLoad = @convention(c) (UnsafePointer<CChar>?) -> Bool
private typealias ShioriRequest = @convention(c) (
    UnsafePointer<UInt8>?, Int,
    UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    UnsafeMutablePointer<Int>?
) -> Bool
private typealias ShioriUnload = @convention(c) () -> Void
private typealias ShioriFree = @convention(c) (UnsafeMutablePointer<UInt8>?) -> Void

private enum WireEncoding {
    static func charset(in data: Data, default defaultValue: String = "UTF-8") -> String {
        let header = String(data: data.prefix(8192), encoding: .isoLatin1) ?? ""
        for line in header.components(separatedBy: .newlines) {
            guard let separator = line.firstIndex(of: ":") else { continue }
            if line[..<separator].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Charset") == .orderedSame {
                return line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return defaultValue
    }

    static func encoding(for charset: String) -> String.Encoding {
        switch charset.lowercased().replacingOccurrences(of: "-", with: "_") {
        case "shift_jis", "shiftjis", "windows_31j", "cp932", "ms932", "sjis", "x_sjis": return .shiftJIS
        case "euc_jp", "eucjp": return .japaneseEUC
        case "iso_2022_jp", "jis": return .iso2022JP
        default: return .utf8
        }
    }
}

private final class NativeShioriModule {
    private var bundle: CFBundle?
    private var dylib: UnsafeMutableRawPointer?
    private var loadFunction: ShioriLoad?
    private var requestFunction: ShioriRequest?
    private var unloadFunction: ShioriUnload?
    private var freeFunction: ShioriFree?

    init(url: URL) throws {
        if ["bundle", "plugin"].contains(url.pathExtension.lowercased()) {
            guard let value = CFBundleCreate(kCFAllocatorDefault, url as CFURL), CFBundleLoadExecutable(value) else {
                throw NSError(domain: "OurinShioriXPC", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bundle load failed"])
            }
            bundle = value
            loadFunction = symbol(in: value, names: ["shiori_loadu", "loadu", "shiori_load", "load"], as: ShioriLoad.self)
            requestFunction = symbol(in: value, names: ["shiori_request", "request"], as: ShioriRequest.self)
            unloadFunction = symbol(in: value, names: ["shiori_unloadu", "unloadu", "shiori_unload", "unload"], as: ShioriUnload.self)
            freeFunction = symbol(in: value, names: ["shiori_free", "free"], as: ShioriFree.self)
        } else {
            guard let handle = dlopen(url.path, RTLD_NOW) else {
                let detail: String
                if let pointer = dlerror() {
                    detail = String(cString: pointer)
                } else {
                    detail = "dlopen failed"
                }
                throw NSError(domain: "OurinShioriXPC", code: 2, userInfo: [NSLocalizedDescriptionKey: detail])
            }
            dylib = handle
            loadFunction = symbol(in: handle, names: ["shiori_loadu", "loadu", "shiori_load", "load"], as: ShioriLoad.self)
            requestFunction = symbol(in: handle, names: ["shiori_request", "request"], as: ShioriRequest.self)
            unloadFunction = symbol(in: handle, names: ["shiori_unloadu", "unloadu", "shiori_unload", "unload"], as: ShioriUnload.self)
            freeFunction = symbol(in: handle, names: ["shiori_free", "free"], as: ShioriFree.self)
        }
        guard requestFunction != nil else { throw missing("shiori_request") }
        guard freeFunction != nil else { throw missing("shiori_free") }
        if let loadFunction {
            let loaded = url.deletingLastPathComponent().path.withCString { loadFunction($0) }
            guard loaded else { throw NSError(domain: "OurinShioriXPC", code: 4, userInfo: [NSLocalizedDescriptionKey: "shiori_load returned false"]) }
        }
    }

    deinit { unload() }

    func request(_ data: Data) -> Data? {
        guard let requestFunction else { return nil }
        var output: UnsafeMutablePointer<UInt8>?
        var outputLength = 0
        let succeeded = data.withUnsafeBytes {
            requestFunction($0.baseAddress?.assumingMemoryBound(to: UInt8.self), data.count, &output, &outputLength)
        }
        guard succeeded, let output, outputLength >= 0 else { return nil }
        let response = Data(bytes: output, count: outputLength)
        freeFunction?(output)
        return response
    }

    func unload() {
        unloadFunction?()
        unloadFunction = nil
        requestFunction = nil
        freeFunction = nil
        loadFunction = nil
        if let bundle { CFBundleUnloadExecutable(bundle); self.bundle = nil }
        if let dylib { dlclose(dylib); self.dylib = nil }
    }

    private func missing(_ symbol: String) -> Error {
        NSError(domain: "OurinShioriXPC", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing required symbol: \(symbol)"])
    }

    private func symbol<T>(in bundle: CFBundle, names: [String], as type: T.Type) -> T? {
        for name in names {
            if let pointer = CFBundleGetFunctionPointerForName(bundle, name as CFString) {
                return unsafeBitCast(pointer, to: type)
            }
        }
        return nil
    }

    private func symbol<T>(in handle: UnsafeMutableRawPointer, names: [String], as type: T.Type) -> T? {
        for name in names {
            if let pointer = dlsym(handle, name) { return unsafeBitCast(pointer, to: type) }
        }
        return nil
    }
}

private final class ShioriSession: NSObject, OurinShioriXPC {
    private let queue = DispatchQueue(label: "jp.ourin.shiori.session")
    private var module: NativeShioriModule?
    private let watchdogTimeout: TimeInterval = 5

    func ping(withReply reply: @escaping () -> Void) { reply() }

    func load(_ bundlePath: String, withReply reply: @escaping (Bool, String?) -> Void) {
        runWithWatchdog {
            self.module?.unload()
            self.module = nil
            do {
                let url = URL(fileURLWithPath: bundlePath).standardizedFileURL
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw NSError(domain: "OurinShioriXPC", code: 5, userInfo: [NSLocalizedDescriptionKey: "Module not found: \(url.path)"])
                }
                self.module = try NativeShioriModule(url: url)
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func execute(_ request: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        runWithWatchdog {
            guard let module = self.module else { reply(nil, "SHIORI module is not loaded"); return }
            guard let response = module.request(request) else { reply(nil, "SHIORI request failed"); return }
            reply(response, nil)
        }
    }

    func unload(withReply reply: @escaping () -> Void) {
        runWithWatchdog {
            self.module?.unload()
            self.module = nil
            reply()
        }
    }

    func execute(_ request: Data, bundlePath: String, withReply reply: @escaping (Data?, String?) -> Void) {
        load(bundlePath) { ok, error in
            guard ok else { reply(nil, error); return }
            self.execute(request, withReply: reply)
        }
    }

    func invalidate() {
        queue.async {
            self.module?.unload()
            self.module = nil
        }
    }

    private func runWithWatchdog(_ operation: @escaping () -> Void) {
        let state = WatchdogState()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + watchdogTimeout) {
            if state.markTimedOutIfRunning() { _exit(124) }
        }
        queue.async {
            operation()
            state.markFinished()
        }
    }
}

private final class WatchdogState {
    private let lock = NSLock()
    private var running = true

    func markFinished() {
        lock.lock(); running = false; lock.unlock()
    }

    func markTimedOutIfRunning() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard running else { return false }
        running = false
        return true
    }
}

private final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let session = ShioriSession()
        connection.exportedInterface = NSXPCInterface(with: OurinShioriXPC.self)
        connection.exportedObject = session
        connection.invalidationHandler = { session.invalidate() }
        connection.interruptionHandler = { session.invalidate() }
        connection.resume()
        return true
    }
}

private let delegate = ServiceDelegate()
private let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
