import Foundation

public indirect enum SerikoInterval: Hashable {
    case always
    case sometimes
    case rarely
    case random(Int?)
    /// periodic,N — N 秒ごとに必ず発火する定間隔モード（UKADOC）
    case periodic(Int?)
    case runonce
    case yenE
    case talk
    /// talk,N — N 文字ごとに発火する会話中アニメーション。
    case talkCharacters(Int)
    /// starttalk — 対象スコープのトーク開始時に一度だけ発火する。
    case startTalk
    /// endtalk — starttalk 発火履歴がある対象スコープのトーク終了時に発火する。
    case endTalk
    case bind
    case never
    /// `bind+runonce` のような SERIKO interval 複合指定。
    case combined([SerikoInterval])
    case unknown(String)

    static func parse(_ raw: String) -> SerikoInterval {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let components = value.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty }) else {
            return .unknown(raw)
        }

        let parsed = components.map { parseSingle($0, raw: raw) }
        guard !parsed.contains(where: { if case .unknown = $0 { return true }; return false }) else {
            return .unknown(raw)
        }
        if parsed.count == 1 {
            return parsed[0]
        }
        // UKADOC は parameterized interval 同士の複合指定を許可していない。
        // これを受理すると random/periodic/talk の判定が曖昧になるため無効化する。
        guard parsed.filter(\.isParameterized).count <= 1 else {
            return .unknown(raw)
        }
        if let parameterizedIndex = parsed.firstIndex(where: \.isParameterized),
           parameterizedIndex != parsed.index(before: parsed.endIndex) {
            // パラメータ付き interval は複合指定の末尾に限る。
            return .unknown(raw)
        }
        return .combined(parsed)
    }

    private static func parseSingle(_ value: String, raw: String) -> SerikoInterval {
        if value == "random" {
            return .random(nil)
        }
        if value.hasPrefix("random,") {
            let parameter = String(value.dropFirst("random,".count))
            return Int(parameter).map { .random($0) } ?? .unknown(raw)
        }
        if value == "periodic" {
            return .periodic(nil)
        }
        if value.hasPrefix("periodic,") {
            let parameter = String(value.dropFirst("periodic,".count))
            return Int(parameter).map { .periodic($0) } ?? .unknown(raw)
        }
        switch value {
        case "always": return .always
        case "sometimes": return .sometimes
        case "rarely": return .rarely
        case "runonce": return .runonce
        case "yen-e": return .yenE
        case "talk": return .talk
        case let value where value.hasPrefix("talk,"):
            let parameter = String(value.dropFirst("talk,".count))
            guard let count = Int(parameter), count > 0 else { return .unknown(raw) }
            return .talkCharacters(count)
        case "starttalk": return .startTalk
        case "endtalk": return .endTalk
        case "bind": return .bind
        case "never": return .never
        default: return .unknown(raw)
        }
    }

    private var isParameterized: Bool {
        switch self {
        case .random, .periodic, .talkCharacters:
            return true
        case .combined(let values):
            return values.contains(where: \.isParameterized)
        default:
            return false
        }
    }

    /// 複合指定を平坦化した interval 列。Executor の判定を単一の実装へ集約する。
    var components: [SerikoInterval] {
        switch self {
        case .combined(let values):
            return values.flatMap(\.components)
        default:
            return [self]
        }
    }
}

public enum SerikoBlendMode: String, CaseIterable, Equatable {
    case multiply
    case screen
    case overlay
    case add
    case addGlow
    case softLight
    case hardLight
    case colorDodge
    case colorDodgeGlow
    case color
    case luminosity
    case hue
    case saturation
    case vividLight
    case linearLight
    case pinLight
    case hardMix
    case darken
    case lighten
    case darkerColor
    case lighterColor
    case colorBurn
    case linearBurn
    case difference
    case exclusion
    case subtract
    case divide
    case dither

    /// `blend-*` と SSP 旧称（`overlaymultiply` 等）を同一の描画モードへ解決する。
    static func parse(_ raw: String) -> (mode: Self, fast: Bool)? {
        let value = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        let normalized: String
        let fast: Bool
        if value.hasPrefix("blend-") {
            let suffix = String(value.dropFirst("blend-".count))
            fast = suffix.hasSuffix("-fast")
            normalized = fast ? String(suffix.dropLast("-fast".count)) : suffix
        } else if value.hasPrefix("overlay") {
            let suffix = String(value.dropFirst("overlay".count))
            fast = true
            normalized = suffix.hasSuffix("-fast") ? String(suffix.dropLast("-fast".count)) : suffix
        } else {
            return nil
        }

        let mode: Self?
        switch normalized {
        case "multiply": mode = .multiply
        case "screen": mode = .screen
        case "overlay": mode = .overlay
        case "add": mode = .add
        case "add-glow": mode = .addGlow
        case "soft-light": mode = .softLight
        case "hard-light": mode = .hardLight
        case "color-dodge": mode = .colorDodge
        case "color-dodge-glow": mode = .colorDodgeGlow
        case "color": mode = .color
        case "luminosity": mode = .luminosity
        case "hue": mode = .hue
        case "saturation": mode = .saturation
        case "vivid-light": mode = .vividLight
        case "linear-light": mode = .linearLight
        case "pin-light": mode = .pinLight
        case "hard-mix": mode = .hardMix
        case "darken": mode = .darken
        case "lighten": mode = .lighten
        case "darker-color": mode = .darkerColor
        case "lighter-color": mode = .lighterColor
        case "color-burn": mode = .colorBurn
        case "linear-burn": mode = .linearBurn
        case "difference": mode = .difference
        case "exclusion": mode = .exclusion
        case "subtract": mode = .subtract
        case "divide": mode = .divide
        case "dither": mode = .dither
        default: mode = nil
        }
        guard let mode else { return nil }
        return (mode, fast)
    }
}

public enum SerikoMethod: Equatable {
    case overlay
    case overlayFast
    case base
    case move
    case scaling
    case add
    case bind
    case auto
    case reduce
    case replace
    case `import`
    case start
    case alternativeStart
    case stop
    case alternativeStop
    /// 別アニメ列を割り込み再生する（start に準じて処理）
    case insert
    /// 宛先アルファに応じたフレーム補間
    case interpolate
    /// Photoshop系のレイヤー合成。fast=true は宛先アルファにも依存する。
    case blend(SerikoBlendMode, fast: Bool)
    /// 指定した候補のうち1つをランダムに開始・停止する。
    case parallelStart
    case parallelStop
    case asis
    case unknown(String)

    static func parse(_ raw: String) -> SerikoMethod {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "overlay": return .overlay
        case "overlayfast", "overlay-fast": return .overlayFast
        case "base": return .base
        case "move": return .move
        case "scaling": return .scaling
        case "add": return .add
        case "bind": return .bind
        case "auto": return .auto
        case "reduce": return .reduce
        case "replace": return .replace
        case "import": return .import
        case "start": return .start
        case "alternativestart", "alternatestart": return .alternativeStart
        case "stop": return .stop
        case "alternativestop", "alternatestop": return .alternativeStop
        case "parallelstart", "parallel-start": return .parallelStart
        case "parallelstop", "parallel-stop": return .parallelStop
        case "insert": return .insert
        case "interpolate": return .interpolate
        case "asis": return .asis
        default:
            if let blend = SerikoBlendMode.parse(value) {
                return .blend(blend.mode, fast: blend.fast)
            }
            return .unknown(raw)
        }
    }
}

public struct SerikoPattern: Equatable {
    public let index: Int
    public let method: SerikoMethod
    public let surfaceID: Int
    public let duration: Int
    /// SSP拡張の `最小ウェイト-最大ウェイト`。`duration` は下限値を保持する。
    public let durationRange: ClosedRange<Int>?
    public let x: Int
    public let y: Int
    /// scaling は小数点以下の倍率指定を許すため、従来の整数座標とは別に保持する。
    public let xValue: Double
    public let yValue: Double
    public let rawArguments: [String]

    public init(
        index: Int,
        method: SerikoMethod,
        surfaceID: Int,
        duration: Int,
        x: Int,
        y: Int,
        rawArguments: [String],
        xValue: Double? = nil,
        yValue: Double? = nil,
        durationRange: ClosedRange<Int>? = nil
    ) {
        self.index = index
        self.method = method
        self.surfaceID = surfaceID
        self.duration = duration
        self.durationRange = durationRange
        self.x = x
        self.y = y
        self.xValue = xValue ?? Double(x)
        self.yValue = yValue ?? Double(y)
        self.rawArguments = rawArguments
    }

    /// `alternativestart` / `alternativestop` / `parallel*` の括弧付きID列。
    /// 通常の画像パターンでは空配列になる。
    public var referencedAnimationIDs: [Int] {
        guard method == .alternativeStart || method == .alternativeStop ||
                method == .parallelStart || method == .parallelStop else {
            return []
        }
        return rawArguments
            .dropFirst()
            .joined(separator: ",")
            .split { $0 == "," || $0 == "." }
            .compactMap { token in
                let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "()[]{} \t\r\n"))
                return Int(value)
            }
    }
}

/// SERIKO/2.0 の element 定義（基底サーフェスを複数画像で合成する）。
/// 形式: `elementN,method,filename,x,y`
public struct SerikoElement: Equatable {
    public let index: Int
    public let method: SerikoMethod
    public let filename: String
    public let x: Int
    public let y: Int
}

public struct SerikoSurfaceDefinition: Equatable {
    public let surfaceID: Int
    public var animations: [Int: SerikoParser.AnimationDefinition]
    public var elements: [SerikoElement] = []
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

        var currentSurfaceIDs: [Int] = []
        var inSurfaceBlock = false

        for raw in lines {
            let line = stripComment(from: raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if line.hasPrefix("surface"), line.contains("{") == false {
                currentSurfaceIDs = parseSurfaceIDs(from: line)
                continue
            }
            if line == "{", !currentSurfaceIDs.isEmpty {
                inSurfaceBlock = true
                continue
            }
            if line == "}" {
                inSurfaceBlock = false
                currentSurfaceIDs = []
                continue
            }
            guard inSurfaceBlock, !currentSurfaceIDs.isEmpty else { continue }

            for surfaceID in currentSurfaceIDs {
                if var surface = result[surfaceID] {
                    parseAnimationLine(line, into: &surface)
                    result[surfaceID] = surface
                } else {
                    var surface = SerikoSurfaceDefinition(surfaceID: surfaceID, animations: [:])
                    parseAnimationLine(line, into: &surface)
                    result[surfaceID] = surface
                }
            }
        }

        return result
    }

    private static func parseAnimationLine(_ line: String, into surface: inout SerikoSurfaceDefinition) {
        // SERIKO/2.0 element 行（基底サーフェスの画像合成）
        if let element = parseElementLine(line) {
            surface.elements.append(element)
            surface.elements.sort { $0.index < $1.index }
            return
        }

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
                duration: durationAt(overlayArgs, index: 1)?.lowerBound ?? 0,
                x: intAt(overlayArgs, index: 2) ?? 0,
                y: intAt(overlayArgs, index: 3) ?? 0,
                rawArguments: overlayArgs,
                durationRange: durationAt(overlayArgs, index: 1)
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
        let rawArgs = splitArguments(argsPart)
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
        let rawArgs = splitArguments(argsPart)
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
        let durationValue = durationAt(rawArgs, index: methodOffset + 1)
        let duration = durationValue?.lowerBound ?? 0
        let x = intAt(rawArgs, index: methodOffset + 2) ?? 0
        let y = intAt(rawArgs, index: methodOffset + 3) ?? 0
        let xValue = doubleAt(rawArgs, index: methodOffset + 2)
        let yValue = doubleAt(rawArgs, index: methodOffset + 3)

        let pattern = SerikoPattern(
            index: patternIndex,
            method: method,
            surfaceID: surfaceID,
            duration: duration,
            x: x,
            y: y,
            rawArguments: rawArgs,
            xValue: xValue,
            yValue: yValue,
            durationRange: durationValue
        )
        return (animID, pattern)
    }

    private static func intAt(_ parts: [String], index: Int) -> Int? {
        guard index >= 0, index < parts.count else { return nil }
        return Int(parts[index])
    }

    /// Parse a fixed SERIKO wait or SSP's inclusive random wait range.
    /// Invalid ranges are rejected so malformed definitions retain the
    /// existing zero-duration fallback instead of silently inventing a frame.
    private static func durationAt(_ parts: [String], index: Int) -> ClosedRange<Int>? {
        guard index >= 0, index < parts.count else { return nil }
        let raw = parts[index].trimmingCharacters(in: .whitespacesAndNewlines)
        if let fixed = Int(raw) {
            return fixed...fixed
        }
        let bounds = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2,
              let lower = Int(bounds[0].trimmingCharacters(in: .whitespacesAndNewlines)),
              let upper = Int(bounds[1].trimmingCharacters(in: .whitespacesAndNewlines)),
              lower >= 0, upper >= 0 else {
            return nil
        }
        return min(lower, upper)...max(lower, upper)
    }

    private static func doubleAt(_ parts: [String], index: Int) -> Double? {
        guard index >= 0, index < parts.count else { return nil }
        return Double(parts[index])
    }

    /// Split a pattern argument list without splitting commas inside the
    /// parenthesized ID list used by alternativestart/parallelstart.
    private static func splitArguments(_ raw: String) -> [String] {
        var result: [String] = []
        var current = ""
        var depth = 0
        for character in raw {
            switch character {
            case "(", "[", "{":
                depth += 1
                current.append(character)
            case ")", "]", "}":
                depth = max(0, depth - 1)
                current.append(character)
            case "," where depth == 0:
                result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current.removeAll(keepingCapacity: true)
            default:
                current.append(character)
            }
        }
        if !current.isEmpty || !result.isEmpty {
            result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result
    }

    private static func parseSurfaceID(from line: String) -> Int? {
        let ids = parseSurfaceIDs(from: line)
        return ids.first
    }

    static func parseSurfaceIDs(from line: String) -> [Int] {
        guard line.hasPrefix("surface") else { return [] }
        var tail = String(line.dropFirst("surface".count))
        // surface.append123 → 123（既存サーフェス定義への追記マージ）
        if tail.hasPrefix(".append") {
            tail = String(tail.dropFirst(".append".count))
        }
        let parts = tail.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.compactMap { Int($0) }
    }

    private static func parseElementLine(_ line: String) -> SerikoElement? {
        let prefix = "element"
        guard line.hasPrefix(prefix) else { return nil }
        let afterPrefix = line.dropFirst(prefix.count)
        guard let comma = afterPrefix.firstIndex(of: ",") else { return nil }
        guard let id = Int(afterPrefix[..<comma]) else { return nil }
        let argsPart = String(afterPrefix[afterPrefix.index(after: comma)...])
        // elementN,method,filename,x,y （filename にカンマは想定しない）
        let args = argsPart.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard args.count >= 2 else { return nil }
        let method = SerikoMethod.parse(args[0])
        let filename = args[1]
        let x = args.count > 2 ? (Int(args[2]) ?? 0) : 0
        let y = args.count > 3 ? (Int(args[3]) ?? 0) : 0
        return SerikoElement(index: id, method: method, filename: filename, x: x, y: y)
    }

    /// Parse surface alias blocks (e.g. `sakura.surface.alias { 35,[55] }`)
    /// Returns a mapping from alias surface ID to target surface ID.
    public static func parseSurfaceAliases(_ content: String) -> [Int: Int] {
        let lines = content.components(separatedBy: .newlines)
        var result: [Int: Int] = [:]
        var inAliasBlock = false

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasSuffix("surface.alias") {
                inAliasBlock = false
                continue
            }
            if line == "{" && !inAliasBlock {
                // Check if previous non-empty line was a surface.alias header
                inAliasBlock = true
                continue
            }
            if line == "}" {
                inAliasBlock = false
                continue
            }
            if inAliasBlock {
                // Format: aliasID,[targetID] or aliasID,targetID
                let parts = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if parts.count >= 2 {
                    let aliasID = Int(parts[0])
                    let targetStr = parts[1].replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
                    let targetID = Int(targetStr)
                    if let a = aliasID, let t = targetID {
                        result[a] = t
                    }
                }
            }
        }

        // Also detect the header properly
        var result2: [Int: Int] = [:]
        var sawAliasHeader = false
        var inBlock = false
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasSuffix("surface.alias") {
                sawAliasHeader = true
                inBlock = false
                continue
            }
            if sawAliasHeader && line == "{" {
                inBlock = true
                sawAliasHeader = false
                continue
            }
            if line == "}" {
                inBlock = false
                sawAliasHeader = false
                continue
            }
            if !line.isEmpty { sawAliasHeader = false }
            if inBlock {
                let parts = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if parts.count >= 2 {
                    let aliasID = Int(parts[0])
                    let targetStr = parts[1].replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
                    let targetID = Int(targetStr)
                    if let a = aliasID, let t = targetID {
                        result2[a] = t
                    }
                }
            }
        }
        return result2
    }

    /// Parse surface alias blocks capturing string-named aliases too
    /// (e.g. `sakura.surface.alias { smile,[5,6] }`). Returns name(lowercased) → first surface ID.
    /// Used to resolve non-numeric `\s[name]` surface references.
    public static func parseNamedSurfaceAliases(_ content: String) -> [String: Int] {
        let lines = content.components(separatedBy: .newlines)
        var result: [String: Int] = [:]
        var sawHeader = false
        var inBlock = false
        for raw in lines {
            let line = stripComment(from: raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasSuffix("surface.alias") { sawHeader = true; inBlock = false; continue }
            if sawHeader && line == "{" { inBlock = true; sawHeader = false; continue }
            if line == "}" { inBlock = false; sawHeader = false; continue }
            if !line.isEmpty && !inBlock { sawHeader = false }
            if inBlock {
                guard let comma = line.firstIndex(of: ",") else { continue }
                let key = line[..<comma].trimmingCharacters(in: .whitespaces).lowercased()
                let valuePart = line[line.index(after: comma)...]
                    .replacingOccurrences(of: "[", with: "")
                    .replacingOccurrences(of: "]", with: "")
                let firstID = valuePart.split(separator: ",").first
                    .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if !key.isEmpty, let id = firstID {
                    result[key] = id
                }
            }
        }
        return result
    }

    private static func stripComment(from line: String) -> String {
        if let idx = line.firstIndex(of: "#") {
            return String(line[..<idx])
        }
        if let range = line.range(of: "//") {
            return String(line[..<range.lowerBound])
        }
        return line
    }
}

public enum SurfaceDefinitionLoader {
    public struct Bundle: Equatable {
        public let content: String
        public let sourceFileNames: [String]
    }

    /// Load shell surface definition text in SSP-compatible order.
    ///
    /// UKADOC/SSP treats every `surfaces***.txt` file in a shell directory as a
    /// surfaces definition file and reads them in filename order. `alias.txt`
    /// is a legacy companion file, so Ourin appends it after the SSP
    /// `surfaces*.txt` set to preserve existing compatibility.
    ///
    /// `surfacetable.txt` is a separate metadata file (サーフィステスト用グループ定義)
    /// whose syntax is incompatible with `surfaces.txt`. It is NOT included in
    /// this bundle; use `loadSurfaceTable(from:)` to parse it independently.
    public static func load(from shellURL: URL, fileManager: FileManager = .default) -> Bundle? {
        var chunks: [String] = []
        var sourceFileNames: [String] = []

        for url in surfaceDefinitionFiles(in: shellURL, fileManager: fileManager) {
            guard let text = readTextFile(url) else { continue }
            chunks.append(text)
            sourceFileNames.append(url.lastPathComponent)
        }

        for companion in ["alias.txt"] {
            let url = shellURL.appendingPathComponent(companion)
            guard isRegularFile(url, fileManager: fileManager),
                  let text = readTextFile(url)
            else { continue }
            chunks.append(text)
            sourceFileNames.append(companion)
        }

        guard !chunks.isEmpty else { return nil }
        return Bundle(content: chunks.joined(separator: "\n"), sourceFileNames: sourceFileNames)
    }

    /// `surfacetable.txt` を読み込んで `SurfaceTable` にパースする。
    /// ファイルが存在しない場合は nil を返す。
    public static func loadSurfaceTable(from shellURL: URL, fileManager: FileManager = .default) -> SurfaceTable? {
        let url = shellURL.appendingPathComponent("surfacetable.txt")
        guard isRegularFile(url, fileManager: fileManager),
              let text = readTextFile(url)
        else { return nil }
        return SurfaceTableParser.parse(text)
    }

    public static func surfaceDefinitionFiles(in shellURL: URL, fileManager: FileManager = .default) -> [URL] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: shellURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { isSurfaceDefinitionFile($0, fileManager: fileManager) }
            .sorted { isFilenameOrderedBefore($0.lastPathComponent, $1.lastPathComponent) }
    }

    private static func isSurfaceDefinitionFile(_ url: URL, fileManager: FileManager) -> Bool {
        let lowerName = url.lastPathComponent.lowercased()
        guard lowerName.hasPrefix("surfaces"), lowerName.hasSuffix(".txt") else {
            return false
        }
        return isRegularFile(url, fileManager: fileManager)
    }

    private static func isRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return false }
        return true
    }

    private static func isFilenameOrderedBefore(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.lowercased()
        let right = rhs.lowercased()
        if left == right {
            return lhs < rhs
        }
        return left < right
    }

    private static func readTextFile(_ url: URL) -> String? {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }
        return try? String(contentsOf: url, encoding: .shiftJIS)
    }
}
