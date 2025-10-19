import Foundation

/// Represents a headline entry.
public struct Headline {
    public let name: String
    public let path: String
    public let craftmanw: String
    public let craftmanurl: String

    public init(name: String, path: String, craftmanw: String = "", craftmanurl: String = "") {
        self.name = name
        self.path = path
        self.craftmanw = craftmanw
        self.craftmanurl = craftmanurl
    }
}

/// Provides headline-related properties for `headlinelist.*`.
final class HeadlinePropertyProvider: PropertyProvider {
    private let headlines: [Headline]

    init(headlines: [Headline] = []) {
        self.headlines = headlines
    }

    func get(key: String) -> String? {
        if key == "count" {
            return String(headlines.count)
        }

        // headlinelist(name/path).property
        if let (identifier, prop) = parseNamedAccess(key: key) {
            if let headline = findHeadline(by: identifier) {
                return getHeadlineProperty(headline, prop: prop)
            }
        }

        // headlinelist.index(n).property
        if let (index, prop) = parseIndex(key: key) {
            guard headlines.indices.contains(index) else { return nil }
            return getHeadlineProperty(headlines[index], prop: prop)
        }

        return nil
    }

    // MARK: - Helpers

    private func getHeadlineProperty(_ headline: Headline, prop: String) -> String? {
        switch prop {
        case "name":
            return headline.name
        case "path":
            return headline.path
        case "craftmanw":
            return headline.craftmanw
        case "craftmanurl":
            return headline.craftmanurl
        default:
            return nil
        }
    }

    private func findHeadline(by identifier: String) -> Headline? {
        return headlines.first { h in
            h.name == identifier || h.path == identifier
        }
    }

    /// Parse `(identifier).property` format
    private func parseNamedAccess(key: String) -> (String, String)? {
        guard key.hasPrefix("("), let close = key.firstIndex(of: ")") else {
            return nil
        }
        let start = key.index(key.startIndex, offsetBy: 1)
        let identifier = String(key[start..<close])
        let rest = String(key[key.index(after: close)...])
        guard rest.first == "." else { return (identifier, "") }
        let prop = String(rest.dropFirst())
        return (identifier, prop)
    }

    /// Parse `index(n).property` format
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
