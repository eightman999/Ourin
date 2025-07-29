import Foundation
import CoreFoundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// FMO など既存のホスト機能を利用して SHIORI パイプラインへ橋渡しを行う仮実装
public enum BridgeToSHIORI {
    /// Resource 用のテスト返値を保持するマップ
    private static var resourceMap: [String: String] = [:]
    /// 実際の SHIORI ホスト
    private static var host: ShioriHost? = {
        if let path = ProcessInfo.processInfo.environment["SHIORI_BUNDLE_PATH"] {
            return ShioriHost(bundlePath: path)
        }
        return nil
    }()

    /// テスト用に返値を登録する
    public static func setResource(_ key: String, value: String) {
        resourceMap[key] = value
    }

    /// テスト用登録値をすべて消去
    public static func reset() {
        resourceMap.removeAll()
    }

    /// 指定されたイベントを SHIORI へ送信し応答を返す。
    /// テスト用に登録されたリソースが存在する場合はそれを優先する。
    public static func handle(event: String, references: [String]) -> String {
        if event == "Resource", let key = references.first, let val = resourceMap[key] {
            return val
        }
        if let res = host?.request(event: event, references: references) {
            return res
        }
        return "\\h\\s0Placeholder"
    }
}

// MARK: - Internal SHIORI host bridge
private final class ShioriHost {
    typealias LoadFn = @convention(c) (UnsafePointer<CChar>?) -> Bool
    typealias UnloadFn = @convention(c) () -> Void
    typealias RequestFn = @convention(c) (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int>?) -> Bool
    typealias FreeFn = @convention(c) (UnsafeMutablePointer<UInt8>?) -> Void

    private let load: LoadFn
    private let unload: UnloadFn
    private let requestFn: RequestFn
    private let freeFn: FreeFn
    private let bundle: CFBundle

    init?(bundlePath: String) {
        let cfStr = CFStringCreateWithCString(kCFAllocatorDefault, bundlePath, CFStringBuiltInEncodings.UTF8.rawValue)
        let cfUrl = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, cfStr, CFURLPathStyle.cfurlposixPathStyle, true)
        guard let b = CFBundleCreate(kCFAllocatorDefault, cfUrl) else { return nil }
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            let s = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.UTF8.rawValue)
            guard let ptr = CFBundleGetFunctionPointerForName(b, s) else { return nil }
            return unsafeBitCast(ptr, to: T.self)
        }
        guard let l: LoadFn = sym("shiori_load", LoadFn.self),
              let u: UnloadFn = sym("shiori_unload", UnloadFn.self),
              let r: RequestFn = sym("shiori_request", RequestFn.self),
              let f: FreeFn = sym("shiori_free", FreeFn.self) else { return nil }
        load = l
        unload = u
        requestFn = r
        freeFn = f
        bundle = b
        let dir = (bundlePath as NSString).deletingLastPathComponent
        let ok = dir.withCString { cstr in
            load(cstr)
        }
        guard ok else { return nil }
    }

    deinit { unload() }

    func request(event: String, references: [String]) -> String? {
        var lines = [
            "GET SHIORI/3.0",
            "Charset: UTF-8",
            "Sender: Ourin",
            "ID: \(event)"
        ]
        for (i, ref) in references.enumerated() {
            lines.append("Reference\(i): \(ref)")
        }
        lines.append("")
        let req = lines.joined(separator: "\r\n") + "\r\n"
        let bytes = req.utf8CString
        var resPtr: UnsafeMutablePointer<UInt8>? = nil
        var resLen: Int = 0
        let success = bytes.withUnsafeBufferPointer { buf -> Bool in
            var tmpPtr: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>? = nil
            var tmpLen: UnsafeMutablePointer<Int>? = nil
            return withUnsafeMutablePointer(to: &resPtr) { pptr in
                withUnsafeMutablePointer(to: &resLen) { plen in
                    tmpPtr = UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>(OpaquePointer(pptr))
                    tmpLen = UnsafeMutablePointer<Int>(OpaquePointer(plen))
                    guard let raw = buf.baseAddress else { return false }
                    let base = UnsafeRawPointer(raw).assumingMemoryBound(to: UInt8.self)
                    return requestFn(base, buf.count - 1, tmpPtr, tmpLen)
                }
            }
        }
        guard success, let ptr = resPtr else { return nil }
        let data = Data(bytes: ptr, count: resLen)
        freeFn(ptr)
        return String(data: data, encoding: .utf8)
    }
}
