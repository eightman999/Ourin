import Foundation

public typealias HeadlineExecuteFn = @convention(c) (UnsafePointer<UInt8>, Int, UnsafeMutablePointer<Int>) -> UnsafePointer<UInt8>?
public typealias HeadlineLoadFn = @convention(c) (UnsafePointer<CChar>) -> Int32
public typealias HeadlineUnloadFn = @convention(c) () -> Void

/// Wrapper for a HEADLINE/2.0M module (`.plugin` / `.bundle` / `.dylib`).
///
/// 呼び出し規約は Plugin と同じく、既定の Ourin C ABI と、Windows DLL と同じ
/// `execute(HGLOBAL, long*)`（Info.plist の `OurinModuleABI` 宣言、または単体 `.dylib`）を扱う。
public struct HeadlineModule: Hashable {
    /// ロード対象のモジュール。
    public let url: URL
    let bundle: Bundle?
    let execute: HeadlineExecuteFn?
    let ukagakaExecute: UkagakaModuleABI.RequestFn?
    let loadEntry: UkagakaModuleABI.LoadFn?
    let unload: HeadlineUnloadFn?

    public init(url: URL) throws {
        guard let executableURL = UkagakaModuleABI.executableURL(forModuleAt: url) else {
            throw NSError(domain: "HeadlineModule", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid bundle"])
        }
        guard let handle = dlopen(executableURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let detail = dlerror().map { String(cString: $0) } ?? "unknown"
            throw NSError(domain: "HeadlineModule", code: -1, userInfo: [NSLocalizedDescriptionKey: "dlopen failed: \(detail)"])
        }
        func sym<T>(_ names: String...) -> T? {
            for name in names {
                if let fp = dlsym(handle, name) { return unsafeBitCast(fp, to: T.self) }
            }
            return nil
        }
        let isBundle = executableURL != url
        self.url = url
        self.bundle = isBundle ? Bundle(url: url) : nil
        let convention = UkagakaModuleABI.convention(declaredIn: bundle?.infoDictionary, fallback: isBundle ? .ourin : .ukagaka)
        self.execute = convention == .ourin ? sym("execute") : nil
        self.ukagakaExecute = convention == .ukagaka ? sym("execute") : nil
        guard execute != nil || ukagakaExecute != nil else {
            throw NSError(domain: "HeadlineModule", code: -2, userInfo: [NSLocalizedDescriptionKey: "execute not found"])
        }
        // ukagaka DLL 規約: `loadu` は UTF-8 パス版 load。存在すれば優先（macOS のパスは UTF-8）。
        self.loadEntry = sym("loadu", "load")
        self.unload = sym("unloadu", "unload")
    }

    /// `load` / `loadu` を呼ぶ（末尾区切り付きディレクトリ、malloc 確保で所有権はモジュールへ）。
    @discardableResult
    public func load(directoryURL: URL) -> Bool {
        guard let loadEntry else { return true }
        return UkagakaModuleABI.callLoad(loadEntry, directoryURL: directoryURL)
    }

    /// Send raw wire text to the module. 要求は `charset` で符号化し、応答は応答の `Charset` に従って復号する。
    public func send(_ text: String, charset: String.Encoding = .utf8) -> String {
        let charsetName = charset == .shiftJIS ? "Shift_JIS" : "UTF-8"
        let requestData = EncodingAdapter.encode(text, charset: charsetName)
        guard let data = send(requestData) else { return "" }
        let responseCharset = EncodingAdapter.detectCharset(in: data, default: charsetName)
        return EncodingAdapter.decode(data, charset: responseCharset)
            ?? String(decoding: data, as: UTF8.self)
    }

    /// Send raw wire bytes and return raw response bytes.
    public func send(_ data: Data) -> Data? {
        if let ukagakaExecute {
            return UkagakaModuleABI.callRequest(ukagakaExecute, data: data)
        }
        guard let execute else { return nil }
        var outLen: Int = 0
        var bytes = Array(data)
        if bytes.isEmpty { bytes = [0] }
        let byteCount = data.count
        let respPtr = bytes.withUnsafeMutableBytes { raw -> UnsafePointer<UInt8>? in
            return execute(raw.bindMemory(to: UInt8.self).baseAddress!, byteCount, &outLen)
        }
        guard let p = respPtr else { return nil }
        return Data(bytes: p, count: max(outLen, 0))
    }
}

extension HeadlineModule {
    public static func == (lhs: HeadlineModule, rhs: HeadlineModule) -> Bool {
        lhs.url == rhs.url
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
