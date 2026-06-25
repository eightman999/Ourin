import SwiftUI
import OSLog

// compat logger ensures 10.15 support

struct GeneralPane: View {
    @State private var dataPath: String = ""
    private let logger = CompatLogger(subsystem: "jp.ourin.devtools", category: "settings")

    var body: some View {
        Form {
            HStack {
                // 基準フォルダ（~/Documents/Ourin）は固定。表示のみ・編集不可。
                TextField("データフォルダ", text: $dataPath)
                    .disabled(true)
                Button("Finderで開く") { reveal() }
            }
            .onAppear(perform: load)
        }
        .padding()
    }

    private func load() {
        if let url = try? OurinPaths.baseDirectory() {
            dataPath = url.path
        }
    }

    private func reveal() {
        guard let url = try? OurinPaths.baseDirectory() else {
            logger.warning("Failed to resolve Ourin base directory for Finder open")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        logger.info("Opened data folder in Finder: \(url.path)")
    }
}

#Preview {
    GeneralPane()
}
