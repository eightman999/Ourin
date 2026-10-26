import AppKit
import CryptoKit
import Foundation
import Security

/// 配布版 Ourin.app の自動アップデート。
///
/// GitHub Releases の最新版（`Ourin-<版>.zip` と `.sha256`）を確認し、次を全て満たすときだけ差し替える。
/// - SHA-256 が `.sha256` と一致する
/// - 展開した Ourin.app のバンドル ID・版数が一致し、現在より新しい
/// - コード署名が有効で、現在のアプリと同じ Developer ID チームで署名されている
/// 差し替えは SSP の updatebaseware と同じ `BasewareUpdateHelper`（終了後に置換して再起動）を使う。
struct AppUpdateRelease: Equatable {
    let version: String
    let notes: String
    let archiveURL: URL
    let checksumURL: URL?
    let pageURL: URL?

    /// GitHub Releases API（`/releases/latest`）の応答を読む。アプリ本体の zip が無ければ nil。
    static func parseGitHubRelease(_ data: Data) -> AppUpdateRelease? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["draft"] as? Bool) != true,
              (json["prerelease"] as? Bool) != true else { return nil }
        let assets = (json["assets"] as? [[String: Any]]) ?? []
        func asset(named name: String) -> URL? {
            assets.first { ($0["name"] as? String) == name }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap(URL.init(string:))
        }
        // 版数はタグ（v0.1.0-beta.1 等）ではなく、アプリ本体の zip 名 `Ourin-<CFBundleShortVersionString>.zip` から読む。
        let names = assets.compactMap { $0["name"] as? String }
        guard let archiveName = names.first(where: { $0.range(of: #"^Ourin-[0-9]+(\.[0-9]+)*\.zip$"#, options: .regularExpression) != nil }),
              let archive = asset(named: archiveName) else { return nil }
        let version = String(archiveName.dropFirst("Ourin-".count).dropLast(".zip".count))
        return AppUpdateRelease(
            version: version,
            notes: (json["body"] as? String) ?? "",
            archiveURL: archive,
            checksumURL: asset(named: archiveName + ".sha256"),
            pageURL: (json["html_url"] as? String).flatMap(URL.init(string:))
        )
    }
}

enum AppVersion {
    /// `0.0.1.21` 形式を数値の並びとして比べる（足りない桁は 0）。
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let l = components(lhs), r = components(rhs)
        for index in 0..<max(l.count, r.count) {
            let a = index < l.count ? l[index] : 0
            let b = index < r.count ? r[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(_ version: String) -> [Int] {
        version.split(whereSeparator: { !$0.isNumber }).map { Int($0) ?? 0 }
    }
}

enum AppUpdateVerifier {
    enum Failure: Swift.Error, CustomStringConvertible {
        case checksumMismatch
        case appNotFound
        case wrongBundle(String)
        case wrongVersion(String)
        case signature(String)
        case currentAppUnsigned

        var description: String {
            switch self {
            case .checksumMismatch:
                return NSLocalizedString("ダウンロードしたファイルのチェックサムが一致しません", comment: "App update error")
            case .appNotFound:
                return NSLocalizedString("ダウンロードしたファイルに Ourin.app がありません", comment: "App update error")
            case .wrongBundle(let id):
                return String(format: NSLocalizedString("別のアプリが含まれています: %@", comment: "App update error"), id)
            case .wrongVersion(let version):
                return String(format: NSLocalizedString("版数が想定と違います: %@", comment: "App update error"), version)
            case .signature(let detail):
                return String(format: NSLocalizedString("署名を確認できません: %@", comment: "App update error"), detail)
            case .currentAppUnsigned:
                return NSLocalizedString("このビルドは配布版として署名されていないため、自動アップデートできません", comment: "App update error")
            }
        }
    }

    /// `.sha256`（`<hex>  <filename>` 形式）の先頭のハッシュと比べる。
    static func verifyChecksum(fileURL: URL, checksumText: String) throws {
        guard let expected = checksumText.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first?.lowercased(),
              let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            throw Failure.checksumMismatch
        }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw Failure.checksumMismatch }
    }

    /// 署名の Team ID（Developer ID の OU）。未署名・ad-hoc なら nil。
    static func teamIdentifier(of url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// 署名が有効で、指定チームの Developer ID（Apple 発行）で署名されていることを確かめる。
    static func verifySignature(of appURL: URL, teamIdentifier: String) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &code) == errSecSuccess, let code else {
            throw Failure.signature("SecStaticCodeCreateWithPath")
        }
        let requirementText = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\"" as CFString
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText, [], &requirement) == errSecSuccess, let requirement else {
            throw Failure.signature("SecRequirementCreateWithString")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        let status = SecStaticCodeCheckValidity(code, flags, requirement)
        guard status == errSecSuccess else {
            throw Failure.signature(SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)")
        }
    }

    /// 展開先から Ourin.app を探し、バンドル ID・版数・署名を確かめる。
    static func verifiedApp(in directory: URL, expectedVersion: String, bundleIdentifier: String, teamIdentifier: String) throws -> URL {
        let candidates = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        guard let app = candidates.first(where: { $0.pathExtension == "app" }),
              let bundle = Bundle(url: app) else { throw Failure.appNotFound }
        guard bundle.bundleIdentifier == bundleIdentifier else {
            throw Failure.wrongBundle(bundle.bundleIdentifier ?? "?")
        }
        let version = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        guard AppVersion.compare(version, expectedVersion) == .orderedSame else { throw Failure.wrongVersion(version) }
        try verifySignature(of: app, teamIdentifier: teamIdentifier)
        return app
    }
}

final class AppUpdater: NSObject {
    static let shared = AppUpdater()

    static let feedInfoKey = "OurinUpdateFeedURL"
    static let defaultFeed = "https://api.github.com/repos/eightman999/Ourin/releases/latest"
    private static let skippedVersionKey = "OurinSkippedUpdateVersion"
    private static let lastCheckKey = "OurinLastUpdateCheck"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private var timer: Timer?
    private var isBusy = false
    private var progressWindow: NSWindow?

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// 設定「自動アップデート確認」（既定オン）。
    var automaticChecksEnabled: Bool {
        (UserDefaults.standard.dictionary(forKey: "OurinGeneralSettings")?["autoUpdate"] as? Bool) ?? true
    }

    /// 起動後しばらくしてから確認し、以後 1 日ごとに確認する。
    func startAutomaticChecks() {
        timer?.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.automaticCheck() }
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in self?.automaticCheck() }
    }

    private func automaticCheck() {
        guard automaticChecksEnabled else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= Self.checkInterval else { return }
        checkForUpdates(userInitiated: false)
    }

    /// メニューの「アップデートを確認…」。
    @objc func checkForUpdatesFromMenu(_ sender: Any?) {
        checkForUpdates(userInitiated: true)
    }

    func checkForUpdates(userInitiated: Bool) {
        guard !isBusy else { return }
        let feedString = (Bundle.main.infoDictionary?[Self.feedInfoKey] as? String) ?? Self.defaultFeed
        guard let feed = URL(string: feedString) else { return }
        isBusy = true
        var request = URLRequest(url: feed)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Ourin/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isBusy = false
                UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard error == nil, status == 200, let data, let release = AppUpdateRelease.parseGitHubRelease(data) else {
                    if userInitiated {
                        self.showMessage(NSLocalizedString("アップデートを確認できませんでした", comment: "App update"),
                                         error?.localizedDescription ?? "HTTP \(status)")
                    }
                    return
                }
                self.handle(release, userInitiated: userInitiated)
            }
        }.resume()
    }

    private func handle(_ release: AppUpdateRelease, userInitiated: Bool) {
        guard AppVersion.compare(release.version, currentVersion) == .orderedDescending else {
            if userInitiated {
                showMessage(NSLocalizedString("Ourin は最新です", comment: "App update"),
                            String(format: NSLocalizedString("現在のバージョン: %@", comment: "App update"), currentVersion))
            }
            return
        }
        if !userInitiated, UserDefaults.standard.string(forKey: Self.skippedVersionKey) == release.version { return }

        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Ourin %@ が利用できます", comment: "App update"), release.version)
        var notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.count > 1200 { notes = String(notes.prefix(1200)) + "…" }
        alert.informativeText = String(format: NSLocalizedString("現在のバージョン: %@", comment: "App update"), currentVersion)
            + (notes.isEmpty ? "" : "\n\n" + notes)
        alert.addButton(withTitle: NSLocalizedString("アップデートして再起動", comment: "App update"))
        alert.addButton(withTitle: NSLocalizedString("あとで", comment: "App update"))
        alert.addButton(withTitle: NSLocalizedString("このバージョンをスキップ", comment: "App update"))
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            install(release)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.version, forKey: Self.skippedVersionKey)
        default:
            break
        }
    }

    private func install(_ release: AppUpdateRelease) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        guard let team = AppUpdateVerifier.teamIdentifier(of: Bundle.main.bundleURL) else {
            fail(AppUpdateVerifier.Failure.currentAppUnsigned, release: release)
            return
        }
        let target = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            fail(String(format: NSLocalizedString("%@ に書き込めません", comment: "App update error"),
                        target.deletingLastPathComponent().path), release: release)
            return
        }
        isBusy = true
        showProgress(String(format: NSLocalizedString("Ourin %@ をダウンロードしています…", comment: "App update"), release.version))
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let staged = try await Self.download(release, bundleIdentifier: bundleID, teamIdentifier: team)
                await MainActor.run { self?.applyStagedApp(staged, version: release.version, target: target) }
            } catch {
                await MainActor.run {
                    self?.isBusy = false
                    self?.hideProgress()
                    self?.fail(error, release: release)
                }
            }
        }
    }

    private static func download(_ release: AppUpdateRelease, bundleIdentifier: String, teamIdentifier: String) async throws -> URL {
        let work = try OurinPaths.subdirectory("temp").appendingPathComponent("app-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let (downloaded, _) = try await URLSession.shared.download(from: release.archiveURL)
        let archive = work.appendingPathComponent(release.archiveURL.lastPathComponent)
        try FileManager.default.moveItem(at: downloaded, to: archive)
        guard let checksumURL = release.checksumURL else { throw AppUpdateVerifier.Failure.checksumMismatch }
        let (checksumData, _) = try await URLSession.shared.data(from: checksumURL)
        try AppUpdateVerifier.verifyChecksum(fileURL: archive, checksumText: String(decoding: checksumData, as: UTF8.self))

        let expanded = work.appendingPathComponent("expanded", isDirectory: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", archive.path, expanded.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw AppUpdateVerifier.Failure.appNotFound }
        return try AppUpdateVerifier.verifiedApp(
            in: expanded,
            expectedVersion: release.version,
            bundleIdentifier: bundleIdentifier,
            teamIdentifier: teamIdentifier
        )
    }

    private func applyStagedApp(_ staged: URL, version: String, target: URL) {
        do {
            let request = BasewareUpdateRequest(
                parentPID: getpid(),
                targetAppURL: target,
                stagedAppURL: staged,
                markerURL: try BasewareUpdateMarker.defaultURL(),
                version: version
            )
            try BasewareUpdateMarker.writePending(request)
            try BasewareUpdateHelper.launch(request)
            hideProgress()
            NSApp.terminate(nil)
        } catch {
            isBusy = false
            hideProgress()
            fail(error, release: nil)
        }
    }

    private func fail(_ error: Any, release: AppUpdateRelease?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("アップデートできませんでした", comment: "App update")
        alert.informativeText = String(describing: error)
        if let page = release?.pageURL {
            alert.addButton(withTitle: NSLocalizedString("ダウンロードページを開く", comment: "App update"))
            alert.addButton(withTitle: NSLocalizedString("閉じる", comment: "App update"))
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
        } else {
            alert.runModal()
        }
    }

    private func showMessage(_ title: String, _ body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showProgress(_ text: String) {
        let label = NSTextField(labelWithString: text)
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        let stack = NSStackView(views: [spinner, label])
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Ourin"
        window.contentView = stack
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        progressWindow = window
    }

    private func hideProgress() {
        progressWindow?.orderOut(nil)
        progressWindow = nil
    }
}
