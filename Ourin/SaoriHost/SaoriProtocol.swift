import Foundation

public struct SaoriRequest: Equatable {
    public let method: String
    public let target: String?
    public let version: String
    public let headers: [String: String]
    public let body: String?

    public func headerValue(_ name: String) -> String? {
        if let direct = headers[name] { return direct }
        let lowered = name.lowercased()
        return headers.first(where: { $0.key.lowercased() == lowered })?.value
    }
}

public struct SaoriResponse: Equatable {
    public let version: String
    public let statusCode: Int
    public let statusMessage: String
    public let headers: [String: String]
    public let body: String?
}

public enum SaoriProtocolError: Error, CustomStringConvertible {
    case malformedStartLine
    case missingSeparator
    case invalidStatusLine
    case unsupportedEncoding(String)
    case decodeFailed(String)
    case encodeFailed(String)

    public var description: String {
        switch self {
        case .malformedStartLine:
            return "Malformed SAORI start line."
        case .missingSeparator:
            return "Missing SAORI header/body separator."
        case .invalidStatusLine:
            return "Malformed SAORI response status line."
        case .unsupportedEncoding(let value):
            return "Unsupported charset: \(value)"
        case .decodeFailed(let value):
            return "Failed to decode bytes using charset: \(value)"
        case .encodeFailed(let value):
            return "Failed to encode text using charset: \(value)"
        }
    }
}

public enum SaoriProtocol {
    public static func parseRequest(_ text: String) throws -> SaoriRequest {
        let normalized = normalizeLineEndings(text)
        guard let splitRange = normalized.range(of: "\r\n\r\n") else {
            throw SaoriProtocolError.missingSeparator
        }

        let head = String(normalized[..<splitRange.lowerBound])
        let bodyStart = splitRange.upperBound
        let bodyRaw = String(normalized[bodyStart...])
        let body = bodyRaw.isEmpty ? nil : bodyRaw

        let lines = head.components(separatedBy: "\r\n")
        guard let first = lines.first else {
            throw SaoriProtocolError.malformedStartLine
        }

        let parts = first.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2 || parts.count == 3 else {
            throw SaoriProtocolError.malformedStartLine
        }

        let method = String(parts[0])
        let target: String?
        let version: String
        if parts.count == 3 {
            target = String(parts[1])
            version = String(parts[2])
        } else {
            target = nil
            version = String(parts[1])
        }
        let headers = parseHeaders(lines.dropFirst())
        return SaoriRequest(method: method, target: target, version: version, headers: headers, body: body)
    }

    public static func parseResponse(_ text: String) throws -> SaoriResponse {
        let normalized = normalizeLineEndings(text)
        guard let splitRange = normalized.range(of: "\r\n\r\n") else {
            throw SaoriProtocolError.missingSeparator
        }

        let head = String(normalized[..<splitRange.lowerBound])
        let bodyStart = splitRange.upperBound
        let bodyRaw = String(normalized[bodyStart...])
        let body = bodyRaw.isEmpty ? nil : bodyRaw

        let lines = head.components(separatedBy: "\r\n")
        guard let first = lines.first else {
            throw SaoriProtocolError.invalidStatusLine
        }
        let firstParts = first.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard firstParts.count >= 2 else {
            throw SaoriProtocolError.invalidStatusLine
        }

        let version = String(firstParts[0])
        guard let statusCode = Int(firstParts[1]) else {
            throw SaoriProtocolError.invalidStatusLine
        }
        let statusMessage = firstParts.count == 3 ? String(firstParts[2]) : statusMessage(for: statusCode)
        let headers = parseHeaders(lines.dropFirst())
        return SaoriResponse(
            version: version,
            statusCode: statusCode,
            statusMessage: statusMessage,
            headers: headers,
            body: body
        )
    }

    public static func buildResponse(_ response: SaoriResponse) -> String {
        var lines: [String] = []
        lines.append("\(response.version) \(response.statusCode) \(response.statusMessage)")
        for key in response.headers.keys.sorted() {
            if let value = response.headers[key] {
                lines.append("\(key): \(value)")
            }
        }
        lines.append("")
        let head = lines.joined(separator: "\r\n")
        if let body = response.body, !body.isEmpty {
            return head + "\r\n" + body
        }
        return head + "\r\n"
    }

    public static func buildRequest(_ request: SaoriRequest) -> String {
        var lines: [String] = []
        if let target = request.target, !target.isEmpty {
            lines.append("\(request.method) \(target) \(request.version)")
        } else {
            lines.append("\(request.method) \(request.version)")
        }
        for key in request.headers.keys.sorted() {
            if let value = request.headers[key] {
                lines.append("\(key): \(value)")
            }
        }
        lines.append("")
        let head = lines.joined(separator: "\r\n")
        if let body = request.body, !body.isEmpty {
            return head + "\r\n" + body
        }
        return head + "\r\n"
    }

    public static func encode(_ text: String, charset: String) throws -> Data {
        guard let encoding = stringEncoding(for: charset) else {
            throw SaoriProtocolError.unsupportedEncoding(charset)
        }
        guard let data = text.data(using: encoding) else {
            throw SaoriProtocolError.encodeFailed(charset)
        }
        return data
    }

    public static func decode(_ data: Data, charset: String) throws -> String {
        guard let encoding = stringEncoding(for: charset) else {
            throw SaoriProtocolError.unsupportedEncoding(charset)
        }
        guard let decoded = String(data: data, encoding: encoding) else {
            throw SaoriProtocolError.decodeFailed(charset)
        }
        return decoded
    }

    public static func stringEncoding(for charset: String) -> String.Encoding? {
        switch charset.lowercased().replacingOccurrences(of: "_", with: "-") {
        case "utf-8", "utf8":
            return .utf8
        case "shift-jis", "shift_jis", "sjis", "cp932", "ms932", "windows-31j":
            return .shiftJIS
        case "euc-jp", "eucjp":
            return .japaneseEUC
        case "iso-2022-jp", "jis":
            return .iso2022JP
        default:
            return nil
        }
    }

    public static func statusMessage(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 311: return "Insecure"
        case 312: return "No Content (Not Trusted)"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "Status"
        }
    }

    private static func parseHeaders<S: Sequence>(_ lines: S) -> [String: String] where S.Element == String {
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let idx = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        return headers
    }

    private static func normalizeLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
    }
}
