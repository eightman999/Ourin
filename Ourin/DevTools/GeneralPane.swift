import SwiftUI
import OSLog

// compat logger ensures 10.15 support

struct GeneralPane: View {
    @State private var dataPath: String = ""
    private let logger = CompatLogger(subsystem: "jp.ourin.devtools", category: "settings")

    var body: some View {
        Form {
            HStack {
                TextField("データフォルダ", text: $dataPath)
                Button("参照…") { browse() }
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

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                dataPath = url.path
                logger.info("data folder set: \(url.path)")
            }
        }
    }
}

#Preview {
    GeneralPane()
}
