// POSIX名前付きセマフォをSwiftオブジェクトとして扱うクラス
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

final class FmoMutex {
    private let name: String
    private var sem: OpaquePointer?

    init(name: String) throws {
        self.name = name
        sem = fmo_sem_open(name, O_CREAT | O_EXCL, 0o666, 1)
        if sem == nil {
            if errno == EEXIST {
                throw FmoError.alreadyRunning
            } else {
                throw FmoError.systemError(String(cString: strerror(errno)))
            }
        }
    }

    /// セマフォを獲得する。失敗時は例外を投げる。
    func lock() throws {
        if fmo_sem_wait(sem) == -1 {
            throw FmoError.systemError("sem_wait failed")
        }
    }

    /// セマフォを解放する。
    func unlock() {
        _ = fmo_sem_post(sem)
    }

    /// セマフォをクローズし、名前付きセマフォを削除する。
    func close() {
        if let s = sem {
            fmo_sem_close(s)
            fmo_sem_unlink(name)
            sem = nil
        }
    }
}
