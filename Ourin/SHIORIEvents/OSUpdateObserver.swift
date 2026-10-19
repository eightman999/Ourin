import Foundation

/// `softwareupdate --history` の1行に対応する、実際にインストール済みの更新履歴。
/// `softwareupdate` は失敗履歴を返さないため、ここに入る項目は成功済み更新として扱う。
struct OSUpdateHistoryRecord: Equatable, Hashable {
    let title: String
    let version: String
    let executedAt: Date
    let status: String
    let errorCode: String

    var wireValue: String {
        [status, errorCode, OSUpdateObserver.wireDate(executedAt), title]
            .joined(separator: "\u{01}")
    }
}

/// OnOSUpdateInfo に必要な時刻と履歴のスナップショット。
struct OSUpdateSnapshot: Equatable {
    let checkedAt: Date?
    let history: [OSUpdateHistoryRecord]

    var executedAt: Date? { history.first?.executedAt }

    var historyFingerprint: [OSUpdateHistoryRecord] { history }
}

/// `softwareupdate` の実コマンド結果。テストでは同じ境界へ固定入力を注入する。
struct OSUpdateCommandResult: Equatable {
    let status: Int32
    let stdout: String
    let stderr: String
}

/// macOS の Software Update 履歴を読み、OnOSUpdateInfo を起動時・履歴更新時に発火する。
///
/// Apple が公開する常駐更新通知 APIへ依存せず、macOS標準の
/// `/usr/sbin/softwareupdate` が返す実データを定期的に再読込する。`--list` の完了時刻を
/// 「確認日時」、`--history` の最新履歴を「実行日時・履歴」として保持する。
final class OSUpdateObserver {
    static let shared = OSUpdateObserver()

    typealias CommandRunner = ([String]) -> OSUpdateCommandResult

    private static let checkedAtKey = "OurinOSUpdateLastCheckDate"
    private static let pollInterval: TimeInterval = 300

    private let defaults: UserDefaults
    private let commandRunner: CommandRunner
    private var timer: DispatchSourceTimer?
    private var handler: ((ShioriEvent) -> Void)?
    private var currentSnapshot: OSUpdateSnapshot?
    private var generation = UUID()

    init(defaults: UserDefaults = .standard,
         commandRunner: @escaping CommandRunner = OSUpdateObserver.runSoftwareUpdate) {
        self.defaults = defaults
        self.commandRunner = commandRunner
    }

    func start(_ handler: @escaping (ShioriEvent) -> Void) {
        stop()
        self.handler = handler
        let token = UUID()
        generation = token

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(
            deadline: .now() + Self.pollInterval,
            repeating: Self.pollInterval,
            leeway: .seconds(10)
        )
        timer.setEventHandler { [weak self] in
            self?.refresh(generation: token)
        }
        timer.resume()
        self.timer = timer

        // 起動時イベントは、実際の --list/--history の結果を得てから発火する。
        refresh(generation: token)
    }

    func stop() {
        timer?.cancel()
        timer = nil
        generation = UUID()
        handler = nil
        currentSnapshot = nil
    }

    /// 監視中のスナップショットを即時再読込する。更新コマンド完了後の回帰検証にも使う。
    func refreshNow() {
        guard handler != nil else { return }
        refresh(generation: generation)
    }

    private func refresh(generation token: UUID) {
        let runner = commandRunner
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let snapshot = self.readSnapshot(using: runner)
            DispatchQueue.main.async {
                guard self.generation == token else { return }
                self.consume(snapshot)
            }
        }
    }

    private func readSnapshot(using runner: CommandRunner) -> OSUpdateSnapshot {
        let historyResult = runner(["--history"])
        let history = Self.parseHistory(historyResult.stdout)

        var checkedAt = defaults.object(forKey: Self.checkedAtKey)
            .flatMap { value -> Date? in
                guard let seconds = value as? TimeInterval else { return nil }
                return Date(timeIntervalSince1970: seconds)
            }

        let checkResult = runner(["--list"])
        if checkResult.status == 0 {
            let now = Date()
            checkedAt = now
            defaults.set(now.timeIntervalSince1970, forKey: Self.checkedAtKey)
        }

        return OSUpdateSnapshot(checkedAt: checkedAt, history: history)
    }

    private func consume(_ snapshot: OSUpdateSnapshot) {
        let initial = currentSnapshot == nil
        let historyChanged = currentSnapshot?.historyFingerprint != snapshot.historyFingerprint
        currentSnapshot = snapshot

        // 起動時は NOTIFY、実際に履歴が増減した場合だけ更新 GET。
        guard initial || historyChanged else { return }
        handler?(Self.event(for: snapshot, initial: initial))
    }

    /// スナップショットから wire 上の Reference0..N を構成する純粋な変換。
    static func event(for snapshot: OSUpdateSnapshot, initial: Bool) -> ShioriEvent {
        var params: [String: String] = [
            "Reference0": wireDate(snapshot.checkedAt),
            "Reference1": wireDate(snapshot.executedAt)
        ]
        for (index, record) in snapshot.history.enumerated() {
            params["Reference\(index + 2)"] = record.wireValue
        }
        return ShioriEvent(
            id: .OnOSUpdateInfo,
            params: params,
            delivery: initial ? .notify : .get,
            ignoreResponseScript: initial
        )
    }

    /// `年,月,日,時,分,秒` のローカル時刻表現（UKADOC準拠）。
    static func wireDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let hour = components.hour,
              let minute = components.minute,
              let second = components.second else { return "" }
        return "\(year),\(month),\(day),\(hour),\(minute),\(second)"
    }

    /// `softwareupdate --history` の表形式出力を実データへ変換する。
    static func parseHistory(_ output: String) -> [OSUpdateHistoryRecord] {
        let parsed = output.split(whereSeparator: \.isNewline).compactMap { rawLine -> OSUpdateHistoryRecord? in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("Display Name"), !line.allSatisfy({ $0 == "-" || $0 == " " }) else {
                return nil
            }
            let columns = line.split { $0 == " " || $0 == "\t" }.map(String.init)
            guard columns.count >= 4 else { return nil }
            let dateString = "\(columns[columns.count - 2]) \(columns[columns.count - 1])"
            guard let date = parseDate(dateString) else { return nil }
            let version = columns[columns.count - 3]
            let title = columns.dropLast(3).joined(separator: " ")
            guard !title.isEmpty else { return nil }
            return OSUpdateHistoryRecord(
                title: title,
                version: version,
                executedAt: date,
                status: "success",
                errorCode: "0"
            )
        }
        return parsed.sorted { $0.executedAt > $1.executedAt }
    }

    private static func parseDate(_ value: String) -> Date? {
        for format in ["yyyy/MM/dd H:mm:ss", "yyyy/MM/dd HH:mm:ss", "yyyy-MM-dd H:mm:ss", "yyyy-MM-dd HH:mm:ss"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func runSoftwareUpdate(arguments: [String]) -> OSUpdateCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return OSUpdateCommandResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(30)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return OSUpdateCommandResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
