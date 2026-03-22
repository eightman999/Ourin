import Foundation

/// SSTP リクエストを表す構造体
public struct SSTPRequest {
    public enum Option: String, CaseIterable, Hashable {
        case notify
        case notranslate
        case nobreak
        case nodescript
    }

    /// メソッド名 (SEND/NOTIFY 等)
    public var method: String
    /// プロトコルバージョン
    public var version: String
    /// ヘッダー集合
    public var headers: [String: String]
    /// 追加データ
    public var body: Data

    public init(method: String = "", version: String = "", headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.version = version
        self.headers = headers
        self.body = body
    }

    public func headerValue(_ name: String) -> String? {
        if let exact = headers[name] { return exact }
        let lowerName = name.lowercased()
        return headers.first(where: { $0.key.lowercased() == lowerName })?.value
    }

    public var ifGhost: [(ghost: String, sakura: String, kero: String)] {
        parseIfGhostHeaders(headers)
    }

    public var entry: [String: String] {
        parseKeyValuePairs(headerValue("Entry"))
    }

    public var hWnd: UInt? {
        parseUnsigned(headerValue("HWnd"))
    }

    public var receiverGhostHWnd: UInt? {
        parseUnsigned(headerValue("ReceiverGhostHWnd"))
    }

    public var receiverGhostName: String? {
        let value = headerValue("ReceiverGhostName")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    public var options: Set<Option> {
        let rawValues = headers
            .filter { $0.key.lowercased() == "option" }
            .map(\.value)
        guard !rawValues.isEmpty else { return [] }

        var parsed: Set<Option> = []
        for raw in rawValues {
            let normalized = raw.replacingOccurrences(of: ";", with: ",")
            let tokens = normalized
                .split(whereSeparator: { $0 == "," || $0.isWhitespace })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            for token in tokens {
                if let option = Option(rawValue: token) {
                    parsed.insert(option)
                }
            }
        }
        return parsed
    }

    public var document: String? {
        headerValue("Document")
    }

    public var song: String? {
        headerValue("Song")
    }

    private func parseUnsigned(_ raw: String?) -> UInt? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            return UInt(text.dropFirst(2), radix: 16)
        }
        return UInt(text)
    }

    private func parseKeyValuePairs(_ raw: String?) -> [String: String] {
        guard let raw else { return [:] }
        var out: [String: String] = [:]
        for item in raw.split(separator: ";") {
            let token = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, let eq = token.firstIndex(of: "=") else { continue }
            let key = String(token[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(token[token.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                out[key] = value
            }
        }
        return out
    }

    private func parseIfGhostHeaders(_ headers: [String: String]) -> [(ghost: String, sakura: String, kero: String)] {
        let candidates = headers
            .filter { $0.key.lowercased() == "ifghost" || $0.key.lowercased().hasPrefix("ifghost.") }
            .sorted { $0.key < $1.key }
            .map(\.value)

        var result: [(ghost: String, sakura: String, kero: String)] = []
        for value in candidates {
            for entry in value.split(separator: ";") {
                let token = entry.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !token.isEmpty else { continue }
                let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count != 2 { continue }
                let ghost = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let scripts = parts[1].split(separator: "|", maxSplits: 1).map(String.init)
                let sakura = scripts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let kero = scripts.count > 1 ? scripts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                if !ghost.isEmpty {
                    result.append((ghost: ghost, sakura: sakura, kero: kero))
                }
            }
        }
        return result
    }
}
