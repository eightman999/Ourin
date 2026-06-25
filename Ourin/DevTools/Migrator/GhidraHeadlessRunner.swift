import Foundation

/// Phase 2: Ghidra `analyzeHeadless` を外部プロセスとして起動するラッパー。
///
/// 計画「Ghidra 解析」節:
/// - Ghidra は Ourin に同梱しない。ユーザー指定の analyzeHeadless を呼び出す。
/// - プロジェクト作業領域は一時ディレクトリに作成する。
/// - 成果物は対象フォルダの `ourin/analysis/` に保存する。
/// - 進捗表示とキャンセルを可能にする。
///
/// 未信頼バイナリを扱うため、Ourin 本体プロセス内では実行しない（計画「注意点」）。
final class GhidraHeadlessRunner {
    struct Configuration {
        /// analyzeHeadless の絶対パス。
        let executableURL: URL
        /// postScript を格納したディレクトリ（Ghidra の -scriptPath）。
        let scriptDirectory: URL
        /// 一時プロジェクトを置くディレクトリ。
        let workDirectory: URL
        /// タイムアウト秒数。0 で無制限。
        let timeoutSeconds: TimeInterval

        init(executableURL: URL,
             scriptDirectory: URL,
             workDirectory: URL,
             timeoutSeconds: TimeInterval = 0) {
            self.executableURL = executableURL
            self.scriptDirectory = scriptDirectory
            self.workDirectory = workDirectory
            self.timeoutSeconds = timeoutSeconds
        }
    }

    /// 解析の進捗・結果を外部（UI）へ通知するためのコールバック群。
    struct Handlers {
        var onStdout: (String) -> Void
        var onStderr: (String) -> Void
        var onFinish: (Result) -> Void

        init(onStdout: @escaping (String) -> Void = { _ in },
             onStderr: @escaping (String) -> Void = { _ in },
             onFinish: @escaping (Result) -> Void = { _ in }) {
            self.onStdout = onStdout
            self.onStderr = onStderr
            self.onFinish = onFinish
        }
    }

    /// 解析結果。
    enum Result {
        case success(logURL: URL, durationSeconds: TimeInterval)
        case failure(message: String, durationSeconds: TimeInterval)
        case cancelled
    }

    private(set) var handlers: Handlers
    private(set) var configuration: Configuration
    private var process: Process?
    private let logger = CompatLogger(subsystem: "jp.ourin.devtools", category: "migrator.ghidra")

    /// stdout/stderr の蓄積用。readabilityHandler（非同期）から追記する。
    private var stdoutAccumulator = Data()
    private var stderrAccumulator = Data()
    private let accumulatorLock = NSLock()

    init(configuration: Configuration, handlers: Handlers = Handlers()) {
        self.configuration = configuration
        self.handlers = handlers
    }

    /// DecompileAll.java を配置済みのディレクトリを返す。
    ///
    /// 解決順序:
    /// 1. バンドル Resources（同梱ビルド時）
    /// 2. 埋め込み文字列から一時ディレクトリへ実体化（参考: 計画「Ghidra は Ourin に同梱しない」）
    static func resolveScript() -> URL? {
        if let url = Bundle.main.url(forResource: "DecompileAll", withExtension: "java") {
            return url.deletingLastPathComponent()
        }
        return materializeEmbeddedScript()
    }

    /// 埋め込みスクリプトを一時ディレクトリへ書き出し、そのディレクトリを返す。
    private static func materializeEmbeddedScript() -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinMigrator/ghidra_scripts", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("DecompileAll.java")
            // 既存かつ内容一致なら再書き出しを省略（best-effort）。
            let data = Data(GhidraScriptSource.decompileAll.utf8)
            if let existing = try? Data(contentsOf: url), existing == data {
                return dir
            }
            try data.write(to: url, options: [.atomic])
            return dir
        } catch {
            return nil
        }
    }

    /// 1 つのバイナリを headless 解析する。
    ///
    /// 成果物は outputDirectory 直下に以下の名前で出力される（DecompileAll.java 側と同期）:
    /// `decompiled.c`, `imports.json`, `exports.json`, `strings.txt`, `resources.txt`
    func analyze(binaryURL: URL, outputDirectory: URL) {
        let start = Date()
        let fm = FileManager.default

        // 成果物ディレクトリを準備（計画: ourin/analysis/）。
        do {
            try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            handlers.onFinish(.failure(message: "出力ディレクトリ作成失敗: \(error.localizedDescription)",
                                      durationSeconds: Date().timeIntervalSince(start)))
            return
        }

        // 一時プロジェクト領域。1 解析 = 1 プロジェクトで衝突を避ける。
        let projectName = "OurinMigrator_\(UUID().uuidString.prefix(8))"
        let projectDir = configuration.workDirectory
            .appendingPathComponent(String(projectName), isDirectory: true)
        do {
            try fm.createDirectory(at: configuration.workDirectory, withIntermediateDirectories: true)
            try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
        } catch {
            handlers.onFinish(.failure(message: "作業ディレクトリ作成失敗: \(error.localizedDescription)",
                                      durationSeconds: Date().timeIntervalSince(start)))
            return
        }

        guard let scriptDir = GhidraHeadlessRunner.resolveScript() else {
            handlers.onFinish(.failure(message: "DecompileAll.java が見つかりません",
                                      durationSeconds: Date().timeIntervalSince(start)))
            return
        }

        // DecompileAll.java が成果物を書き出すディレクトリを環境変数で渡す。
        let env = ProcessInfo.processInfo.environment.merging(
            ["OURIN_ANALYSIS_OUT": outputDirectory.path]
        ) { _, new in new }

        let proc = Process()
        proc.executableURL = configuration.executableURL
        proc.environment = env
        proc.currentDirectoryURL = projectDir
        proc.arguments = [
            projectDir.path,           // <project_location>
            String(projectName),       // <project_name>
            "-import", binaryURL.path,
            "-overwrite",
            "-scriptPath", scriptDir.path,
            "-postScript", "DecompileAll.java"
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        // キャンセル対応のため保持。
        process = proc
        resetAccumulators()

        attachReader(stdoutPipe.fileHandleForReading, isStdout: true)
        attachReader(stderrPipe.fileHandleForReading, isStdout: false)

        // 終了ハンドリング。
        proc.terminationHandler = { [weak self] p in
            guard let self = self else { return }
            let duration = Date().timeIntervalSince(start)

            // ログを保存。
            let logURL = outputDirectory.appendingPathComponent("ghidra.log")
            self.saveLog(into: logURL, process: p)

            if p.terminationStatus == 0 {
                self.logger.info("Ghidra analysis finished for \(binaryURL.lastPathComponent)")
                self.handlers.onFinish(.success(logURL: logURL, durationSeconds: duration))
            } else if p.terminationReason == .uncaughtSignal {
                self.logger.info("Ghidra analysis cancelled for \(binaryURL.lastPathComponent)")
                self.handlers.onFinish(.cancelled)
            } else {
                self.logger.warning("Ghidra analysis failed (status \(p.terminationStatus))")
                self.handlers.onFinish(.failure(
                    message: "analyzeHeadless 終了コード \(p.terminationStatus)",
                    durationSeconds: duration
                ))
            }
            // 一時プロジェクトを片付ける（best-effort）。
            try? fm.removeItem(at: projectDir)
        }

        do {
            try proc.run()
        } catch {
            handlers.onFinish(.failure(message: "analyzeHeadless 起動失敗: \(error.localizedDescription)",
                                      durationSeconds: Date().timeIntervalSince(start)))
        }

        // タイムアウト設定（0 は無効）。
        if configuration.timeoutSeconds > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + configuration.timeoutSeconds) { [weak self] in
                guard let self = self, let p = self.process, p.isRunning else { return }
                self.logger.warning("Ghidra analysis timed out, cancelling")
                self.cancel()
            }
        }
    }

    /// 実行中の解析をキャンセルする。
    func cancel() {
        process?.terminate()
    }

    // MARK: - Private

    private func resetAccumulators() {
        accumulatorLock.lock()
        stdoutAccumulator = Data()
        stderrAccumulator = Data()
        accumulatorLock.unlock()
    }

    /// Pipe の読み込みハンドラを取り付ける。受信データは蓄積しつつハンドラへ転送。
    private func attachReader(_ handle: FileHandle, isStdout: Bool) {
        handle.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            self?.append(data: data, isStdout: isStdout)
            if let text = String(data: data, encoding: .utf8) {
                if isStdout {
                    self?.handlers.onStdout(text)
                } else {
                    self?.handlers.onStderr(text)
                }
            }
        }
    }

    private func append(data: Data, isStdout: Bool) {
        accumulatorLock.lock()
        if isStdout {
            stdoutAccumulator.append(data)
        } else {
            stderrAccumulator.append(data)
        }
        accumulatorLock.unlock()
    }

    /// ログを保存する（stdout/stderr を結合）。
    private func saveLog(into url: URL, process: Process) {
        accumulatorLock.lock()
        let out = stdoutAccumulator
        let err = stderrAccumulator
        accumulatorLock.unlock()

        var combined = "Ghidra analyzeHeadless exit=\(process.terminationStatus) reason=\(process.terminationReason.rawValue)\n\n"
        combined += "===== stdout =====\n"
        combined += String(data: out, encoding: .utf8) ?? ""
        combined += "\n===== stderr =====\n"
        combined += String(data: err, encoding: .utf8) ?? ""
        combined += "\n"
        try? combined.data(using: .utf8)?.write(to: url, options: [.atomic])
    }
}
