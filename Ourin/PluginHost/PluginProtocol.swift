import Foundation

// MARK: - PLUGIN/2.0M Protocol Types

/// PLUGIN/2.0M request method
public enum PluginMethod: String {
    case get = "GET"
    case notify = "NOTIFY"
}

/// PLUGIN/2.0M request representation
public struct PluginRequest {
    public let method: PluginMethod
    public let version: String  // "PLUGIN/2.0M"
    public let id: String
    public let charset: String
    public let sender: String?
    public let target: String?
    public let references: [String: String]  // Reference0, Reference1, etc.
    public let otherHeaders: [String: String]

    public init(
        method: PluginMethod,
        version: String = "PLUGIN/2.0M",
        id: String,
        charset: String = "UTF-8",
        sender: String? = nil,
        target: String? = nil,
        references: [String: String] = [:],
        otherHeaders: [String: String] = [:]
    ) {
        self.method = method
        self.version = version
        self.id = id
        self.charset = charset
        self.sender = sender
        self.target = target
        self.references = references
        self.otherHeaders = otherHeaders
    }
}

/// PLUGIN/2.0M response representation
public struct PluginResponse {
    public let version: String  // "PLUGIN/2.0M"
    public let statusCode: Int
    public let statusMessage: String
    public let charset: String
    public let value: String?
    public let script: String?
    public let scriptOption: String?
    public let eventOption: String?
    public let target: String?
    public let otherHeaders: [String: String]

    public init(
        version: String = "PLUGIN/2.0M",
        statusCode: Int,
        statusMessage: String,
        charset: String = "UTF-8",
        value: String? = nil,
        script: String? = nil,
        scriptOption: String? = nil,
        eventOption: String? = nil,
        target: String? = nil,
        otherHeaders: [String: String] = [:]
    ) {
        self.version = version
        self.statusCode = statusCode
        self.statusMessage = statusMessage
        self.charset = charset
        self.value = value
        self.script = script
        self.scriptOption = scriptOption
        self.eventOption = eventOption
        self.target = target
        self.otherHeaders = otherHeaders
    }
}

// MARK: - Protocol Parser

public enum PluginProtocolError: Error {
    case invalidFormat
    case missingRequiredHeader(String)
    case unsupportedMethod(String)
}

// MARK: - Wire Codec

enum PluginWireCodec {
    static func encodeRequest(_ text: String, charset: String) -> Data {
        EncodingAdapter.encode(text, charset: charset)
    }

    static func decodeResponse(_ data: Data, requestCharset: String) -> String? {
        let responseCharset = EncodingAdapter.detectCharset(in: data, default: requestCharset)
        return EncodingAdapter.decode(data, charset: responseCharset)
            ?? EncodingAdapter.decode(data, charset: requestCharset)
            ?? String(data: data, encoding: .utf8)
    }

    static func responseCharset(in data: Data, default requestCharset: String) -> String {
        EncodingAdapter.detectCharset(in: data, default: requestCharset)
    }
}

public struct PluginProtocolParser {

    /// Parse PLUGIN/2.0M request from wire text (CRLF-delimited)
    public static func parseRequest(_ text: String) throws -> PluginRequest {
        let lines = text.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw PluginProtocolError.invalidFormat }

        // Parse first line: "GET PLUGIN/2.0M" or "NOTIFY PLUGIN/2.0M"
        let firstLine = lines[0].trimmingCharacters(in: .whitespaces)
        let parts = firstLine.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw PluginProtocolError.invalidFormat }

        guard let method = PluginMethod(rawValue: parts[0]) else {
            throw PluginProtocolError.unsupportedMethod(parts[0])
        }
        let version = parts[1]

        // Parse headers
        var headers: [String: String] = [:]
        var references: [String: String] = [:]

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }  // Empty line = end of headers

            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

            // Check if it's a Reference header
            if key.lowercased().starts(with: "reference") {
                references[key] = value
            } else {
                headers[key] = value
            }
        }

        // Extract required headers
        guard let id = headerValue("ID", in: headers) else {
            throw PluginProtocolError.missingRequiredHeader("ID")
        }

        let charset = headerValue("Charset", in: headers) ?? "UTF-8"
        let sender = headerValue("Sender", in: headers)
        let target = headerValue("Target", in: headers)

        // Collect other headers (excluding known ones)
        let knownKeys = Set(["id", "charset", "sender", "target"])
        let otherHeaders = headers.filter { !knownKeys.contains($0.key.lowercased()) }

        return PluginRequest(
            method: method,
            version: version,
            id: id,
            charset: charset,
            sender: sender,
            target: target,
            references: references,
            otherHeaders: otherHeaders
        )
    }

    /// Parse PLUGIN/2.0M response from wire text (CRLF-delimited)
    public static func parseResponse(_ text: String) throws -> PluginResponse {
        let lines = text.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw PluginProtocolError.invalidFormat }

        // Parse first line: "PLUGIN/2.0M 200 OK"
        let firstLine = lines[0].trimmingCharacters(in: .whitespaces)
        let parts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { throw PluginProtocolError.invalidFormat }

        let version = parts[0]
        guard let statusCode = Int(parts[1]) else {
            throw PluginProtocolError.invalidFormat
        }
        let statusMessage = parts.count > 2 ? parts[2] : ""

        // Parse headers
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }  // Empty line = end of headers

            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let charset = headerValue("Charset", in: headers) ?? "UTF-8"
        let value = headerValue("Value", in: headers)
        let script = headerValue("Script", in: headers)
        let scriptOption = headerValue("ScriptOption", in: headers)
        let eventOption = headerValue("EventOption", in: headers)
        let target = headerValue("Target", in: headers)

        // Collect other headers
        let knownKeys = Set(["charset", "value", "script", "scriptoption", "eventoption", "target"])
        let otherHeaders = headers.filter { !knownKeys.contains($0.key.lowercased()) }

        return PluginResponse(
            version: version,
            statusCode: statusCode,
            statusMessage: statusMessage,
            charset: charset,
            value: value,
            script: script,
            scriptOption: scriptOption,
            eventOption: eventOption,
            target: target,
            otherHeaders: otherHeaders
        )
    }

    private static func headerValue(_ name: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

// MARK: - Protocol Builder

public struct PluginProtocolBuilder {

    /// Build PLUGIN/2.0M request wire text (CRLF-delimited, empty line terminated)
    public static func buildRequest(_ request: PluginRequest) -> String {
        var lines: [String] = []

        // First line: "GET PLUGIN/2.0M" or "NOTIFY PLUGIN/2.0M"
        lines.append("\(request.method.rawValue) \(request.version)")

        // Required headers
        lines.append("ID: \(request.id)")
        lines.append("Charset: \(request.charset)")

        // Optional headers
        if let sender = request.sender {
            lines.append("Sender: \(sender)")
        }
        if let target = request.target {
            lines.append("Target: \(target)")
        }

        // References (numeric order — lexical sort would put Reference10 before Reference2)
        let sortedRefs = request.references.sorted { lhs, rhs in
            let l = Int(lhs.key.dropFirst("Reference".count))
            let r = Int(rhs.key.dropFirst("Reference".count))
            if let l, let r { return l < r }
            return lhs.key < rhs.key
        }
        for (key, value) in sortedRefs {
            lines.append("\(key): \(value)")
        }

        // Other headers (sorted by key for consistency)
        for (key, value) in request.otherHeaders.sorted(by: { $0.key < $1.key }) {
            lines.append("\(key): \(value)")
        }

        // Empty line to terminate headers
        lines.append("")

        return lines.joined(separator: "\r\n")
    }

    /// Build PLUGIN/2.0M response wire text (CRLF-delimited, empty line terminated)
    public static func buildResponse(_ response: PluginResponse) -> String {
        var lines: [String] = []

        // First line: "PLUGIN/2.0M 200 OK"
        lines.append("\(response.version) \(response.statusCode) \(response.statusMessage)")

        // Charset header
        lines.append("Charset: \(response.charset)")

        // Optional headers
        if let value = response.value {
            lines.append("Value: \(value)")
        }
        if let script = response.script {
            lines.append("Script: \(script)")
        }
        if let scriptOption = response.scriptOption {
            lines.append("ScriptOption: \(scriptOption)")
        }
        if let eventOption = response.eventOption {
            lines.append("EventOption: \(eventOption)")
        }
        if let target = response.target {
            lines.append("Target: \(target)")
        }

        // Other headers (sorted by key for consistency)
        for (key, value) in response.otherHeaders.sorted(by: { $0.key < $1.key }) {
            lines.append("\(key): \(value)")
        }

        // Empty line to terminate headers
        lines.append("")

        return lines.joined(separator: "\r\n")
    }
}
