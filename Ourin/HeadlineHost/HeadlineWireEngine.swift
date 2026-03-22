import Foundation

/// HEADLINE protocol version
public enum HeadlineProtocolVersion: String {
    case v2_0 = "HEADLINE/2.0"
    case v2_0M = "HEADLINE/2.0M"
}

/// Build HEADLINE/2.0 and HEADLINE/2.0M requests and parse responses
public struct HeadlineWireEngine {
    /// Build GET Version request
    public static func buildVersionRequest(
        version: HeadlineProtocolVersion = .v2_0,
        charset: String.Encoding = .utf8,
        sender: String = "Ourin"
    ) -> String {
        let cs = charsetString(for: charset)
        return "GET Version \(version.rawValue)\r\nCharset: \(cs)\r\nSender: \(sender)\r\n\r\n"
    }

    /// Build GET Headline request
    public static func buildHeadlineRequest(
        path: String,
        version: HeadlineProtocolVersion = .v2_0,
        charset: String.Encoding = .utf8,
        sender: String = "Ourin"
    ) -> String {
        let cs = charsetString(for: charset)
        let normalizedPath = normalizePathForWire(path)
        return "GET Headline \(version.rawValue)\r\nCharset: \(cs)\r\nSender: \(sender)\r\nOption: url\r\nPath: \(normalizedPath)\r\n\r\n"
    }

    /// Legacy method for backward compatibility
    public static func buildRequest(path: String, charset: String.Encoding = .utf8) -> String {
        return buildHeadlineRequest(path: path, version: .v2_0M, charset: charset)
    }

    /// Parse HEADLINE response lines to array of (text,url)
    public static func parseLines(_ response: String) -> [(String, String?)] {
        var results: [(String, String?)] = []
        for line in response.split(whereSeparator: { $0.isNewline }) {
            let raw = String(line)
            guard raw.lowercased().hasPrefix("headline:") else { continue }
            let value = raw.dropFirst("Headline:".count).trimmingCharacters(in: .whitespaces)
            if let sep = value.firstIndex(of: "\u{01}") {
                let text = String(value[..<sep])
                let url = String(value[value.index(after: sep)...])
                results.append((text, url))
            } else {
                results.append((String(value), nil))
            }
        }
        return results
    }

    /// Parse Version response to get version string
    public static func parseVersion(_ response: String) -> String? {
        for line in response.split(whereSeparator: { $0.isNewline }) {
            let raw = String(line)
            guard raw.lowercased().hasPrefix("value:") else { continue }
            return String(raw.dropFirst("Value:".count).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// Parse response charset
    public static func parseCharset(_ response: String) -> String.Encoding {
        for line in response.split(whereSeparator: { $0.isNewline }) {
            let raw = String(line)
            guard raw.lowercased().hasPrefix("charset:") else { continue }
            let value = raw.dropFirst("Charset:".count).trimmingCharacters(in: .whitespaces).lowercased()
            if ["shift_jis", "windows-31j", "cp932", "ms932", "sjis"].contains(value) {
                return .shiftJIS
            }
            return .utf8
        }
        return .utf8
    }

    /// Parse RequestCharset (next request's preferred charset)
    public static func parseRequestCharset(_ response: String) -> String.Encoding? {
        for line in response.split(whereSeparator: { $0.isNewline }) {
            let raw = String(line)
            guard raw.lowercased().hasPrefix("requestcharset:") else { continue }
            let value = raw.dropFirst("RequestCharset:".count).trimmingCharacters(in: .whitespaces).lowercased()
            if ["shift_jis", "windows-31j", "cp932", "ms932", "sjis"].contains(value) {
                return .shiftJIS
            }
            return .utf8
        }
        return nil
    }

    // MARK: - Private Helpers

    private static func charsetString(for encoding: String.Encoding) -> String {
        switch encoding {
        case .shiftJIS: return "Shift_JIS"
        default: return "UTF-8"
        }
    }

    private static func normalizePathForWire(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if trimmed.lowercased().hasPrefix("file://") {
            return trimmed
        }

        if trimmed.range(of: #"^[A-Za-z]:\\"#, options: .regularExpression) != nil {
            let pathPart = trimmed.replacingOccurrences(of: "\\", with: "/")
            let absolute = pathPart.hasPrefix("/") ? pathPart : "/" + pathPart
            if let encoded = absolute.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                return "file://\(encoded)"
            }
            return "file://\(absolute)"
        }

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL.absoluteString
        }

        return trimmed
    }
}
