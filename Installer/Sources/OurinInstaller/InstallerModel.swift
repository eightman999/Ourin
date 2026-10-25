import AppKit
import OurinInstallerCore
import UniformTypeIdentifiers

@MainActor
final class InstallerModel: ObservableObject {
    enum Step: Int, CaseIterable, Identifiable {
        case welcome, destination, migration, ghost, install, done
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome: return "ようこそ"
            case .destination: return "インストール先"
            case .migration: return "SSP からの移行"
            case .ghost: return "最初のゴースト"
            case .install: return "インストール"
            case .done: return "完了"
            }
        }
    }

    enum Destination: Hashable {
        case applications
        case userApplications

        var url: URL {
            switch self {
            case .applications:
                return DevOverrides.root?.appendingPathComponent("Applications", isDirectory: true)
                    ?? URL(fileURLWithPath: "/Applications", isDirectory: true)
            case .userApplications:
                return DevOverrides.home.appendingPathComponent("Applications", isDirectory: true)
            }
        }
    }

    enum StartupChoice: Hashable {
        /// 既存の起動ゴースト設定をそのまま使う。
        case keepCurrent
        /// 同梱の emily4（Ourin 本体が初回起動時に入れる）。
        case bundledDefault
        /// 既にインストール済み、または今回移行するゴースト（ディレクトリ名）。
        case ghost(String)
    }

    enum InstallState: Equatable {
        case idle
        case running
        case succeeded
        case failed(String)
    }

    @Published var step: Step = .welcome

    // インストール先
    @Published var destination: Destination = .applications

    // 移行
    @Published var sspCandidates: [SSPLocator.Candidate] = []
    @Published var isSearchingSSP = false
    @Published var hasSearchedSSP = false
    @Published var sspRoot: URL?
    @Published var migrationItems: [MigrationItem] = []
    @Published var selectedItemIDs: Set<String> = []

    // 最初のゴースト
    @Published var startupChoice: StartupChoice = .bundledDefault
    @Published var extraNars: [URL] = []

    // インストール
    @Published var installState: InstallState = .idle
    @Published var log: [String] = []
    @Published var migrationResults: [DataMigrator.Result] = []

    let payload: URL
    let appInstaller: AppInstaller
    let existingStartupGhost: String?
    private let dataLocation: OurinDataLocation?

    init() {
        let env = ProcessInfo.processInfo.environment
        if let override = env["OURIN_INSTALLER_PAYLOAD"], !override.isEmpty {
            payload = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            payload = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Ourin.app", isDirectory: true)
        }
        appInstaller = AppInstaller(payload: payload)
        existingStartupGhost = OurinPreferences(suiteName: DevOverrides.preferencesSuite)?.startupGhost.flatMap { $0.isEmpty ? nil : $0 }
        dataLocation = DevOverrides.root.map { OurinDataLocation(base: $0.appendingPathComponent("Documents/Ourin", isDirectory: true)) }
            ?? (try? OurinDataLocation.resolve())
        if existingStartupGhost != nil { startupChoice = .keepCurrent }
    }

    // MARK: - 表示用

    var payloadVersion: String { appInstaller.payloadVersion ?? "不明" }

    var payloadExists: Bool {
        FileManager.default.fileExists(atPath: payload.appendingPathComponent("Contents/Info.plist").path)
    }

    var installedVersion: String? { appInstaller.installedVersion(in: destination.url) }

    var needsAdministrator: Bool { !appInstaller.canWrite(to: destination.url) }

    var dataFolderPath: String { dataLocation?.base.path ?? "~/Documents/Ourin" }

    var installedGhosts: [String] { dataLocation?.installedGhostDirectories() ?? [] }

    var selectedItems: [MigrationItem] { migrationItems.filter { selectedItemIDs.contains($0.id) } }

    /// 起動ゴーストに選べる、今回移行するゴースト（既にあるものは除く）。
    var migratingGhosts: [MigrationItem] {
        let installed = Set(installedGhosts)
        return selectedItems.filter { $0.kind == .ghost && !installed.contains($0.directory) }
    }

    func licenseText() -> String {
        let resources = payload.appendingPathComponent("Contents/Resources", isDirectory: true)
        let parts: [(String, String)] = [("Ourin", "AppLicense.txt"), ("同梱ゴースト emily4", "Emily4.txt"),
                                         ("YAYA", "YAYA_Core.txt"), ("里々", "SATORI.txt")]
        let texts = parts.compactMap { title, file -> String? in
            guard let text = try? String(contentsOf: resources.appendingPathComponent(file), encoding: .utf8) else { return nil }
            return "■ \(title)\n\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return texts.isEmpty ? "ライセンス情報を読み込めませんでした。" : texts.joined(separator: "\n\n")
    }

    // MARK: - 画面遷移

    var canGoBack: Bool {
        step != .welcome && step != .done && installState != .running
    }

    var canContinue: Bool {
        switch step {
        case .welcome: return payloadExists
        case .install: return installState == .succeeded
        case .done: return false
        default: return true
        }
    }

    func goBack() {
        guard canGoBack, let previous = Step(rawValue: step.rawValue - 1) else { return }
        if step == .install { installState = .idle; log = [] }
        step = previous
    }

    func goNext() {
        guard canContinue, let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
        if next == .migration, !hasSearchedSSP { searchSSP() }
        if next == .ghost { normalizeStartupChoice() }
    }

    /// 移行の選択を変えた結果、選べなくなった起動ゴーストを既定に戻す。
    private func normalizeStartupChoice() {
        guard case .ghost(let dir) = startupChoice else { return }
        let available = Set(installedGhosts).union(migratingGhosts.map(\.directory))
        if !available.contains(dir) { startupChoice = existingStartupGhost != nil ? .keepCurrent : .bundledDefault }
    }

    // MARK: - SSP

    func searchSSP() {
        isSearchingSSP = true
        Task.detached(priority: .userInitiated) {
            let found = SSPLocator(home: DevOverrides.home).locate()
            await MainActor.run {
                self.sspCandidates = found
                self.isSearchingSSP = false
                self.hasSearchedSSP = true
                if self.sspRoot == nil, let first = found.first { self.selectSSPRoot(first.root) }
            }
        }
    }

    func chooseSSPFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "SSP のフォルダ（ghost フォルダがある場所）を選んでください"
        panel.prompt = "選択"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard SSPLocator.isMigratableRoot(url) else {
            NSAlert.show(title: "SSP のフォルダではありません",
                         text: "選んだフォルダに ghost / balloon フォルダが見つかりませんでした。")
            return
        }
        selectSSPRoot(url)
    }

    func selectSSPRoot(_ url: URL?) {
        sspRoot = url
        guard let url else {
            migrationItems = []
            selectedItemIDs = []
            return
        }
        migrationItems = SSPScanner.scan(root: url)
        // Windows 用 SHIORI のゴーストは動かない可能性が高いので、既定では選ばない。
        selectedItemIDs = Set(migrationItems.filter {
            if case .windowsShiori = $0.compatibility { return false }
            return true
        }.map(\.id))
    }

    func isAlreadyInstalled(_ item: MigrationItem) -> Bool {
        guard let dataLocation else { return false }
        return FileManager.default.fileExists(atPath: DataMigrator(location: dataLocation).destination(for: item).path)
    }

    // MARK: - .nar

    func addNars() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "nar") ?? .zip, .zip]
        panel.message = "インストール後に Ourin で開く .nar を選んでください"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !extraNars.contains(url) { extraNars.append(url) }
    }

    // MARK: - インストール

    func startInstall() {
        guard installState != .running else { return }
        installState = .running
        log = []
        migrationResults = []
        Task { await runInstall() }
    }

    private func appendLog(_ line: String) { log.append(line) }

    private func runInstall() async {
        do {
            if DevOverrides.root == nil, RunningOurin.isRunning {
                appendLog("起動中の Ourin を終了しています…")
                guard await RunningOurin.requestQuit() else {
                    throw InstallFailure("Ourin が終了しませんでした。Ourin を終了してからもう一度お試しください。")
                }
            }

            appendLog("Ourin \(payloadVersion) を \(destination.url.path) に配置しています…")
            try await installApp()
            appendLog("Ourin.app を配置しました。")

            let items = selectedItems
            if !items.isEmpty {
                guard let dataLocation else { throw InstallFailure("Ourin のデータフォルダを用意できませんでした。") }
                appendLog("SSP からゴースト・バルーンをコピーしています…")
                let migrator = DataMigrator(location: dataLocation)
                let results = await Task.detached(priority: .userInitiated) { migrator.migrate(items) }.value
                migrationResults = results
                for result in results {
                    switch result.outcome {
                    case .copied: appendLog("  コピー: \(result.item.name)")
                    case .skippedExisting: appendLog("  既にあるため省略: \(result.item.name)")
                    case .failed(let message): appendLog("  失敗: \(result.item.name)（\(message)）")
                    }
                }
            }

            applyStartupChoice()
            appendLog("完了しました。")
            installState = .succeeded
        } catch {
            appendLog("エラー: \(error)")
            installState = .failed(String(describing: error))
        }
    }

    private func installApp() async throws {
        let installer = appInstaller
        let directory = destination.url
        if installer.canWrite(to: directory) {
            try await Task.detached(priority: .userInitiated) { _ = try installer.install(into: directory) }.value
            return
        }
        appendLog("管理者権限が必要です。パスワードの入力を求められます。")
        let script = installer.privilegedInstallScript(into: directory)
        try await Task.detached(priority: .userInitiated) { try PrivilegedShell.run(script) }.value
    }

    private func applyStartupChoice() {
        guard let prefs = OurinPreferences(suiteName: DevOverrides.preferencesSuite) else { return }
        switch startupChoice {
        case .keepCurrent:
            break
        case .bundledDefault:
            prefs.setStartupGhost(nil)
        case .ghost(let directory):
            prefs.setStartupGhost(directory)
            appendLog("最初に起動するゴーストを「\(directory)」にしました。")
        }
    }

    func launchOurin() {
        let app = appInstaller.target(in: destination.url)
        let config = NSWorkspace.OpenConfiguration()
        let nars = extraNars
        NSWorkspace.shared.openApplication(at: app, configuration: config) { _, error in
            if let error {
                Task { @MainActor in NSAlert.show(title: "Ourin を起動できませんでした", text: error.localizedDescription) }
                return
            }
            // 追加の .nar は本体のインストール処理（SHIORI のインストールイベント込み）に任せる。
            guard !nars.isEmpty else { return }
            NSWorkspace.shared.open(nars, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// 開発・検証用：`OURIN_INSTALLER_ROOT` を指定すると、/Applications・ホーム・データフォルダ・
/// Ourin の設定をすべてその配下（設定は専用ドメイン）へ向け、実環境に触れずに通しで試せる。
enum DevOverrides {
    static let root: URL? = ProcessInfo.processInfo.environment["OURIN_INSTALLER_ROOT"]
        .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }

    static var home: URL {
        root?.appendingPathComponent("home", isDirectory: true) ?? FileManager.default.homeDirectoryForCurrentUser
    }

    static var preferencesSuite: String {
        root == nil ? OurinPreferences.bundleIdentifier : "jp.ourin.installer.devroot"
    }
}

struct InstallFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// `/Applications` に書けない一般ユーザー向けの権限昇格。
enum PrivilegedShell {
    static func run(_ script: String) throws {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: source) else {
            throw InstallFailure("権限昇格の準備に失敗しました。")
        }
        appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            if (errorInfo[NSAppleScript.errorNumber] as? Int) == -128 {
                throw InstallFailure("管理者権限の入力がキャンセルされました。")
            }
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "不明なエラー"
            throw InstallFailure("Ourin.app を配置できませんでした: \(message)")
        }
    }
}

extension NSAlert {
    @MainActor
    static func show(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
