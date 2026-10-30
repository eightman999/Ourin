import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ShioriEngineBrowserView: View {
    @State private var installed: [InstalledShioriEngine] = []
    @State private var message: String?
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SHIORIエンジン").font(.headline)
                Spacer()
                Button("自動選択に戻す…") { selectGhost(engineID: nil) }
                Button("配置先を開く") {
                    do {
                        let root = try ShioriEnginePlugins.installationRoot()
                        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(root)
                    } catch { message = error.localizedDescription }
                }
                Button(importing ? "導入中…" : "プラグインを導入…", action: selectPackage)
                    .disabled(importing)
                    .accessibilityIdentifier("importShioriEngine")
            }
            Text("SHIORIエンジンの.pluginファイルをそのまま導入できます。必要な実行環境も含まれます。対応するゴーストは次回起動時に自動で選択されます。")
                .font(.callout).foregroundColor(.secondary)
            if let message { Text(message).font(.callout) }
            List(installed) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(item.descriptor.name).font(.headline)
                        Spacer()
                        Text(status(item.descriptor)).font(.caption).foregroundColor(.secondary)
                        if !item.descriptor.isDevelopmentSample {
                            Button("ゴーストに使用…") { selectGhost(engineID: item.id) }
                                .disabled(!item.descriptor.supportsCurrentArchitecture || !item.descriptor.supportsCurrentSystem)
                        }
                        Button("Finderで表示") {
                            NSWorkspace.shared.activateFileViewerSelecting([item.packageURL])
                        }
                    }
                    Text(item.descriptor.moduleNames.joined(separator: " / ")).font(.caption)
                    if let limitations = item.descriptor.limitations {
                        Text(limitations).font(.caption).foregroundColor(.secondary)
                    }
                }.padding(.vertical, 5)
            }
            .accessibilityIdentifier("installedShioriEngines")
            if installed.isEmpty {
                Text("追加SHIORIは未導入です。YAYA・里々・KAGARIは本体の内蔵エンジンを使用できます。")
                    .font(.callout).foregroundColor(.secondary)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func status(_ descriptor: ShioriEnginePlugin) -> String {
        if descriptor.isDevelopmentSample { return "開発用サンプル" }
        if !descriptor.supportsCurrentArchitecture { return "対象CPUが異なります" }
        if !descriptor.supportsCurrentSystem { return "macOS \(descriptor.minimumOSVersion ?? "") 以降が必要です" }
        return "導入済み"
    }

    private func refresh() { installed = ShioriEnginePlugins.installed() }

    private func selectGhost(engineID: String?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = try? OurinPaths.subdirectory("ghost")
        panel.title = "対象ゴーストのフォルダを選択"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard FileManager.default.fileExists(atPath: url.appendingPathComponent("ghost/master/descript.txt").path) else {
                message = "ghost/master/descript.txtを含むゴーストのフォルダを選択してください。"
                return
            }
            do {
                try ShioriEnginePlugins.assign(engineID: engineID, to: url)
                message = engineID == nil ? "自動選択へ戻しました。ゴーストを再起動してください。"
                    : "エンジンを割り当てました。ゴーストを再起動してください。"
            } catch { message = error.localizedDescription }
        }
    }

    private func selectPackage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "SHIORIエンジンの.pluginを選択"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            importing = true
            message = nil
            Task {
                do {
                    let name = try await Task.detached(priority: .userInitiated) {
                        try ShioriEnginePlugins.install(from: url).descriptor.name
                    }.value
                    message = "\(name) を導入しました。ゴーストの再起動後に使用できます。"
                    refresh()
                } catch { message = error.localizedDescription }
                importing = false
            }
        }
    }
}
