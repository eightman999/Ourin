// FMO全体の初期化と後始末をまとめる管理クラス
import Foundation

final class FmoManager {
    let mutex: FmoMutex
    let memory: FmoSharedMemory

    /// 共有メモリとセマフォを初期化する
    ///
    /// 初期化時に使用するリソース名をログに出力しておくことで、
    /// サンドボックス環境などでのパスのずれや権限不足を調査しやすくする。
    init(mutexName: String = "/ssp_mutex", sharedName: String = "/ssp_fmo") throws {
        NSLog("FMO initializing: mutex=%@ shared=%@", mutexName, sharedName)
        mutex = try FmoMutex(name: mutexName)
        memory = try FmoSharedMemory(name: sharedName)
    }

    /// 使用したリソースを解放する
    func cleanup() {
        memory.close()
        mutex.close()
    }
}
