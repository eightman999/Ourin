import Foundation

/// Phase 2/3: Ghidra 解析とレポート生成を統合するオーケストレータ。
///
/// 計画「Phase 2: 解析」「Phase 3: レポート生成」を束ねる。
/// GhidraRunner を起動し、終了後に report.md と ourin.json の更新を行う。
///
/// 計画「Ghidra 解析は時間がかかるため、DevTools 上で進捗表示とキャンセルを可能にする」
/// を踏まえ、進捗コールバックとキャンセルを提供する。
final class LegacyBinaryAnalyzer {
    /// 解析の進捗イベント。
    enum Progress {
        case started(binaryName: String)
        case stdout(String)
        case stderr(String)
        case finishedAnalysis(durationSeconds: TimeInterval)
        case failed(String)
        case cancelled
    }

    private var runner: GhidraHeadlessRunner?
    private let logger = CompatLogger(subsystem: "jp.ourin.devtools", category: "migrator.analyzer")

    /// 既定の Ghidra パス候補。計画「Ghidra の既定候補」節。
    static let defaultGhidraCandidates: [String] = [
        "/Users/eightman/Downloads/ghidra_12.0.4_PUBLIC/support/analyzeHeadless"
    ]

    /// 与えられたパスから analyzeHeadless として使える最初の候補を返す。
    static func resolveGhidra(from candidates: [String]) -> URL? {
        for path in candidates {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// 1 件の asset を解析する。
    ///
    /// - Parameters:
    ///   - asset: 解析対象。
    ///   - ghidraURL: analyzeHeadless の絶対パス。
    ///   - progress: 進捗通知。
    ///   - completion: 全工程（解析 + report.md + ourin.json 更新）完了時に呼ばれる。
    ///     成功時は更新後の asset を返す。
    func analyze(asset: LegacyAssetScanner.Asset,
                 ghidraURL: URL,
                 progress: @escaping (Progress) -> Void,
                 completion: @escaping (Result<LegacyAssetScanner.Asset, Error>) -> Void) {
        guard let binaryURL = asset.binaryURL else {
            let err = NSError(domain: "OurinMigrator", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "バイナリが存在しません"])
            completion(.failure(err))
            return
        }

        let analysisDir = asset.directoryURL.appendingPathComponent("ourin/analysis", isDirectory: true)
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinMigrator", isDirectory: true)

        let scriptDir: URL
        if let dir = GhidraHeadlessRunner.resolveScript() {
            scriptDir = dir
        } else {
            // フォールバック: スクリプトが見つからなくても進め、Ghidra 側でエラーにする。
            scriptDir = workDir
        }

        let config = GhidraHeadlessRunner.Configuration(
            executableURL: ghidraURL,
            scriptDirectory: scriptDir,
            workDirectory: workDir
        )
        let handlers = GhidraHeadlessRunner.Handlers(
            onStdout: { progress(.stdout($0)) },
            onStderr: { progress(.stderr($0)) },
            onFinish: { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(_, let duration):
                    progress(.finishedAnalysis(durationSeconds: duration))
                    self.finalizeReport(asset: asset, analysisDir: analysisDir, duration: duration)
                    let updated = self.updatedAsset(asset: asset, analysisDir: analysisDir)
                    completion(.success(updated))
                case .failure(let msg, _):
                    progress(.failed(msg))
                    // 失敗時も成果物が部分的にあればレポートは出す。
                    self.finalizeReport(asset: asset, analysisDir: analysisDir, duration: nil)
                    completion(.failure(NSError(domain: "OurinMigrator", code: 2,
                                                userInfo: [NSLocalizedDescriptionKey: msg])))
                case .cancelled:
                    progress(.cancelled)
                    completion(.failure(NSError(domain: "OurinMigrator", code: 3,
                                                userInfo: [NSLocalizedDescriptionKey: "キャンセルされました"])))
                }
            }
        )

        let runner = GhidraHeadlessRunner(configuration: config, handlers: handlers)
        self.runner = runner
        progress(.started(binaryName: asset.filename))
        runner.analyze(binaryURL: binaryURL, outputDirectory: analysisDir)
    }

    /// 実行中の解析をキャンセルする。
    func cancel() {
        runner?.cancel()
    }

    // MARK: - Private

    /// report.md を生成し、ourin.json を更新する。
    private func finalizeReport(asset: LegacyAssetScanner.Asset,
                                analysisDir: URL,
                                duration: TimeInterval?) {
        // ourin.json を読み込み or 生成し、analysis 参照を更新。
        let manifestURL = asset.directoryURL.appendingPathComponent("ourin.json")
        var manifest = OurinManifest.read(from: manifestURL) ?? OurinManifest.makeDefault(for: asset)
        manifest.analysis = OurinManifest.AnalysisRef(
            decompiled: "ourin/analysis/decompiled.c",
            report: "ourin/analysis/report.md"
        )
        do {
            try manifest.write(to: manifestURL)
        } catch {
            logger.warning("Failed to write ourin.json: \(error.localizedDescription)")
        }

        MigrationReport.write(asset: asset,
                              analysisDirectory: analysisDir,
                              manifest: manifest,
                              ghidraDurationSeconds: duration)
    }

    /// 解析後の状態を反映した asset を返す。
    private func updatedAsset(asset: LegacyAssetScanner.Asset, analysisDir: URL) -> LegacyAssetScanner.Asset {
        var copy = asset
        let manifest = OurinManifest.read(from: asset.directoryURL.appendingPathComponent("ourin.json"))
        copy.status = LegacyAssetScanner.MigrationStatus.analyzed
        if let mode = manifest?.mode {
            switch mode {
            case .nativeReplacement, .nativePlugin: copy.status = .mapped
            case .scaffold: copy.status = .scaffolded
            default: break
            }
        }
        return copy
    }
}
