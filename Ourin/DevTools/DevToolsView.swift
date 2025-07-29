import SwiftUI
import OSLog

/// DevTools main view with sidebar and toolbar
struct DevToolsView: View {
    /// sidebar sections
    enum Section: String, CaseIterable, Identifiable {
        case general = "基本設定"
        case shioriResource = "SHIORIリソース"
        var id: String { rawValue }
    }

    @State private var selection: Section? = .general
    private let logger = Logger(subsystem: "jp.ourin.devtools", category: "ui")

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Text(section.rawValue)
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 180)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar {
                    ToolbarItemGroup {
                        Button(action: reload) {
                            Image(systemName: "arrow.clockwise")
                        }.help("再読込")
                    }
                }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .general:
            GeneralPane()
        case .shioriResource:
            ResourcePane()
        case .none:
            Text("セクションを選択")
        }
    }

    private func reload() {
        logger.info("DevTools reload triggered")
        ResourceBridge.shared.invalidateAll()
    }
}

#Preview {
    DevToolsView()
}
