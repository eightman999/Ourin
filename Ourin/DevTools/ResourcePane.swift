import SwiftUI

struct ResourcePane: View {
    private struct Item: Identifiable {
        let id = UUID()
        let key: String
        let value: String
    }
    @State private var items: [Item] = []

    var body: some View {
        VStack {
            HStack {
                Button("読み込み") { load() }
                Spacer()
            }
            tableView
        }
        .padding()
        .onAppear(perform: load)
    }

    private func load() {
        items = ["sakura.name", "kero.name"].map { key in
            Item(key: key, value: ResourceBridge.shared.get(key) ?? "")
        }
    }

    @ViewBuilder
    private var tableView: some View {
#if compiler(>=5.5)
        if #available(macOS 12.0, *) {
            Table(items) {
                TableColumn("キー") { Text($0.key) }
                TableColumn("値") { Text($0.value) }
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
                Text(item.key).frame(minWidth: 120, alignment: .leading)
                Spacer()
                Text(item.value)
            }
        }
    }
}

#Preview {
    ResourcePane()
}
