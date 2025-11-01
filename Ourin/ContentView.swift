//
//  ContentView.swift
//  MacUkagaka
//
//  Created by eightman on 2025/07/26.
//

import SwiftUI
import AppKit
import OSLog

struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case shioriResource = "SHIORI Resource"
        case pluginsEvents = "Plugins & Events"
        case external = "External"
        case headline = "Headline / Balloon"
        case narInstall = "NAR Install"
        case logging = "Logging & Diagnostics"
        case network = "Network"

        var id: String { rawValue }

        var localized: LocalizedStringKey {
            LocalizedStringKey(rawValue)
        }
    }

    @State private var selection: Section? = .general
    @State private var runningTask: Task<Void, Never>? = nil
    @State private var closeDelegate: CloseConfirmationDelegate? = nil

    private let logger = CompatLogger(subsystem: "jp.ourin.devtools", category: "ui")

    var body: some View {
        NavigationView {
            List(selection: $selection) {
                ForEach(Section.allCases) { section in
                    Text(section.localized)
                        .tag(section)
                }
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 200)

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .modifier(ToolbarModifierIfAvailable(
            reload: reload,
            start: startSelectedGhost,
            export: exportDiagnostics
        ))
        .background(
            WindowAccessor { win in
                if let win = win, closeDelegate == nil {
                    let del = CloseConfirmationDelegate()
                    win.delegate = del
                    closeDelegate = del
                }
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: .devToolsReload)) { _ in
            reload()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .general:
            GeneralSettingsView()
        case .shioriResource:
            ShioriResourceView()
        case .pluginsEvents:
            PluginEventView()
        case .external:
            ExternalEventsView()
        case .headline:
            HeadlineBalloonView()
        case .narInstall:
            NarInstallView()
        case .logging:
            LoggingDiagnosticsView()
        case .network:
            NetworkStatusView()
        case .none:
            Text("Select a section")
        }
    }

    private func reload() {
        logger.info("reload triggered")
        ResourceBridge.shared.invalidateAll()
        if let app = NSApp.delegate as? AppDelegate {
            app.pluginRegistry?.unloadAll()
            app.pluginRegistry?.discoverAndLoad()
        }
    }

    private func startSelectedGhost() {
        let startupGhostKey = "OurinStartupGhost"
        if let ghostName = UserDefaults.standard.string(forKey: startupGhostKey), !ghostName.isEmpty {
            logger.info("starting selected ghost: \(ghostName)")
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.runNamedGhost(name: ghostName)
            }
        } else {
            logger.info("no selected ghost, starting default")
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.installDefaultGhost()
            }
        }
    }

    private func exportDiagnostics() {
        logger.info("export diagnostics")

        if #available(macOS 11.0, *) {
            let logStore = LogStore()
            let since = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            let entries = logStore.fetchLogEntries(subsystem: "jp.ourin.devtools", category: "", level: .undefined, since: since)

            var logText = "Ourin Diagnostics Log - Exported at \(Date())\n\n"
            logText += "Found \(entries.count) entries in the last 24 hours for subsystem 'jp.ourin.devtools'.\n\n"

            for entry in entries {
                logText += "[\(entry.timestamp)] [\(entry.level.uppercased())] [\(entry.category)] \(entry.message)\n"
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("OurinDiagnostics.txt")
            do {
                try logText.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.activateFileViewerSelecting([url])
                logger.info("Diagnostics exported to \(url.path)")
            } catch {
                logger.error("Failed to write diagnostics file: \(error.localizedDescription)")
            }
        } else {
            // Fallback for older macOS versions
            let format = NSLocalizedString("Diagnostics exported at %@", comment: "Diagnostics export message")
            let text = String(format: format, Date().description)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("OurinDiagnostics.txt")
            try? text.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

// MARK: - Conditional toolbar modifier for macOS 11.0+
private struct ToolbarModifierIfAvailable: ViewModifier {
    var reload: () -> Void
    var start: () -> Void
    var export: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button(action: reload) {
                    Image(systemName: "arrow.clockwise")
                }.help(Text("Reload"))

                Button(action: start) {
                    Image(systemName: "play.fill")
                }.help(Text("Start"))

                Button(action: export) {
                    Image(systemName: "square.and.arrow.up")
                }.help(Text("Export"))
            }
        }
    }
}

#Preview {
    ContentView()
}

// MARK: - SHIORI Resource Viewer

fileprivate struct ShioriResourceView: View {
    // Data model for a table row
    fileprivate struct ResourceItem: Identifiable {
        let id = UUID()
        let key: String
        var value: String? // Value from SHIORI
        var overlay: String // User-defined overlay
        var effectiveValue: String { overlay.isEmpty ? (value ?? "") : overlay }
        var lastFetched: Date
    }

    // Filter categories for the segmented control
    fileprivate enum ResourceFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case shiori = "SHIORI"
        case ghost = "Ghost"
        case menu = "Menu"
        case colors = "Colors"
        case update = "Update"
        var id: String { rawValue }
    }

    // Sort field selector
    private enum SortField: String, CaseIterable, Identifiable {
        case key = "Key"
        case value = "Value"
        case effective = "Effective"
        case lastFetched = "Last Fetched"
        var id: String { rawValue }
    }

    @State private var items: [ResourceItem] = []
    @State private var filter: ResourceFilter = .all
    @State private var selection: ResourceItem.ID?
    @State private var overlayStore: [String: String] = [:] // Mock persistence
    @State private var searchText: String = ""
    @State private var sortField: SortField = .key
    @State private var sortAscending: Bool = true
    @State private var showOnlyOverridden: Bool = false

    private var displayedItems: [ResourceItem] {
        // 1) Category filter
        var arr: [ResourceItem]
        if filter == .all {
            arr = items
        } else {
            arr = items.filter { item in
                let key = item.key.lowercased()
                switch filter {
                case .all: return true
                case .shiori: return key.hasPrefix("version") || key.hasPrefix("shiori.") || key.hasPrefix("name") || key.hasPrefix("craftman")
                case .ghost: return key.hasPrefix("ghost.") || key.hasPrefix("shell.")
                case .menu: return key.hasPrefix("menu.")
                case .colors: return key.contains(".color")
                case .update: return key.hasPrefix("update.")
                }
            }
        }
        // 2) Overridden only
        if showOnlyOverridden {
            arr = arr.filter { !$0.overlay.isEmpty }
        }
        // 3) Search
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            arr = arr.filter { item in
                item.key.lowercased().contains(q) ||
                (item.value ?? "").lowercased().contains(q) ||
                item.effectiveValue.lowercased().contains(q)
            }
        }
        // 4) Sort
        arr.sort { lhs, rhs in
            let cmp: ComparisonResult
            switch sortField {
            case .key:
                cmp = lhs.key.localizedCaseInsensitiveCompare(rhs.key)
            case .value:
                cmp = (lhs.value ?? "").localizedCaseInsensitiveCompare(rhs.value ?? "")
            case .effective:
                cmp = lhs.effectiveValue.localizedCaseInsensitiveCompare(rhs.effectiveValue)
            case .lastFetched:
                cmp = lhs.lastFetched.compare(rhs.lastFetched)
            }
            return sortAscending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
        }
        return arr
    }
    
    private var selectedItem: ResourceItem? {
        guard let selection = selection else { return nil }
        return items.first { $0.id == selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolBar
            Divider()
            HSplitView {
                resourceTable
                previewPane
            }
        }
        .onAppear(perform: loadResources)
    }

    private var toolBar: some View {
        HStack(spacing: 12) {
            Picker("Filter", selection: $filter) {
                ForEach(ResourceFilter.allCases) { f in Text(f.rawValue).tag(f) }
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(maxWidth: 420)

            Toggle("Overridden only", isOn: $showOnlyOverridden).toggleStyle(.switch)

            Spacer(minLength: 8)

            // Sort controls (compact)
            Picker("Sort", selection: $sortField) {
                ForEach(SortField.allCases) { f in Text(f.rawValue).tag(f) }
            }.frame(width: 140)
            Toggle("Asc", isOn: $sortAscending).frame(width: 60)

            // Search
            if #available(macOS 12.0, *) {
                TextField("Search…", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 220)
            } else {
                TextField("Search…", text: $searchText).frame(width: 220)
            }

            Button(action: loadResources) { Label("Reload", systemImage: "arrow.clockwise") }
            Button(action: applyOverlay) { Label("Apply", systemImage: "checkmark.circle") }
            Button(action: clearOverlay) { Label("Clear", systemImage: "xmark.circle") }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var resourceTable: some View {
        if #available(macOS 12.0, *) {
            Table(displayedItems, selection: $selection) {
                TableColumn("Key") { item in
                    Text(item.key)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 180, ideal: 220)

                TableColumn("Value (read-only)") { item in
                    Text(item.value ?? "N/A")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .width(min: 180, ideal: 240)

                TableColumn("Overlay (Ourin)") { item in
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        TextField("Override", text: $items[index].overlay)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(applyOverlay)
                    } else {
                        Text("")
                    }
                }
                .width(min: 180, ideal: 220)

                TableColumn("Effective") { item in
                    HStack(spacing: 6) {
                        Text(item.effectiveValue)
                            .font(item.overlay.isEmpty ? .body : .body.bold())
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if !item.overlay.isEmpty {
                            Text("Overridden")
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(6)
                        }
                    }
                }
                .width(min: 200, ideal: 260)

                TableColumn("Last Fetched") { item in
                    Text(item.lastFetched, style: .time)
                        .foregroundColor(.secondary)
                }
                .width(min: 100, ideal: 120)
            }
            .frame(minWidth: 800)
            .contextMenu { contextMenu }
        } else {
            List(displayedItems, selection: $selection) { item in
                HStack {
                    Text(item.key).font(.system(.body, design: .monospaced)).frame(width: 160, alignment: .leading)
                    Text(item.effectiveValue).lineLimit(1)
                    Spacer()
                }
            }.contextMenu { contextMenu }
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let item = selectedItem {
                Text("Preview for \(item.key)").font(.headline).padding(.bottom, 5)
                if item.key.lowercased().contains(".color.") {
                    colorPreview(forKey: item.key)
                } else if item.key.lowercased().hasSuffix(".caption") {
                    menuCaptionPreview(forKey: item.key)
                } else if let url = urlIfPath(from: item.effectiveValue) {
                    imagePreview(from: url)
                } else {
                    Text("No preview available.").foregroundColor(.secondary)
                }
                Spacer()
            } else {
                Text("Select an item to see a preview.").foregroundColor(.secondary)
            }
        }.padding()
    }
    
    @ViewBuilder
    private func colorPreview(forKey key: String) -> some View {
        let baseKey = key.components(separatedBy: ".color.")[0] + ".color"
        let r = Int(items.first { $0.key == "\(baseKey).r" }?.effectiveValue ?? "0") ?? 0
        let g = Int(items.first { $0.key == "\(baseKey).g" }?.effectiveValue ?? "0") ?? 0
        let b = Int(items.first { $0.key == "\(baseKey).b" }?.effectiveValue ?? "0") ?? 0
        let color = Color(NSColor(red: Double(r)/255.0, green: Double(g)/255.0, blue: Double(b)/255.0, alpha: 1.0))
        
        VStack(alignment: .leading) {
            Text("Color Preview (\(baseKey))")
            Rectangle().fill(color).frame(width: 100, height: 100).border(Color.primary, width: 1)
            Text("R: \(r), G: \(g), B: \(b)")
        }
    }
    
    private func menuCaptionPreview(forKey key: String) -> some View {
        guard let item = items.first(where: { $0.key == key }) else {
            return AnyView(Text("Item not found"))
        }
        
        let caption = item.effectiveValue
        var displayCaption = caption
        var shortcut: Character?
        if let amp = caption.firstIndex(of: "&"), caption.index(after: amp) < caption.endIndex {
            shortcut = caption[caption.index(after: amp)]
            displayCaption.remove(at: amp)
        }
        let visibleKey = key.replacingOccurrences(of: ".caption", with: ".visible")
        let visibleStr = items.first(where: { $0.key == visibleKey })?.effectiveValue.lowercased()
        let visible = ["1", "true", "on"].contains(visibleStr ?? "")

        return AnyView(VStack(alignment: .leading) {
            Text("Menu Item Preview")
            Text("Caption: \(displayCaption)")
            Text("Shortcut: \(shortcut.map(String.init) ?? "None")")
            Text("Visible: \(visible ? "Yes" : "No")")
        })
    }
    
    private func urlIfPath(from path: String) -> URL? {
        if ["png", "jpg", "jpeg", "gif", "bmp"].contains(path.split(separator: ".").last?.lowercased() ?? "") {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
    
    @ViewBuilder
    private func imagePreview(from url: URL) -> some View {
        VStack(alignment: .leading) {
            Text("Bitmap Preview")
            if url.isFileURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 200, maxHeight: 200).border(Color.secondary)
            } else {
                Text("Preview not available.")
            }
        }
    }

    private func loadResources() {
        let keys = [
            "version", "name", "craftman", "shiori.version", "ghost.name", "shell.name",
            "menu.background.color.r", "menu.background.color.g", "menu.background.color.b",
            "menu.foreground.color.r", "menu.foreground.color.g", "menu.foreground.color.b",
            "menu.item1.caption", "menu.item1.visible", "update.url", "ghostpath", "shellpath", "homeurl"
        ]
        ResourceBridge.shared.invalidate(keys: keys)
        let now = Date()
        self.items = keys.map { key in
            ResourceItem(key: key, value: ResourceBridge.shared.get(key), overlay: overlayStore[key] ?? "", lastFetched: now)
        }
    }
    
    private func applyOverlay() {
        for item in items {
            if !item.overlay.isEmpty {
                overlayStore[item.key] = item.overlay
            } else {
                overlayStore.removeValue(forKey: item.key)
            }
        }
    }
    
    private func clearOverlay() {
        for index in items.indices {
            items[index].overlay = ""
        }
        overlayStore.removeAll()
    }
}

// MARK: - Context Menu for copy
fileprivate extension ShioriResourceView {
    @ViewBuilder
    var contextMenu: some View {
        Button("Copy key") {
            if let item = selectedItem { NSPasteboard.general.setString(item.key, forType: .string) }
        }
        Button("Copy value") {
            if let item = selectedItem { NSPasteboard.general.setString(item.value ?? "", forType: .string) }
        }
        Button("Copy effective") {
            if let item = selectedItem { NSPasteboard.general.setString(item.effectiveValue, forType: .string) }
        }
    }
}

// MARK: - General Settings View

fileprivate struct GeneralSettingsView: View {
    @State private var dataFolderPath = ""
    @State private var defaultEncoding = "UTF-8"
    @State private var acceptCP932 = true
    @State private var autoStart = false
    @State private var autoUpdate = true
    @State private var rosettaStatus = "Unknown"
    @State private var startupGhost = ""
    @State private var availableGhosts: [String] = []
    @State private var logOutputPath = ""
    @State private var enableFileLogging = false

    private let logger = CompatLogger(subsystem: "jp.ourin.devtools", category: "settings")
    private let startupGhostKey = "OurinStartupGhost"
    private let logOutputPathKey = "OurinLogOutputPath"
    private let enableFileLoggingKey = "OurinEnableFileLogging"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    Text("基本設定").font(.headline)
                    HStack(alignment: .top) {
                        Text("データフォルダ:")
                            .frame(minWidth: 100, alignment: .trailing)
                        TextField("パス", text: $dataFolderPath)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button("参照...") {
                            selectDataFolder()
                        }
                    }

                    HStack(alignment: .top) {
                        Text("文字コード:")
                            .frame(minWidth: 100, alignment: .trailing)
                        Picker("文字コード", selection: $defaultEncoding) {
                            Text("UTF-8").tag("UTF-8")
                            Text("Shift_JIS").tag("Shift_JIS")
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(minWidth: 100)

                        Toggle("CP932 受理", isOn: $acceptCP932)
                        Spacer()
                    }

                    HStack(alignment: .top) {
                        Text("Rosetta互換:")
                            .frame(minWidth: 100, alignment: .trailing)
                        Text(rosettaStatus)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            
                Group {
                    Text("システム設定").font(.headline)
                    Toggle("自動起動", isOn: $autoStart)
                    Toggle("自動アップデート確認", isOn: $autoUpdate)
                    HStack(alignment: .top) {
                        Text("起動ゴースト:")
                            .frame(minWidth: 100, alignment: .trailing)
                        Picker("起動ゴースト", selection: $startupGhost) {
                            ForEach(availableGhosts, id: \.self) { ghost in
                                Text(ghost).tag(ghost)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(minWidth: 150)
                        Spacer()
                    }
                }

                Group {
                    Text("ログ設定").font(.headline)
                    Toggle("ファイルへのログ出力を有効化", isOn: $enableFileLogging)
                    HStack(alignment: .top) {
                        Text("ログ出力先:")
                            .frame(minWidth: 100, alignment: .trailing)
                        TextField("パス", text: $logOutputPath)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disabled(!enableFileLogging)
                        Button("参照...") {
                            selectLogOutputPath()
                        }
                        .disabled(!enableFileLogging)
                    }
                    Text("ログはシステムログと同時にファイルにも出力されます")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 100)
                }

                Group {
                    Text("操作").font(.headline)
                    HStack {
                        Button("設定を保存") {
                            saveSettings()
                        }
                        .buttonStyle(DefaultButtonStyle())

                        Button("デフォルトに戻す") {
                            resetToDefaults()
                        }
                        .buttonStyle(BorderedButtonStyle())

                        Spacer()
                    }
                }
            }
            .padding()
        }
        .onAppear(perform: loadSettings)
    }
    
    private func loadSettings() {
        // データフォルダパスを取得
        if let url = try? OurinPaths.baseDirectory() {
            dataFolderPath = url.path
        }

        // Rosetta状態を確認
        checkRosettaStatus()

        // Load ghosts
        availableGhosts = NarRegistry.shared.installedGhosts()
        if let savedGhost = UserDefaults.standard.string(forKey: startupGhostKey), availableGhosts.contains(savedGhost) {
            startupGhost = savedGhost
        } else if let firstGhost = availableGhosts.first {
            startupGhost = firstGhost
        }

        // Load log settings
        enableFileLogging = UserDefaults.standard.bool(forKey: enableFileLoggingKey)
        logOutputPath = UserDefaults.standard.string(forKey: logOutputPathKey) ?? ""
        // デフォルトのログパスを設定
        if logOutputPath.isEmpty {
            logOutputPath = NSHomeDirectory() + "/Library/Logs/Ourin/ourin.log"
        }

        logger.info("General settings loaded")
    }
    
    private func selectDataFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "データフォルダを選択"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                dataFolderPath = url.path
                logger.info("Data folder selected: \(url.path)")
            }
        }
    }

    private func selectLogOutputPath() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "ourin.log"
        panel.title = "ログファイルの保存先を選択"
        panel.message = "ログファイルを保存する場所を選択してください"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                logOutputPath = url.path
                logger.info("Log output path selected: \(url.path)")
            }
        }
    }
    
    private func checkRosettaStatus() {
        #if arch(x86_64)
        rosettaStatus = "Rosetta2 (Intel emulation)"
        #elseif arch(arm64)
        rosettaStatus = "Native Apple Silicon"
        #else
        rosettaStatus = "Unknown Architecture"
        #endif
    }
    
    private func saveSettings() {
        // 設定の保存処理（実際の実装では UserDefaults や設定ファイルに保存）
        let settings = [
            "dataFolderPath": dataFolderPath,
            "defaultEncoding": defaultEncoding,
            "acceptCP932": acceptCP932,
            "autoStart": autoStart,
            "autoUpdate": autoUpdate
        ] as [String : Any]

        UserDefaults.standard.set(settings, forKey: "OurinGeneralSettings")
        UserDefaults.standard.set(startupGhost, forKey: startupGhostKey)
        UserDefaults.standard.set(enableFileLogging, forKey: enableFileLoggingKey)
        UserDefaults.standard.set(logOutputPath, forKey: logOutputPathKey)
        logger.info("Settings saved: \(settings)")

        // 設定適用の通知
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("設定が保存されました", comment: "Settings saved title")
        alert.informativeText = NSLocalizedString("変更は次回起動時に適用されます", comment: "Settings saved note")
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    private func resetToDefaults() {
        dataFolderPath = NSHomeDirectory() + "/Library/Application Support/Ourin"
        defaultEncoding = "UTF-8"
        acceptCP932 = true
        autoStart = false
        autoUpdate = true
        if let firstGhost = availableGhosts.first {
            startupGhost = firstGhost
        }
        enableFileLogging = false
        logOutputPath = NSHomeDirectory() + "/Library/Logs/Ourin/ourin.log"
        UserDefaults.standard.removeObject(forKey: startupGhostKey)
        UserDefaults.standard.removeObject(forKey: enableFileLoggingKey)
        UserDefaults.standard.removeObject(forKey: logOutputPathKey)

        logger.info("Settings reset to defaults")
    }
}


// MARK: - Headline/Balloon Test View

fileprivate struct HeadlineBalloonView: View {
    @State private var headlineURL = "https://example.com/feed.rss"
    @State private var headlineResponse = ""
    @State private var selectedGhost = ""
    @State private var selectedShell = ""
    @State private var selectedBalloon = ""
    @State private var balloonPreviewScale = 1.0
    @State private var showDPI = false
    @State private var testScript = "\\h\\s[0]こんにちは！\\nこれはテストメッセージです。\\e"
    
    @State private var ghosts: [String] = []
    @State private var shells: [String] = []
    @State private var balloons: [String] = []
    
    var body: some View {
        HSplitView {
            // Headline セクション
            VStack(alignment: .leading, spacing: 15) {
                Text("Headline テスト").font(.headline)
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("URL/Path:")
                        TextField("Headline URL", text: $headlineURL)
                    }
                    
                    HStack {
                        Button("更新テスト") {
                            testHeadlineUpdate()
                        }
                        Button("クリア") {
                            headlineResponse = ""
                        }
                        Spacer()
                    }
                    
                    Text("レスポンス:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        Text(headlineResponse.isEmpty ? "更新テストを実行してください" : headlineResponse)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(5)
                    }
                    .frame(height: 150)
                }
                
                Spacer()
            }
            .padding()
            .frame(minWidth: 300)
            
            // Balloon セクション
            VStack(alignment: .leading, spacing: 15) {
                Text("Balloon テスト").font(.headline)
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("ゴースト:")
                        Picker("ゴースト", selection: $selectedGhost) {
                            ForEach(ghosts, id: \.self) { ghost in
                                Text(ghost).tag(ghost)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 120)
                    }

                    HStack {
                        Text("シェル:")
                        Picker("シェル", selection: $selectedShell) {
                            ForEach(shells, id: \.self) { shell in
                                Text(shell).tag(shell)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 120)
                    }
                    
                    HStack {
                        Text("バルーン:")
                        Picker("バルーン", selection: $selectedBalloon) {
                            ForEach(balloons, id: \.self) { balloon in
                                Text(balloon).tag(balloon)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 120)
                    }
                    
                    HStack {
                        Text("スケール:")
                        Slider(value: $balloonPreviewScale, in: 0.5...2.0, step: 0.1)
                        Text("\(String(format: "%.1f", balloonPreviewScale))x")
                            .frame(width: 40)
                    }
                    
                    Toggle("DPI情報を表示", isOn: $showDPI)
                    
                    Text("テストスクリプト:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $testScript)
                        .frame(height: 80)
                        .border(Color.gray.opacity(0.3), width: 1)
                    
                    HStack {
                        Button("プレビュー") {
                            previewBalloon()
                        }
                        Button("スクリプト実行") {
                            executeScript()
                        }
                        Spacer()
                    }
                }
                
                // バルーンプレビューエリア
                VStack {
                    Text("バルーンプレビュー")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 200 * balloonPreviewScale, height: 100 * balloonPreviewScale)
                        
                        VStack {
                            Text("💬")
                                .font(.system(size: 30 * balloonPreviewScale))
                            Text("\(selectedShell)/\(selectedBalloon)")
                                .font(.caption)
                                .scaleEffect(balloonPreviewScale)
                            
                            if showDPI {
                                Text("72 DPI • 32bit • 透過")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .scaleEffect(balloonPreviewScale)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .frame(minWidth: 350)
        }
        .onAppear(perform: loadData)
    }

    private func loadData() {
        self.ghosts = NarRegistry.shared.installedGhosts()
        self.shells = NarRegistry.shared.installedShells(for: selectedGhost)
        self.balloons = NarRegistry.shared.installedBalloons()

        if selectedGhost.isEmpty, let firstGhost = ghosts.first {
            selectedGhost = firstGhost
        }
        if selectedShell.isEmpty, let firstShell = shells.first {
            selectedShell = firstShell
        }
        if selectedBalloon.isEmpty, let firstBalloon = balloons.first {
            selectedBalloon = firstBalloon
        }
    }
    
    private func testHeadlineUpdate() {
        // Headline URL からデータを取得するテスト
        guard let url = URL(string: headlineURL) else {
            let fmt = NSLocalizedString("Error: %@", comment: "error prefix with message")
            headlineResponse = String(format: fmt, NSLocalizedString("Invalid URL", comment: "invalid URL"))
            return
        }
        
        headlineResponse = NSLocalizedString("Loading...", comment: "loading status")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    let fmt = NSLocalizedString("Error: %@", comment: "error prefix with message")
                    headlineResponse = String(format: fmt, error.localizedDescription)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    let statusFmt = NSLocalizedString("Status: %d", comment: "http status code line")
                    headlineResponse = String(format: statusFmt, httpResponse.statusCode) + "\n"
                    let headersFmt = NSLocalizedString("Headers: %@", comment: "http headers line")
                    headlineResponse += String(format: headersFmt, String(describing: httpResponse.allHeaderFields)) + "\n\n"
                }
                
                if let data = data {
                    let utf8 = String(data: data, encoding: .utf8)
                    let content = utf8 ?? String(format: NSLocalizedString("Binary data (%d bytes)", comment: "binary data placeholder"), data.count)
                    let contentTitle = NSLocalizedString("Content:\n%@", comment: "content block")
                    let body = String(content.prefix(500))
                    headlineResponse += String(format: contentTitle, body)
                    if content.count > 500 {
                        headlineResponse += "\n" + NSLocalizedString("... (truncated)", comment: "truncated suffix")
                    }
                }
            }
        }.resume()
    }
    
    private func previewBalloon() {
        // バルーンプレビューの更新
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Balloon Preview", comment: "Balloon preview title")
        let shellLabel = NSLocalizedString("Shell:", comment: "shell label")
        let balloonLabel = NSLocalizedString("Balloon:", comment: "balloon label")
        let scaleLabel = NSLocalizedString("Scale:", comment: "scale label")
        let dpiLabel = NSLocalizedString("DPI:", comment: "dpi label")
        let enabled = NSLocalizedString("Enabled", comment: "enabled state")
        let disabled = NSLocalizedString("Disabled", comment: "disabled state")
        alert.informativeText = "\(shellLabel) \(selectedShell)\n\(balloonLabel) \(selectedBalloon)\n\(scaleLabel) \(String(format: "%.1f", balloonPreviewScale))x\n\(dpiLabel) \(showDPI ? enabled : disabled)"
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    private func executeScript() {
        // さくらスクリプト実行のテスト
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Script Result", comment: "Script execution result title")
        let execLabel = NSLocalizedString("Executed Script:", comment: "executed script label")
        let parseLabel = NSLocalizedString("Parse Result:", comment: "parse result label")
        let surfaceLabel = NSLocalizedString("- Surface:", comment: "surface label")
        let textLabel = NSLocalizedString("- Text:", comment: "text label")
        let endDetected = NSLocalizedString("- End tag detected", comment: "end tag detected")
        alert.informativeText = "\(execLabel)\n\(testScript)\n\n\(parseLabel)\n\(surfaceLabel) 0\n\(textLabel) \"こんにちは！これはテストメッセージです。\"\n\(endDetected)"
        alert.alertStyle = .informational
        alert.runModal()
    }
}

// MARK: - Plugin Manager & Event Injector

fileprivate struct PluginEventView: View {
    // Data model for a plugin
    fileprivate struct PluginInfo: Identifiable {
        let id: String
        let name: String
        let version: String
        let path: String
        var isEnabled: Bool = true
    }

    // Event definition
    fileprivate struct EventDefinition {
        let id: String
        let refs: [String]
        let notify: Bool
    }

    @State private var plugins: [PluginInfo] = []
    @State private var selection: PluginInfo.ID?
    @State private var selectedEventId: String = "OnGhostBoot"
    @State private var refs: [String] = Array(repeating: "", count: 5)

    private let logger = CompatLogger(subsystem: "jp.ourin.devtools", category: "plugin")
    private let dispatcher = (NSApp.delegate as? AppDelegate)?.pluginDispatcher
    private let registry = (NSApp.delegate as? AppDelegate)?.pluginRegistry

    private let eventDefs: [EventDefinition] = [
        .init(id: "OnGhostBoot", refs: ["WindowIDs", "GhostName", "ShellName", "GhostID", "Path"], notify: false),
        .init(id: "OnGhostExit", refs: ["WindowIDs", "GhostName", "ShellName", "GhostID", "Path"], notify: true),
        .init(id: "OnMenuExec", refs: ["WindowIDs", "GhostName", "ShellName", "GhostID", "Path"], notify: false),
        .init(id: "OnInstallComplete", refs: ["Type", "Name", "Path"], notify: false),
        .init(id: "OnSecondChange", refs: [], notify: false),
    ]

    private var selectedEventDef: EventDefinition? {
        eventDefs.first { $0.id == selectedEventId }
    }

    var body: some View {
        HSplitView {
            pluginList.frame(minWidth: 300, idealWidth: 400)
            eventInjector.frame(minWidth: 400)
        }
        .onAppear(perform: loadPlugins)
    }

    private var pluginList: some View {
        VStack(alignment: .leading) {
            Text("Loaded Plugins").font(.headline).padding([.top, .leading])
            if #available(macOS 12.0, *) {
                Table(plugins, selection: $selection) {
                    TableColumn("Enabled") { item in
                        Toggle("", isOn: binding(for: item.id)).labelsHidden()
                    }.width(40)
                    TableColumn("Name", value: \.name)
                    TableColumn("ID", value: \.id)
                    TableColumn("Version", value: \.version)
                    TableColumn("Path", value: \.path)
                }
            } else {
                List(plugins) { item in
                    HStack {
                        Toggle("", isOn: binding(for: item.id)).labelsHidden()
                        Text(item.name)
                        Spacer()
                        Text(item.id).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var eventInjector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Event Injector").font(.headline)
            Picker("Event ID", selection: $selectedEventId) {
                ForEach(eventDefs, id: \.id) { def in
                    Text(def.id).tag(def.id)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .onChange(of: selectedEventId) { _ in
                refs = Array(repeating: "", count: 5)
            }

            if let def = selectedEventDef {
                ForEach(0..<def.refs.count, id: \.self) { i in
                    HStack {
                        Text("Ref\(i): \(def.refs[i])").frame(width: 120, alignment: .trailing)
                        TextField("Value", text: $refs[i])
                    }
                }
            }

            HStack {
                Spacer()
                Button(action: dispatchEvent) {
                    Label("Dispatch", systemImage: "paperplane.fill")
                }
            }
            Spacer()
        }
        .padding()
    }

    private func binding(for id: String) -> Binding<Bool> {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else {
            fatalError("Plugin not found")
        }
        return $plugins[index].isEnabled
    }

    private func loadPlugins() {
        guard let registry = registry else {
            logger.warning("PluginRegistry not found")
            return
        }
        self.plugins = registry.metas.map { (plugin, meta) in
            PluginInfo(
                id: meta.id,
                name: meta.name,
                version: plugin.bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A",
                path: plugin.bundle.bundleURL.lastPathComponent
            )
        }.sorted { $0.name < $1.name }
        logger.info("Loaded \(self.plugins.count) plugins for display")
    }

    private func dispatchEvent() {
        guard let dispatcher = dispatcher, let def = selectedEventDef else {
            logger.warning("Dispatcher or event definition not found")
            return
        }
        let finalRefs = Array(refs.prefix(def.refs.count))
        logger.info("Dispatching \(def.id) with refs: \(finalRefs.joined(separator: ", "))")
        dispatcher.onArbitraryEvent(id: def.id, refs: finalRefs, notify: def.notify)
    }
}

// MARK: - External Events Harness

fileprivate struct ExternalEventsView: View {
    @State private var tcpStatus = "Stopped"
    @State private var httpStatus = "Stopped"
    @State private var xpcStatus = "Stopped"
    @State private var tcpConnections = 0
    @State private var httpRequests = 0
    @State private var xpcClients = 0
    @State private var sampleRequest = "NOTIFY SSTP/1.1\r\nSender: ExternalTester\r\nEvent: OnSecondChange\r\n\r\n"
    
    private let logger = CompatLogger(subsystem: "jp.ourin.devtools", category: "external")
    private let externalServer = (NSApp.delegate as? AppDelegate)?.externalServer

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("External Events Harness").font(.largeTitle).padding(.bottom)
            
            serversStatus
            Divider()
            utilityTools
            Spacer()
        }
        .padding()
        .onAppear(perform: loadStatus)
    }
    
    private var serversStatus: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Server Status").font(.headline)
            
            // TCP SSTP Server
            HStack {
                VStack(alignment: .leading) {
                    Text("SSTP (TCP/9801)").font(.subheadline)
                    Text("Status: \(tcpStatus)").foregroundColor(tcpStatus == "Running" ? .green : .red)
                    Text("Connections: \(tcpConnections)")
                }
                Spacer()
                Button(tcpStatus == "Running" ? "Stop" : "Start") {
                    toggleTcpServer()
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            // HTTP Server
            HStack {
                VStack(alignment: .leading) {
                    Text("HTTP (/api/sstp/v1)").font(.subheadline)
                    Text("Status: \(httpStatus)").foregroundColor(httpStatus == "Running" ? .green : .red)
                    Text("Requests: \(httpRequests)")
                }
                Spacer()
                Button(httpStatus == "Running" ? "Stop" : "Start") {
                    toggleHttpServer()
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            // XPC Server
            HStack {
                VStack(alignment: .leading) {
                    Text("XPC (jp.ourin.sstp)").font(.subheadline)
                    Text("Status: \(xpcStatus)").foregroundColor(xpcStatus == "Running" ? .green : .red)
                    Text("Clients: \(xpcClients)")
                }
                Spacer()
                Button("Start") {
                    startXpcServer()
                }.disabled(xpcStatus == "Running")
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private var utilityTools: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Utility Tools").font(.headline)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Sample SSTP Request").font(.subheadline)
                TextEditor(text: $sampleRequest)
                    .frame(height: 100)
                    .border(Color.gray, width: 1)
                
                HStack {
                    Button("Send to TCP") {
                        sendSampleRequest(via: .tcp)
                    }
                    Button("Send via HTTP") {
                        sendSampleRequest(via: .http)
                    }
                    Button("Copy curl Command") {
                        copyCurlCommand()
                    }
                    Button("Copy XPC Snippet") {
                        copyXpcSnippet()
                    }
                }
            }
        }
    }
    
    private enum RequestMethod {
        case tcp, http, xpc
    }
    
    private func loadStatus() {
        // Mock status for now - in real implementation, query actual server status
        tcpStatus = "Stopped"
        httpStatus = "Stopped"
        xpcStatus = "Running"
        tcpConnections = 0
        httpRequests = 42
        xpcClients = 1
    }
    
    private func toggleTcpServer() {
        guard let server = externalServer else { return }
        
        if tcpStatus == "Running" {
            server.stop()
            tcpStatus = "Stopped"
            logger.info("TCP server stopped")
        } else {
            server.start()
            tcpStatus = "Running"
            logger.info("TCP server started")
        }
    }
    
    private func toggleHttpServer() {
        guard let server = externalServer else { return }
        
        if httpStatus == "Running" {
            server.stop()
            httpStatus = "Stopped"
            logger.info("HTTP server stopped")
        } else {
            server.start()
            httpStatus = "Running"
            logger.info("HTTP server started")
        }
    }
    
    private func startXpcServer() {
        guard let server = externalServer else { return }
        server.start()
        xpcStatus = "Running"
        logger.info("XPC server started")
    }
    
    private func sendSampleRequest(via method: RequestMethod) {
        switch method {
        case .tcp:
            logger.info("Sending sample request via TCP: \(sampleRequest)")
            // Send to localhost:9801
        case .http:
            logger.info("Sending sample request via HTTP")
            // POST to localhost:9810/api/sstp/v1
        case .xpc:
            logger.info("Sending sample request via XPC")
            // Send via XPC connection
        }
    }
    
    private func copyCurlCommand() {
        let curlCommand = """
        curl -X POST http://localhost:9810/api/sstp/v1 \\
        -H "Content-Type: text/plain" \\
        -d "\(sampleRequest)"
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(curlCommand, forType: .string)
        logger.info("Curl command copied to clipboard")
    }
    
    private func copyXpcSnippet() {
        let xpcSnippet = """
        // Swift XPC Client Code
        let connection = NSXPCConnection(machServiceName: "jp.ourin.sstp")
        connection.remoteObjectInterface = NSXPCInterface(with: OurinSSTPProtocol.self)
        connection.resume()
        
        let service = connection.remoteObjectProxy as? OurinSSTPProtocol
        service?.deliverSSTP("\(sampleRequest)".data(using: .utf8)!) { response in
            print("Response: \\(response)")
        }
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(xpcSnippet, forType: .string)
        logger.info("XPC snippet copied to clipboard")
    }
}

// MARK: - Logging & Diagnostics View

fileprivate struct LoggingDiagnosticsView: View {
    @State private var selectedSubsystem = "jp.ourin.*"
    @State private var selectedCategory = ""
    @State private var selectedLevel = "all"
    @State private var sincePeriod = "1h"
    @State private var logEntries: [LogEntry] = []
    @State private var signpostData: [SignpostEntry] = []
    @State private var showSignpostTimeline = false
    @State private var selection: Set<LogEntry.ID> = []

    @State private var logStore = LogStore()

    private let subsystems = ["jp.ourin.*", "jp.ourin.devtools", "Ourin", "jp.ourin.plugin"]
    private let categories = ["", "ui", "plugin", "resource", "external", "settings"]
    private let levels = ["all", "debug", "info", "notice", "error", "fault"]
    private let periods = ["1h", "6h", "1d", "3d", "1w"]
    
    var body: some View {
        VStack(spacing: 0) {
            // クエリバー
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Subsystem:")
                        .font(.caption)
                    Picker("Subsystem", selection: $selectedSubsystem) {
                        ForEach(subsystems, id: \.self) { system in
                            Text(system).tag(system)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 120)
                }
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("Category:")
                        .font(.caption)
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { category in
                            Text(category.isEmpty ? "All" : category).tag(category)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 100)
                }
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("Level:")
                        .font(.caption)
                    Picker("Level", selection: $selectedLevel) {
                        ForEach(levels, id: \.self) { level in
                            Text(level.capitalized).tag(level)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 80)
                }
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("Since:")
                        .font(.caption)
                    Picker("Since", selection: $sincePeriod) {
                        ForEach(periods, id: \.self) { period in
                            Text(period).tag(period)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 60)
                }
                
                Spacer()
                
                Button("更新") {
                    loadLogs()
                }
                
                Button("クリア") {
                    logEntries.removeAll()
                }

                Button("コピー") {
                    copySelectedLogs()
                }
                .disabled(selection.isEmpty)

                Toggle("Signpost Timeline", isOn: $showSignpostTimeline)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            
            if showSignpostTimeline {
                // Signpost Timeline
                VStack(alignment: .leading) {
                    Text("Signpost Timeline")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(signpostData) { entry in
                                signpostView(for: entry)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 120)
                    .background(Color.black.opacity(0.05))
                }
                
                Divider()
            }
            
            // ログテーブル
            VStack(alignment: .leading) {
                Text("Log Entries (\(logEntries.count) entries)")
                    .font(.headline)
                    .padding(.horizontal)
                
                if #available(macOS 12.0, *) {
                    Table(logEntries, selection: $selection) {
                        TableColumn("Time") { entry in
                            Text(entry.timestamp, style: .time)
                                .textSelection(.enabled)
                        }.width(min: 80, ideal: 100)

                        TableColumn("Level") { entry in
                            HStack {
                                Circle()
                                    .fill(colorForLevel(entry.level))
                                    .frame(width: 8, height: 8)
                                Text(entry.level.capitalized)
                                    .textSelection(.enabled)
                            }
                        }.width(min: 60, ideal: 80)

                        TableColumn("Category") { entry in
                            Text(entry.category)
                                .textSelection(.enabled)
                        }.width(min: 80, ideal: 120)

                        TableColumn("Message") { entry in
                            Text(entry.message)
                                .textSelection(.enabled)
                        }.width(min: 200)

                        TableColumn("Metadata") { entry in
                            if !entry.metadata.isEmpty {
                                Text(entry.metadata)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                        }.width(min: 100, ideal: 150)
                    }
                    .contextMenu {
                        contextMenuContent
                    }
                } else {
                    List(logEntries, selection: $selection) { entry in
                        HStack {
                            Text(entry.timestamp, style: .time)
                                .frame(width: 80)
                            Circle()
                                .fill(colorForLevel(entry.level))
                                .frame(width: 8, height: 8)
                            Text(entry.level)
                                .frame(width: 60)
                            Text(entry.category)
                                .frame(width: 100)
                            Text(entry.message)
                            Spacer()
                        }
                    }
                    .contextMenu {
                        contextMenuContent
                    }
                }
            }
        }
        .onAppear(perform: loadLogs)
    }
    
    @ViewBuilder
    private func signpostView(for entry: SignpostEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.name)
                .font(.caption)
                .fontWeight(.medium)
            
            RoundedRectangle(cornerRadius: 3)
                .fill(entry.type == .interval ? Color.blue : Color.green)
                .frame(width: max(20, entry.duration * 100), height: 20)
            
            Text("\(String(format: "%.2f", entry.duration))s")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private func colorForLevel(_ level: String) -> Color {
        switch level.lowercased() {
        case "debug": return .gray
        case "info": return .blue
        case "notice": return .green
        case "error": return .orange
        case "fault": return .red
        default: return .primary
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        Button("選択したログをコピー") {
            copySelectedLogs()
        }
        .disabled(selection.isEmpty)

        Button("すべてコピー") {
            copyAllLogs()
        }
        .disabled(logEntries.isEmpty)

        Divider()

        Button("選択をクリア") {
            selection.removeAll()
        }
        .disabled(selection.isEmpty)
    }

    private func copySelectedLogs() {
        let selectedEntries = logEntries.filter { selection.contains($0.id) }
        guard !selectedEntries.isEmpty else { return }

        let text = selectedEntries.map { entry in
            formatLogEntry(entry)
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyAllLogs() {
        let text = logEntries.map { entry in
            formatLogEntry(entry)
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func formatLogEntry(_ entry: LogEntry) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timeString = formatter.string(from: entry.timestamp)

        var parts = [timeString, entry.level.uppercased(), entry.category, entry.message]
        if !entry.metadata.isEmpty {
            parts.append("[\(entry.metadata)]")
        }
        return parts.joined(separator: " | ")
    }

    private func loadLogs() {
        if #available(macOS 11.0, *) {
            let sinceDate: Date
            switch sincePeriod {
            case "1h": sinceDate = Calendar.current.date(byAdding: .hour, value: -1, to: Date())!
            case "6h": sinceDate = Calendar.current.date(byAdding: .hour, value: -6, to: Date())!
            case "1d": sinceDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
            case "3d": sinceDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
            case "1w": sinceDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date())!
            default: sinceDate = Date().addingTimeInterval(-3600)
            }

            let level = OSLogEntryLog.Level.fromString(selectedLevel)

            logEntries = logStore.fetchLogEntries(
                subsystem: selectedSubsystem,
                category: selectedCategory,
                level: level,
                since: sinceDate
            ).sorted(by: { $0.timestamp > $1.timestamp })
        }
        
        // Signpost データの模擬実装はそのまま
        signpostData = [
            SignpostEntry(name: "ourin.resource.apply", type: .interval, duration: 0.12),
            SignpostEntry(name: "ourin.plugin.inject", type: .interval, duration: 0.05),
            SignpostEntry(name: "ourin.net.sstp", type: .instant, duration: 0.01),
            SignpostEntry(name: "ourin.ghost.boot", type: .interval, duration: 0.25),
            SignpostEntry(name: "ourin.script.parse", type: .interval, duration: 0.08)
        ]
    }
}


// MARK: - Network Status View

fileprivate struct NetworkStatusView: View {
    @State private var tcpRunning = false
    @State private var httpRunning = false
    @State private var xpcRunning = false
    @State private var averageLatency: Double = 0
    @State private var errorRate: Double = 0
    @State private var updateTimer: Timer?

    private let externalServer = (NSApp.delegate as? AppDelegate)?.externalServer
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Network & Listener Status")
                    .font(.largeTitle)
                    .padding(.bottom)
                
                // SSTP (TCP/9801) Status
                VStack(alignment: .leading) {
                    Text("SSTP (TCP/9801)").font(.headline)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            statusIndicator(color: tcpRunning ? .green : .gray)
                            Text("状態: \(tcpRunning ? "稼働中" : "停止中")")
                            Spacer()
                        }

                        if tcpRunning {
                            HStack {
                                Text("平均レイテンシ:")
                                Text("\(String(format: "%.1f", averageLatency * 1000))ms")
                                    .foregroundColor(averageLatency > 0.1 ? .orange : .green)
                                Spacer()
                            }

                            HStack {
                                Text("エラー率:")
                                Text("\(String(format: "%.2f", errorRate * 100))%")
                                    .foregroundColor(errorRate > 0.05 ? .red : .green)
                                Spacer()
                            }
                        }

                        Text("Network.framework の NWListener を使用")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                // HTTP (9810) Status
                VStack(alignment: .leading) {
                    Text("HTTP (9810)").font(.headline)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            statusIndicator(color: httpRunning ? .green : .gray)
                            Text("状態: \(httpRunning ? "稼働中" : "停止中")")
                            Spacer()
                        }

                        if httpRunning {
                            HStack {
                                Text("平均レイテンシ:")
                                Text("\(String(format: "%.1f", averageLatency * 1000))ms")
                                    .foregroundColor(averageLatency > 0.1 ? .orange : .green)
                                Spacer()
                            }

                            HStack {
                                Text("エラー率:")
                                Text("\(String(format: "%.2f", errorRate * 100))%")
                                    .foregroundColor(errorRate > 0.05 ? .red : .green)
                                Spacer()
                            }
                        }

                        Text("POST /api/sstp/v1 エンドポイントを提供")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                // XPC Status
                VStack(alignment: .leading) {
                    Text("XPC (jp.ourin.sstp)").font(.headline)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            statusIndicator(color: xpcRunning ? .green : .gray)
                            Text("状態: \(xpcRunning ? "稼働中" : "停止中")")
                            Spacer()
                        }

                        if xpcRunning {
                            HStack {
                                Text("平均レイテンシ:")
                                Text("\(String(format: "%.1f", averageLatency * 1000))ms")
                                    .foregroundColor(averageLatency > 0.1 ? .orange : .green)
                                Spacer()
                            }

                            HStack {
                                Text("エラー率:")
                                Text("\(String(format: "%.2f", errorRate * 100))%")
                                    .foregroundColor(errorRate > 0.05 ? .red : .green)
                                Spacer()
                            }
                        }

                        Text("machService 経由の直接通信")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                // Technical Notes
                VStack(alignment: .leading) {
                    Text("技術仕様").font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Network.framework を使用（Apple推奨、ソケット代替）")
                        Text("• 技術選定ノート TN3151 準拠")
                        Text("• ローカルネットワーク権限が必要")
                        Text("• TeamID/コード署名によるXPC権限制御")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                }
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                Spacer()
            }
            .padding()
        }
        .onAppear {
            startUpdating()
        }
        .onDisappear {
            updateTimer?.invalidate()
        }
    }
    
    @ViewBuilder
    private func statusIndicator(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: 2)
                    .scaleEffect(1.5)
                    .opacity(color == .green ? 1 : 0)
                    .animation(.easeInOut(duration: 1).repeatForever(), value: color == .green)
            )
    }
    
    private func startUpdating() {
        // 初回の状態取得
        updateStatus()

        // 定期的に状態を更新
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.updateStatus()
        }
    }

    private func updateStatus() {
        guard let server = externalServer else { return }

        // サーバーの稼働状態を取得
        tcpRunning = server.tcp.isRunning
        httpRunning = server.http.isRunning
        xpcRunning = server.xpc.isRunning

        // メトリクスを取得
        averageLatency = ServerMetrics.shared.averageLatency
        errorRate = ServerMetrics.shared.errorRate
    }
}
