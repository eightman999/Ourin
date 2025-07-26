import Foundation

typealias ReqFn = @convention(c) (UnsafePointer<UInt8>, Int, UnsafeMutablePointer<Int>) -> UnsafePointer<UInt8>?
typealias LoadFn = @convention(c) (UnsafePointer<CChar>) -> Int32
typealias UnloadFn = @convention(c) () -> Void

public struct Plugin {
    let bundle: Bundle
    let request: ReqFn
    let load: LoadFn?
    let unload: UnloadFn?

    public init(url: URL) throws {
        guard let bundle = Bundle(url: url) else { throw NSError(domain: "Plugin", code: -1) }
        self.bundle = bundle
        _ = bundle.principalClass // force load image
        func sym<T>(_ name: String) -> T? {
            let fp = CFBundleGetFunctionPointerForName(bundle._cfBundle, name as CFString)
            guard fp != nil else { return nil }
            return unsafeBitCast(fp, to: Optional<T>.self)
        }
        guard let req: ReqFn = sym("request") else { throw NSError(domain:"Plugin", code:-2) }
        self.request = req
        self.load = sym("load")
        self.unload = sym("unload")
    }

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

private extension Bundle { var _cfBundle: CFBundle { CFBundleGetBundleWithIdentifier(self.bundleIdentifier! as CFString)! } }
