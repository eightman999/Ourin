import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

public enum SaoriLoaderError: Error, CustomStringConvertible {
    case openFailed(String)
    case missingRequestSymbol
    case moduleLoadFailed(String)
    case requestFailed
    case responseDecodeFailed

    public var description: String {
        switch self {
        case .openFailed(let detail):
            return "Failed to open SAORI module: \(detail)"
        case .missingRequestSymbol:
            return "SAORI request symbol was not found."
        case .moduleLoadFailed(let path):
            return "SAORI load() returned failure for \(path)"
        case .requestFailed:
            return "SAORI request invocation failed."
        case .responseDecodeFailed:
            return "SAORI response could not be decoded."
        }
    }
}

public final class SaoriLoader {
    // The SAORI/DLL common ABI uses HGLOBAL + long on Windows. On macOS the
    // POSIX-compatible modules use the equivalent malloc-owned pointer + long
    // layout (long is Int64 on macOS). The module owns and frees the input
    // buffer, and the host owns and frees the returned buffer after copying it.
    public typealias SaoriLoadFn = @convention(c) (UnsafeMutableRawPointer?, Int64) -> Int32
    public typealias SaoriUnloadFn = @convention(c) () -> Int32
    public typealias SaoriRequestFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int64>?) -> UnsafeMutableRawPointer?

    public let moduleURL: URL
    private var handle: UnsafeMutableRawPointer?
    private var loadFn: SaoriLoadFn?
    private var unloadFn: SaoriUnloadFn?
    private var requestFn: SaoriRequestFn?

    public init(url: URL) throws {
        self.moduleURL = url
        // ディレクトリ型バンドル（.plugin/.bundle）は dlopen に渡せないため、
        // Bundle(url:) の executableURL で中の実行体（Contents/MacOS/<name>）を解決する。
        // 通常の dylib/so パスはそのまま扱う（ShioriLoader.BundleBackend と同じ方針）。
        let resolvedURL: URL
        let ext = url.pathExtension.lowercased()
        if ext == "bundle" || ext == "plugin" {
            guard let execURL = Bundle(url: url)?.executableURL else {
                throw SaoriLoaderError.openFailed("bundle executable not found: \(url.path)")
            }
            resolvedURL = execURL
        } else {
            resolvedURL = url
        }
        guard let h = dlopen(resolvedURL.path, RTLD_NOW) else {
            let err = dlerror().map { String(cString: $0) } ?? "unknown"
            throw SaoriLoaderError.openFailed(err)
        }
        handle = h

        func loadSymbol<T>(_ names: [String], as type: T.Type) -> T? {
            for name in names {
                if let symbol = dlsym(h, name) {
                    return unsafeBitCast(symbol, to: T.self)
                }
            }
            return nil
        }

        requestFn = loadSymbol(["request", "saori_request"], as: SaoriRequestFn.self)
        // ukagaka DLL 規約: `loadu` は UTF-8 パス版の load エントリ。存在すれば優先する
        // （macOS のパスは UTF-8 なので withCString はそのまま UTF-8 を渡せる）。
        loadFn = loadSymbol(["loadu", "saori_loadu", "load", "saori_load"], as: SaoriLoadFn.self)
        unloadFn = loadSymbol(["unloadu", "unload", "saori_unloadu", "saori_unload"], as: SaoriUnloadFn.self)

        guard requestFn != nil else {
            closeHandle()
            throw SaoriLoaderError.missingRequestSymbol
        }

        if let loadFn {
            let directory = url.deletingLastPathComponent().path
            let directoryData = Data(directory.utf8)
            // SAORI modules receive ownership of this buffer. Keep a trailing
            // NUL for modules that treat the path as a C string; the explicit
            // length remains the authoritative size per the common ABI.
            guard let directoryBuffer = malloc(max(directoryData.count + 1, 1)) else {
                closeHandle()
                throw SaoriLoaderError.openFailed("could not allocate module directory buffer")
            }
            directoryBuffer.initializeMemory(as: UInt8.self, repeating: 0, count: max(directoryData.count + 1, 1))
            if !directoryData.isEmpty {
                directoryData.withUnsafeBytes { raw in
                    directoryBuffer.copyMemory(from: raw.baseAddress!, byteCount: directoryData.count)
                }
            }
            let result = loadFn(directoryBuffer, Int64(directoryData.count))
            guard result != 0 else {
                closeHandle()
                throw SaoriLoaderError.moduleLoadFailed(directory)
            }
        }
    }

    deinit {
        unload()
    }

    public func send(_ requestText: String, charset: String = "UTF-8") throws -> String {
        guard let requestFn else {
            throw SaoriLoaderError.requestFailed
        }
        let encoded = try SaoriProtocol.encode(requestText, charset: charset)
        guard let requestBuffer = malloc(max(encoded.count, 1)) else {
            throw SaoriLoaderError.requestFailed
        }
        if !encoded.isEmpty {
            encoded.withUnsafeBytes { raw in
                requestBuffer.copyMemory(from: raw.baseAddress!, byteCount: encoded.count)
            }
        }

        var outLen: Int64 = 0
        let resultPtr = requestFn(requestBuffer, &outLen)
        guard let resultPtr else {
            throw SaoriLoaderError.requestFailed
        }
        defer {
            free(resultPtr)
        }

        guard outLen >= 0, let resultCount = Int(exactly: outLen) else {
            throw SaoriLoaderError.responseDecodeFailed
        }
        let data = Data(bytes: resultPtr, count: resultCount)
        if let decoded = try? SaoriProtocol.decode(data, charset: charset) {
            return decoded
        }
        if let utf8Fallback = String(data: data, encoding: .utf8) {
            return utf8Fallback
        }
        throw SaoriLoaderError.responseDecodeFailed
    }

    public func unload() {
        _ = unloadFn?()
        closeHandle()
        loadFn = nil
        unloadFn = nil
        requestFn = nil
    }

    private func closeHandle() {
        if let handle {
            dlclose(handle)
            self.handle = nil
        }
    }
}
