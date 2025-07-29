// POSIX名前付きセマフォをSwiftオブジェクトとして扱うクラス。
// FMO の詳細は docs/About_FMO.md を参照。
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// 名前付きセマフォをラップしたミューテックス
final class FmoMutex {
    /// セマフォの識別名
    private let name: String
    /// POSIX セマフォの実体ポインタ
    private var sem: UnsafeMutablePointer<sem_t>?  // ← 型を変更

    /// 新規セマフォを作成する。既に存在すればエラーを投げる
    init(name: String) throws {
        self.name = name
        NSLog("Opening semaphore '%@'", name)
        sem = fmo_sem_open(name, O_CREAT | O_EXCL, 0o666, 1)
        if sem == nil {
            if errno == EEXIST {
                throw FmoError.alreadyRunning
            } else {
                throw FmoError.systemError(String(cString: strerror(errno)))
            }
        }
    }

    /// セマフォを待機しロックを取得する
    func lock() throws {
        if fmo_sem_wait(sem) == -1 {
            throw FmoError.systemError("sem_wait failed")
        }
    }

    /// ロックを解放する
    func unlock() {
        _ = fmo_sem_post(sem)
    }

    /// セマフォを閉じてリソースを解放する
    func close() {
        if let s = sem {
            fmo_sem_close(s)
            fmo_sem_unlink(name)
            sem = nil
        }
    }
}
