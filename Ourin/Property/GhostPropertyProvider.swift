import Foundation

/// Represents a ghost entry used for property values.
struct Ghost {
    let name: String
    let path: String
    let icon: String
}

/// Provides ghost related properties such as `ghostlist.*`,
/// `activeghostlist.*` and `currentghost.*`.
final class GhostPropertyProvider: PropertyProvider {
    enum Mode {
        case ghostlist
        case activeghostlist
        case currentghost
    }

    private let mode: Mode
    private let ghosts: [Ghost]
    private let activeIndices: [Int]

    init(mode: Mode, ghosts: [Ghost], activeIndices: [Int]) {
        self.mode = mode
        self.ghosts = ghosts
        self.activeIndices = activeIndices
    }

    func get(key: String) -> String? {
        switch mode {
        case .ghostlist:
            return ghostlist(key: key)
        case .activeghostlist:
            return activeghostlist(key: key)
        case .currentghost:
            return currentghost(key: key)
        }
    }

    // MARK: - ghostlist
    private func ghostlist(key: String) -> String? {
        if key == "count" {
            return String(ghosts.count)
        }
        if let (index, prop) = parseIndex(key: key) {
            guard ghosts.indices.contains(index) else { return nil }
            let g = ghosts[index]
            switch prop {
            case "name":
                return g.name
            case "path":
                return g.path
            case "icon":
                return g.icon
            default:
                return nil
            }
        }
        return nil
    }

    // MARK: - activeghostlist
    private func activeghostlist(key: String) -> String? {
        if key == "count" {
            return String(activeIndices.count)
        }
        if let (index, prop) = parseIndex(key: key) {
            guard activeIndices.indices.contains(index) else { return nil }
            let g = ghosts[activeIndices[index]]
            switch prop {
            case "name":
                return g.name
            case "path":
                return g.path
            case "icon":
                return g.icon
            default:
                return nil
            }
        }
        return nil
    }

    // MARK: - currentghost
    private func currentghost(key: String) -> String? {
        guard let idx = activeIndices.first, ghosts.indices.contains(idx) else {
            return nil
        }
        let g = ghosts[idx]
        switch key {
        case "name":
            return g.name
        case "path":
            return g.path
        case "icon":
            return g.icon
        case "status":
            return "online"
        default:
            return nil
        }
    }

    // Helper to parse `index(n).property` strings
    private func parseIndex(key: String) -> (Int, String)? {
        guard key.hasPrefix("index("), let close = key.firstIndex(of: ")") else {
            return nil
        }
        let start = key.index(key.startIndex, offsetBy: 6)
        let idxString = String(key[start..<close])
        guard let idx = Int(idxString) else { return nil }
        let rest = String(key[key.index(after: close)...])
        guard rest.first == "." else { return nil }
        let prop = String(rest.dropFirst())
        return (idx, prop)
    }
}
