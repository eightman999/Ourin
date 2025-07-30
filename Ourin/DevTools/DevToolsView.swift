import SwiftUI
import OSLog

// Use compat logger to support macOS 10.15

/// DevTools main view with sidebar and toolbar
struct DevToolsView: View {
    /// sidebar sections
    enum Section: String, CaseIterable, Identifiable {
        case general = "基本設定"
        case shioriResource = "SHIORIリソース"
        case narList = "NAR一覧"
        var id: String { rawValue }
    }

    @State private var selection: Section? = .general
    private let logger = CompatLogger(subsystem: "jp.ourin.devtools", category: "ui")

    var body: some View {
#if compiler(>=5.7)
        if #available(macOS 13.0, *) {
            NavigationSplitView {
                List(Section.allCases, selection: $selection) { section in
                    Text(section.rawValue)
                }
                .listStyle(SidebarListStyle())
                .frame(minWidth: 180)
            } detail: {
                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .applyToolbar(reload: reload)
            }
        } else {
            navigationViewCompat
        }
#else
        navigationViewCompat
#endif
    }

    private var navigationViewCompat: some View {
        NavigationView {
            List(Section.allCases, selection: $selection) { section in
                Text(section.rawValue)
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 180)

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .applyToolbar(reload: reload)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .general:
            GeneralPane()
        case .shioriResource:
            ResourcePane()
        case .narList:
            NarListPane()
        case .none:
            Text("セクションを選択")
        }
    }

    private func reload() {
        logger.info("DevTools reload triggered")
        ResourceBridge.shared.invalidateAll()
    }
}

#if os(macOS)
private struct ToolbarCompat: ViewModifier {
    let action: () -> Void
    func body(content: Content) -> some View {
        if #available(macOS 11.0, *) {
            content.toolbar {
                ToolbarItemGroup {
                    Button(action: action) {
                        Image(systemName: "arrow.clockwise")
                    }.help("再読込")
                }
            }
        } else {
            content
        }
    }
}

private extension View {
    func applyToolbar(reload: @escaping () -> Void) -> some View {
        modifier(ToolbarCompat(action: reload))
    }
}
#else
private extension View {
    func applyToolbar(reload: @escaping () -> Void) -> some View { self }
}
#endif
#Preview {
    DevToolsView()
}
