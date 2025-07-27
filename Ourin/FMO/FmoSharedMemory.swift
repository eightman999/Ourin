// 共有メモリ領域を扱うSwiftラッパー。64KBを確保し先頭にサイズを書き込む
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

final class FmoSharedMemory {
    private let name: String
    private let size: Int
    private var ptr: UnsafeMutableRawPointer
    private let fd: Int32

    init(name: String, size: Int = 64 * 1024) throws {
        self.name = name
        self.size = size
        NSLog("Opening shared memory '%@' (%d bytes)", name, size)
        let fdTemp = fmo_open_shared(name, size)
        if fdTemp == -1 {
            throw FmoError.systemError(String(cString: strerror(errno)))
        }
        fd = Int32(fdTemp)
        // エフェメラルに運用するため作成直後に名前を削除
        _ = fmo_shm_unlink(name)
        guard let p = fmo_map(fdTemp, size) else {
            fmo_close_fd(fdTemp)
            throw FmoError.systemError("mmap failed")
        }
        ptr = p
    }

    /// 共有メモリの生ポインタへのアクセスを提供する
    var pointer: UnsafeMutableRawPointer { ptr }

    /// mutexで保護しながらデータを書き込む
    func write(_ data: Data, mutex: FmoMutex) throws {
        try mutex.lock()
        defer { mutex.unlock() }
        let len = min(data.count, size - 5)
        data.withUnsafeBytes { bytes in
            ptr.storeBytes(of: UInt32(len), as: UInt32.self)
            memcpy(ptr.advanced(by: 4), bytes.baseAddress, len)
            ptr.advanced(by: 4 + len).storeBytes(of: UInt8(0), as: UInt8.self)
        }
    }

    /// mutexで保護しながらデータを読み出す
    func read(mutex: FmoMutex) throws -> Data {
        try mutex.lock()
        defer { mutex.unlock() }
        let len = ptr.load(as: UInt32.self)
        return Data(bytes: ptr.advanced(by: 4), count: Int(len))
    }

    /// マップ解除と共有メモリの削除を行う
    func close() {
        fmo_munmap(ptr, size)
        fmo_close_fd(fd)
        fmo_shm_unlink(name)
    }
}
