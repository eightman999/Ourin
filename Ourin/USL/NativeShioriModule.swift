import Foundation
import Darwin

/// Shared by the app and the isolated XPC service. Never infer a C signature from
/// the unprefixed `request` symbol: two incompatible SHIORI ABIs use that name.
final class NativeShioriModule {
    enum ABI: String {
        case ourin
        case ukagakaLong = "ukagaka-long"
        case ukagakaInt32 = "ukagaka-int32"
        /// KAGARI POSIX 版 (`kagari_load` / `kagari_request(id,…)` / `kagari_unload`).
        case kagari
        /// Aosora POSIX ABI uses C long instance IDs and lengths.
        case aosora
        /// Official YAYA POSIX multi-instance ABI; instance zero is reserved.
        case yaya
    }
    private typealias KagariLoad = @convention(c) (UnsafeMutableRawPointer?, Int) -> Int32
    private typealias KagariUnload = @convention(c) (Int32) -> Int32
    private typealias KagariRequest = @convention(c) (Int32, UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?) -> UnsafeMutableRawPointer?
    private typealias AosoraLoad = @convention(c) (UnsafeMutableRawPointer?, Int) -> Int
    private typealias AosoraUnload = @convention(c) (Int) -> Int32
    private typealias AosoraRequest = @convention(c) (Int, UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?) -> UnsafeMutableRawPointer?
    private typealias LegacyLoad = @convention(c) (UnsafePointer<CChar>?) -> Bool
    private typealias LegacyRequest = @convention(c) (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int>?) -> Bool
    private typealias Load64 = @convention(c) (UnsafeMutableRawPointer?, Int) -> Int32
    private typealias Load32 = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
    private typealias Request64 = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?) -> UnsafeMutableRawPointer?
    private typealias Request32 = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer?
    private typealias LegacyUnload = @convention(c) () -> Void
    private typealias StandardUnload = @convention(c) () -> Int32
    private typealias Free = @convention(c) (UnsafeMutableRawPointer?) -> Void

    private var handle: UnsafeMutableRawPointer?
    private var performRequest: ((Data) -> Data?)?
    private var performUnload: (() -> Void)?
    private var kagariInstanceID: Int32 = -1
    let moduleURL: URL

    init(url: URL, loadDirectory: URL? = nil) throws {
        moduleURL = url
        let isBundle = ["bundle", "plugin"].contains(url.pathExtension.lowercased())
        let bundle = isBundle ? Bundle(url: url) : nil
        let executable = isBundle ? bundle?.executableURL : url
        guard let executable, let handle = dlopen(executable.path, RTLD_NOW | RTLD_LOCAL) else {
            throw Self.error(dlerror().map { String(cString: $0) } ?? "Cannot open native SHIORI")
        }
        self.handle = handle
        do {
            func symbol<T>(_ names: [String], _: T.Type) -> T? {
                for name in names {
                    if let pointer = dlsym(handle, name) { return unsafeBitCast(pointer, to: T.self) }
                }
                return nil
            }
            var info = bundle?.infoDictionary
            if !isBundle {
                var metadataURLs = [url.appendingPathExtension("plist")]
                // Signed app Frameworks contains code only; bundled ABI declarations are resources.
                if url.deletingLastPathComponent().lastPathComponent == "Frameworks" {
                    metadataURLs.append(url.deletingLastPathComponent().deletingLastPathComponent()
                        .appendingPathComponent("Resources/EngineMetadata")
                        .appendingPathComponent(url.lastPathComponent + ".plist"))
                }
                for metadataURL in metadataURLs {
                    if let data = try? Data(contentsOf: metadataURL) {
                        info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                        break
                    }
                }
            }
            let declared = info?["OurinShioriABI"] as? String
            let abi: ABI
            if let declared {
                guard let value = ABI(rawValue: declared.lowercased()) else { throw Self.error("Unknown OurinShioriABI: \(declared)") }
                abi = value
            } else if dlsym(handle, "kagari_request") != nil {
                abi = .kagari
            } else if dlsym(handle, "aosora_request") != nil {
                abi = .aosora
            } else {
                guard dlsym(handle, "shiori_request") != nil else {
                    throw Self.error("Unprefixed request requires an explicit OurinShioriABI declaration")
                }
                abi = .ourin
            }
            let directory = loadDirectory ?? url.deletingLastPathComponent()
            let path = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
            let names = ["shiori_loadu", "loadu", "shiori_load", "load"]
            let requestNames = ["shiori_request", "request"]
            let unloadNames = ["shiori_unloadu", "unloadu", "shiori_unload", "unload"]
            let release = symbol(["shiori_free"], Free.self) ?? { free($0) }
            let loaded: Bool
            switch abi {
            case .ourin:
                guard let request = symbol(requestNames, LegacyRequest.self) else { throw Self.error("Missing request") }
                performRequest = { data in
                    var output: UnsafeMutablePointer<UInt8>?
                    var length = 0
                    let ok = data.withUnsafeBytes { request($0.baseAddress?.assumingMemoryBound(to: UInt8.self), data.count, &output, &length) }
                    defer { if let output { release(UnsafeMutableRawPointer(output)) } }
                    guard ok, let output, length >= 0, length <= 64 * 1024 * 1024 else { return nil }
                    return Data(bytes: output, count: length)
                }
                if let load = symbol(names, LegacyLoad.self) { loaded = path.withCString { load($0) } } else { loaded = true }
                if loaded, let unload = symbol(unloadNames, LegacyUnload.self) { performUnload = { unload() } }
            case .ukagakaLong:
                guard let request = symbol(requestNames, Request64.self) else { throw Self.error("Missing request") }
                performRequest = { data in
                    guard let input = Self.owned(data) else { return nil }
                    var length = data.count
                    guard let output = request(input, &length) else { return nil }
                    defer { free(output) }
                    guard length >= 0, length <= 64 * 1024 * 1024 else { return nil }
                    return Data(bytes: output, count: length)
                }
                if let load = symbol(names, Load64.self) {
                    let data = Data(path.utf8)
                    guard let input = Self.owned(data) else { throw Self.error("Allocation failed") }
                    loaded = load(input, data.count) != 0
                } else { loaded = true }
                if loaded, let unload = symbol(unloadNames, StandardUnload.self) { performUnload = { _ = unload() } }
            case .ukagakaInt32:
                guard let request = symbol(requestNames, Request32.self) else { throw Self.error("Missing request") }
                performRequest = { data in
                    guard let count = Int32(exactly: data.count), let input = Self.owned(data) else { return nil }
                    var length = count
                    guard let output = request(input, &length) else { return nil }
                    defer { free(output) }
                    guard length >= 0, length <= 64 * 1024 * 1024 else { return nil }
                    return Data(bytes: output, count: Int(length))
                }
                if let load = symbol(names, Load32.self) {
                    let data = Data(path.utf8)
                    guard let count = Int32(exactly: data.count), let input = Self.owned(data) else { throw Self.error("Allocation failed") }
                    loaded = load(input, count) != 0
                } else { loaded = true }
                if loaded, let unload = symbol(unloadNames, StandardUnload.self) { performUnload = { _ = unload() } }
            case .kagari:
                guard let load = symbol(["kagari_load"], KagariLoad.self),
                      let unload = symbol(["kagari_unload"], KagariUnload.self),
                      let request = symbol(["kagari_request"], KagariRequest.self) else {
                    throw Self.error("Missing kagari_load/kagari_request/kagari_unload")
                }
                let pathData = Data(path.utf8)
                guard let pathBuffer = Self.owned(pathData) else { throw Self.error("Allocation failed") }
                let instance = load(pathBuffer, pathData.count)
                guard instance >= 0 else { throw Self.error("kagari_load failed") }
                kagariInstanceID = instance
                let activeID = instance
                performRequest = { data in
                    guard let input = Self.owned(data) else { return nil }
                    var length = data.count
                    guard let output = request(activeID, input, &length) else { return nil }
                    defer { free(output) }
                    guard length >= 0, length <= 64 * 1024 * 1024 else { return nil }
                    return Data(bytes: output, count: length)
                }
                performUnload = { _ = unload(activeID) }
                loaded = true
            case .aosora, .yaya:
                let loadName = abi == .yaya ? "multi_loadu" : "aosora_load"
                let requestName = abi == .yaya ? "multi_request" : "aosora_request"
                let unloadName = abi == .yaya ? "multi_unload" : "aosora_unload"
                guard let load = symbol([loadName], AosoraLoad.self),
                      let unload = symbol([unloadName], AosoraUnload.self),
                      let request = symbol([requestName], AosoraRequest.self) else {
                    throw Self.error("Missing \(loadName)/\(requestName)/\(unloadName)")
                }
                let pathData = Data(path.utf8)
                guard let pathBuffer = Self.owned(pathData) else { throw Self.error("Allocation failed") }
                let instance = load(pathBuffer, pathData.count)
                guard instance > 0 else { throw Self.error("\(loadName) failed") }
                performRequest = { data in
                    guard let input = Self.owned(data) else { return nil }
                    var length = data.count
                    guard let output = request(instance, input, &length) else { return nil }
                    defer { free(output) }
                    guard length >= 0, length <= 64 * 1024 * 1024 else { return nil }
                    return Data(bytes: output, count: length)
                }
                performUnload = { _ = unload(instance) }
                loaded = true
            }
            guard loaded else { throw Self.error("SHIORI load returned false") }
        } catch {
            performRequest = nil
            performUnload = nil
            dlclose(handle)
            self.handle = nil
            throw error
        }
    }

    func request(_ data: Data) -> Data? { performRequest?(data) }
    func unload() {
        performUnload?()
        performUnload = nil
        performRequest = nil
        kagariInstanceID = -1
        if let handle { dlclose(handle); self.handle = nil }
    }
    deinit { unload() }

    private static func owned(_ data: Data) -> UnsafeMutableRawPointer? {
        guard let pointer = malloc(data.count + 1) else { return nil }
        pointer.initializeMemory(as: UInt8.self, repeating: 0, count: data.count + 1)
        if !data.isEmpty { data.withUnsafeBytes { pointer.copyMemory(from: $0.baseAddress!, byteCount: data.count) } }
        return pointer
    }
    private static func error(_ message: String) -> NSError {
        NSError(domain: "Ourin.NativeShiori", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
