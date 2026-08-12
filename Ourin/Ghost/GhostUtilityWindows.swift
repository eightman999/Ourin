import SwiftUI
import AppKit

/// `open,backlogviewer` が表示する1件の発言。
struct GhostBacklogEntry: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let text: String

    init(id: UUID = UUID(), date: Date = Date(), text: String) {
        self.id = id
        self.date = date
        self.text = text
    }
}

struct GhostArchiveEntry: Identifiable {
    let id = UUID()
    let path: String
}

extension Notification.Name {
    static let ghostBacklogDidChange = Notification.Name("OurinGhostBacklogDidChange")
}

extension GhostManager {
    /// 表示対象のスクリプトを発言履歴へ追加する。制御タグのみのスクリプトは記録しない。
    func recordBacklog(from script: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.recordBacklog(from: script)
            }
            return
        }

        let text = sakuraEngine.displayText(from: script)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if usageSessionStarted {
            RateOfUseStore.shared.recordTalk(
                identifier: ghostURL.standardizedFileURL.path,
                name: ghostConfig?.name ?? ghostURL.lastPathComponent,
                sakuraname: ghostConfig?.sakuraName ?? sakuraEngine.envExpander.selfname ?? "",
                keroname: ghostConfig?.keroName ?? sakuraEngine.envExpander.keroname ?? "",
                characterCount: text.count
            )
        }

        backlogEntries.append(GhostBacklogEntry(text: text))
        let maximumEntries = 200
        if backlogEntries.count > maximumEntries {
            backlogEntries.removeFirst(backlogEntries.count - maximumEntries)
        }
        NotificationCenter.default.post(name: .ghostBacklogDidChange, object: self)
    }

    func openAddressBar() {
        presentUtilityWindow(
            key: "addressbar",
            title: "Address Bar",
            size: NSSize(width: 520, height: 210)
        ) { [weak self] in
            AddressBarView(
                onSubmit: { [weak self] value in self?.openAddressBarURL(value) },
                onClose: { [weak self] in self?.closeUtilityWindow(key: "addressbar") }
            )
        }
    }

    func openErrorLogViewer() {
        presentUtilityWindow(
            key: "errorlog",
            title: "Error Log",
            size: NSSize(width: 900, height: 560)
        ) {
            ErrorLogViewerView()
        }
    }

    func openBacklogViewer() {
        let entries = backlogEntries
        presentUtilityWindow(
            key: "backlogviewer",
            title: "Backlog",
            size: NSSize(width: 620, height: 520)
        ) {
            BacklogViewerView(
                initialEntries: entries,
                entriesProvider: { [weak self] in self?.backlogEntries ?? [] }
            )
        }
    }

    /// SHIORI Resource `getaistate(ex)` を使ったAI状態グラフを開く。
    /// リソースを提供しないゴーストでは、存在しないファイルを開く代わりに
    /// 利用不可を明示する。
    func openAIGraph() {
        guard let runtime = shioriRuntime, runtime.isLoaded else {
            showUtilityError(title: "AI Graph", message: "SHIORI がロードされていません。")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak runtime] in
            guard let runtime else { return }
            let stateResponse = runtime.request(method: "GET", id: "getaistate", headers: [:], refs: [], timeout: 2.0)
            let extendedResponse = runtime.request(method: "GET", id: "getaistateex", headers: [:], refs: [], timeout: 2.0)
            let state = stateResponse?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let values = (extendedResponse?.value ?? "")
                .split(separator: "\u{01}", omittingEmptySubsequences: true)
                .map(String.init)

            DispatchQueue.main.async {
                guard let self else { return }
                guard !state.isEmpty || !values.isEmpty else {
                    self.showUtilityError(title: "AI Graph", message: "ゴーストが getaistate / getaistateex を提供していません。")
                    return
                }
                self.presentUtilityWindow(
                    key: "aigraph",
                    title: "AI Graph",
                    size: NSSize(width: 760, height: 520)
                ) {
                    AIGraphView(state: state, values: values)
                }
            }
        }
    }

    /// ゴースト／バルーンの使用率グラフを開く。
    /// バルーン別カウンタを持たない環境では、仕様に従いゴースト使用率へ
    /// フォールバックし、`rateofuselist.*` と同じ永続統計を表示する。
    func openRateOfUseGraph(kind: String) {
        let normalizedKind = kind.lowercased()
        let allSnapshots = RateOfUseStore.shared.snapshots()
        let isTotal = normalizedKind == "rateofusegraphtotal"
        let currentIdentifier = ghostURL.standardizedFileURL.path
        let snapshots: [GhostUsageSnapshot]
        if isTotal {
            snapshots = allSnapshots
        } else {
            snapshots = allSnapshots.filter { $0.id == currentIdentifier }
        }

        let title: String
        switch normalizedKind {
        case "rateofusegraphballoon":
            title = "使用率 - バルーン（ゴースト使用率）"
        case "rateofusegraphtotal":
            title = "使用率 - 合算"
        default:
            title = "使用率 - \(ghostConfig?.name ?? ghostURL.lastPathComponent)"
        }

        presentUtilityWindow(
            key: "rateofuse-\(normalizedKind)",
            title: title,
            size: NSSize(width: 760, height: 520)
        ) {
            RateOfUseGraphView(
                title: title,
                snapshots: snapshots,
                isTotal: isTotal,
                currentIdentifier: currentIdentifier
            )
        }
    }

    func openPictureViewer(path: String?) {
        let url: URL?
        if let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            url = utilityFileURL(path)
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedFileTypes = NSImage.imageTypes
            url = panel.runModal() == .OK ? panel.url : nil
        }

        guard let url else { return }
        guard FileManager.default.fileExists(atPath: url.path),
              let image = NSImage(contentsOf: url) else {
            showUtilityError(title: "Picture Viewer", message: "画像を読み込めませんでした:\n\(url.path)")
            return
        }

        closeUtilityWindow(key: "pictureviewer")
        presentUtilityWindow(
            key: "pictureviewer",
            title: "Picture Viewer - \(url.lastPathComponent)",
            size: NSSize(width: 720, height: 560)
        ) {
            PictureViewerView(image: image, path: url.path)
        }
    }

    func openArchiveViewer(path: String?) {
        let url: URL?
        if let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            url = utilityFileURL(path)
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedFileTypes = ["zip", "nar"]
            url = panel.runModal() == .OK ? panel.url : nil
        }

        guard let url else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            showUtilityError(title: "Archive Viewer", message: "アーカイブが見つかりません:\n\(url.path)")
            return
        }

        closeUtilityWindow(key: "archiveviewer")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let entries = try Self.readArchiveEntries(from: url)
                DispatchQueue.main.async {
                    self?.presentUtilityWindow(
                        key: "archiveviewer",
                        title: "Archive Viewer - \(url.lastPathComponent)",
                        size: NSSize(width: 700, height: 560)
                    ) {
                        ArchiveViewerView(archivePath: url.path, entries: entries)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.showUtilityError(title: "Archive Viewer", message: error.localizedDescription)
                }
            }
        }
    }

    func openAddressBarURL(_ rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            showUtilityError(title: "Address Bar", message: "URLを入力してください。")
            return
        }

        let candidate: String
        if value.contains("://") || value.lowercased().hasPrefix("mailto:") {
            candidate = value
        } else {
            candidate = "https://\(value)"
        }

        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto", "file"].contains(scheme) else {
            showUtilityError(title: "Address Bar", message: "URL形式が正しくありません:\n\(value)")
            return
        }

        if scheme == "mailto" {
            openEmail(candidate)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func presentUtilityWindow<Content: View>(
        key: String,
        title: String,
        size: NSSize,
        content: @escaping () -> Content
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.presentUtilityWindow(key: key, title: title, size: size, content: content)
            }
            return
        }
        if let window = utilityWindows[key] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
        window.identifier = NSUserInterfaceItemIdentifier("GhostUtilityWindow_\(key)_\(sstpUniqueID)")
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        window.center()
        window.makeKeyAndOrderFront(nil)
        utilityWindows[key] = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeUtilityWindow(key: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.closeUtilityWindow(key: key) }
            return
        }
        utilityWindows.removeValue(forKey: key)?.close()
    }

    private func utilityFileURL(_ rawPath: String) -> URL {
        SSPCompat.resolvePath(rawPath, relativeTo: ghostURL).standardizedFileURL
    }

    private func showUtilityError(title: String, message: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.showUtilityError(title: title, message: message) }
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        alert.runModal()
    }

    private static func readArchiveEntries(from url: URL) throws -> [GhostArchiveEntry] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "Ourin.ArchiveViewer",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: detail.isEmpty ? "アーカイブを読み込めませんでした。" : detail]
            )
        }
        return output
            .split(whereSeparator: { $0.isNewline })
            .map { GhostArchiveEntry(path: String($0)) }
    }
}

private struct AddressBarView: View {
    let onSubmit: (String) -> Void
    let onClose: () -> Void
    @State private var address = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("URLを入力するか、下の領域へURLをドラッグ＆ドロップしてください。")
                .font(.callout)
                .foregroundColor(.secondary)
            TextField("https://example.com", text: $address, onEditingChanged: { _ in }, onCommit: submit)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("閉じる", action: onClose)
                Button("開く", action: submit)
                    .keyboardShortcut(.defaultAction)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [5]))
                Text("ここへURLをドロップ")
                    .foregroundColor(.secondary)
            }
            .frame(height: 54)
            .background(
                DragDropView { event in
                    EventBridge.shared.notify(event.id, params: event.params)
                    guard event.id == .OnURLDropped || event.id == .OnURLDrop,
                          let value = event.params["Reference0"] ?? event.params["url"] else { return }
                    address = value
                }
            )
        }
        .padding(20)
        .frame(minWidth: 480)
    }

    private func submit() {
        onSubmit(address)
    }
}

private struct ErrorLogViewerView: View {
    @State private var entries: [LogEntry] = []
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ourin ログ（直近24時間）")
                    .font(.headline)
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Button("コピー", action: copyAll)
                    .disabled(entries.isEmpty)
                Button("更新", action: load)
            }
            .padding(12)
            Divider()
            if entries.isEmpty && !isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text("ログはありません")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(entry.timestamp, style: .date)
                            Text(entry.timestamp, style: .time)
                            Text(entry.level.uppercased())
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(levelColor(entry.level))
                            if !entry.category.isEmpty { Text(entry.category).foregroundColor(.secondary) }
                        }
                        .font(.caption)
                        Text(entry.message)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !isLoading else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let logs = LogStore().fetchLogEntries(
                subsystem: "jp.ourin.*",
                category: "",
                level: .debug,
                since: Date().addingTimeInterval(-24 * 60 * 60)
            ).sorted { $0.timestamp > $1.timestamp }
            DispatchQueue.main.async {
                entries = logs
                isLoading = false
            }
        }
    }

    private func copyAll() {
        let formatter = ISO8601DateFormatter()
        let text = entries.map {
            "\(formatter.string(from: $0.timestamp)) | \($0.level.uppercased()) | \($0.category) | \($0.message)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func levelColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "error": return .orange
        case "fault": return .red
        case "notice": return .green
        default: return .secondary
        }
    }
}

private struct PictureViewerView: View {
    let image: NSImage
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(12)
            }
            Divider()
            Text(path)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(8)
        }
    }
}

private struct ArchiveViewerView: View {
    let archivePath: String
    let entries: [GhostArchiveEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(archivePath)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(10)
            Divider()
            if entries.isEmpty {
                VStack {
                    Text("空のアーカイブです")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    Text(entry.path)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
    }
}

private struct AIGraphView: View {
    let state: String
    let values: [String]

    private var numericValues: [Double] {
        let records = values.isEmpty ? [state] : values
        return records.flatMap { record in
            record.split { character in
                character == "," || character == ";" || character == " " || character == "\t"
            }.compactMap { Double($0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Graph")
                    .font(.headline)
                Spacer()
                Text(state.isEmpty ? "状態なし" : "state: \(state)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            if numericValues.isEmpty {
                Text(values.isEmpty ? state : values.joined(separator: "\n"))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                GeometryReader { geometry in
                    let maximum = max(numericValues.map { abs($0) }.max() ?? 1, 1)
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(Array(numericValues.enumerated()), id: \.offset) { index, value in
                            VStack(spacing: 4) {
                                Text(String(format: "%.2f", value))
                                    .font(.system(size: 10, design: .monospaced))
                                    .rotationEffect(.degrees(-55))
                                    .frame(height: 36)
                                Rectangle()
                                    .fill(value < 0 ? Color.orange : Color.accentColor)
                                    .frame(height: max(2, CGFloat(abs(value) / maximum) * (geometry.size.height - 58)))
                                Text("\(index)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                    .padding(.top, 16)
                }
            }
        }
        .padding(16)
    }
}

private struct BacklogViewerView: View {
    let entriesProvider: () -> [GhostBacklogEntry]
    @State private var entries: [GhostBacklogEntry]

    init(initialEntries: [GhostBacklogEntry], entriesProvider: @escaping () -> [GhostBacklogEntry]) {
        self.entriesProvider = entriesProvider
        _entries = State(initialValue: initialEntries)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("発言履歴（\(entries.count)件）")
                    .font(.headline)
                Spacer()
                Button("コピー", action: copyAll)
                    .disabled(entries.isEmpty)
                Button("更新") { entries = entriesProvider() }
            }
            .padding(12)
            Divider()
            if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                    Text("発言履歴はありません")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(entries.reversed())) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.date, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(entry.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 14)
                            Divider()
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ghostBacklogDidChange)) { _ in
            entries = entriesProvider()
        }
    }

    private func copyAll() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let text = entries.map { "[\(formatter.string(from: $0.date))] \($0.text)" }
            .joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct RateOfUseGraphView: View {
    let title: String
    let isTotal: Bool
    let currentIdentifier: String
    @State private var snapshots: [GhostUsageSnapshot]

    init(title: String, snapshots: [GhostUsageSnapshot], isTotal: Bool, currentIdentifier: String) {
        self.title = title
        self.isTotal = isTotal
        self.currentIdentifier = currentIdentifier
        _snapshots = State(initialValue: snapshots)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("更新", action: reload)
            }

            Text("起動時間を基準にした Ourin の実使用統計。起動回数・発言数・表示文字数も確認できます。")
                .font(.callout)
                .foregroundColor(.secondary)

            Divider()

            if snapshots.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                    Text("使用記録はありません")
                        .foregroundColor(.secondary)
                    Text("ゴーストを起動して会話すると記録されます。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(snapshots) { snapshot in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(snapshot.name)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(snapshot.percent)%")
                                        .font(.system(.body, design: .monospaced))
                                }
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.secondary.opacity(0.18))
                                        Capsule()
                                            .fill(Color.accentColor)
                                            .frame(width: max(2, geometry.size.width * CGFloat(snapshot.percent) / 100))
                                    }
                                }
                                .frame(height: 12)
                                HStack(spacing: 16) {
                                    Text("起動 \(snapshot.bootCount)回")
                                    Text("稼働 \(snapshot.activeMinutes)分")
                                    Text("発言 \(snapshot.talkCount)回")
                                    Text("文字 \(snapshot.characterCount)")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                                if let lastUsedAt = snapshot.lastUsedAt {
                                    Text("最終利用: \(Self.dateFormatter.string(from: lastUsedAt))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(16)
    }

    private func reload() {
        let all = RateOfUseStore.shared.snapshots()
        snapshots = isTotal ? all : all.filter { $0.id == currentIdentifier }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
