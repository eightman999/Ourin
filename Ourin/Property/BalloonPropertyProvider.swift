import Foundation

/// Represents a balloon entry.
public struct Balloon {
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

/// Balloon scope data for current balloon display.
public struct BalloonScopeData {
    public let count: Int
    public let num: Int
    public let validWidth: Int
    public let validWidthInitial: Int
    public let validHeight: Int
    public let validHeightInitial: Int
    public let lines: Int
    public let linesInitial: Int
    public let basePosX: Int
    public let basePosY: Int
    public let charWidth: Int

    public init(count: Int = 0, num: Int = 0, validWidth: Int = 0, validWidthInitial: Int = 0,
                validHeight: Int = 0, validHeightInitial: Int = 0, lines: Int = 0, linesInitial: Int = 0,
                basePosX: Int = 0, basePosY: Int = 0, charWidth: Int = 0) {
        self.count = count
        self.num = num
        self.validWidth = validWidth
        self.validWidthInitial = validWidthInitial
        self.validHeight = validHeight
        self.validHeightInitial = validHeightInitial
        self.lines = lines
        self.linesInitial = linesInitial
        self.basePosX = basePosX
        self.basePosY = basePosY
        self.charWidth = charWidth
    }
}

/// Provides balloon-related properties such as `balloonlist.*` and `currentghost.balloon.*`.
final class BalloonPropertyProvider: PropertyProvider {
    enum Mode {
        case balloonlist
        case currentBalloon
    }

    private let mode: Mode
    private let balloons: [Balloon]
    private var currentBalloonIndex: Int
    private var scopeData: [Int: BalloonScopeData]

    init(mode: Mode, balloons: [Balloon] = [], currentBalloonIndex: Int = 0,
         scopeData: [Int: BalloonScopeData] = [:]) {
        self.mode = mode
        self.balloons = balloons
        self.currentBalloonIndex = currentBalloonIndex
        self.scopeData = scopeData
    }

    func get(key: String) -> String? {
        switch mode {
        case .balloonlist:
            return balloonlist(key: key)
        case .currentBalloon:
            return currentBalloon(key: key)
        }
    }

    // MARK: - balloonlist
    private func balloonlist(key: String) -> String? {
        if key == "count" {
            return String(balloons.count)
        }

        // balloonlist(name/path).property
        if let (identifier, prop) = parseNamedAccess(key: key) {
            if let balloon = findBalloon(by: identifier) {
                return getBalloonProperty(balloon, prop: prop)
            }
        }

        // balloonlist.index(n).property
        if let (index, prop) = parseIndex(key: key) {
            guard balloons.indices.contains(index) else { return nil }
            return getBalloonProperty(balloons[index], prop: prop)
        }

        return nil
    }

    // MARK: - currentghost.balloon
    private func currentBalloon(key: String) -> String? {
        // balloon.scope(n).property
        if key.hasPrefix("scope(") {
            if let (scopeId, prop) = parseScopeAccess(key: key) {
                guard let data = scopeData[scopeId] else { return nil }
                return getScopeProperty(data, prop: prop)
            }
        }

        return nil
    }

    // MARK: - Helpers

    private func getBalloonProperty(_ balloon: Balloon, prop: String) -> String? {
        switch prop {
        case "name":
            return balloon.name
        case "path":
            return balloon.path
        case "craftmanw":
            return balloon.craftmanw
        case "craftmanurl":
            return balloon.craftmanurl
        default:
            return nil
        }
    }

    private func getScopeProperty(_ scope: BalloonScopeData, prop: String) -> String? {
        switch prop {
        case "count":
            return String(scope.count)
        case "num":
            return String(scope.num)
        case "validwidth":
            return String(scope.validWidth)
        case "validwidth.initial":
            return String(scope.validWidthInitial)
        case "validheight":
            return String(scope.validHeight)
        case "validheight.initial":
            return String(scope.validHeightInitial)
        case "lines":
            return String(scope.lines)
        case "lines.initial":
            return String(scope.linesInitial)
        case "basepos.x":
            return String(scope.basePosX)
        case "basepos.y":
            return String(scope.basePosY)
        case "char_width":
            return String(scope.charWidth)
        default:
            return nil
        }
    }

    private func findBalloon(by identifier: String) -> Balloon? {
        return balloons.first { b in
            b.name == identifier || b.path == identifier
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

    /// Parse `scope(n).property` format
    private func parseScopeAccess(key: String) -> (Int, String)? {
        guard key.hasPrefix("scope("), let close = key.firstIndex(of: ")") else {
            return nil
        }
        let start = key.index(key.startIndex, offsetBy: 6)
        let idString = String(key[start..<close])
        guard let scopeId = Int(idString) else { return nil }
        let rest = String(key[key.index(after: close)...])
        guard rest.first == "." else { return nil }
        let prop = String(rest.dropFirst())
        return (scopeId, prop)
    }
}
