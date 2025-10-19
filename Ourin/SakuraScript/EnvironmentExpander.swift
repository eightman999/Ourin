import Foundation
import AppKit

/// Expands SSP-style percent variables inside plain text segments.
/// - Supports date/time variables like `%month`, `%day`, ...
/// - Supports user/character names like `%username`, `%selfname`, `%keroname`.
/// - Supports screen metrics `%screenwidth`, `%screenheight`.
/// - Supports word-classes (単語-系) like `%ms`, `%mh`, `%me`, selecting randomly from `lexicon`.
/// - Supports `%property[system.year]` by delegating to `PropertyManager`.
/// - Unknown variables are kept as-is to allow later expansion by other layers.
public final class EnvironmentExpander {
    public var propertyManager: PropertyManager

    // Context values
    public var username: String?
    public var selfname: String?
    public var selfname2: String?
    public var keroname: String?

    /// Lexicon for word-classes (ms, mz, ml, mc, mh, mt, me, mp, m?, dms)
    public var lexicon: [String: [String]] = [:]

    public init(propertyManager: PropertyManager) {
        self.propertyManager = propertyManager
    }

    /// Expand percent variables in given text.
    public func expand(text: String, now: Date = Date()) -> String {
        if text.isEmpty { return text }
        // Match %key or %key[arg]; allow letters, '?' and '*' in key
        // Regex (as Swift string): "%([a-zA-Z?*]+)(?:\\[([^\\]]+)\\])?"
        let pattern = "%([a-zA-Z?*]+)(?:\\[([^\\]]+)\\])?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        let ns = text as NSString
        var result = text
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))

        // Replace from the end to preserve ranges
        for m in matches.reversed() {
            guard m.numberOfRanges >= 2, let keyRange = Range(m.range(at: 1), in: text) else { continue }
            let key = String(text[keyRange]).lowercased()
            let arg: String? = {
                if m.numberOfRanges >= 3, m.range(at: 2).location != NSNotFound, let r = Range(m.range(at: 2), in: text) { return String(text[r]) }
                return nil
            }()

            let replacement = expandVariable(key: key, arg: arg, now: now)
            if let full = Range(m.range(at: 0), in: result) {
                result.replaceSubrange(full, with: replacement)
            }
        }
        return result
    }

    private func expandVariable(key: String, arg: String?, now: Date) -> String {
        // Date/time
        let cal = Calendar.current
        switch key {
        case "month":   return String(cal.component(.month, from: now))
        case "day":     return String(cal.component(.day, from: now))
        case "hour":    return String(cal.component(.hour, from: now))
        case "minute":  return String(cal.component(.minute, from: now))
        case "second":  return String(cal.component(.second, from: now))
        case "username":
            if let v = username, !v.isEmpty { return v }
            return NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
        case "selfname":  return selfname ?? ""
        case "selfname2": return selfname2 ?? ""
        case "keroname":  return keroname ?? ""
        case "charname":
            // %(charname[scope]) - Get character name for scope
            if let arg = arg, let scope = Int(arg) {
                switch scope {
                case 0: return selfname ?? ""
                case 1: return keroname ?? ""
                default: return ""
                }
            }
            return ""
        case "screenwidth":
            return String(Int(NSScreen.main?.frame.width ?? 0))
        case "screenheight":
            return String(Int(NSScreen.main?.frame.height ?? 0))
        case "exh":
            // OS uptime in hours (rounded down)
            let hours = Int(ProcessInfo.processInfo.systemUptime / 3600)
            return String(hours)
        case "et":
            // Wrong (random) uptime with OS-localized units.
            let h = Int.random(in: 0...999)
            let m = Int.random(in: 0...59)
            let s = Int.random(in: 0...59)
            let total = h * 3600 + m * 60 + s
            let fmt = DateComponentsFormatter()
            fmt.allowedUnits = [.hour, .minute, .second]
            fmt.unitsStyle = .abbreviated // OS/Locale-compliant like "1時間23分45秒" in ja_JP
            if let localized = fmt.string(from: TimeInterval(total)), !localized.isEmpty {
                return localized
            }
            // Fallback
            return "\(h)h\(m)m\(s)s"
        case "wronghour":
            // Random hour (0-23) as per request
            return String(Int.random(in: 0...23))
        case "*":
            // `%*` behaves like `!\[*]`; keep empty for now
            return ""
        case "property":
            if let name = arg { return propertyManager.get(name) ?? "" }
            return ""
        case "ms", "mz", "ml", "mc", "mh", "mt", "me", "mp", "m?", "dms":
            let items = lexicon[key] ?? []
            return items.randomElement() ?? ""
        default:
            // Unknown: keep original placeholder intact by returning with leading '%'
            // However, our caller replaces based on matched range; to preserve, return placeholder
            if let arg = arg { return "%\(key)[\(arg)]" } else { return "%\(key)" }
        }
    }
}
