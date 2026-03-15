import Foundation

private var moduleDir: String = ""
private var responseBuffer: UnsafeMutablePointer<UInt8>?
private var responseLength: Int = 0

private func storeResponse(_ text: String) {
    responseBuffer?.deallocate()
    let bytes = Array(text.utf8)
    responseLength = bytes.count
    let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
    ptr.initialize(from: bytes, count: bytes.count)
    responseBuffer = ptr
}

@_cdecl("load")
public func load(_ module_dir_utf8: UnsafePointer<CChar>?) -> Int32 {
    moduleDir = module_dir_utf8.map { String(cString: $0) } ?? ""
    return 1
}

@_cdecl("unload")
public func unload() {
    responseBuffer?.deallocate()
    responseBuffer = nil
    responseLength = 0
    moduleDir = ""
}

@_cdecl("request")
public func request(
    _ req: UnsafePointer<UInt8>?,
    _ req_len: Int32,
    _ res_len: UnsafeMutablePointer<Int32>?
) -> UnsafePointer<UInt8>? {
    let reqText: String
    if let req, req_len > 0 {
        let data = Data(bytes: req, count: Int(req_len))
        reqText = String(data: data, encoding: .utf8) ?? ""
    } else {
        reqText = ""
    }

    var value = "Hello from Swift SAORI"
    if let range = reqText.range(of: "Argument0:") {
        let tail = reqText[range.upperBound...]
        let line = tail.split(separator: "\r", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        value = "Echo \(line.trimmingCharacters(in: .whitespaces))"
    }

    let wire = """
    SAORI/1.0 200 OK\r
    Charset: UTF-8\r
    Result: 1\r
    Value: \(value)\r
    \r
    """
    storeResponse(wire)
    res_len?.pointee = Int32(responseLength)
    guard let responseBuffer else { return nil }
    return UnsafePointer(responseBuffer)
}
