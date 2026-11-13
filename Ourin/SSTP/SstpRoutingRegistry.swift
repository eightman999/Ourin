import Foundation

protocol SstpRoutingRegistry: Sendable {
    func matches(id: String?, receiverGhostName: String?) -> Bool
    func hasGhosts() -> Bool
    func contains(ghostName: String) -> Bool
    func allGhostNames() -> [String]
}

struct LiveSstpRoutingRegistry: SstpRoutingRegistry {
    static let live = LiveSstpRoutingRegistry()

    func matches(id: String?, receiverGhostName: String?) -> Bool {
        SSTPOwnershipRegistry.shared.matches(id: id, receiverGhostName: receiverGhostName)
    }

    func hasGhosts() -> Bool {
        !runningGhosts().isEmpty || GhostRegistry.shared.hasEntries()
    }

    func contains(ghostName: String) -> Bool {
        let isRunning = runningGhosts().contains {
            $0.name.caseInsensitiveCompare(ghostName) == .orderedSame
                || $0.folderName.caseInsensitiveCompare(ghostName) == .orderedSame
        }
        return isRunning || GhostRegistry.shared.contains(name: ghostName)
    }

    func allGhostNames() -> [String] {
        // 起動中ゴースト（プライマリが先頭）→ GhostRegistry の登録分の順。名前の重複は除く。
        var names: [String] = []
        for name in runningGhosts().map({ $0.name }) + GhostRegistry.shared.allNames() {
            if !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                names.append(name)
            }
        }
        return names
    }

    /// 起動中ゴースト（プライマリ＋追加）の名前。`GhostRegistry` に登録する処理は本番コードに無いため、
    /// 宛先ゴーストの解決（`AppDelegate.resolveGhostManager`）と同じ AppDelegate の一覧を参照する。
    /// `ghostManager` / `additionalGhosts` はメインスレッドで更新され、SSTP はバックグラウンドの
    /// キューから呼ばれるため、メインへ同期で戻って読む（既にメインなら直接読む）。
    private func runningGhosts() -> [(name: String, folderName: String)] {
        let read: () -> [(name: String, folderName: String)] = {
            AppDelegate.resolve()?.runningGhostRoutingNames() ?? []
        }
        if Thread.isMainThread {
            return read()
        }
        return DispatchQueue.main.sync(execute: read)
    }
}
