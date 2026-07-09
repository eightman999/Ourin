import Foundation

/// SHIORI/3.0 ワイヤを SHIORI/2.x ワイヤへ変換する互換レイヤー。
///
/// 2.x と判定されたバックエンドにだけ変換を適用し、3.0 バックエンドには入力をそのまま渡す。
/// 2.x 側へ既に整形済みのリクエストが来た場合は、XPC サービス内の二重変換を避けるため素通しする。
final class Shiori2CompatBackend: ShioriBackend {
    private enum ProtocolMode {
        case unknown
        case shiori2(String)
        case shiori3
    }

    private let backend: ShioriBackend
    private let lock = NSLock()
    private var mode: ProtocolMode

    init(wrapping backend: ShioriBackend, detectedVersion: String? = nil) {
        self.backend = backend
        if let detectedVersion, Self.isShiori2Version(detectedVersion) {
            self.mode = .shiori2(detectedVersion.uppercased())
        } else {
            self.mode = .unknown
        }
    }

    func request(_ text: String) -> String? {
        guard let parsed = Shiori2Request.parse(text) else {
            return backend.request(text)
        }

        if Self.isShiori2Version(parsed.protocolVersion) {
            return backend.request(text)
        }

        switch resolveMode() {
        case .shiori2:
            guard let converted = Shiori2CompatAdapter.buildRequest(from: parsed) else {
                return Shiori2CompatAdapter.noContentResponse()
            }
            guard let response = backend.request(converted.wire) else {
                return nil
            }
            let normalized = Shiori2CompatAdapter.normalizeResponse(response)
            if parsed.method == "NOTIFY", normalized.status == 200 {
                return Shiori2CompatAdapter.noContentResponse()
            }
            return normalized.wire
        case .shiori3, .unknown:
            return backend.request(text)
        }
    }

    func unload() {
        backend.unload()
    }

    private func resolveMode() -> ProtocolMode {
        lock.lock()
        let current = mode
        lock.unlock()
        if case .unknown = current {
            let detected = detectProtocolMode()
            lock.lock()
            if case .unknown = mode {
                mode = detected
            }
            let resolved = mode
            lock.unlock()
            return resolved
        }
        return current
    }

    private func detectProtocolMode() -> ProtocolMode {
        let request = Shiori2CompatAdapter.versionRequest()
        guard let response = backend.request(request),
              let status = Shiori2Response.parseStatusLine(response),
              Self.isShiori2Version(status.version),
              status.code >= 200,
              status.code < 300 else {
            return .shiori3
        }
        return .shiori2(status.version.uppercased())
    }

    private static func isShiori2Version(_ version: String) -> Bool {
        version.uppercased().hasPrefix("SHIORI/2.")
    }
}

struct Shiori2Request {
    let method: String
    let protocolVersion: String
    let target: String?
    let headerEntries: [(key: String, value: String)]

    var id: String? { headerValue("ID") }
    var securityLevel: String { headerValue("SecurityLevel")?.lowercased() == "external" ? "external" : "local" }
    var sender: String { headerValue("Sender") ?? "Ourin" }

    func headerValue(_ name: String) -> String? {
        if let exact = headerEntries.first(where: { $0.key == name }) {
            return exact.value
        }
        return headerEntries.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    func headers(named name: String) -> [String] {
        headerEntries
            .filter { $0.key.caseInsensitiveCompare(name) == .orderedSame }
            .map(\.value)
    }

    func references(limit: Int? = nil) -> [String] {
        let maxCount = limit ?? Int.max
        var refs: [String] = []
        for i in 0..<maxCount {
            guard let value = headerValue("Reference\(i)") else { break }
            refs.append(value)
        }
        return refs
    }

    static func parse(_ text: String) -> Shiori2Request? {
        let lines = text.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return nil }

        let method = parts[0].uppercased()
        let target: String?
        let version: String
        if parts.count >= 3, parts[2].uppercased().hasPrefix("SHIORI/") {
            target = parts[1]
            version = parts[2].uppercased()
        } else {
            target = nil
            version = parts[1].uppercased()
        }

        var entries: [(key: String, value: String)] = []
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            entries.append((key: key, value: value))
        }
        return Shiori2Request(method: method, protocolVersion: version, target: target, headerEntries: entries)
    }
}

struct Shiori2WireRequest {
    let wire: String
}

struct Shiori2NormalizedResponse {
    let status: Int
    let wire: String
}

private struct Shiori2ResponseStatus {
    let version: String
    let code: Int
    let phrase: String
}

private struct Shiori2Response {
    let status: Shiori2ResponseStatus
    let headerEntries: [(key: String, value: String)]

    func headerValue(_ name: String) -> String? {
        if let exact = headerEntries.first(where: { $0.key == name }) {
            return exact.value
        }
        return headerEntries.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    static func parse(_ text: String) -> Shiori2Response? {
        guard let status = parseStatusLine(text) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        var entries: [(key: String, value: String)] = []
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            entries.append((key: key, value: value))
        }
        return Shiori2Response(status: status, headerEntries: entries)
    }

    static func parseStatusLine(_ text: String) -> Shiori2ResponseStatus? {
        guard let first = text.components(separatedBy: "\r\n").first else { return nil }
        let parts = first.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2, parts[0].uppercased().hasPrefix("SHIORI/"), let code = Int(parts[1]) else {
            return nil
        }
        let phrase = parts.count >= 3 ? parts[2] : Shiori2CompatAdapter.statusPhrase(for: code)
        return Shiori2ResponseStatus(version: parts[0].uppercased(), code: code, phrase: phrase)
    }
}

enum Shiori2CompatAdapter {
    private static let shiori2EventIDs: Set<String> = [
        "OnFirstBoot", "OnBoot", "OnClose", "OnWindowStateMinimize", "OnWindowStateRestore", "OnTeachStart",
        "OnGhostChanging", "OnGhostChanged", "OnShellChanging", "OnShellChanged",
        "OnVanishSelecting", "OnVanishSelected", "OnVanishCancel", "OnVanishButtonHold", "OnVanished",
        "OnSecondChange", "OnMinuteChange",
        "OnSurfaceChange", "OnSurfaceRestore",
        "OnMouseMove", "OnMouseClick", "OnMouseDoubleClick", "OnMouseWheel", "OnKeyPress",
        "OnChoiceSelect", "OnChoiceTimeout",
        "OnSSTPBreak",
        "OnInstallBegin", "OnInstallComplete", "OnInstallFailure", "OnInstallRefuse",
        "OnFileDropping", "OnFileDropped", "OnDirectoryDrop", "OnWallpaperChange", "OnURLDropping", "OnURLDropped",
        "OnDisplayChange", "OnNetworkHeavy", "OnSSTPBlacklisting", "OnRecommendsiteChoice",
        "OnBIFF", "OnSNTPComplete", "OnSNTPFailure", "OnHeadlinesenseComplete", "OnHeadlinesenseFailure",
        "OnMusicPlay", "OnNarCreating", "OnNarCreated", "OnUpdatedataCreating", "OnUpdatedataCreated"
    ]

    static func versionRequest() -> String {
        buildWire(firstLine: "GET Version SHIORI/2.0", headers: [
            ("Sender", "Ourin"),
            ("SecurityLevel", "local"),
            ("Charset", "Shift_JIS")
        ])
    }

    static func buildRequest(from request: Shiori2Request) -> Shiori2WireRequest? {
        let id = request.id ?? request.target ?? ""
        let lowerID = id.lowercased()

        if request.method == "TEACH" || lowerID == "onteach" {
            return buildTeachRequest(from: request)
        }
        if lowerID == "resource" {
            return buildStringRequest(from: request)
        }
        if lowerID == "ownerghostname" {
            return buildOwnerGhostNameRequest(from: request)
        }
        if lowerID == "otherghostname" || lowerID == "installedghostname" {
            return buildOtherGhostNameRequest(from: request)
        }
        if lowerID == "oncommunicate" {
            return buildCommunicateRequest(from: request)
        }
        if lowerID == "ontalkrequest" {
            return buildUserSentenceRequest(from: request)
        }
        if lowerID == "word" || lowerID == "getword" {
            return buildWordRequest(from: request)
        }
        if lowerID == "status" || lowerID == "getstatus" {
            return buildStatusRequest(from: request)
        }
        guard shiori2EventIDs.contains(id) else {
            return nil
        }
        return buildEventRequest(from: request, eventID: id)
    }

    static func normalizeResponse(_ response: String) -> Shiori2NormalizedResponse {
        guard let parsed = Shiori2Response.parse(response),
              parsed.status.version.hasPrefix("SHIORI/2.") else {
            return Shiori2NormalizedResponse(status: 0, wire: response)
        }
        if parsed.status.code == 310 {
            return Shiori2NormalizedResponse(status: 204, wire: noContentResponse())
        }

        var headers: [(String, String)] = [("Charset", "UTF-8")]
        var value: String?

        for entry in parsed.headerEntries {
            let lower = entry.key.lowercased()
            switch lower {
            case "charset", "sender":
                continue
            case "sentence", "word", "string":
                if value == nil { value = entry.value }
            case "status":
                headers.append(("Status", entry.value))
                if value == nil { value = entry.value }
            case "to":
                headers.append(("To", entry.value))
                if parsed.headerValue("Reference0") == nil {
                    headers.append(("Reference0", entry.value))
                }
            default:
                headers.append((entry.key, entry.value))
            }
        }

        if let value {
            headers.append(("Value", value))
        }

        let wire = buildWire(
            firstLine: "SHIORI/3.0 \(parsed.status.code) \(statusPhrase(for: parsed.status.code, fallback: parsed.status.phrase))",
            headers: headers
        )
        return Shiori2NormalizedResponse(status: parsed.status.code, wire: wire)
    }

    static func noContentResponse() -> String {
        buildWire(firstLine: "SHIORI/3.0 204 No Content", headers: [("Charset", "UTF-8")])
    }

    fileprivate static func statusPhrase(for code: Int, fallback: String? = nil) -> String {
        if let fallback, !fallback.trimmingCharacters(in: .whitespaces).isEmpty {
            return fallback
        }
        switch code {
        case 200: return "OK"
        case 204: return "No Content"
        case 310: return "Communicate"
        case 311: return "Not Enough"
        case 312: return "Advice"
        case 400: return "Bad Request"
        case 500: return "Internal Server Error"
        default: return code < 300 ? "OK" : "Error"
        }
    }

    private static func buildEventRequest(from request: Shiori2Request, eventID: String) -> Shiori2WireRequest {
        var headers: [(String, String)] = [
            ("Sender", request.sender),
            ("Event", eventID)
        ]
        for (index, value) in request.references(limit: 8).enumerated() {
            headers.append(("Reference\(index)", value))
        }
        appendSecurityAndCharset(from: request, to: &headers)
        return Shiori2WireRequest(wire: buildWire(firstLine: "GET Sentence SHIORI/2.2", headers: headers))
    }

    private static func buildUserSentenceRequest(from request: Shiori2Request) -> Shiori2WireRequest? {
        let sentence = request.headerValue("Sentence") ?? request.references(limit: 1).first
        guard let sentence else { return nil }
        var headers: [(String, String)] = [
            ("Sender", "User"),
            ("Sentence", sentence)
        ]
        appendSecurityAndCharset(from: request, to: &headers)
        return Shiori2WireRequest(wire: buildWire(firstLine: "GET Sentence SHIORI/2.0", headers: headers))
    }

    private static func buildOwnerGhostNameRequest(from request: Shiori2Request) -> Shiori2WireRequest? {
        let ghost = request.headerValue("Ghost") ?? request.references(limit: 1).first
        guard let ghost else { return nil }
        var headers: [(String, String)] = [
            ("Sender", request.sender),
            ("Ghost", ghost)
        ]
        appendSecurityAndCharset(from: request, to: &headers)
        return Shiori2WireRequest(wire: buildWire(firstLine: "NOTIFY OwnerGhostName SHIORI/2.3", headers: headers))
    }

    private static func buildOtherGhostNameRequest(from request: Shiori2Request) -> Shiori2WireRequest {
        var headers: [(String, String)] = [("Sender", request.sender)]
        let ghostExValues = request.headers(named: "GhostEx")
        if ghostExValues.isEmpty {
            for value in request.references(limit: 8) {
                headers.append(("GhostEx", value))
            }
        } else {
            for value in ghostExValues {
                headers.append(("GhostEx", value))
            }
        }
        appendSecurityAndCharset(from: request, to: &headers)
        return Shiori2WireRequest(wire: buildWire(firstLine: "NOTIFY OtherGhostName SHIORI/2.3", headers: headers))
    }

    private static func buildCommunicateRequest(from request: Shiori2Request) -> Shiori2WireRequest? {
        let refs = request.references(limit: 8)
        let sender = refs.first ?? request.headerValue("Sender")
        let sentence = refs.dropFirst().first ?? request.headerValue("Sentence")
        guard let sender, let sentence else { return nil }
        var headers: [(String, String)] = [
            ("Sender", sender),
            ("Sentence", sentence)
        ]
        if let age = request.headerValue("Age") {
            headers.append(("Age", age))
        }
        if let surface = request.headerValue("Surface") {
            headers.append(("Surface", surface))
        }
        for (index, value) in refs.dropFirst(2).prefix(8).enumerated() {
            headers.append(("Reference\(index)", value))
        }
        appendSecurityAndCharset(from: request, to: &headers)
        return Shiori2WireRequest(wire: buildWire(firstLine: "GET Sentence SHIORI/2.3", headers: headers))
    }

    private static func buildWordRequest(from request: Shiori2Request) -> Shiori2WireRequest? {
        let type = request.headerValue("Type") ?? request.references(limit: 1).first
        guard let type else { return nil }
        var headers: [(String, String)] = [
            ("Sender", request.sender),
            ("Type", type)
        ]
        appendSecurityAndCharset(from: request, to: &headers)
        return Shiori2WireRequest(wire: buildWire(firstLine: "GET Word SHIORI/2.0", headers: headers))
    }

    private static func buildStatusRequest(from request: Shiori2Request) -> Shiori2WireRequest {
        var headers: [(String, String)] = [("Sender", request.sender)]
        appendSecurityAndCharset(from: request, to: &headers)
        return Shiori2WireRequest(wire: buildWire(firstLine: "GET Status SHIORI/2.0", headers: headers))
    }

    private static func buildStringRequest(from request: Shiori2Request) -> Shiori2WireRequest? {
        let id = request.references(limit: 1).first ?? request.headerValue("Resource") ?? request.headerValue("StringID")
        guard let id else { return nil }
        var headers: [(String, String)] = [("ID", id)]
        appendSecurityAndCharset(from: request, to: &headers)
        return Shiori2WireRequest(wire: buildWire(firstLine: "GET String SHIORI/2.5", headers: headers))
    }

    private static func buildTeachRequest(from request: Shiori2Request) -> Shiori2WireRequest? {
        let refs = request.references()
        let word = request.headerValue("Word") ?? refs.first ?? request.headerValue("Sentence")
        guard let word else { return nil }
        var headers: [(String, String)] = [("Word", word)]
        let referenceStart = request.headerValue("Word") == nil ? 1 : 0
        for (index, value) in refs.dropFirst(referenceStart).enumerated() {
            headers.append(("Reference\(index)", value))
        }
        appendSecurityAndCharset(from: request, to: &headers)
        return Shiori2WireRequest(wire: buildWire(firstLine: "TEACH SHIORI/2.4", headers: headers))
    }

    private static func appendSecurityAndCharset(from request: Shiori2Request, to headers: inout [(String, String)]) {
        headers.append(("SecurityLevel", request.securityLevel))
        headers.append(("Charset", "Shift_JIS"))
    }

    private static func buildWire(firstLine: String, headers: [(String, String)]) -> String {
        var lines = [firstLine]
        for (key, value) in headers {
            lines.append("\(sanitizeHeader(key)): \(sanitizeHeader(value))")
        }
        return lines.joined(separator: "\r\n") + "\r\n\r\n"
    }

    private static func sanitizeHeader(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }
}
