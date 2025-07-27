import Foundation

// MARK: - SHIORI/3.0M エントリポイント

@_cdecl("shiori_load")
/// プラグイン初期化。`dir_utf8` はプラグインディレクトリの UTF-8 文字列
public func shiori_load(_ dir_utf8: UnsafePointer<CChar>?) -> Bool {
    // 今回は特に初期化を行わない
    return true
}

@_cdecl("shiori_unload")
/// プラグイン終了処理
public func shiori_unload() {
}

@_cdecl("shiori_request")
/// リクエスト処理。
/// `req` と `req_len` にはリクエストのワイヤ形式が渡される。
/// `res` と `res_len` に応答の UTF-8 文字列を返す。
public func shiori_request(
    _ req: UnsafePointer<UInt8>?,
    _ req_len: Int,
    _ res: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    _ res_len: UnsafeMutablePointer<Int>?
) -> Bool {
    // 固定の応答を返す簡易実装
    let response = """
SHIORI/3.0 200 OK\r
Charset: UTF-8\r
Value: \\h\\s0Hello from Swift SHIORI\r\n\r\n
"""
    let bytes = Array(response.utf8)
    let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
    ptr.initialize(from: bytes, count: bytes.count)
    res?.pointee = ptr
    res_len?.pointee = bytes.count
    return true
}

@_cdecl("shiori_free")
/// `shiori_request` で確保したバッファを解放する
public func shiori_free(_ p: UnsafeMutablePointer<UInt8>?) {
    p?.deallocate()
}
