// FMO全体の初期化と後始末をまとめる管理クラス。
// SSP風レコード形式でゴースト情報を共有メモリに公開する。
import Foundation

/// FMO に書き込む1ゴースト分のレコード情報
struct FmoGhostRecord {
    /// FMOレコードの32文字一意ID。空の場合だけ旧呼び出し互換で配列indexを使用する。
    var id: String = ""
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
    /// UKADOC `modulestate` の値。
    /// 例: `shiori:running,makoto-ghost:running,makoto-shell:running`
    var moduleState: String = ""
}

/// UKADOC FMO `modulestate` を安定した順序で構築する。
struct FmoModuleState: Equatable {
    enum Health: String, Equatable {
        case running
        case critical
    }

    var shiori: Health?
    var ghostMakoto: Health?
    var shellMakoto: Health?
    var compatible: Health?

    var value: String {
        [
            shiori.map { "shiori:\($0.rawValue)" },
            ghostMakoto.map { "makoto-ghost:\($0.rawValue)" },
            shellMakoto.map { "makoto-shell:\($0.rawValue)" },
            compatible.map { "compatible:\($0.rawValue)" }
        ].compactMap { $0 }.joined(separator: ",")
    }
}

/// SSP 互換 FMO テキストを構造化して読むためのビュー。
///
/// Ourin の POSIX 共有メモリ実体は Windows の FileMapping 互換ではないため、
/// 外部連携やテストでは `FmoManager.buildSnapshot(records:)` が返す
/// `id.key SOH value CRLF` の互換ビューを基準に扱う。
struct FmoCompatibilityEntry: Equatable {
    let id: String
    let fields: [String: String]

    subscript(key: String) -> String? {
        fields[key]
    }
}

struct FmoCompatibilityView: Equatable {
    let entries: [FmoCompatibilityEntry]

    var isEmpty: Bool {
        entries.isEmpty
    }

    func entry(id: String) -> FmoCompatibilityEntry? {
        entries.first { $0.id == id }
    }

    func value(id: String, key: String) -> String? {
        entry(id: id)?[key]
    }

    /// 旧テスト・呼び出しの段階移行用。
    func entry(id: Int) -> FmoCompatibilityEntry? { entry(id: String(id)) }
    func value(id: Int, key: String) -> String? { value(id: String(id), key: key) }

    static func parse(_ snapshot: String) -> FmoCompatibilityView {
        var fieldsByID: [String: [String: String]] = [:]

        for line in snapshot.components(separatedBy: "\r\n") where !line.isEmpty {
            let pair = line.split(separator: "\u{01}", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }

            let keyPart = String(pair[0])
            guard let dot = keyPart.firstIndex(of: ".") else {
                continue
            }
            let id = String(keyPart[..<dot])
            guard !id.isEmpty else { continue }

            let fieldStart = keyPart.index(after: dot)
            guard fieldStart < keyPart.endIndex else { continue }
            let fieldName = String(keyPart[fieldStart...])
            fieldsByID[id, default: [:]][fieldName] = String(pair[1])
        }

        return FmoCompatibilityView(
            entries: fieldsByID.keys.sorted().map { id in
                FmoCompatibilityEntry(id: id, fields: fieldsByID[id] ?? [:])
            }
        )
    }
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
    /// 形式: `id.key\x01value\r\n`（SOH 区切り、CRLF 終端、UTF-8）。
    /// レコード ID（先頭の `id.`）は配列インデックスだが、hwnd の値は
    /// レコード固有の安定・一意・非ゼロな識別子を出力する。
    static func buildSnapshot(records: [FmoGhostRecord]) -> String {
        var lines: [String] = []
        for (index, record) in records.enumerated() {
            let id = validRecordID(record.id) ?? String(index)
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
            lines.append("\(id).modulestate\u{01}\(record.moduleState)\r\n")
            // Ourin 独自拡張キー（標準 SSP FMO には無い）
            lines.append("\(id).shell\u{01}\(record.shell)\r\n")
            lines.append("\(id).balloon\u{01}\(record.balloon)\r\n")
        }
        return lines.joined()
    }

    private static func validRecordID(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("."),
              !trimmed.contains("\u{01}"),
              !trimmed.contains("\r"),
              !trimmed.contains("\n") else { return nil }
        return trimmed
    }

    /// 互換テキストを構造化ビューとして返す。
    ///
    /// `writeSnapshot(records:)` と `EXECUTE GetFMO` は従来どおり文字列を返す。
    /// この API はテスト、診断 UI、macOS 側ブリッジで同じ内容を安全に再利用するための補助ビュー。
    static func buildCompatibilityView(records: [FmoGhostRecord]) -> FmoCompatibilityView {
        FmoCompatibilityView.parse(buildSnapshot(records: records))
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
