import Foundation
import Darwin

private var moduleDir: String = ""
private var responseBuffer: UnsafeMutablePointer<CChar>?
private var responseLength: Int = 0

private func storeResponse(_ text: String) {
    if let responseBuffer {
        free(responseBuffer)
    }
    let bytes = Array(text.utf8)
    responseLength = bytes.count
    guard let ptr = malloc(max(bytes.count, 1)) else {
        responseLength = 0
        responseBuffer = nil
        return
    }
    if !bytes.isEmpty {
        bytes.withUnsafeBytes { raw in
            ptr.copyMemory(from: raw.baseAddress!, byteCount: bytes.count)
        }
    }
    responseBuffer = ptr.assumingMemoryBound(to: CChar.self)
}

@_cdecl("load")
public func load(_ module_dir_utf8: UnsafeMutablePointer<CChar>?, _ module_dir_len: Int64) -> Int32 {
    if let module_dir_utf8, module_dir_len > 0, module_dir_len <= Int64(Int.max) {
        let data = Data(bytes: module_dir_utf8, count: Int(module_dir_len))
        moduleDir = String(decoding: data, as: UTF8.self)
    } else {
        moduleDir = ""
    }
    if let module_dir_utf8 {
        free(module_dir_utf8)
    }
    return 1
}

@_cdecl("unload")
public func unload() -> Int32 {
    if let responseBuffer {
        free(responseBuffer)
    }
    responseBuffer = nil
    responseLength = 0
    moduleDir = ""
    return 1
}

@_cdecl("request")
public func request(
    _ req: UnsafeMutablePointer<CChar>?,
    _ res_len: UnsafeMutablePointer<Int64>?
) -> UnsafeMutablePointer<CChar>? {
    let reqText: String
    let reqLength = res_len?.pointee ?? 0
    if let req, reqLength > 0, reqLength <= Int64(Int.max) {
        let data = Data(bytes: req, count: Int(reqLength))
        reqText = String(data: data, encoding: .utf8) ?? ""
    } else {
        reqText = ""
    }
    if let req {
        free(req)
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
    Value0: \(value)\r
    \r
    """
    storeResponse(wire)
    res_len?.pointee = Int64(responseLength)
    guard let responseBuffer else { return nil }
    return responseBuffer
}
