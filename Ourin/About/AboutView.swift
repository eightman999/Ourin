import SwiftUI

struct AboutView: View {
    @State private var showLicenses = false
    @State private var appLicenseText: String = ""
    @State private var thirdPartyFiles: [LicenseFile] = []
    @State private var selectedLicense: LicenseFile?

    struct LicenseFile: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let content: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                if let icon = NSApplication.shared.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .cornerRadius(12)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(Bundle.main.appName)
                        .font(.title2).bold()
                    Text("バージョン: \(Bundle.main.appVersion) (\(Bundle.main.appBuild))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if let release = Bundle.main.appReleaseDate {
                        Text("リリース日: \(release)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            Divider()

            Text(Bundle.main.appCopyright ?? "")
                .font(.footnote)
                .foregroundColor(.secondary)

            HStack {
                Button("ライセンスを表示…") { showLicenses = true }
                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 220)
        .onAppear(perform: loadLicenses)
        .sheet(isPresented: $showLicenses) {
            LicenseBrowser(files: thirdPartyFilesWithAppLicense(), selected: $selectedLicense)
        }
    }

    private func thirdPartyFilesWithAppLicense() -> [LicenseFile] {
        var files = thirdPartyFiles
        if !appLicenseText.isEmpty {
            files.insert(LicenseFile(name: "Ourin ライセンス", content: appLicenseText), at: 0)
        }
        return files
    }

    private func loadLicenses() {
        // Load app license
        if let url = Bundle.main.url(forResource: "AppLicense", withExtension: "txt", subdirectory: "Licenses") {
            appLicenseText = (try? String(contentsOf: url)) ?? ""
        }
        // Load all txt licenses in Licenses/
        if let urls = Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: "Licenses") {
            thirdPartyFiles = urls
                .filter { $0.lastPathComponent != "AppLicense.txt" }
                .compactMap { url in
                    let name = url.deletingPathExtension().lastPathComponent
                    let title = name.replacingOccurrences(of: "_", with: " ")
                    if let content = try? String(contentsOf: url) {
                        return LicenseFile(name: title, content: content)
                    }
                    return nil
                }
                .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }
}

private struct LicenseBrowser: View {
    let files: [AboutView.LicenseFile]
    @Binding var selected: AboutView.LicenseFile?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ライセンス")
                    .font(.headline)
                Spacer()
                Button("閉じる") { dismiss() }
            }
            .padding(12)
            Divider()
            HStack(spacing: 0) {
                List(selection: $selected) {
                    ForEach(files) { file in
                        Text(file.name)
                            .tag(file as AboutView.LicenseFile?)
                    }
                }
                .frame(minWidth: 180, maxWidth: 220)
                Divider()
                if let sel = selected ?? files.first {
                    ScrollView {
                        Text(sel.content)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                    }
                } else {
                    Text("左の一覧から選択してください")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}

private extension Bundle {
    var appName: String { infoDictionary?["CFBundleName"] as? String ?? "Ourin" }
    var appVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }
    var appBuild: String { infoDictionary?["CFBundleVersion"] as? String ?? "" }
    var appReleaseDate: String? { infoDictionary?["AppReleaseDate"] as? String }
    var appCopyright: String? { infoDictionary?["NSHumanReadableCopyright"] as? String }
}
