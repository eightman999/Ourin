import Foundation

extension String.Encoding {
    static let ourinShiftJIS = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)
        )
    )
}

enum LegacyDescriptor {
    static func readDictionary(from url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url),
              let text = decode(data) else { return nil }
        return parseDictionary(text)
    }

    static func decode(_ data: Data) -> String? {
        let probe = String(data: data.prefix(256), encoding: .utf8) ?? ""
        var encoding: String.Encoding = .utf8
        if let firstLine = probe.split(whereSeparator: { $0.isNewline }).first {
            let lower = firstLine.lowercased()
            if lower.starts(with: "charset") {
                let value = lower.split(separator: ",", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if ["shift_jis", "windows-31j", "cp932", "ms932", "sjis"].contains(value) {
                    encoding = .ourinShiftJIS
                }
            }
        }
        return String(data: data, encoding: encoding)
            ?? String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ourinShiftJIS)
    }

    static func parseDictionary(_ text: String) -> [String: String] {
        var dict: [String: String] = [:]
        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") { continue }
            let parts = line.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                dict[key] = value
            }
        }
        return dict
    }
}
