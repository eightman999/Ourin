import SwiftUI

/// Ourin Migrator のメイン UI。
///
/// 計画「UI の基本形」節:
/// ```text
/// Ourin Migrator
///   [Scan Documents/Ourin]
///   [Ghidra Path: ...]
///   [Analyze Selected]
///   [Generate ourin.json]
///   [Create Plugin Scaffold]
/// Name | Kind | Binary | Status | Action
/// ```
///
/// 詳細ペイン（計画「詳細ペイン」節）:
/// descript.txt summary / imports / exports / strings preview / resources preview /
/// migration recommendation / generated files
struct OurinMigratorView: View {
    @State private var assets: [LegacyAssetScanner.Asset] = []
    @State private var selectedAssetID: String?
    @State private var ghidraPath: String = ""
    @State private var scanLog: String = ""
    @State private var isScanning: Bool = false
    @State private var isAnalyzing: Bool = false
    @State private var analyzeProgress: String = ""
    @State private var overwriteConfirm: OverwriteRequest?

    private let logger = CompatLogger(subsystem: "jp.ourin.devtools", category: "migrator.ui")
    private let analyzer = LegacyBinaryAnalyzer()

    private enum OverwriteRequest: Identifiable {
        case manifest(LegacyAssetScanner.Asset)
        case scaffold(LegacyAssetScanner.Asset)
        var id: String {
            switch self {
            case .manifest(let a): return "manifest:\(a.id)"
            case .scaffold(let a): return "scaffold:\(a.id)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            contentSplit
            Divider()
            statusBar
        }
        .onAppear {
            loadGhidraDefault()
            performScan()
        }
        .alert(item: $overwriteConfirm) { request in
            confirmAlert(for: request)
        }
    }

    private func confirmAlert(for request: OverwriteRequest) -> Alert {
        switch request {
        case .manifest(let asset):
            return Alert(
                title: Text("ourin.json を上書き"),
                message: Text("既存の ourin.json が上書きされます。続行しますか？"),
                primaryButton: .destructive(Text("上書き")) {
                    writeManifest(for: asset)
                },
                secondaryButton: .cancel()
            )
        case .scaffold(let asset):
            return Alert(
                title: Text(".plugin 雛形を上書き"),
                message: Text("既存の雛形が上書きされます。続行しますか？"),
                primaryButton: .destructive(Text("上書き")) {
                    performScaffold(for: asset, force: true)
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: performScan) {
                Label("Scan Documents/Ourin", systemImage: "magnifyingglass")
            }
            .disabled(isScanning || isAnalyzing)

            HStack(spacing: 4) {
                Text("Ghidra Path:")
                    .font(.caption)
                TextField("/path/to/analyzeHeadless", text: $ghidraPath)
                    .frame(minWidth: 240)
                    .font(.system(.body, design: .monospaced))
                Button("Browse…") { browseGhidra() }
            }

            Spacer()

            Button(action: analyzeSelected) {
                Label("Analyze Selected", systemImage: "waveform.path.ecg")
            }
            .disabled(selectedAsset == nil || isAnalyzing || ghidraURL == nil)

            Button(action: generateManifest) {
                Label("Generate ourin.json", systemImage: "doc.text")
            }
            .disabled(selectedAsset == nil || isAnalyzing)

            Button(action: createScaffold) {
                Label("Create Plugin Scaffold", systemImage: "hammer")
            }
            .disabled(selectedAsset == nil || isAnalyzing)

            if isAnalyzing {
                Button("Cancel") { analyzer.cancel() }
                    .foregroundColor(.red)
            }
        }
        .padding(8)
    }

    // MARK: - Content

    private var contentSplit: some View {
        HSplitView {
            assetTable
            detailPane
        }
    }

    @ViewBuilder
    private var assetTable: some View {
        if #available(macOS 12.0, *) {
            Table(assets, selection: $selectedAssetID) {
                TableColumn("Name") { Text($0.displayName).help($0.directoryURL.path) }
                TableColumn("Kind") { Text($0.kind.rawValue) }
                    .width(min: 90, ideal: 110)
                TableColumn("Binary") { Text($0.binaryKind.displayName) }
                    .width(min: 60, ideal: 70)
                TableColumn("Status") { Text($0.status.rawValue) }
                    .width(min: 90, ideal: 100)
                TableColumn("Action") { asset in
                    Text(actionRecommendation(for: asset))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .width(min: 120, ideal: 160)
            }
        } else {
            legacyList
        }
    }

    private var legacyList: some View {
        List(assets, selection: $selectedAssetID) { asset in
            HStack {
                Text(asset.displayName)
                Spacer()
                Text(asset.binaryKind.displayName)
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text(asset.status.rawValue)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .tag(asset.id)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let asset = selectedAsset {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection(asset)
                    descriptorSection(asset)
                    importsSection(asset)
                    exportsSection(asset)
                    stringsSection(asset)
                    resourcesSection(asset)
                    recommendationSection(asset)
                    generatedFilesSection(asset)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("資産を選択してください")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Detail sections

    private func headerSection(_ asset: LegacyAssetScanner.Asset) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(asset.displayName).font(.title2.bold())
            HStack {
                migratorBadge(asset.kind.rawValue)
                migratorBadge(asset.binaryKind.displayName)
                migratorBadge(asset.status.rawValue)
            }
            if !asset.filename.isEmpty {
                Text("file: \(asset.filename)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Text(asset.directoryURL.path)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private func descriptorSection(_ asset: LegacyAssetScanner.Asset) -> some View {
        detailBlock(title: "descript.txt") {
            if asset.descriptor.isEmpty {
                emptyText("(descript.txt がありません)")
            } else {
                gridPairs(asset.descriptor.sorted(by: { $0.key < $1.key }).map { ($0.key, $0.value) })
            }
        }
    }

    private func importsSection(_ asset: LegacyAssetScanner.Asset) -> some View {
        let dir = analysisDir(for: asset)
        let imports = MigrationReport.readImports(at: dir)
        return detailBlock(title: "Imports (\(imports.count))") {
            if imports.isEmpty {
                emptyText("(解析後に表示されます)")
            } else {
                gridPairs(imports.prefix(30).map { ($0.name, $0.library ?? "-") })
            }
        }
    }

    private func exportsSection(_ asset: LegacyAssetScanner.Asset) -> some View {
        let dir = analysisDir(for: asset)
        let exports = MigrationReport.readExports(at: dir)
        return detailBlock(title: "Exports (\(exports.count))") {
            if exports.isEmpty {
                emptyText("(解析後に表示されます)")
            } else {
                gridPairs(exports.prefix(30).map { ($0.name, $0.type ?? "-") })
            }
        }
    }

    private func stringsSection(_ asset: LegacyAssetScanner.Asset) -> some View {
        let dir = analysisDir(for: asset)
        let strings = MigrationReport.readStringsPreview(at: dir)
        return detailBlock(title: "Strings preview") {
            if strings.isEmpty {
                emptyText("(解析後に表示されます)")
            } else {
                Text(strings.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(4)
            }
        }
    }

    private func resourcesSection(_ asset: LegacyAssetScanner.Asset) -> some View {
        let dir = analysisDir(for: asset)
        let url = dir.appendingPathComponent("resources.txt")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return detailBlock(title: "Resources preview") {
            if text.isEmpty {
                emptyText("(解析後に表示されます)")
            } else {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(4)
            }
        }
    }

    private func recommendationSection(_ asset: LegacyAssetScanner.Asset) -> some View {
        let manifest = asset.existingManifest ?? OurinManifest.makeDefault(for: asset)
        let (mode, impl) = OurinManifest.recommendedMode(for: asset.filename)
        let displayMode = asset.existingManifest?.mode ?? mode
        return detailBlock(title: "Migration recommendation") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mode: \(displayMode.rawValue)")
                    .bold()
                Text(displayMode.recommendation)
                    .foregroundColor(.secondary)
                if let impl = impl ?? manifest.implementation {
                    Text("Implementation: \(impl)")
                        .font(.system(.body, design: .monospaced))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func generatedFilesSection(_ asset: LegacyAssetScanner.Asset) -> some View {
        let dir = analysisDir(for: asset)
        let files = ["decompiled.c", "imports.json", "exports.json", "strings.txt", "resources.txt", "report.md"]
        let manifestExists = FileManager.default.fileExists(
            atPath: asset.directoryURL.appendingPathComponent("ourin.json").path
        )
        return detailBlock(title: "Generated files") {
            HStack {
                fileStatus("ourin.json", exists: manifestExists)
                ForEach(files, id: \.self) { f in
                    fileStatus(f, exists: FileManager.default.fileExists(atPath: dir.appendingPathComponent(f).path))
                }
            }
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack {
            if isScanning {
                ProgressView().scaleEffect(0.7)
                Text("スキャン中…")
            } else if isAnalyzing {
                ProgressView().scaleEffect(0.7)
                Text("解析中…")
                Text(analyzeProgress).lineLimit(1).truncationMode(.tail)
            } else if !scanLog.isEmpty {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
                Text(scanLog).lineLimit(1).truncationMode(.tail)
            }
            Spacer()
            Text("\(assets.count) 件")
                .foregroundColor(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func performScan() {
        isScanning = true
        scanLog = ""
        DispatchQueue.global().async {
            guard let base = try? OurinPaths.baseDirectory() else {
                DispatchQueue.main.async {
                    self.scanLog = "基準ディレクトリが解決できません"
                    self.isScanning = false
                }
                return
            }
            let roots = LegacyAssetScanner.defaultScanRoots(baseDirectory: base)
            let found = LegacyAssetScanner.scan(roots: roots)
            DispatchQueue.main.async {
                self.assets = found
                self.scanLog = "スキャン完了: \(found.count) 件"
                self.isScanning = false
            }
        }
    }

    private func analyzeSelected() {
        guard let asset = selectedAsset, let url = ghidraURL else { return }
        isAnalyzing = true
        analyzeProgress = asset.filename
        var outputAccum = ""
        analyzer.analyze(asset: asset,
                         ghidraURL: url,
                         progress: { p in
            DispatchQueue.main.async {
                switch p {
                case .started(let name): self.analyzeProgress = "開始: \(name)"
                case .stdout(let s), .stderr(let s):
                    outputAccum += s
                    if let last = outputAccum.split(whereSeparator: { $0.isNewline }).last {
                        self.analyzeProgress = String(last)
                    }
                case .finishedAnalysis(let dur): self.analyzeProgress = "完了 (\(String(format: "%.1f", dur))s)"
                case .failed(let m):
                    self.isAnalyzing = false
                    self.analyzeProgress = ""
                    self.scanLog = "解析失敗: \(m)"
                case .cancelled:
                    self.isAnalyzing = false
                    self.analyzeProgress = ""
                    self.scanLog = "解析をキャンセルしました"
                }
            }
        }, completion: { result in
            DispatchQueue.main.async {
                self.isAnalyzing = false
                self.analyzeProgress = ""
                switch result {
                case .success(let updated):
                    if let idx = self.assets.firstIndex(where: { $0.id == updated.id }) {
                        self.assets[idx] = updated
                    }
                    self.scanLog = "解析完了: \(updated.filename)"
                case .failure(let err):
                    self.scanLog = "解析失敗: \(err.localizedDescription)"
                }
            }
        })
    }

    private func generateManifest() {
        guard let asset = selectedAsset else { return }
        let url = asset.directoryURL.appendingPathComponent("ourin.json")
        let exists = FileManager.default.fileExists(atPath: url.path)
        if exists {
            overwriteConfirm = .manifest(asset)
        } else {
            writeManifest(for: asset)
        }
    }

    private func createScaffold() {
        guard let asset = selectedAsset else { return }
        let pluginName = PluginScaffolder.pluginBundleName(for: asset)
        let packageURL = asset.directoryURL
            .appendingPathComponent("ourin/macos/\(pluginName)_mac")
        if FileManager.default.fileExists(atPath: packageURL.path) {
            overwriteConfirm = .scaffold(asset)
        } else {
            performScaffold(for: asset)
        }
    }

    // MARK: - Helpers

    private var selectedAsset: LegacyAssetScanner.Asset? {
        assets.first { $0.id == selectedAssetID }
    }

    private var ghidraURL: URL? {
        let path = ghidraPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func loadGhidraDefault() {
        if let url = LegacyBinaryAnalyzer.resolveGhidra(
            from: LegacyBinaryAnalyzer.defaultGhidraCandidates
        ) {
            ghidraPath = url.path
        }
    }

    private func browseGhidra() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "analyzeHeadless を選択"
        if let url = ghidraURL { panel.directoryURL = url.deletingLastPathComponent() }
        if panel.runModal() == .OK, let url = panel.url {
            ghidraPath = url.path
        }
    }

    private func analysisDir(for asset: LegacyAssetScanner.Asset) -> URL {
        asset.directoryURL.appendingPathComponent("ourin/analysis", isDirectory: true)
    }

    private func actionRecommendation(for asset: LegacyAssetScanner.Asset) -> String {
        if OurinManifest.isKnownBuiltin(asset.filename) {
            return "native-replacement"
        }
        switch asset.status {
        case .analyzed, .mapped: return "review"
        case .scaffolded: return "implement"
        default: return "analyze"
        }
    }

    private func writeManifest(for asset: LegacyAssetScanner.Asset) {
        var manifest = OurinManifest.makeDefault(for: asset)
        let analysisDir = analysisDir(for: asset)
        let reportExists = FileManager.default.fileExists(
            atPath: analysisDir.appendingPathComponent("report.md").path
        )
        if reportExists {
            manifest.analysis = OurinManifest.AnalysisRef(
                decompiled: "ourin/analysis/decompiled.c",
                report: "ourin/analysis/report.md"
            )
        }
        do {
            try manifest.write(to: asset.directoryURL.appendingPathComponent("ourin.json"))
            scanLog = "ourin.json を生成しました"
            refreshStatus(of: asset)
        } catch {
            scanLog = "ourin.json 生成失敗: \(error.localizedDescription)"
        }
    }

    private func performScaffold(for asset: LegacyAssetScanner.Asset, force: Bool = false) {
        if let result = PluginScaffolder.scaffold(for: asset, force: force) {
            scanLog = result.overwritten
                ? "雛形を上書きしました: \(result.packageURL.lastPathComponent)"
                : "雛形を生成しました: \(result.packageURL.lastPathComponent)"
            refreshStatus(of: asset)
        } else {
            scanLog = "雛形生成をスキップしました（既存）"
        }
    }

    private func refreshStatus(of asset: LegacyAssetScanner.Asset) {
        guard let idx = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        var copy = assets[idx]
        let manifest = OurinManifest.read(
            from: asset.directoryURL.appendingPathComponent("ourin.json")
        )
        let reportExists = FileManager.default.fileExists(
            atPath: analysisDir(for: asset).appendingPathComponent("report.md").path
        )
        if let mode = manifest?.mode {
            switch mode {
            case .nativeReplacement, .nativePlugin: copy.status = .mapped
            case .scaffold: copy.status = .scaffolded
            default: copy.status = reportExists ? .analyzed : .metadataOnly
            }
        } else if reportExists {
            copy.status = .analyzed
        } else {
            copy.status = .metadataOnly
        }
        copy.existingManifest = manifest
        assets[idx] = copy
    }
}

// MARK: - Small UI helpers

private func migratorBadge(_ text: String) -> some View {
    Text(text)
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12))
        .cornerRadius(4)
}

private func detailBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.headline)
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private func gridPairs(_ pairs: [(String, String)]) -> some View {
    let rows = Array(pairs)
    return VStack(alignment: .leading, spacing: 2) {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, pair in
            HStack(alignment: .top) {
                Text(pair.0)
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 160, alignment: .leading)
                Text(pair.1)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private func emptyText(_ s: String) -> some View {
    Text(s).foregroundColor(.secondary).font(.caption)
}

private func fileStatus(_ name: String, exists: Bool) -> some View {
    HStack(spacing: 3) {
        Image(systemName: exists ? "checkmark.circle.fill" : "circle")
            .foregroundColor(exists ? .green : .secondary)
            .font(.caption2)
        Text(name).font(.system(.caption2, design: .monospaced))
    }
}

#Preview {
    OurinMigratorView()
        .frame(width: 1000, height: 640)
}
