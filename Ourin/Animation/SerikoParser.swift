import Foundation

public enum SerikoInterval: Hashable {
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
        public var surfaceOption: Int?
        public var seriesOption: String?
        public var pingPong: Bool
        public enum HorizontalAlignment: String { case left, center, right }
        public enum VerticalAlignment: String { case top, center, bottom }
        public var alignX: HorizontalAlignment?
        public var alignY: VerticalAlignment?

        public init(
            id: Int,
            interval: SerikoInterval,
            options: [String],
            patterns: [SerikoPattern],
            surfaceOption: Int? = nil,
            seriesOption: String? = nil,
            pingPong: Bool = false,
            alignX: HorizontalAlignment? = nil,
            alignY: VerticalAlignment? = nil
        ) {
            self.id = id
            self.interval = interval
            self.options = options
            self.patterns = patterns
            self.surfaceOption = surfaceOption
            self.seriesOption = seriesOption
            self.pingPong = pingPong
            self.alignX = alignX
            self.alignY = alignY
        }
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
            for token in parseOptionTokens(optionRaw) {
                if let eq = token.firstIndex(of: "=") {
                    let key = token[..<eq].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let value = token[token.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
                    switch key {
                    case "interval":
                        definition.interval = SerikoInterval.parse(value)
                    case "surface":
                        definition.surfaceOption = Int(value)
                    case "series":
                        definition.seriesOption = value.isEmpty ? nil : value
                    case "pingpong", "ping-pong":
                        definition.pingPong = (value.lowercased() == "1" || value.lowercased() == "true" || value.isEmpty)
                    case "align", "alignment":
                        let v = value.lowercased()
                        if v == "center" { definition.alignX = .center; definition.alignY = .center }
                        if v == "left" { definition.alignX = .left }
                        if v == "right" { definition.alignX = .right }
                        if v == "top" { definition.alignY = .top }
                        if v == "bottom" { definition.alignY = .bottom }
                    case "alignx":
                        switch value.lowercased() {
                        case "left": definition.alignX = .left
                        case "center": definition.alignX = .center
                        case "right": definition.alignX = .right
                        default: break
                        }
                    case "aligny":
                        switch value.lowercased() {
                        case "top": definition.alignY = .top
                        case "center": definition.alignY = .center
                        case "bottom": definition.alignY = .bottom
                        default: break
                        }
                    default:
                        if !definition.options.contains(token) {
                            definition.options.append(token)
                        }
                    }
                } else if !definition.options.contains(token) {
                    // bare token (e.g. "pingpong")
                    let lower = token.lowercased()
                    if lower == "pingpong" || lower == "ping-pong" {
                        definition.pingPong = true
                    } else if lower == "center" {
                        definition.alignX = .center; definition.alignY = .center
                    } else if lower == "left" {
                        definition.alignX = .left
                    } else if lower == "right" {
                        definition.alignX = .right
                    } else if lower == "top" {
                        definition.alignY = .top
                    } else if lower == "bottom" {
                        definition.alignY = .bottom
                    }
                    definition.options.append(token)
                }
            }
            surface.animations[animID] = definition
            return
        }

        if let (animID, overlayArgs) = parseAnimationOverlay(line) {
            var definition = surface.animations[animID] ?? AnimationDefinition(
                id: animID,
                interval: .never,
                options: [],
                patterns: []
            )
            let nextIndex = definition.patterns.count
            let overlayPattern = SerikoPattern(
                index: nextIndex,
                method: .overlay,
                surfaceID: intAt(overlayArgs, index: 0) ?? -1,
                duration: intAt(overlayArgs, index: 1) ?? 0,
                x: intAt(overlayArgs, index: 2) ?? 0,
                y: intAt(overlayArgs, index: 3) ?? 0,
                rawArguments: overlayArgs
            )
            definition.patterns.append(overlayPattern)
            definition.patterns.sort { $0.index < $1.index }
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

    private static func parseOptionTokens(_ raw: String) -> [String] {
        raw.replacingOccurrences(of: "+", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private static func parseAnimationOverlay(_ line: String) -> (Int, [String])? {
        let prefix = "animation"
        let marker = ".overlay,"
        guard line.hasPrefix(prefix), let markerRange = line.range(of: marker) else { return nil }
        let idPart = String(line[line.index(line.startIndex, offsetBy: prefix.count)..<markerRange.lowerBound])
        guard let id = Int(idPart) else { return nil }
        let argsPart = String(line[markerRange.upperBound...])
        let rawArgs = argsPart.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return (id, rawArgs)
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
