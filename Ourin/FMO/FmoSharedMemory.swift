// 共有メモリ領域を扱うSwiftラッパー。64KBを確保し先頭にサイズを書き込む。
// FMO の詳細は docs/About_FMO.md を参照。
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// POSIX 共有メモリを扱うためのラッパークラス
final class FmoSharedMemory {
    /// 共有メモリ名（作成後すぐに unlink する）
    private let name: String
    /// 確保するバイト数
    private let size: Int
    /// マッピングしたポインタ
    private var ptr: UnsafeMutableRawPointer
    /// ファイルディスクリプタ
    private let fd: Int32
    /// このインスタンスが共有メモリを作成したか
    private let isCreator: Bool

    /// 新規共有メモリ領域を確保してマッピングする、または既存のものを開く
    init(name: String, size: Int = 64 * 1024, createNew: Bool = true) throws {
        self.name = name
        self.size = size

        let fdTemp: Int32
        if createNew {
            // 新規作成モード
            NSLog("Creating new shared memory '%@' (%d bytes)", name, size)
            fdTemp = fmo_open_shared(name, size)
            if fdTemp == -1 {
                throw FmoError.systemError(String(cString: strerror(errno)))
            }
            // エフェメラルに運用するため作成直後に名前を削除
            _ = fmo_shm_unlink(name)
            isCreator = true
        } else {
            // 既存オープンモード
            NSLog("Opening existing shared memory '%@'", name)
            fdTemp = fmo_open_existing_shared(name)
            if fdTemp == -1 {
                throw FmoError.systemError(String(cString: strerror(errno)))
            }
            isCreator = false
        }

        fd = Int32(fdTemp)
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
        // 作成者のみがunlinkする (ただしエフェメラルモードでは作成直後に既にunlink済み)
        if isCreator {
            fmo_shm_unlink(name)
        }
    }
}
