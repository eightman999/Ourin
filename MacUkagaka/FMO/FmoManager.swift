// FMO全体の初期化と後始末をまとめる管理クラス
import Foundation

final class FmoManager {
    let mutex: FmoMutex
    let memory: FmoSharedMemory

    /// 共有メモリとセマフォを初期化する
    init(mutexName: String = "/ssp_mutex", sharedName: String = "/ssp_fmo") throws {
        mutex = try FmoMutex(name: mutexName)
        memory = try FmoSharedMemory(name: sharedName)
    }

    /// 使用したリソースを解放する
    func cleanup() {
        memory.close()
        mutex.close()
    }
}
