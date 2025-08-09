import SwiftUI

/// View that lists installed NAR packages under Application Support
struct NarListPane: View {
    private struct Item: Identifiable {
        let id = UUID()
        let type: String
        let name: String
        let path: String
    }
    @State private var items: [Item] = []

    var body: some View {
        VStack {
            HStack {
                Button("再読み込み") { load() }
                Spacer()
            }
            tableView
        }
        .padding()
        .onAppear(perform: load)
    }

    private func load() {
        items.removeAll()
        let kinds = ["ghost", "balloon", "shell", "plugin", "package"]
        for kind in kinds {
            let packages = NarRegistry.shared.installedItems(ofType: kind)
            let newItems = packages.map { Item(type: $0.type, name: $0.name, path: $0.path.path) }
            items.append(contentsOf: newItems)
        }
    }

    @ViewBuilder
    private var tableView: some View {
#if compiler(>=5.5)
        if #available(macOS 12.0, *) {
            Table(items) {
                TableColumn("種別") { Text($0.type) }
                TableColumn("名前") { Text($0.name) }
                TableColumn("パス") { Text($0.path) }
            }
        } else {
            legacyList
        }
#else
        legacyList
#endif
    }

    private var legacyList: some View {
        List(items) { item in
            HStack {
                Text(item.type).frame(minWidth: 70, alignment: .leading)
                Text(item.name).frame(minWidth: 120, alignment: .leading)
                Text(item.path).lineLimit(1)
            }
        }
    }
}

#Preview {
    NarListPane()
}
