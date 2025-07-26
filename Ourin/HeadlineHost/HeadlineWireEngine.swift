import Foundation

/// Build HEADLINE/2.0M request and parse response
public struct HeadlineWireEngine {
    public static func buildRequest(path: String, charset: String.Encoding = .utf8) -> String {
        let cs: String
        switch charset {
        case .shiftJIS: cs = "Shift_JIS"
        default: cs = "UTF-8"
        }
        return "GET Headline HEADLINE/2.0M\r\nCharset: \(cs)\r\nOption: url\r\nPath: \(path)\r\n\r\n"
    }

    /// Parse HEADLINE response lines to array of (text,url)
    public static func parseLines(_ response: String) -> [(String, String?)] {
        var results: [(String, String?)] = []
        for line in response.split(whereSeparator: { $0.isNewline }) {
            guard line.hasPrefix("Headline:") else { continue }
            let value = line.dropFirst("Headline:".count).trimmingCharacters(in: .whitespaces)
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
}
