// FMO全体の初期化と後始末をまとめる管理クラス。
// SSP風レコード形式でゴースト情報を共有メモリに公開する。
import Foundation

/// FMO に書き込む1ゴースト分のレコード情報
struct FmoGhostRecord {
    var name: String = ""
    var keroname: String = ""
    var path: String = ""
    // shell / balloon は Ourin 独自拡張（標準 SSP FMO には無いキー）
    var shell: String = "master"
    var balloon: String = ""
    var sakuraSurface: Int = 0
    var keroSurface: Int = 10

    // 標準 SSP/UKADOC FMO フィールド（他ゴーストが識別・通信に使う）
    /// \1（sakura）ウィンドウの安定・一意・非ゼロな識別子（NSWindow.windowNumber 由来、不可なら安定ハッシュ）
    var hwnd: Int = 0
    /// \1（kero）ウィンドウの安定・一意・非ゼロな識別子
    var kerohwnd: Int = 0
    /// このゴーストの全ウィンドウ識別子のカンマ区切りリスト（sakura, kero, ...）
    var hwndList: String = ""
    /// ゴーストのフルネーム（descript の name）
    var fullname: String = ""
    /// descript のゴースト名（ディレクトリ／descript 名）
    var ghostname: String = ""
    /// ゴーストのインストールパス
    var ghostpath: String = ""
    /// モジュール状態（例: "running"）
    var moduleState: String = "running"
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

    /// クラッシュや強制終了で残った FMO リソースを削除する。
    @discardableResult
    static func reclaimStaleResources(
        mutexName: String = defaultMutexName,
        sharedName: String = defaultSharedName
    ) -> Bool {
        let shmResult = fmo_shm_unlink(sharedName)
        let shmErrno = errno
        let semResult = fmo_sem_unlink(mutexName)
        let semErrno = errno

        let shmOK = shmResult == 0 || shmErrno == ENOENT
        let semOK = semResult == 0 || semErrno == ENOENT

        if !shmOK {
            NSLog("Failed to reclaim stale FMO shared memory '%@': %@", sharedName, String(cString: strerror(shmErrno)))
        }
        if !semOK {
            NSLog("Failed to reclaim stale FMO semaphore '%@': %@", mutexName, String(cString: strerror(semErrno)))
        }
        if shmOK || semOK {
            NSLog("Reclaimed stale FMO resources: mutex=%@ shared=%@", mutexName, sharedName)
        }

        return shmOK && semOK
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
    /// 形式: `(id).(key)\x01(value)\r\n`（SOH 区切り、CRLF 終端、UTF-8）。
    /// レコード ID（先頭の `(id).`）は配列インデックスだが、hwnd の値は
    /// レコード固有の安定・一意・非ゼロな識別子を出力する。
    static func buildSnapshot(records: [FmoGhostRecord]) -> String {
        var lines: [String] = []
        for (index, record) in records.enumerated() {
            let id = String(index)
            // 標準 SSP/UKADOC FMO キー
            lines.append("\(id).name\u{01}\(record.name)\r\n")
            lines.append("\(id).keroname\u{01}\(record.keroname)\r\n")
            lines.append("\(id).fullname\u{01}\(record.fullname)\r\n")
            lines.append("\(id).ghostname\u{01}\(record.ghostname)\r\n")
            lines.append("\(id).path\u{01}\(record.path)\r\n")
            lines.append("\(id).ghostpath\u{01}\(record.ghostpath)\r\n")
            lines.append("\(id).sakura.surface\u{01}\(record.sakuraSurface)\r\n")
            lines.append("\(id).kero.surface\u{01}\(record.keroSurface)\r\n")
            lines.append("\(id).hwnd\u{01}\(record.hwnd)\r\n")
            lines.append("\(id).kerohwnd\u{01}\(record.kerohwnd)\r\n")
            lines.append("\(id).hwndlist\u{01}\(record.hwndList)\r\n")
            lines.append("\(id).module.state\u{01}\(record.moduleState)\r\n")
            // Ourin 独自拡張キー（標準 SSP FMO には無い）
            lines.append("\(id).shell\u{01}\(record.shell)\r\n")
            lines.append("\(id).balloon\u{01}\(record.balloon)\r\n")
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
