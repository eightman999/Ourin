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
        GhostRegistry.shared.hasEntries()
    }

    func contains(ghostName: String) -> Bool {
        GhostRegistry.shared.contains(name: ghostName)
    }

    func allGhostNames() -> [String] {
        GhostRegistry.shared.allNames()
    }
}
