import SwiftUI
import AppKit

/// サーフィステストに表示する一つのサーフェス。
struct SurfaceTestEntry: Identifiable {
    let id: String
    let surfaceID: Int
    let name: String
    let preferredScope: Int?
}

/// サーフィステストのグループ。
struct SurfaceTestGroup: Identifiable {
    let id: String
    let name: String
    let scope: Int?
    let entries: [SurfaceTestEntry]
}

/// `surfacetable.txt` と実ファイルを統合してサーフィステストの一覧を構築する。
enum SurfaceTestCatalog {
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "ico", "cur"
    ]

    /// `surface*.png` 系のファイル名からサーフェス ID を抽出する。
    /// `surface1<ID>` は scope 1 用の別名なので、共通形式の ID と scope 1 の ID の
    /// 両方を返す。重複は Set で排除する。
    static func imageSurfaceIDs(fileNames: [String]) -> Set<Int> {
        var result = Set<Int>()
        for fileName in fileNames {
            let url = URL(fileURLWithPath: fileName)
            guard imageExtensions.contains(url.pathExtension.lowercased()) else { continue }

            var stem = url.deletingPathExtension().lastPathComponent.lowercased()
            for suffix in ["@3x", "@2x"] where stem.hasSuffix(suffix) {
                stem.removeLast(suffix.count)
                break
            }
            guard stem.hasPrefix("surface") else { continue }
            let digits = String(stem.dropFirst("surface".count))
            guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let id = Int(digits) else { continue }

            result.insert(id)
            if digits.first == "1", digits.count > 1,
               let scopedID = Int(String(digits.dropFirst())) {
                result.insert(scopedID)
            }
        }
        return result
    }

    static func makeGroups(
        surfaceTable: SurfaceTable?,
        definitionIDs: Set<Int>,
        imageIDs: Set<Int>,
        nameAliases: [String: Int] = [:]
    ) -> [SurfaceTestGroup] {
        var groups: [SurfaceTestGroup] = []
        var listedIDs = Set<Int>()

        if let surfaceTable {
            for (groupIndex, group) in surfaceTable.groups.enumerated() {
                // UKADOC: __disabled はサーフィステストの一覧から除外する。
                guard group.name != "__disabled" else { continue }
                let entries = group.entries.compactMap { entry -> SurfaceTestEntry? in
                    // __parts はパーツ用サーフェスであり、通常の一覧名を持たない。
                    guard entry.name != "__parts" else { return nil }
                    listedIDs.insert(entry.surfaceID)
                    return SurfaceTestEntry(
                        id: "table-\(groupIndex)-\(entry.surfaceID)-\(entry.name)",
                        surfaceID: entry.surfaceID,
                        name: entry.name,
                        preferredScope: group.scope
                    )
                }
                guard !entries.isEmpty else { continue }
                groups.append(SurfaceTestGroup(
                    id: "table-\(groupIndex)-\(group.name)",
                    name: group.name,
                    scope: group.scope,
                    entries: entries
                ))
            }
        }

        let allIDs = definitionIDs.union(imageIDs)
        let unlistedIDs = allIDs.subtracting(listedIDs).sorted()
        if !unlistedIDs.isEmpty {
            let aliasesByID = Dictionary(grouping: nameAliases, by: { $0.value })
            let entries = unlistedIDs.map { surfaceID in
                let alias = aliasesByID[surfaceID]?
                    .map(\.key)
                    .sorted()
                    .first
                return SurfaceTestEntry(
                    id: "unlisted-\(surfaceID)",
                    surfaceID: surfaceID,
                    name: alias ?? "",
                    preferredScope: nil
                )
            }
            groups.append(SurfaceTestGroup(
                id: "unlisted",
                name: "未分類（実ファイル・定義）",
                scope: nil,
                entries: entries
            ))
        }

        if groups.isEmpty {
            groups.append(SurfaceTestGroup(
                id: "empty",
                name: "サーフェスなし",
                scope: nil,
                entries: []
            ))
        }
        return groups
    }
}

private struct SurfaceTestRow: View {
    let manager: GhostManager
    let entry: SurfaceTestEntry
    let targetScope: Int
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var image: NSImage?

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                ZStack {
                    Color.gray.opacity(0.12)
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(4)
                    } else {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 72, height: 72)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.35)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name.isEmpty ? "（名前なし）" : entry.name)
                        .lineLimit(1)
                    Text("surface\(entry.surfaceID) · scope \(entry.preferredScope.map(String.init) ?? String(targetScope))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .onAppear {
            guard image == nil else { return }
            image = manager.loadImage(surfaceId: entry.surfaceID, scope: entry.preferredScope ?? targetScope)
        }
    }
}

/// SSP互換のサーフェステストウィンドウ。
struct SurfaceTestView: View {
    let manager: GhostManager
    let availableScopes: [Int]

    @State private var groups: [SurfaceTestGroup]
    @State private var targetScope: Int
    @State private var selectedSurfaceID: Int?

    init(manager: GhostManager, groups: [SurfaceTestGroup], initialScope: Int) {
        self.manager = manager
        self.availableScopes = Array(Set(manager.characterViewModels.keys).union([0, 1])).sorted()
        _groups = State(initialValue: groups)
        _targetScope = State(initialValue: initialScope)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("表示対象")
                Picker("表示対象", selection: $targetScope) {
                    ForEach(availableScopes, id: \.self) { scope in
                        Text(scope == 0 ? "scope 0（本体）" : "scope \(scope)").tag(scope)
                    }
                }
                .labelsHidden()
                .frame(width: 150)

                Text("shell: \(manager.activeShellName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("再読み込み") {
                    manager.loadAnimationsForCurrentSurface()
                    groups = manager.makeSurfaceTestGroups()
                    selectedSurfaceID = manager.characterViewModels[targetScope]?.currentSurfaceID
                }
            }
            .padding(12)

            Divider()

            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            SurfaceTestRow(
                                manager: manager,
                                entry: entry,
                                targetScope: targetScope,
                                isSelected: selectedSurfaceID == entry.surfaceID,
                                onSelect: {
                                    let scope = entry.preferredScope ?? targetScope
                                    targetScope = scope
                                    selectedSurfaceID = entry.surfaceID
                                    manager.selectSurfaceForTest(id: entry.surfaceID, scope: scope)
                                }
                            )
                        }
                    } header: {
                        HStack {
                            Text(group.name)
                            if let scope = group.scope {
                                Text("scope \(scope)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            Divider()
            HStack {
                Text("クリックしたサーフェスを実際のキャラクターへ適用します")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("current: \(manager.characterViewModels[targetScope]?.currentSurfaceID ?? 0)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(10)
        }
        .frame(minWidth: 430, minHeight: 500)
    }
}

extension GhostManager {
    /// 現在シェルのサーフェステスト一覧を作る。
    func makeSurfaceTestGroups() -> [SurfaceTestGroup] {
        if parsedSurfaceDefs.isEmpty || surfaceTable == nil {
            loadAnimationsForCurrentSurface()
        }
        let fileNames = loadShellPath().flatMap { url in
            try? FileManager.default.contentsOfDirectory(atPath: url.path)
        } ?? []
        let imageIDs = SurfaceTestCatalog.imageSurfaceIDs(fileNames: fileNames)
        return SurfaceTestCatalog.makeGroups(
            surfaceTable: surfaceTable,
            definitionIDs: Set(parsedSurfaceDefs.keys),
            imageIDs: imageIDs,
            nameAliases: surfaceNameAliases
        )
    }

    /// サーフェステストから指定スコープへ実サーフェスを適用する。
    func selectSurfaceForTest(id: Int, scope: Int) {
        guard scope >= 0, !isShuttingDown else { return }
        let previousScope = currentScope
        currentScope = scope
        updateSurface(id: id)
        currentScope = previousScope
    }

    /// `\![open,surfacetest]` のウィンドウを表示する。
    func openSurfaceTestWindow() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.openSurfaceTestWindow() }
            return
        }
        if let surfaceTestWindow {
            surfaceTestWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        loadAnimationsForCurrentSurface()
        let groups = makeSurfaceTestGroups()
        let view = SurfaceTestView(manager: self, groups: groups, initialScope: currentScope)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.identifier = NSUserInterfaceItemIdentifier("GhostSurfaceTestWindow_\(sstpUniqueID)")
        window.title = "\(ghostConfig?.name ?? ghostURL.lastPathComponent) - Surface Test"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 680))
        window.center()
        window.makeKeyAndOrderFront(nil)
        surfaceTestWindow = window
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
