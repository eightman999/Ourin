// FMO全体の初期化と後始末をまとめる管理クラス。
// SSP風レコード形式でゴースト情報を共有メモリに公開する。
import Foundation

/// FMO に書き込む1ゴースト分のレコード情報
struct FmoGhostRecord {
    var name: String = ""
    var keroname: String = ""
    var path: String = ""
    var shell: String = "master"
    var balloon: String = ""
    var sakuraSurface: Int = 0
    var keroSurface: Int = 10
}

/// FMO の初期化・スナップショット生成・後始末を司る管理クラス
final class FmoManager {
    static let defaultSharedName = "/ourin_fmo"
    static let defaultMutexName = "/ourin_fmo_mutex"

    let mutex: FmoMutex
    let memory: FmoSharedMemory

    /// 他のベースウェアインスタンスが起動しているかを判定する
    static func isAnotherInstanceRunning(sharedName: String = defaultSharedName) -> Bool {
        let result = fmo_check_running(sharedName)
        if result == 1 {
            NSLog("Another baseware instance detected via FMO '%@'", sharedName)
            return true
        } else if result == 0 {
            NSLog("No other baseware instance detected (FMO '%@' does not exist)", sharedName)
            return false
        } else {
            let errorMsg = String(cString: strerror(errno))
            NSLog("FMO check error for '%@': %@", sharedName, errorMsg)
            return false
        }
    }

    /// 共有メモリとセマフォを初期化する
    init(mutexName: String = defaultMutexName, sharedName: String = defaultSharedName) throws {
        NSLog("FMO initializing: mutex=%@ shared=%@", mutexName, sharedName)
        mutex = try FmoMutex(name: mutexName)
        memory = try FmoSharedMemory(name: sharedName)
    }

    // MARK: - SSP-style FMO snapshot

    /// SSP風レコード形式のFMOスナップショットを生成する。
    /// POSIX共有メモリへの書き込みと SSTP EXECUTE GetFMO の応答は
    /// ともにこの関数の出力を使う。
    ///
    /// 形式: `(id).(key)\x01(value)\r\n`
    /// hwnd はmacOSでは意味を持たないため 0 を返す。
    static func buildSnapshot(records: [FmoGhostRecord]) -> String {
        var lines: [String] = []
        for (index, record) in records.enumerated() {
            let id = String(index)
            lines.append("\(id).name\u{01}\(record.name)\r\n")
            lines.append("\(id).keroname\u{01}\(record.keroname)\r\n")
            lines.append("\(id).path\u{01}\(record.path)\r\n")
            lines.append("\(id).shell\u{01}\(record.shell)\r\n")
            lines.append("\(id).balloon\u{01}\(record.balloon)\r\n")
            lines.append("\(id).sakura.surface\u{01}\(record.sakuraSurface)\r\n")
            lines.append("\(id).kero.surface\u{01}\(record.keroSurface)\r\n")
            lines.append("\(id).hwnd\u{01}0\r\n")
        }
        return lines.joined()
    }

    /// 共有メモリにスナップショットを書き込む
    func writeSnapshot(records: [FmoGhostRecord]) {
        let snapshot = Self.buildSnapshot(records: records)
        guard let data = snapshot.data(using: .utf8) else { return }
        do {
            try memory.write(data, mutex: mutex)
        } catch {
            NSLog("FMO writeSnapshot failed: %@", String(describing: error))
        }
    }

    /// 使用したリソースを解放する
    func cleanup() {
        writeSnapshot(records: [])
        memory.close()
        mutex.close()
    }
}
