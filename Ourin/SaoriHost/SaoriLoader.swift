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
    public typealias SaoriLoadFn = @convention(c) (UnsafePointer<CChar>?) -> Int32
    public typealias SaoriUnloadFn = @convention(c) () -> Void
    public typealias SaoriRequestFn = @convention(c) (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<Int>?) -> UnsafePointer<UInt8>?

    public let moduleURL: URL
    private var handle: UnsafeMutableRawPointer?
    private var loadFn: SaoriLoadFn?
    private var unloadFn: SaoriUnloadFn?
    private var requestFn: SaoriRequestFn?

    public init(url: URL) throws {
        self.moduleURL = url
        guard let h = dlopen(url.path, RTLD_NOW) else {
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
        loadFn = loadSymbol(["load", "saori_load"], as: SaoriLoadFn.self)
        unloadFn = loadSymbol(["unload", "saori_unload"], as: SaoriUnloadFn.self)

        guard requestFn != nil else {
            closeHandle()
            throw SaoriLoaderError.missingRequestSymbol
        }

        if let loadFn {
            let directory = url.deletingLastPathComponent().path
            let result = directory.withCString { cPath in
                loadFn(cPath)
            }
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
        var outLen: Int = 0
        let resultPtr = encoded.withUnsafeBytes { raw -> UnsafePointer<UInt8>? in
            requestFn(raw.bindMemory(to: UInt8.self).baseAddress, encoded.count, &outLen)
        }
        guard let resultPtr else {
            throw SaoriLoaderError.requestFailed
        }

        let data = Data(bytes: resultPtr, count: max(outLen, 0))
        if let decoded = try? SaoriProtocol.decode(data, charset: charset) {
            return decoded
        }
        if let utf8Fallback = String(data: data, encoding: .utf8) {
            return utf8Fallback
        }
        throw SaoriLoaderError.responseDecodeFailed
    }

    public func unload() {
        unloadFn?()
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
