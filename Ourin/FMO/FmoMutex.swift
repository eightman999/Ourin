// POSIX名前付きセマフォをSwiftオブジェクトとして扱うクラス。
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
    private var sem: UnsafeMutablePointer<sem_t>?
    /// このインスタンスがセマフォを作成したか (cleanup時にunlinkするため)
    private let isCreator: Bool

    /// セマフォを作成する。
    /// クラッシュ後に残ったセマフォがあれば自動的に上書き再作成する。
    init(name: String, createNew: Bool = true) throws {
        self.name = name

        if createNew {
            NSLog("Creating semaphore '%@'", name)
            sem = fmo_sem_open(name, O_CREAT | O_EXCL, 0o666, 1)
            if sem == nil {
                if errno == EEXIST {
                    // クラッシュ後に残った古いセマフォ → unlink して再作成
                    NSLog("Stale semaphore '%@' found, reclaiming", name)
                    fmo_sem_unlink(name)
                    sem = fmo_sem_open(name, O_CREAT | O_EXCL, 0o666, 1)
                    if sem == nil {
                        throw FmoError.systemError(String(cString: strerror(errno)))
                    }
                } else {
                    throw FmoError.systemError(String(cString: strerror(errno)))
                }
            }
            isCreator = true
        } else {
            NSLog("Opening existing semaphore '%@'", name)
            sem = fmo_sem_open(name, 0, 0, 0)
            if sem == nil {
                throw FmoError.systemError(String(cString: strerror(errno)))
            }
            isCreator = false
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
            if isCreator {
                fmo_sem_unlink(name)
            }
            sem = nil
        }
    }
}
