import Foundation
import CoreFoundation

typealias ShioriLoad = @convention(c) (UnsafePointer<CChar>?) -> Bool
typealias ShioriUnload = @convention(c) () -> Void
typealias ShioriRequest = @convention(c) (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int>?) -> Bool
typealias ShioriFree = @convention(c) (UnsafeMutablePointer<UInt8>?) -> Void

func loadFunction<T>(_ bundle: CFBundle, _ name: String, as type: T.Type) -> T {
    let cfName = name as CFString
    let ptr = CFBundleGetFunctionPointerForName(bundle, cfName)
    precondition(ptr != nil, "Function \(name) not found")
    return unsafeBitCast(ptr!, to: type)
}

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: ourin-shiori-host /path/to/OurinSampleSHIORI.bundle\n", stderr)
    exit(2)
}

let bundleURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let bundle = CFBundleCreate(kCFAllocatorDefault, bundleURL as CFURL) else {
    fputs("Failed to load bundle at \(bundleURL.path)\n", stderr)
    exit(1)
}

let shiori_load = loadFunction(bundle, "shiori_load", as: ShioriLoad.self)
let shiori_unload = loadFunction(bundle, "shiori_unload", as: ShioriUnload.self)
let shiori_request = loadFunction(bundle, "shiori_request", as: ShioriRequest.self)
let shiori_free = loadFunction(bundle, "shiori_free", as: ShioriFree.self)

let ok = shiori_load(bundleURL.deletingLastPathComponent().path.cString(using: .utf8))
guard ok else { fputs("shiori_load failed\n", stderr); exit(1) }

let req = """
GET SHIORI/3.0\r
Charset: UTF-8\r
ID: OnBoot\r
\r
"""
var resPtr: UnsafeMutablePointer<UInt8>? = nil
var resLen: Int = 0
let success = req.withCString { cstr in
    let u8 = UnsafePointer<UInt8>(OpaquePointer(cstr))
    var tmpPtr: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>? = nil
    var tmpLen: UnsafeMutablePointer<Int>? = nil
    withUnsafeMutablePointer(to: &resPtr) { pptr in
        withUnsafeMutablePointer(to: &resLen) { plen in
            tmpPtr = UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>(OpaquePointer(pptr))
            tmpLen = UnsafeMutablePointer<Int>(OpaquePointer(plen))
            return shiori_request(u8, strlen(cstr), tmpPtr, tmpLen)
        }
    }
}
if success, let resPtr = resPtr {
    let data = Data(bytes: resPtr, count: resLen)
    if let text = String(data: data, encoding: .utf8) {
        print(text)
    } else {
        print("Received \(resLen) bytes")
    }
    shiori_free(resPtr)
} else {
    fputs("shiori_request failed\n", stderr)
}

shiori_unload()
