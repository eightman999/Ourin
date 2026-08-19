// Ourin/DevTools/SaveSharePane.swift
import SwiftUI
import UniformTypeIdentifiers

/// SaveShare (.ssg) の手動エクスポート/インポート UI。
/// SSP 互換の .ssg 形式でゴーストのプロファイル (data/profile/<ghost>/) を保存・復元する。
struct SaveSharePane: View {
    private let logger = CompatLogger(subsystem: "jp.ourin.devtools", category: "saveshare")

    @State private var ghostNames: [String] = []
    @State private var selectedGhost: String? = nil
    @State private var statusMessage: String = ""
    @State private var errorMessage: String? = nil

    private let ssgType = UTType(filenameExtension: "ssg") ?? .data

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("セーブ共有 (SaveShare)")
                .font(.title2).bold()
            Text("SSP 互換の .ssg 形式でゴーストのセーブデータをエクスポート/インポートします。")
                .font(.caption).foregroundColor(.secondary)

            Picker("ゴースト", selection: $selectedGhost) {
                Text("選択してください").tag(String?.none)
                ForEach(ghostNames, id: \.self) { name in
                    Text(name).tag(String?.some(name))
                }
            }
            .onAppear {
                if ghostNames.isEmpty {
                    ghostNames = NarRegistry.shared.installedGhosts()
                    if selectedGhost == nil {
                        selectedGhost = ghostNames.first
                    }
                }
            }

            HStack(spacing: 12) {
                Button("エクスポート (.ssg)") {
                    export()
                }
                .disabled(selectedGhost == nil)
                .help("選択したゴーストのプロファイルを .ssg に書き出す")

                Button("インポート (.ssg)") {
                    importFromPicker()
                }
                .disabled(selectedGhost == nil)
                .help(".ssg を選択したゴーストのプロファイルへ復元する")
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func profileURL() -> URL? {
        guard let selectedGhost else { return nil }
        return try? OurinPaths.profileDirectory(for: selectedGhost)
    }

    private func export() {
        guard let ghost = selectedGhost, let profile = profileURL() else { return }
        let panel = NSSavePanel()
        panel.title = "セーブデータをエクスポート"
        panel.nameFieldStringValue = "\(ghost).ssg"
        panel.allowedContentTypes = [ssgType]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let included = try SaveShareManager.exportSSG(
                    ghostName: ghost,
                    computerName: Host.current().localizedName ?? "",
                    profileURL: profile,
                    to: url
                )
                statusMessage = "エクスポート完了: \(url.lastPathComponent) (\(included.count) ファイル)"
                errorMessage = nil
                logger.info("SaveShare export \(ghost) -> \(url.path): \(included)")
            } catch {
                errorMessage = "エクスポート失敗: \(error.localizedDescription)"
                logger.error("SaveShare export failed: \(error)")
            }
        }
    }

    private func importFromPicker() {
        guard let ghost = selectedGhost, let profile = profileURL() else { return }
        let panel = NSOpenPanel()
        panel.title = "セーブデータをインポート"
        panel.allowedContentTypes = [ssgType]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let restored = try SaveShareManager.importSSG(from: url, to: profile)
                statusMessage = "インポート完了: \(url.lastPathComponent) (\(restored.count) ファイル復元)"
                errorMessage = nil
                logger.info("SaveShare import \(url.path) -> \(ghost): \(restored)")
            } catch {
                errorMessage = "インポート失敗: \(error.localizedDescription)"
                logger.error("SaveShare import failed: \(error)")
            }
        }
    }
}
