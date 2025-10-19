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
    private var sem: UnsafeMutablePointer<sem_t>?
    /// このインスタンスがセマフォを作成したか (cleanup時にunlinkするため)
    private let isCreator: Bool

    /// 新規セマフォを作成する。既に存在すればエラーを投げる
    init(name: String, createNew: Bool = true) throws {
        self.name = name

        if createNew {
            // 新規作成モード: O_CREAT | O_EXCL で排他的に作成
            NSLog("Creating new semaphore '%@'", name)
            sem = fmo_sem_open(name, O_CREAT | O_EXCL, 0o666, 1)
            if sem == nil {
                if errno == EEXIST {
                    throw FmoError.alreadyRunning
                } else {
                    throw FmoError.systemError(String(cString: strerror(errno)))
                }
            }
            isCreator = true
        } else {
            // 既存オープンモード: O_CREAT なしで開く
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
            // 作成者のみがunlinkする
            if isCreator {
                fmo_sem_unlink(name)
            }
            sem = nil
        }
    }
}
