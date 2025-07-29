// FMO全体の初期化と後始末をまとめる管理クラス。
// 実装方針は docs/About_FMO.md を参照。
import Foundation

/// FMO の初期化と後始末を司る管理クラス
final class FmoManager {
    /// 排他制御用の名前付きセマフォ
    let mutex: FmoMutex
    /// 共有メモリ領域のラッパー
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
    ///
    /// アプリケーション終了時に必ず呼び出してメモリリークを防ぐ
    func cleanup() {
        memory.close()
        mutex.close()
    }
}
