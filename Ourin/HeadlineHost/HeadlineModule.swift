import Foundation

public typealias HeadlineExecuteFn = @convention(c) (UnsafePointer<UInt8>, Int, UnsafeMutablePointer<Int>) -> UnsafePointer<UInt8>?
public typealias HeadlineLoadFn = @convention(c) (UnsafePointer<CChar>) -> Int32
public typealias HeadlineUnloadFn = @convention(c) () -> Void

/// Wrapper for a HEADLINE/2.0M module bundle
public struct HeadlineModule: Hashable {
    let bundle: Bundle
    let execute: HeadlineExecuteFn
    let load: HeadlineLoadFn?
    let unload: HeadlineUnloadFn?

    public init(url: URL) throws {
        guard let bundle = Bundle(url: url) else {
            throw NSError(domain: "HeadlineModule", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid bundle"])
        }
        self.bundle = bundle
        _ = bundle.principalClass // force load image
        func sym<T>(_ name: String) -> T? {
            let fp = CFBundleGetFunctionPointerForName(bundle._cfBundle, name as CFString)
            guard fp != nil else { return nil }
            return unsafeBitCast(fp, to: Optional<T>.self)
        }
        guard let exe: HeadlineExecuteFn = sym("execute") else {
            throw NSError(domain: "HeadlineModule", code: -2, userInfo: [NSLocalizedDescriptionKey: "execute not found"])
        }
        self.execute = exe
        self.load = sym("load")
        self.unload = sym("unload")
    }

    /// Send raw wire text to the module and get UTF-8 response string
    public func send(_ text: String) -> String {
        var outLen: Int = 0
        var bytes = Array(text.utf8)
        let respPtr = bytes.withUnsafeMutableBytes { raw -> UnsafePointer<UInt8>? in
            return execute(raw.bindMemory(to: UInt8.self).baseAddress!, bytes.count, &outLen)
        }
        guard let p = respPtr else { return "" }
        let buf = UnsafeBufferPointer(start: p, count: outLen)
        return String(decoding: buf, as: UTF8.self)
    }
}

extension HeadlineModule {
    public static func == (lhs: HeadlineModule, rhs: HeadlineModule) -> Bool {
        lhs.bundle.bundleURL == rhs.bundle.bundleURL
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bundle.bundleURL)
    }
}

private extension Bundle {
    var _cfBundle: CFBundle {
        CFBundleGetBundleWithIdentifier(self.bundleIdentifier! as CFString)!
    }
}
