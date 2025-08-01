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
    @State private var ghostWindow: NSWindow? = nil
    @State private var testYaya: YayaAdapter? = nil

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
            runTest: runTestScenario,
            stop: stopScenario,
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
        .onReceive(NotificationCenter.default.publisher(for: .testScenarioStarted)) { _ in
            runTestScenario()
        }
        .onReceive(NotificationCenter.default.publisher(for: .testScenarioStopped)) { _ in
            stopScenario()
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

    private func runTestScenario() {
        logger.info("run test scenario")
        stopScenario()
        
        // ゴーストウィンドウを表示
        showGhostWindow()
        
        guard let dispatcher = (NSApp.delegate as? AppDelegate)?.pluginDispatcher else { return }
        let windows = NSApplication.shared.windows
        let path = Bundle.main.bundlePath
        
        runningTask = Task {
            // まずテスト用のゴーストを起動してみる
            await startTestGhost()
            
            // プラグインイベントを送信
            dispatcher.onGhostBoot(windows: windows, ghostName: "TestGhost", shellName: "default", ghostID: "test", path: path)
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒待機
            
            dispatcher.onMenuExec(windows: windows, ghostName: "TestGhost", shellName: "default", ghostID: "test", path: path)
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒待機
            
            dispatcher.onGhostExit(windows: windows, ghostName: "TestGhost", shellName: "default", ghostID: "test", path: path)
            
            // ゴーストウィンドウを閉じる
            await MainActor.run {
                closeGhostWindow()
            }
        }
    }

    private func stopScenario() {
        logger.info("stop scenario")
        runningTask?.cancel()
        runningTask = nil
        closeGhostWindow()
        testYaya?.unload()
        testYaya = nil
    }
    
    private func showGhostWindow() {
        if ghostWindow == nil {
            let controller = NSHostingController(rootView: TestGhostView())
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 300, height: 400))
            window.title = "Test Ghost"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            ghostWindow = window
        }
        ghostWindow?.makeKeyAndOrderFront(nil)
        logger.info("Ghost window displayed")
    }
    
    private func closeGhostWindow() {
        ghostWindow?.close()
        ghostWindow = nil
        logger.info("Ghost window closed")
    }
    
    private func startTestGhost() async {
        logger.info("Starting test ghost with YAYA adapter")
        
        // サンプルのゴーストパス（実在しない場合は単純なテキスト表示）
        let sampleGhostPaths = [
            Bundle.main.bundlePath + "/Contents/Resources/ghost/test",
            NSHomeDirectory() + "/Desktop/ghost/test",
            "/tmp/test_ghost"
        ]
        
        for ghostPath in sampleGhostPaths {
            if FileManager.default.fileExists(atPath: ghostPath) {
                if let yaya = YayaAdapter() {
                    testYaya = yaya
                    let ghostRoot = URL(fileURLWithPath: ghostPath).appendingPathComponent("ghost/master")
                    
                    // YAYA辞書ファイルを探す
                    if let contents = try? FileManager.default.contentsOfDirectory(at: ghostRoot, includingPropertiesForKeys: nil) {
                        let dics = contents.filter { $0.pathExtension.lowercased() == "dic" }.map { $0.lastPathComponent }
                        
                        if yaya.load(ghostRoot: ghostRoot, dics: dics) {
                            if let res = yaya.request(method: "GET", id: "OnBoot"), res.ok {
                                logger.info("Ghost OnBoot: \(res.value ?? "empty")")
                                return
                            }
                        }
                    }
                }
            }
        }
        
        logger.info("No valid ghost found, showing demo ghost")
    }

    private func exportDiagnostics() {
        logger.info("export diagnostics")
        let format = NSLocalizedString("Diagnostics exported at %@", comment: "Diagnostics export message")
        let text = String(format: format, Date().description)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OurinDiagnostics.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Conditional toolbar modifier for macOS 11.0+
private struct ToolbarModifierIfAvailable: ViewModifier {
    var reload: () -> Void
    var runTest: () -> Void
    var stop: () -> Void
    var export: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button(action: reload) {
                    Image(systemName: "arrow.clockwise")
                }.help(Text("Reload"))

                Button(action: runTest) {
                    Image(systemName: "play.fill")
                }.help(Text("Run Test"))

                Button(action: stop) {
                    Image(systemName: "stop.fill")
                }.help(Text("Stop"))

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

    @State private var items: [ResourceItem] = []
    @State private var filter: ResourceFilter = .all
    @State private var selection: ResourceItem.ID?
    @State private var overlayStore: [String: String] = [:] // Mock persistence

    private var filteredItems: [ResourceItem] {
        if filter == .all { return items }
        return items.filter { item in
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
        HStack {
            Picker("Filter", selection: $filter) {
                ForEach(ResourceFilter.allCases) { f in Text(f.rawValue).tag(f) }
            }
            .pickerStyle(SegmentedPickerStyle()).frame(maxWidth: 400)
            Spacer()
            Button(action: loadResources) { Label("Reload", systemImage: "arrow.clockwise") }
            Button(action: applyOverlay) { Label("Apply Overlay", systemImage: "checkmark.circle") }
            Button(action: clearOverlay) { Label("Clear Overlay", systemImage: "xmark.circle") }
        }.padding()
    }

    @ViewBuilder
    private var resourceTable: some View {
        if #available(macOS 12.0, *) {
            Table(filteredItems, selection: $selection) {
                TableColumn("Key", value: \.key).width(min: 150, ideal: 200)
                TableColumn("Value (read-only)") { item in Text(item.value ?? "N/A") }.width(min: 150, ideal: 200)
                TableColumn("Overlay (Ourin)") { item in
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        TextField("Override", text: $items[index].overlay).onSubmit(applyOverlay)
                    } else { Text("Error") }
                }.width(min: 150, ideal: 200)
                TableColumn("Effective") { item in
                    Text(item.effectiveValue).fontWeight(item.overlay.isEmpty ? .regular : .bold)
                }.width(min: 150, ideal: 200)
                TableColumn("Last Fetched") { item in Text(item.lastFetched, style: .time) }.width(min: 80, ideal: 100)
            }.frame(minWidth: 600)
        } else {
            List(filteredItems, selection: $selection) { item in
                HStack {
                    Text(item.key).frame(width: 150)
                    Text(item.effectiveValue)
                    Spacer()
                }
            }
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

// MARK: - General Settings View

fileprivate struct GeneralSettingsView: View {
    @State private var dataFolderPath = ""
    @State private var defaultEncoding = "UTF-8"
    @State private var acceptCP932 = true
    @State private var autoStart = false
    @State private var autoUpdate = true
    @State private var rosettaStatus = "Unknown"
    
    private let logger = CompatLogger(subsystem: "jp.ourin.devtools", category: "settings")
    
    var body: some View {
        Form {
            Group {
                Text("基本設定").font(.headline).padding(.bottom, 5)
                HStack {
                    Text("データフォルダ:")
                        .frame(width: 120, alignment: .trailing)
                    TextField("パス", text: $dataFolderPath)
                    Button("参照...") {
                        selectDataFolder()
                    }
                }
                
                HStack {
                    Text("文字コード:")
                        .frame(width: 120, alignment: .trailing)
                    Picker("文字コード", selection: $defaultEncoding) {
                        Text("UTF-8").tag("UTF-8")
                        Text("Shift_JIS").tag("Shift_JIS")
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 120)
                    
                    Toggle("CP932 受理", isOn: $acceptCP932)
                }
                
                HStack {
                    Text("Rosetta互換:")
                        .frame(width: 120, alignment: .trailing)
                    Text(rosettaStatus)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            
            Group {
                Text("システム設定").font(.headline).padding(.bottom, 5)
                Toggle("自動起動", isOn: $autoStart)
                Toggle("自動アップデート確認", isOn: $autoUpdate)
            }
            
            Group {
                Text("操作").font(.headline).padding(.bottom, 5)
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
        .onAppear(perform: loadSettings)
    }
    
    private func loadSettings() {
        // データフォルダパスを取得
        if let url = try? OurinPaths.baseDirectory() {
            dataFolderPath = url.path
        }
        
        // Rosetta状態を確認
        checkRosettaStatus()
        
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
        logger.info("Settings saved: \(settings)")
        
        // 設定適用の通知
        let alert = NSAlert()
        alert.messageText = "設定が保存されました"
        alert.informativeText = "変更は次回起動時に適用されます"
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    private func resetToDefaults() {
        dataFolderPath = NSHomeDirectory() + "/Library/Application Support/Ourin"
        defaultEncoding = "UTF-8"
        acceptCP932 = true
        autoStart = false
        autoUpdate = true
        
        logger.info("Settings reset to defaults")
    }
}

// MARK: - Test Ghost View

fileprivate struct TestGhostView: View {
    @State private var currentMessage = "👻 テストゴーストが起動中..."
    @State private var messageIndex = 0
    @State private var timer: Timer?
    
    private let messages = [
        "👻 こんにちは！テストゴーストです",
        "🎭 SHIORI システムをテスト中...",
        "📝 プラグインイベントを受信しました",
        "🔄 OnGhostBoot イベント実行中",
        "⚡ OnMenuExec イベント実行中",
        "👋 OnGhostExit - まもなく終了します"
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            // ゴーストキャラクター表示エリア
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 200, height: 200)
                
                VStack {
                    Text("👻")
                        .font(.system(size: 60))
                        .scaleEffect(sin(Date().timeIntervalSince1970 * 2) * 0.1 + 1.0)
                        .animation(.easeInOut(duration: 1).repeatForever(), value: Date())
                    
                    Text("テストゴースト")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // メッセージバルーン
            VStack {
                Text(currentMessage)
                    .padding()
                    .background(Color.primary.opacity(0.1))
                    .cornerRadius(10)
                    .frame(maxWidth: 250)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut, value: currentMessage)
                
                Text("SHIORI Test Mode")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("DevTools Test Scenario実行中")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            startMessageCycle()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startMessageCycle() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentMessage = messages[messageIndex % messages.count]
                messageIndex += 1
            }
        }
    }
}

// MARK: - Headline/Balloon Test View

fileprivate struct HeadlineBalloonView: View {
    @State private var headlineURL = "https://example.com/feed.rss"
    @State private var headlineResponse = ""
    @State private var selectedShell = "master"
    @State private var selectedBalloon = "balloon1"
    @State private var balloonPreviewScale = 1.0
    @State private var showDPI = false
    @State private var testScript = "\\h\\s[0]こんにちは！\\nこれはテストメッセージです。\\e"
    
    private let shells = ["master", "shell1", "shell2"]
    private let balloons = ["balloon1", "balloon2", "balloon3"]
    
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
    }
    
    private func testHeadlineUpdate() {
        // Headline URL からデータを取得するテスト
        guard let url = URL(string: headlineURL) else {
            headlineResponse = "Error: Invalid URL"
            return
        }
        
        headlineResponse = "Loading..."
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    headlineResponse = "Error: \(error.localizedDescription)"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    headlineResponse = "Status: \(httpResponse.statusCode)\n"
                    headlineResponse += "Headers: \(httpResponse.allHeaderFields)\n\n"
                }
                
                if let data = data {
                    let content = String(data: data, encoding: .utf8) ?? "Binary data (\(data.count) bytes)"
                    headlineResponse += "Content:\n\(content.prefix(500))"
                    if content.count > 500 {
                        headlineResponse += "\n... (truncated)"
                    }
                }
            }
        }.resume()
    }
    
    private func previewBalloon() {
        // バルーンプレビューの更新
        let alert = NSAlert()
        alert.messageText = "バルーンプレビュー"
        alert.informativeText = """
        シェル: \(selectedShell)
        バルーン: \(selectedBalloon)
        スケール: \(String(format: "%.1f", balloonPreviewScale))x
        DPI表示: \(showDPI ? "有効" : "無効")
        """
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    private func executeScript() {
        // さくらスクリプト実行のテスト
        let alert = NSAlert()
        alert.messageText = "スクリプト実行結果"
        alert.informativeText = """
        実行スクリプト:
        \(testScript)
        
        パース結果:
        - Surface: 0
        - テキスト: "こんにちは！これはテストメッセージです。"
        - 終了タグ検出
        """
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
                    Table(logEntries) {
                        TableColumn("Time") { entry in
                            Text(entry.timestamp, style: .time)
                        }.width(min: 80, ideal: 100)
                        
                        TableColumn("Level") { entry in
                            HStack {
                                Circle()
                                    .fill(colorForLevel(entry.level))
                                    .frame(width: 8, height: 8)
                                Text(entry.level.capitalized)
                            }
                        }.width(min: 60, ideal: 80)
                        
                        TableColumn("Category", value: \.category).width(min: 80, ideal: 120)
                        TableColumn("Message", value: \.message).width(min: 200)
                        
                        TableColumn("Metadata") { entry in
                            if !entry.metadata.isEmpty {
                                Text(entry.metadata)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }.width(min: 100, ideal: 150)
                    }
                } else {
                    List(logEntries) { entry in
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
    
    private func loadLogs() {
        // OSLogStore からログを取得する（模擬実装）
        logEntries = [
            LogEntry(timestamp: Date(), level: "info", category: "ui", message: "DevTools started", metadata: ""),
            LogEntry(timestamp: Date().addingTimeInterval(-60), level: "debug", category: "plugin", message: "Plugin loaded: TestPlugin", metadata: "bundle: TestPlugin.plugin"),
            LogEntry(timestamp: Date().addingTimeInterval(-120), level: "error", category: "resource", message: "Failed to load resource", metadata: "key: ghost.name"),
            LogEntry(timestamp: Date().addingTimeInterval(-180), level: "notice", category: "external", message: "SSTP server started", metadata: "port: 9801"),
            LogEntry(timestamp: Date().addingTimeInterval(-240), level: "info", category: "settings", message: "Settings loaded", metadata: "path: ~/Library/Preferences/...")
        ]
        
        // Signpost データの模擬実装
        signpostData = [
            SignpostEntry(name: "ourin.resource.apply", type: .interval, duration: 0.12),
            SignpostEntry(name: "ourin.plugin.inject", type: .interval, duration: 0.05),
            SignpostEntry(name: "ourin.net.sstp", type: .instant, duration: 0.01),
            SignpostEntry(name: "ourin.ghost.boot", type: .interval, duration: 0.25),
            SignpostEntry(name: "ourin.script.parse", type: .interval, duration: 0.08)
        ]
    }
}

// MARK: - Log Data Models

fileprivate struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: String
    let category: String
    let message: String
    let metadata: String
}

fileprivate struct SignpostEntry: Identifiable {
    let id = UUID()
    let name: String
    let type: SignpostType
    let duration: Double
}

fileprivate enum SignpostType {
    case interval
    case instant
}

// MARK: - Network Status View

fileprivate struct NetworkStatusView: View {
    @State private var sstpConnections = 0
    @State private var sstpRequestsPerSecond = 0.0
    @State private var sstpErrorsPerSecond = 0.0
    @State private var httpRequests2xx = 42
    @State private var httpRequests4xx = 3
    @State private var httpRequests5xx = 1
    @State private var httpAverageTime = 85.5
    @State private var xpcConnectedApps: [String] = []
    @State private var xpcRequestsPerSecond = 1.2
    @State private var updateTimer: Timer?
    
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
                            statusIndicator(color: sstpConnections > 0 ? .green : .gray)
                            Text("アクティブ接続数: \(sstpConnections)")
                            Spacer()
                        }
                        
                        HStack {
                            Text("受信/秒:")
                            ProgressView(value: sstpRequestsPerSecond, total: 10.0)
                                .frame(width: 100)
                            Text("\(String(format: "%.1f", sstpRequestsPerSecond))")
                            Spacer()
                        }
                        
                        HStack {
                            Text("エラー/秒:")
                            ProgressView(value: sstpErrorsPerSecond, total: 5.0)
                                .progressViewStyle(LinearProgressViewStyle(tint: .red))
                                .frame(width: 100)
                            Text("\(String(format: "%.1f", sstpErrorsPerSecond))")
                            Spacer()
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
                            statusIndicator(color: .green)
                            Text("サーバー稼働中")
                            Spacer()
                        }
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("2xx: \(httpRequests2xx)")
                                    .foregroundColor(.green)
                                Text("4xx: \(httpRequests4xx)")
                                    .foregroundColor(.orange)
                                Text("5xx: \(httpRequests5xx)")
                                    .foregroundColor(.red)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Text("平均処理時間")
                                Text("\(String(format: "%.1f", httpAverageTime))ms")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                    .foregroundColor(httpAverageTime > 100 ? .orange : .green)
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
                            statusIndicator(color: .green)
                            Text("サービス稼働中")
                            Spacer()
                        }
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("接続中のアプリ:")
                            if xpcConnectedApps.isEmpty {
                                Text("接続なし")
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(xpcConnectedApps, id: \.self) { app in
                                    HStack {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                        Text(app)
                                    }
                                }
                            }
                        }
                        
                        HStack {
                            Text("要求/秒:")
                            ProgressView(value: xpcRequestsPerSecond, total: 10.0)
                                .frame(width: 100)
                            Text("\(String(format: "%.1f", xpcRequestsPerSecond))")
                            Spacer()
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
        // 模擬データの更新
        xpcConnectedApps = ["TestApp.app", "DevHelper"]
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            // ランダムな統計データを生成
            sstpConnections = Int.random(in: 0...5)
            sstpRequestsPerSecond = Double.random(in: 0...8)
            sstpErrorsPerSecond = Double.random(in: 0...2)
            
            httpRequests2xx += Int.random(in: 0...3)
            httpRequests4xx += Int.random(in: 0...1)
            if Bool.random() {
                httpRequests5xx += 1
            }
            httpAverageTime = Double.random(in: 50...150)
            
            xpcRequestsPerSecond = Double.random(in: 0...5)
        }
    }
}
