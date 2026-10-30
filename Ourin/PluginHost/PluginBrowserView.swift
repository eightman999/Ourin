import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// ユーザー向けのプラグイン検索。イベント注入の開発画面から分離する。
struct PluginBrowserView: View {
    @State private var tab = 0
    @State private var query = ""
    @State private var catalog: [PluginCatalogItem] = []
    @State private var installed: [InstalledPluginItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var hasLoaded = false

    private var visibleInstalled: [InstalledPluginItem] {
        installed.filter { PluginCatalog.matches(query, fields: [$0.name, $0.pluginID, $0.author]) }
    }
    private var visibleCatalog: [PluginCatalogItem] { catalog.filter { $0.matches(query) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("プラグイン").font(.title2)
                Spacer()
                if tab != 2 {
                    Button("配置先フォルダを開く") {
                        do { NSWorkspace.shared.open(try OurinPaths.subdirectory("plugin")) }
                        catch { self.error = "配置先を開けませんでした：\(error.localizedDescription)" }
                    }
                    Button("NARから導入…", action: selectArchive)
                }
            }
            Picker("表示", selection: $tab) {
                Text("探す").tag(0)
                Text("導入済み").tag(1)
                Text("SHIORIエンジン").tag(2)
            }.pickerStyle(.segmented)
            if tab == 2 {
                ShioriEngineBrowserView()
            } else {
                TextField("名前・ID・作者で検索", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("pluginSearch")
                if tab == 0 { discovery } else { installedList }
            }
        }
        .padding()
        .frame(minWidth: 620, minHeight: 440)
        .onAppear { refreshInstalled(); Task { await loadCatalog() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshInstalled()
        }
    }

    private var discovery: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Link("Ourin対応版・導入手順", destination: PluginCatalog.sourceURL)
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Button("更新") { Task { await loadCatalog() } }.disabled(loading)
            }
            Text("Ourinサイトで配布している対応版です。ZIPを展開し、同梱READMEの手順でプラグインフォルダへ配置してください。各項目の検証範囲・制限も確認できます。")
                .font(.caption).foregroundColor(.secondary)
            if let error {
                Text(error).foregroundColor(.red)
            }
            List {
                ForEach(visibleCatalog) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.name).font(.headline)
                            Spacer()
                            if let url = item.pageURL { Link("原作者の配布元 ↗", destination: url) }
                            if let url = item.downloadURL { Link("Ourin版ZIPを入手 ↗", destination: url) }
                        }
                        Text(item.id).font(.caption).foregroundColor(.secondary)
                        Text(item.limitations).font(.callout)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(item.bytes), countStyle: .file))
                            .font(.caption).foregroundColor(.secondary)
                    }.padding(.vertical, 5)
                }
            }
            if hasLoaded && !loading && error == nil && visibleCatalog.isEmpty {
                Text(catalog.isEmpty ? "配布情報はありません。" : "検索条件に一致するプラグインはありません。")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var installedList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(visibleInstalled.count)件 / 全\(installed.count)件")
                Spacer()
                Button("更新", action: refreshInstalled)
            }
            List(visibleInstalled) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(item.name).font(.headline)
                        Spacer()
                        Text(item.status)
                            .font(.caption).foregroundColor(.secondary)
                        Button("Finderで表示") {
                            let path = item.path
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                    }
                    Text("ID: \(item.pluginID)　作者: \(item.author)")
                        .font(.caption)
                }.padding(.vertical, 5)
            }
            if visibleInstalled.isEmpty {
                Text(installed.isEmpty ? "導入済みのプラグインはありません。" : "検索条件に一致するプラグインはありません。")
                    .foregroundColor(.secondary)
            }
        }
    }

    @MainActor private func loadCatalog() async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            catalog = try await PluginCatalog.fetch()
            hasLoaded = true
        } catch is CancellationError {
        } catch {
            self.error = "配布情報を取得できませんでした。「更新」で再試行できます。\n\(error.localizedDescription)"
        }
    }

    private func refreshInstalled() {
        installed = PluginCatalog.installedItems(
            registered: AppDelegate.resolve()?.pluginRegistry?.compatibilityEntries ?? [],
            paths: PluginRegistry.searchPaths())
    }

    private func selectArchive() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "nar")].compactMap { $0 }
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "プラグインのNARファイルを選択"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            NSApp.delegate?.application?(NSApp, openFiles: [url.path])
        }
    }
}

/// メニューから同じ窓を再利用する。ゴースト未起動時も利用できる。
@MainActor enum PluginBrowserWindow {
    private static var window: NSWindow?
    static func show() {
        if window == nil {
            let win = NSWindow(contentViewController: NSHostingController(rootView: PluginBrowserView()))
            win.title = "プラグインを探す・管理"
            win.identifier = NSUserInterfaceItemIdentifier("PluginBrowserWindow")
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.isReleasedWhenClosed = false
            win.setContentSize(NSSize(width: 780, height: 560))
            win.center()
            window = win
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
