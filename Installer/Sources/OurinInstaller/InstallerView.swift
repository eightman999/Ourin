import AppKit
import OurinInstallerCore
import SwiftUI

struct InstallerView: View {
    @EnvironmentObject private var model: InstallerModel

    var body: some View {
        HStack(spacing: 0) {
            StepSidebar()
                .frame(width: 190)
            Divider()
            VStack(spacing: 0) {
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                }
                Divider()
                footer
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .welcome: WelcomeStep()
        case .destination: DestinationStep()
        case .migration: MigrationStep()
        case .ghost: GhostStep()
        case .install: InstallStep()
        case .done: DoneStep()
        }
    }

    private var footer: some View {
        HStack {
            if model.step == .done {
                Spacer()
                Button("閉じる") { NSApp.terminate(nil) }
                Button("Ourin を起動") {
                    model.launchOurin()
                    NSApp.terminate(nil)
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button("戻る") { model.goBack() }
                    .disabled(!model.canGoBack)
                Spacer()
                if model.step == .install && model.installState != .succeeded {
                    Button(model.installState == .idle ? "インストール" : "もう一度試す") { model.startInstall() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.installState == .running)
                } else {
                    Button("続ける") { model.goNext() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canContinue)
                }
            }
        }
    }
}

private struct StepSidebar: View {
    @EnvironmentObject private var model: InstallerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: AppIcon.image)
                    .resizable()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ourin").font(.headline)
                    Text(model.payloadVersion).font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 8)

            ForEach(InstallerModel.Step.allCases) { step in
                HStack(spacing: 8) {
                    Image(systemName: icon(for: step))
                        .foregroundColor(color(for: step))
                        .frame(width: 16)
                    Text(step.title)
                        .fontWeight(step == model.step ? .semibold : .regular)
                        .foregroundColor(step.rawValue > model.step.rawValue ? .secondary : .primary)
                }
            }
            Spacer()
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func icon(for step: InstallerModel.Step) -> String {
        if step.rawValue < model.step.rawValue { return "checkmark.circle.fill" }
        if step == model.step { return "circle.inset.filled" }
        return "circle"
    }

    private func color(for step: InstallerModel.Step) -> Color {
        step.rawValue <= model.step.rawValue ? .accentColor : .secondary
    }
}

enum AppIcon {
    /// 同梱 Ourin.app のアイコン。無ければインストーラー自身のアイコン。
    @MainActor static var image: NSImage {
        let payload = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Ourin.app")
        if FileManager.default.fileExists(atPath: payload.path) {
            return NSWorkspace.shared.icon(forFile: payload.path)
        }
        return NSApp.applicationIconImage
    }
}

// MARK: - ようこそ

private struct WelcomeStep: View {
    @EnvironmentObject private var model: InstallerModel
    @State private var showLicense = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ourin へようこそ").font(.title2).bold()
            Text("Ourin（桜鈴）は macOS で動く伺かベースウェアです。このインストーラーは次のことを行います。")
            VStack(alignment: .leading, spacing: 6) {
                Label("Ourin.app をアプリケーションフォルダに配置します", systemImage: "app.badge")
                Label("SSP で使っていたゴースト・バルーンを取り込めます（任意）", systemImage: "square.and.arrow.down.on.square")
                Label("最初に起動するゴーストを選べます", systemImage: "person.crop.circle")
            }
            if !model.payloadExists {
                Label("インストールする Ourin.app が見つかりません。インストーラーを入手し直してください。",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            }
            Text("続けると、以下の使用許諾に同意したものとみなします。")
                .foregroundColor(.secondary)
            DisclosureGroup("使用許諾とライセンス", isExpanded: $showLicense) {
                ScrollView {
                    Text(model.licenseText())
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 180)
            }
        }
    }
}

// MARK: - インストール先

private struct DestinationStep: View {
    @EnvironmentObject private var model: InstallerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("インストール先").font(.title2).bold()
            Picker("", selection: $model.destination) {
                Text("アプリケーション（/Applications）— すべてのユーザー").tag(InstallerModel.Destination.applications)
                Text("自分のアプリケーション（~/Applications）— このユーザーだけ").tag(InstallerModel.Destination.userApplications)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if let installed = model.installedVersion {
                Label("Ourin \(installed) が既にあります。\(model.payloadVersion) に置き換えます。",
                      systemImage: "arrow.triangle.2.circlepath")
            }
            if model.needsAdministrator {
                Label("このフォルダへの書き込みには管理者のパスワードが必要です。", systemImage: "lock")
                    .foregroundColor(.secondary)
            }
            if RunningOurin.isRunning {
                Label("Ourin が起動中です。インストール時に終了を求めます（ゴーストの終了トークを待ちます）。",
                      systemImage: "exclamationmark.circle")
                    .foregroundColor(.orange)
            }
            Divider()
            Text("ゴーストなどのデータは \(model.dataFolderPath) に置かれます。既にあるデータは消しません。")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - SSP からの移行

private struct MigrationStep: View {
    @EnvironmentObject private var model: InstallerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SSP からの移行").font(.title2).bold()
            Text("Wine・CrossOver・Whisky で使っている SSP のゴーストとバルーンを Ourin にコピーできます。SSP 側のデータは変更しません。")
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if model.isSearchingSSP {
                    ProgressView().controlSize(.small)
                    Text("SSP を探しています…").foregroundColor(.secondary)
                } else {
                    Picker("移行元", selection: Binding(get: { model.sspRoot }, set: { model.selectSSPRoot($0) })) {
                        Text("移行しない").tag(URL?.none)
                        ForEach(model.sspCandidates, id: \.root) { candidate in
                            Text("\(candidate.source)：\(candidate.root.lastPathComponent)").tag(URL?.some(candidate.root))
                        }
                        if let root = model.sspRoot, !model.sspCandidates.contains(where: { $0.root == root }) {
                            Text(root.path).tag(URL?.some(root))
                        }
                    }
                    .frame(maxWidth: 380)
                }
                Button("フォルダを選ぶ…") { model.chooseSSPFolder() }
                    .disabled(model.isSearchingSSP)
            }
            if model.hasSearchedSSP && model.sspCandidates.isEmpty && model.sspRoot == nil {
                Text("SSP は自動では見つかりませんでした。SSP を使っていた場合は「フォルダを選ぶ…」から指定してください。")
                    .foregroundColor(.secondary)
            }
            if let root = model.sspRoot {
                Text(root.path).font(.caption).foregroundColor(.secondary).textSelection(.enabled)
                MigrationList()
            }
        }
    }
}

private struct MigrationList: View {
    @EnvironmentObject private var model: InstallerModel

    var body: some View {
        if model.migrationItems.isEmpty {
            Text("移行できるゴースト・バルーンが見つかりませんでした。").foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(model.selectedItemIDs.count) / \(model.migrationItems.count) 件を選択中")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("すべて選択") { model.selectedItemIDs = Set(model.migrationItems.map(\.id)) }
                    Button("選択解除") { model.selectedItemIDs = [] }
                }
                ForEach([MigrationItem.Kind.ghost, .balloon], id: \.self) { kind in
                    let items = model.migrationItems.filter { $0.kind == kind }
                    if !items.isEmpty {
                        Text(kind == .ghost ? "ゴースト" : "バルーン").font(.headline).padding(.top, 6)
                        ForEach(items) { item in row(item) }
                    }
                }
            }
        }
    }

    private func row(_ item: MigrationItem) -> some View {
        let selected = Binding(
            get: { model.selectedItemIDs.contains(item.id) },
            set: { on in
                if on { model.selectedItemIDs.insert(item.id) } else { model.selectedItemIDs.remove(item.id) }
            }
        )
        return HStack(alignment: .firstTextBaseline) {
            Toggle(isOn: selected) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                    Text(detail(item)).font(.caption).foregroundColor(caption(item))
                }
            }
        }
    }

    private func detail(_ item: MigrationItem) -> String {
        var parts = [item.directory]
        switch item.compatibility {
        case .supported(let runtime): parts.append("\(runtime) で動作")
        case .windowsShiori(let module): parts.append("Windows 用 SHIORI（\(module)）のため動かない可能性があります")
        case .notApplicable: break
        }
        if model.isAlreadyInstalled(item) { parts.append("Ourin に同名のフォルダがあるため省略します") }
        return parts.joined(separator: " ・ ")
    }

    private func caption(_ item: MigrationItem) -> Color {
        if case .windowsShiori = item.compatibility { return .orange }
        return .secondary
    }
}

// MARK: - 最初のゴースト

private struct GhostStep: View {
    @EnvironmentObject private var model: InstallerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("最初に起動するゴースト").font(.title2).bold()
            Picker("", selection: $model.startupChoice) {
                if let current = model.existingStartupGhost {
                    Text("今の設定のまま（\(current)）").tag(InstallerModel.StartupChoice.keepCurrent)
                }
                Text("Emily/Phase4.5（同梱）").tag(InstallerModel.StartupChoice.bundledDefault)
                ForEach(model.migratingGhosts) { item in
                    Text("\(item.name)（SSP から移行）").tag(InstallerModel.StartupChoice.ghost(item.directory))
                }
                ForEach(model.installedGhosts, id: \.self) { directory in
                    Text("\(directory)（インストール済み）").tag(InstallerModel.StartupChoice.ghost(directory))
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Divider()
            Text("ほかのゴーストやシェル・バルーン（.nar）も入れる").font(.headline)
            Text("ここで選んだ .nar は、インストール後に Ourin を起動したとき Ourin が読み込みます。")
                .foregroundColor(.secondary)
            ForEach(model.extraNars, id: \.self) { url in
                HStack {
                    Image(systemName: "doc.zipper")
                    Text(url.lastPathComponent)
                    Spacer()
                    Button {
                        model.extraNars.removeAll { $0 == url }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button(".nar を追加…") { model.addNars() }
        }
    }
}

// MARK: - インストール

private struct InstallStep: View {
    @EnvironmentObject private var model: InstallerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("インストール").font(.title2).bold()
            if model.installState == .idle {
                summary
            }
            if model.installState == .running {
                ProgressView().progressViewStyle(.linear)
            }
            if case .failed(let message) = model.installState {
                Label(message, systemImage: "xmark.octagon.fill").foregroundColor(.red)
            }
            if model.installState == .succeeded {
                Label("インストールが完了しました。", systemImage: "checkmark.seal.fill").foregroundColor(.green)
            }
            if !model.log.isEmpty {
                ScrollView {
                    Text(model.log.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 220)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("次の内容でインストールします。").foregroundColor(.secondary)
            Label("Ourin \(model.payloadVersion) → \(model.destination.url.path)", systemImage: "app.badge")
            if model.selectedItems.isEmpty {
                Label("SSP からの移行：しない", systemImage: "square.and.arrow.down.on.square")
            } else {
                Label("SSP からの移行：\(model.selectedItems.count) 件", systemImage: "square.and.arrow.down.on.square")
            }
            Label("最初のゴースト：\(startupDescription)", systemImage: "person.crop.circle")
            if !model.extraNars.isEmpty {
                Label("追加の .nar：\(model.extraNars.count) 件（起動後に読み込み）", systemImage: "doc.zipper")
            }
            if model.needsAdministrator {
                Label("管理者のパスワードを求められます", systemImage: "lock").foregroundColor(.secondary)
            }
        }
    }

    private var startupDescription: String {
        switch model.startupChoice {
        case .keepCurrent: return "今の設定のまま（\(model.existingStartupGhost ?? "")）"
        case .bundledDefault: return "Emily/Phase4.5（同梱）"
        case .ghost(let directory): return directory
        }
    }
}

// MARK: - 完了

private struct DoneStep: View {
    @EnvironmentObject private var model: InstallerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("インストールが完了しました").font(.title2).bold()
            Text("Ourin を起動すると、選んだゴーストが現れます。")
            let failed = model.migrationResults.filter {
                if case .failed = $0.outcome { return true }
                return false
            }
            if !failed.isEmpty {
                Label("コピーできなかった項目があります：\(failed.map(\.item.name).joined(separator: "、"))",
                      systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
            }
            if model.migrationResults.contains(where: {
                if case .windowsShiori = $0.item.compatibility, case .copied = $0.outcome { return true }
                return false
            }) {
                Text("Windows 用 SHIORI のゴーストは、Ourin では起動できない場合があります。")
                    .foregroundColor(.secondary)
            }
            Button("データフォルダを開く") {
                NSWorkspace.shared.open(URL(fileURLWithPath: model.dataFolderPath, isDirectory: true))
            }
        }
    }
}
