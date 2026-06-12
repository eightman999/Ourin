import Foundation

/// SSTP リクエストを表す構造体
public struct SSTPRequest {
    public enum Option: String, CaseIterable, Hashable {
        case notify
        case notranslate
        case nobreak
        case nodescript
    }

    /// IfGhost ヘッダと Script ヘッダの組（UKADOC: IfGhost は直後の Script と対応付け）。
    /// ifGhost が nil のものはデフォルトスクリプト。
    public struct ScriptBinding: Equatable {
        public let ifGhost: String?
        public let script: String

        public init(ifGhost: String?, script: String) {
            self.ifGhost = ifGhost
            self.script = script
        }
    }

    /// メソッド名 (SEND/NOTIFY 等)
    public var method: String
    /// プロトコルバージョン
    public var version: String
    /// 受信順を保持したヘッダ列。IfGhost/Script の対応付けや重複ヘッダ（Option 等）に順序が必要
    public private(set) var headerEntries: [(key: String, value: String)]
    /// 追加データ
    public var body: Data

    /// 辞書形式のヘッダ（重複ヘッダは後勝ち）。順序・重複が意味を持つ場合は headerEntries を使う。
    /// setter は順序情報を失うため、個別の変更には setHeader(_:_:) を使うこと。
    public var headers: [String: String] {
        get {
            var dict: [String: String] = [:]
            for entry in headerEntries {
                dict[entry.key] = entry.value
            }
            return dict
        }
        set {
            headerEntries = newValue.map { (key: $0.key, value: $0.value) }
        }
    }

    public init(method: String = "", version: String = "", headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.version = version
        self.headerEntries = headers.map { (key: $0.key, value: $0.value) }
        self.body = body
    }

    public init(method: String, version: String, headerEntries: [(key: String, value: String)], body: Data = Data()) {
        self.method = method
        self.version = version
        self.headerEntries = headerEntries
        self.body = body
    }

    /// ヘッダを受信順の末尾に追加する（重複可。パーサ用）
    public mutating func appendHeader(_ key: String, _ value: String) {
        headerEntries.append((key: key, value: value))
    }

    /// ヘッダを設定する。既存キー（大文字小文字無視）があれば最初の出現を上書き、無ければ末尾に追加。
    public mutating func setHeader(_ key: String, _ value: String) {
        if let index = headerEntries.firstIndex(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
            headerEntries[index].value = value
        } else {
            headerEntries.append((key: key, value: value))
        }
    }

    public func headerValue(_ name: String) -> String? {
        if let exact = headerEntries.first(where: { $0.key == name }) {
            return exact.value
        }
        return headerEntries.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame })?.value
    }

    /// UKADOC「IfGhostによるスクリプト振り分け」用に、IfGhost と Script を出現順で対応付けた組を返す。
    /// 最初の IfGhost より前（または IfGhost の直後でない位置）の Script は ifGhost == nil となる。
    public var scriptBindings: [ScriptBinding] {
        var result: [ScriptBinding] = []
        var pendingIfGhost: String? = nil
        for entry in headerEntries {
            switch entry.key.lowercased() {
            case "ifghost":
                pendingIfGhost = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            case "script":
                result.append(ScriptBinding(ifGhost: pendingIfGhost, script: entry.value))
                pendingIfGhost = nil
            default:
                continue
            }
        }
        return result
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
        let rawValues = headerEntries
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
}
