import Foundation

/// SHIORI 実行系の種類。
///
/// ベースウェア側は、YAYA/里々/ネイティブ SHIORI の違いではなく、
/// この分類と共通要求インターフェースだけを扱う。
enum ShioriRuntimeKind: String, Codable, Equatable {
    case yaya
    case satori
    case native
}

/// descript.txtのshiori.*をワイヤ境界まで保持する通信設定。
public struct ShioriCommunicationOptions: Equatable {
    public var version: String?
    public var encoding: String?
    public var forceEncoding: String?
    public var escapeUnknown: Bool
    public var cache: Bool

    public init(version: String? = nil, encoding: String? = nil, forceEncoding: String? = nil,
                escapeUnknown: Bool = false, cache: Bool = false) {
        self.version = version
        self.encoding = encoding
        self.forceEncoding = forceEncoding
        self.escapeUnknown = escapeUnknown
        self.cache = cache
    }

    var outboundCharset: String { forceEncoding ?? encoding ?? "UTF-8" }
}

/// SHIORIランタイムをロードする際に必要な、ゴースト共通の入力。
///
/// YAYA固有の辞書一覧もここへ格納するが、Native/里々ランタイムは不要な値を
/// 無視できる。GhostManager側でランタイム型を判定してロード処理を分岐しないための境界。
struct ShioriRuntimeLoadContext {
    let ghostURL: URL
    let ghostRoot: URL
    let moduleName: String
    let dictionaryEntries: [DicEntry]
    let dictionaryEncoding: String
    let communication: ShioriCommunicationOptions

    init(
        ghostURL: URL,
        ghostRoot: URL,
        moduleName: String,
        dictionaryEntries: [DicEntry] = [],
        dictionaryEncoding: String = "auto",
        communication: ShioriCommunicationOptions = .init()
    ) {
        self.ghostURL = ghostURL
        self.ghostRoot = ghostRoot
        self.moduleName = moduleName
        self.dictionaryEntries = dictionaryEntries
        self.dictionaryEncoding = dictionaryEncoding
        self.communication = communication
    }
}

/// SHIORI ヘルパーが返す構造化応答。
///
/// `loaded_dics` は現在の yaya_core IPC 互換の診断フィールドで、
/// 他の SHIORI 実装では nil でよい。YayaResponse は移行期間の別名として残す。
struct ShioriRuntimeResponse: Codable, Equatable {
    let ok: Bool
    let status: Int
    let headers: [String: String]?
    let value: String?
    let error: String?
    let loaded_dics: [String]?

    init(
        ok: Bool,
        status: Int,
        headers: [String: String]? = nil,
        value: String? = nil,
        error: String? = nil,
        loaded_dics: [String]? = nil
    ) {
        self.ok = ok
        self.status = status
        self.headers = headers
        self.value = value
        self.error = error
        self.loaded_dics = loaded_dics
    }
}

/// ゴーストから見た SHIORI 実行系の共通境界。
///
/// ロード処理は実装ごとに辞書形式が異なるため、最初の共通化スライスでは
/// 要求・応答・終了の境界を定義する。各 runtime の生成・初期ロードは
/// `ShioriRuntimeFactory` に集約する。
protocol GhostShioriRuntime: AnyObject {
    var kind: ShioriRuntimeKind { get }
    var isLoaded: Bool { get }
    var resourceManager: ResourceManager? { get set }

    @discardableResult
    func load(context: ShioriRuntimeLoadContext) -> Bool

    func request(
        method: String,
        id: String,
        headers: [String: String],
        refs: [String],
        timeout: TimeInterval
    ) -> ShioriRuntimeResponse?

    func unload()
}

extension GhostShioriRuntime {
    func request(method: String, id: String, refs: [String] = [], timeout: TimeInterval) -> ShioriRuntimeResponse? {
        request(method: method, id: id, headers: [:], refs: refs, timeout: timeout)
    }
}

/// 既存コードとテストの段階移行用。新規コードでは ShioriRuntimeResponse を使う。
typealias YayaResponse = ShioriRuntimeResponse

/// SHIORI/3.xの構造化要求とワイヤ文字列の相互変換。
/// Native SHIORIだけが独自実装を持つと、YAYA経路とのヘッダ差分が発生するため、
/// ワイヤ境界をここへ集約する。
enum ShioriWireCodec {
    static func makeRequest(
        method: String,
        id: String,
        headers: [String: String],
        refs: [String],
        protocolVersion: String = "SHIORI/3.0",
        charset: String = "UTF-8"
    ) -> String {
        let verb = method.uppercased() == "NOTIFY" ? "NOTIFY" : "GET"
        var merged = headers
        setDefaultHeader("Charset", value: charset, in: &merged)
        setDefaultHeader("Sender", value: "Ourin", in: &merged)
        setHeader("ID", value: id, in: &merged)
        for (index, reference) in refs.enumerated() {
            setHeader("Reference\(index)", value: reference, in: &merged)
        }

        let ordered = merged.sorted { lhs, rhs in
            headerSortKey(lhs.key) < headerSortKey(rhs.key)
        }
        let version = protocolVersion.uppercased().hasPrefix("SHIORI/") ? protocolVersion.uppercased() : "SHIORI/3.0"
        var lines = ["\(verb) \(version)"]
        lines.append(contentsOf: ordered.map { "\(sanitize($0.key)): \(sanitize($0.value))" })
        return lines.joined(separator: "\r\n") + "\r\n\r\n"
    }

    static func parseResponse(_ text: String) -> ShioriRuntimeResponse? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard let statusLine = lines.first else { return nil }
        let statusParts = statusLine.split(whereSeparator: { $0.isWhitespace })
        guard statusParts.count >= 2,
              statusParts[0].uppercased().hasPrefix("SHIORI/"),
              let status = Int(statusParts[1]) else {
            return nil
        }

        var headers: [String: String] = [:]
        var value: String?
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            if key.caseInsensitiveCompare("Value") == .orderedSame {
                value = rawValue
            } else {
                headers[key] = rawValue
            }
        }
        return ShioriRuntimeResponse(
            // `ok` はSHIORIステータスの成否ではなく、ランタイムとの通信・応答解析が
            // 完了したことを表す。YAYA IPCも204/400を含む有効応答ではtrueを返す。
            ok: true,
            status: status,
            headers: headers.isEmpty ? nil : headers,
            value: value
        )
    }

    private static func setDefaultHeader(_ key: String, value: String, in headers: inout [String: String]) {
        guard !headers.keys.contains(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) else { return }
        headers[key] = value
    }

    private static func setHeader(_ key: String, value: String, in headers: inout [String: String]) {
        if let existing = headers.keys.first(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) {
            headers.removeValue(forKey: existing)
        }
        headers[key] = value
    }

    private static func headerSortKey(_ key: String) -> String {
        let lower = key.lowercased()
        if lower == "charset" { return "00" }
        if lower == "sender" { return "01" }
        if lower == "id" { return "02" }
        if lower.hasPrefix("reference"), let index = Int(lower.dropFirst("reference".count)) {
            return String(format: "03-%08d", index)
        }
        return "04-\(lower)"
    }

    private static func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }
}
