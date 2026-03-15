import Foundation

public enum SerikoInterval: Equatable {
    case always
    case sometimes
    case rarely
    case random(Int?)
    case runonce
    case yenE
    case talk
    case bind
    case never
    case unknown(String)

    static func parse(_ raw: String) -> SerikoInterval {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("random") {
            let parts = value.split(separator: ",", maxSplits: 1).map(String.init)
            if parts.count == 2, let n = Int(parts[1]) {
                return .random(n)
            }
            return .random(nil)
        }
        switch value {
        case "always": return .always
        case "sometimes": return .sometimes
        case "rarely": return .rarely
        case "runonce": return .runonce
        case "yen-e": return .yenE
        case "talk": return .talk
        case "bind": return .bind
        case "never": return .never
        default: return .unknown(raw)
        }
    }
}

public enum SerikoMethod: Equatable {
    case overlay
    case overlayFast
    case base
    case move
    case reduce
    case replace
    case start
    case alternativeStart
    case stop
    case asis
    case unknown(String)

    static func parse(_ raw: String) -> SerikoMethod {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "overlay": return .overlay
        case "overlayfast": return .overlayFast
        case "base": return .base
        case "move": return .move
        case "reduce": return .reduce
        case "replace": return .replace
        case "start": return .start
        case "alternativestart", "alternatestart": return .alternativeStart
        case "stop": return .stop
        case "asis": return .asis
        default: return .unknown(raw)
        }
    }
}

public struct SerikoPattern: Equatable {
    public let index: Int
    public let method: SerikoMethod
    public let surfaceID: Int
    public let duration: Int
    public let x: Int
    public let y: Int
    public let rawArguments: [String]
}

public struct SerikoSurfaceDefinition: Equatable {
    public let surfaceID: Int
    public var animations: [Int: SerikoParser.AnimationDefinition]
}

public enum SerikoParser {
    public struct AnimationDefinition: Equatable {
        public let id: Int
        public var interval: SerikoInterval
        public var options: [String]
        public var patterns: [SerikoPattern]
    }

    public static func parseSurfaces(_ content: String) -> [Int: SerikoSurfaceDefinition] {
        let lines = content.components(separatedBy: .newlines)
        var result: [Int: SerikoSurfaceDefinition] = [:]

        var currentSurface: Int?
        var inSurfaceBlock = false

        for raw in lines {
            let line = stripComment(from: raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if line.hasPrefix("surface"), line.contains("{") == false {
                currentSurface = parseSurfaceID(from: line)
                continue
            }
            if line == "{", currentSurface != nil {
                inSurfaceBlock = true
                continue
            }
            if line == "}" {
                inSurfaceBlock = false
                currentSurface = nil
                continue
            }
            guard inSurfaceBlock, let surfaceID = currentSurface else { continue }

            if var surface = result[surfaceID] {
                parseAnimationLine(line, into: &surface)
                result[surfaceID] = surface
            } else {
                var surface = SerikoSurfaceDefinition(surfaceID: surfaceID, animations: [:])
                parseAnimationLine(line, into: &surface)
                result[surfaceID] = surface
            }
        }

        return result
    }

    private static func parseAnimationLine(_ line: String, into surface: inout SerikoSurfaceDefinition) {
        if let (animID, intervalRaw) = parseAnimationInterval(line) {
            var definition = surface.animations[animID] ?? AnimationDefinition(
                id: animID,
                interval: .never,
                options: [],
                patterns: []
            )
            definition.interval = SerikoInterval.parse(intervalRaw)
            surface.animations[animID] = definition
            return
        }

        if let (animID, optionRaw) = parseAnimationOption(line) {
            var definition = surface.animations[animID] ?? AnimationDefinition(
                id: animID,
                interval: .never,
                options: [],
                patterns: []
            )
            definition.options.append(optionRaw)
            surface.animations[animID] = definition
            return
        }

        if let (animID, pattern) = parseAnimationPattern(line) {
            var definition = surface.animations[animID] ?? AnimationDefinition(
                id: animID,
                interval: .never,
                options: [],
                patterns: []
            )
            definition.patterns.append(pattern)
            definition.patterns.sort { $0.index < $1.index }
            surface.animations[animID] = definition
        }
    }

    private static func parseAnimationInterval(_ line: String) -> (Int, String)? {
        let prefix = "animation"
        let marker = ".interval,"
        guard line.hasPrefix(prefix), let markerRange = line.range(of: marker) else { return nil }
        let idPart = String(line[line.index(line.startIndex, offsetBy: prefix.count)..<markerRange.lowerBound])
        guard let id = Int(idPart) else { return nil }
        let value = String(line[markerRange.upperBound...])
        return (id, value)
    }

    private static func parseAnimationOption(_ line: String) -> (Int, String)? {
        let prefix = "animation"
        let marker = ".option,"
        guard line.hasPrefix(prefix), let markerRange = line.range(of: marker) else { return nil }
        let idPart = String(line[line.index(line.startIndex, offsetBy: prefix.count)..<markerRange.lowerBound])
        guard let id = Int(idPart) else { return nil }
        let value = String(line[markerRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (id, value)
    }

    private static func parseAnimationPattern(_ line: String) -> (Int, SerikoPattern)? {
        let prefix = "animation"
        let marker = ".pattern"
        guard line.hasPrefix(prefix), let markerRange = line.range(of: marker) else { return nil }

        let animIDPart = String(line[line.index(line.startIndex, offsetBy: prefix.count)..<markerRange.lowerBound])
        guard let animID = Int(animIDPart) else { return nil }

        let afterPattern = line[markerRange.upperBound...]
        guard let commaIndex = afterPattern.firstIndex(of: ",") else { return nil }
        let patternIndexPart = String(afterPattern[..<commaIndex])
        guard let patternIndex = Int(patternIndexPart) else { return nil }

        let argsPart = String(afterPattern[afterPattern.index(after: commaIndex)...])
        let rawArgs = argsPart.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !rawArgs.isEmpty else { return nil }

        let method: SerikoMethod
        let methodOffset: Int
        if Int(rawArgs[0]) != nil {
            method = .overlay
            methodOffset = 0
        } else {
            method = SerikoMethod.parse(rawArgs[0])
            methodOffset = 1
        }

        let surfaceID = intAt(rawArgs, index: methodOffset) ?? -1
        let duration = intAt(rawArgs, index: methodOffset + 1) ?? 0
        let x = intAt(rawArgs, index: methodOffset + 2) ?? 0
        let y = intAt(rawArgs, index: methodOffset + 3) ?? 0

        let pattern = SerikoPattern(
            index: patternIndex,
            method: method,
            surfaceID: surfaceID,
            duration: duration,
            x: x,
            y: y,
            rawArguments: rawArgs
        )
        return (animID, pattern)
    }

    private static func intAt(_ parts: [String], index: Int) -> Int? {
        guard index >= 0, index < parts.count else { return nil }
        return Int(parts[index])
    }

    private static func parseSurfaceID(from line: String) -> Int? {
        guard line.hasPrefix("surface") else { return nil }
        let tail = line.dropFirst("surface".count)
        let digits = String(tail.prefix { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    private static func stripComment(from line: String) -> String {
        if let idx = line.firstIndex(of: "#") {
            return String(line[..<idx])
        }
        return line
    }
}
