// FMO全体の初期化と後始末をまとめる管理クラス。
// 実装方針は docs/About_FMO.md を参照。
import Foundation

/// FMO の初期化と後始末を司る管理クラス
final class FmoManager {
    /// 排他制御用の名前付きセマフォ
    let mutex: FmoMutex
    /// 共有メモリ領域のラッパー
    let memory: FmoSharedMemory

    /// 他のベースウェアインスタンスが起動しているかを判定する (ninix仕様準拠)
    ///
    /// - Parameter sharedName: 共有メモリ名 (デフォルト: "/ninix")
    /// - Returns: 起動中なら true、起動していなければ false
    /// - Note: ninix仕様では shm_open(name, O_RDWR, 0) が成功するかで判定
    static func isAnotherInstanceRunning(sharedName: String = "/ninix") -> Bool {
        let result = fmo_check_running(sharedName)
        if result == 1 {
            NSLog("Another baseware instance detected via FMO '%@'", sharedName)
            return true
        } else if result == 0 {
            NSLog("No other baseware instance detected (FMO '%@' does not exist)", sharedName)
            return false
        } else {
            // エラーの場合は errno を確認してログ出力
            let errorMsg = String(cString: strerror(errno))
            NSLog("FMO check error for '%@': %@", sharedName, errorMsg)
            return false
        }
    }

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
