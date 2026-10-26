import Foundation

enum LegacyDescriptor {
    static func readDictionary(from url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url),
              let text = decode(data) else { return nil }
        return parseDictionary(text)
    }

    static func decode(_ data: Data) -> String? {
        EncodingAdapter.decodeTextDefinition(data)
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

    /// ukadoc descript.txt 共通規則: 先頭が `\` / `%` の値はさくらスクリプト・環境変数タグとみなして破棄し、
    /// 先頭の `\\` / `\%` は文字としての `\` / `%` へ戻す。
    static func literalValue(_ raw: String) -> String? {
        if raw.hasPrefix("\\\\") || raw.hasPrefix("\\%") {
            return String(raw.dropFirst())
        }
        if raw.hasPrefix("\\") || raw.hasPrefix("%") {
            return nil
        }
        return raw
    }
}
