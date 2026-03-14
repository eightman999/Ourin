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
        // Match %("key(arg)") - e.g., %("charname(0)")
        let pattern1 = "%\\(([^\\)]+)\\(([^\\)]+)\\)\\)"
        if let regex1 = try? NSRegularExpression(pattern: pattern1) {
            let matches = regex1.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
            Foundation.NSLog("[EnvironmentExpander] Pattern 1: \(pattern1), matches: \(matches.count)")
            
            var result = text
            for m in matches.reversed() {
                let full = Range(m.range(at: 0), in: result)!
                let keyRange = Range(m.range(at: 1), in: result)!
                let argRange = Range(m.range(at: 2), in: result)!
                let key = String(result[keyRange]).lowercased()
                let arg = String(result[argRange])
                
                Foundation.NSLog("[EnvironmentExpander] Pattern 1 matched: key=\(key), arg=\(arg)")
                
                let replacement = expandVariable(key: key, arg: arg, now: now)
                Foundation.NSLog("[EnvironmentExpander] Replacement: \(replacement)")
                result.replaceSubrange(full, with: replacement)
            }
            if !matches.isEmpty {
                Foundation.NSLog("[EnvironmentExpander] Final result: \(result)")
                return result
            }
        }
        
        // Match %key[arg] or %key(arg) - e.g., %charname[0] or %charname(0)
        let pattern2 = "%([a-zA-Z?*]+)(?:\\[([^\\]]+)\\]|\\(([^\\)]+)\\))"
        if let regex2 = try? NSRegularExpression(pattern: pattern2) {
            let matches = regex2.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
            Foundation.NSLog("[EnvironmentExpander] Pattern 2: \(pattern2), matches: \(matches.count)")
            
            var result = text
            for m in matches.reversed() {
                let full = Range(m.range(at: 0), in: result)!
                let keyRange = Range(m.range(at: 1), in: result)!
                let argRange: Range<String.Index>?
                
                if m.range(at: 2).location != NSNotFound {
                    argRange = Range(m.range(at: 2), in: result)!
                } else if m.range(at: 3).location != NSNotFound {
                    argRange = Range(m.range(at: 3), in: result)!
                } else {
                    argRange = nil
                }
                
                let key = String(result[keyRange]).lowercased()
                let arg = argRange.map { String(result[$0]) }
                
                Foundation.NSLog("[EnvironmentExpander] Pattern 2 matched: key=\(key), arg=\(arg ?? "nil")")
                
                let replacement = expandVariable(key: key, arg: arg, now: now)
                Foundation.NSLog("[EnvironmentExpander] Replacement: \(replacement)")
                result.replaceSubrange(full, with: replacement)
            }
            Foundation.NSLog("[EnvironmentExpander] Final result: \(result)")
            return result
        }
        
        // Match %key - e.g., %charname
        let pattern3 = "%([a-zA-Z?*]+)"
        if let regex3 = try? NSRegularExpression(pattern: pattern3) {
            let matches = regex3.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
            Foundation.NSLog("[EnvironmentExpander] Pattern 3: \(pattern3), matches: \(matches.count)")
            
            var result = text
            for m in matches.reversed() {
                let full = Range(m.range(at: 0), in: result)!
                let keyRange = Range(m.range(at: 1), in: result)!
                let key = String(result[keyRange]).lowercased()
                
                Foundation.NSLog("[EnvironmentExpander] Pattern 3 matched: key=\(key)")
                
                let replacement = expandVariable(key: key, arg: nil, now: now)
                Foundation.NSLog("[EnvironmentExpander] Replacement: \(replacement)")
                result.replaceSubrange(full, with: replacement)
            }
            Foundation.NSLog("[EnvironmentExpander] Final result: \(result)")
            return result
        }
        
        return text
    }

    private func expandVariable(key: String, arg: String?, now: Date) -> String {
        Foundation.NSLog("[EnvironmentExpander] expandVariable() called: key=\(key), arg=\(arg ?? "nil")")

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
            Foundation.NSLog("[EnvironmentExpander] charname: arg=\(arg ?? "nil"), selfname=\(selfname ?? "nil"), keroname=\(keroname ?? "nil")")
            // %(charname[scope]) - Get character name for scope
            if let arg = arg, let scope = Int(arg) {
                switch scope {
                case 0:
                    Foundation.NSLog("[EnvironmentExpander] charname(0) returning: \(selfname ?? "")")
                    return selfname ?? ""
                case 1:
                    Foundation.NSLog("[EnvironmentExpander] charname(1) returning: \(keroname ?? "")")
                    return keroname ?? ""
                default:
                    Foundation.NSLog("[EnvironmentExpander] charname(\(scope)) returning empty")
                    return ""
                }
            }
            Foundation.NSLog("[EnvironmentExpander] charname: no valid arg, returning empty")
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
