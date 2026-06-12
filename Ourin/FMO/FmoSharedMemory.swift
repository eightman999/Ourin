// 共有メモリ領域を扱うSwiftラッパー。64KBを確保し先頭にサイズを書き込む。
// プロセス生存中は共有メモリ名を保持し、外部プロセスからアタッチ可能にする。
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// POSIX 共有メモリを扱うためのラッパークラス
final class FmoSharedMemory {
    /// 共有メモリ名
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
    ///
    /// `createNew: true` の場合、既にクラッシュ等で残った共有メモリがあっても
    /// O_CREAT で安全に上書き・初期化する。名前はプロセス生存中は保持される。
    init(name: String, size: Int = 64 * 1024, createNew: Bool = true) throws {
        self.name = name
        self.size = size

        let fdTemp: Int32
        if createNew {
            NSLog("Creating shared memory '%@' (%d bytes)", name, size)
            fdTemp = fmo_open_shared(name, size)
            if fdTemp == -1 {
                throw FmoError.systemError(String(cString: strerror(errno)))
            }
            isCreator = true
        } else {
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
        if isCreator {
            fmo_shm_unlink(name)
        }
    }
}
