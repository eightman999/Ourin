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
    public typealias SaoriLoadFn = UkagakaModuleABI.LoadFn
    public typealias SaoriUnloadFn = @convention(c) () -> Int32
    public typealias SaoriRequestFn = UkagakaModuleABI.RequestFn

    public let moduleURL: URL
    private var handle: UnsafeMutableRawPointer?
    private var loadFn: SaoriLoadFn?
    private var unloadFn: SaoriUnloadFn?
    private var requestFn: SaoriRequestFn?
    /// Ourin 内蔵の互換 SAORI（`BuiltinSaori`）。dlopen せず要求文を直接処理する。
    private var builtinHandler: ((String) -> String)?

    /// Windows 専用 SAORI の代わりに内蔵実装で応答するローダー。
    init(builtinModuleURL url: URL, handler: @escaping (String) -> String) {
        self.moduleURL = url
        self.builtinHandler = handler
    }

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
            // SSP と同じく末尾区切り付きのディレクトリを渡す（`path + "config.txt"` 形式の連結に対応）。
            // バッファは malloc 確保・NUL 終端で、所有権はモジュールへ移る（共通 ABI）。
            let directoryURL = url.deletingLastPathComponent()
            guard UkagakaModuleABI.callLoad(loadFn, directoryURL: directoryURL) else {
                closeHandle()
                throw SaoriLoaderError.moduleLoadFailed(directoryURL.path)
            }
        }
    }

    deinit {
        unload()
    }

    public func send(_ requestText: String, charset: String = "UTF-8") throws -> String {
        if let builtinHandler {
            return builtinHandler(requestText)
        }
        guard let requestFn else {
            throw SaoriLoaderError.requestFailed
        }
        let encoded = try SaoriProtocol.encode(requestText, charset: charset)
        // 共通 ABI: *len に入力長を入れて呼び、戻り値の長さを受け取る。入力領域はモジュールが free する。
        guard let data = UkagakaModuleABI.callRequest(requestFn, data: encoded) else {
            throw SaoriLoaderError.requestFailed
        }
        // 応答は応答側の Charset ヘッダを優先して復号する（未指定なら要求の Charset）。
        let responseCharset = EncodingAdapter.detectCharset(in: data, default: charset)
        if let decoded = try? SaoriProtocol.decode(data, charset: responseCharset) {
            return decoded
        }
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
        builtinHandler = nil
    }

    private func closeHandle() {
        if let handle {
            dlclose(handle)
            self.handle = nil
        }
    }
}
