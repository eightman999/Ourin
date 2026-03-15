import Foundation

/// SSTP メソッドを受け取り SHIORI ブリッジへ振り分けるディスパッチャ
public enum SSTPDispatcher {
    public static func dispatch(request: SSTPRequest) -> String {
        let version = request.version.isEmpty ? "SSTP/1.4" : request.version
        switch request.method.uppercased() {
        case "SEND":
            return routeToShiori(request: request, method: .send)
        case "NOTIFY":
            return handleNotify(request)
        case "COMMUNICATE":
            return handleCommunicate(request)
        case "EXECUTE":
            return handleExecute(request)
        case "GIVE":
            return handleGive(request)
        case "INSTALL":
            return handleInstall(request)
        default:
            return buildResponse(
                version: version,
                status: 400,
                charset: request.headers["Charset"] ?? "UTF-8",
                script: nil,
                data: nil,
                passThru: request.headers["X-SSTP-PassThru"]
            )
        }
    }

    private enum DispatchMethod {
        case send
        case notify
        case communicate
        case execute
        case give
        case install
    }

    private static func routeToShiori(request: SSTPRequest, method: DispatchMethod) -> String {
        let version = request.version.isEmpty ? "SSTP/1.4" : request.version
        let charset = request.headers["Charset"] ?? "UTF-8"
        let refs = extractReferences(from: request)
        let event = resolveEvent(request: request, method: method)
        let shioriHeaders = buildShioriHeaders(from: request, charset: charset)

        let raw = BridgeToSHIORI.handle(event: event, references: refs, headers: shioriHeaders)
        let mapped = mapShioriResponse(raw)

        let status: Int
        if method == .notify {
            status = 204
        } else {
            status = mapped.status ?? 200
        }

        let scriptForSstp: String?
        if method == .notify {
            scriptForSstp = nil
        } else if let script = mapped.script, !script.isEmpty {
            scriptForSstp = script
        } else if let value = mapped.value, !value.isEmpty {
            scriptForSstp = value
        } else {
            scriptForSstp = nil
        }

        let data = mapped.data
        return buildResponse(
            version: version,
            status: status,
            charset: charset,
            script: scriptForSstp,
            data: data,
            passThru: request.headers["X-SSTP-PassThru"]
        )
    }

    private static func handleNotify(_ request: SSTPRequest) -> String {
        routeToShiori(request: request, method: .notify)
    }

    private static func handleCommunicate(_ request: SSTPRequest) -> String {
        routeToShiori(request: request, method: .communicate)
    }

    private static func handleExecute(_ request: SSTPRequest) -> String {
        if request.headers["Command"]?.isEmpty ?? true {
            let version = request.version.isEmpty ? "SSTP/1.4" : request.version
            return buildResponse(
                version: version,
                status: 400,
                charset: request.headers["Charset"] ?? "UTF-8",
                script: nil,
                data: nil,
                passThru: request.headers["X-SSTP-PassThru"]
            )
        }
        return routeToShiori(request: request, method: .execute)
    }

    private static func handleGive(_ request: SSTPRequest) -> String {
        routeToShiori(request: request, method: .give)
    }

    private static func handleInstall(_ request: SSTPRequest) -> String {
        routeToShiori(request: request, method: .install)
    }

    private static func resolveEvent(request: SSTPRequest, method: DispatchMethod) -> String {
        if let event = request.headers["Event"], !event.isEmpty {
            return event
        }
        switch method {
        case .send:
            return "OnSend"
        case .notify:
            return "OnNotify"
        case .communicate:
            return "OnCommunicate"
        case .execute:
            return "OnExecute"
        case .give:
            return "OnChoiceSelect"
        case .install:
            return "OnInstall"
        }
    }

    private static func extractReferences(from request: SSTPRequest) -> [String] {
        var refs: [String] = []
        for i in 0..<32 {
            if let ref = request.headers["Reference\(i)"] {
                refs.append(ref)
            } else {
                break
            }
        }
        if request.method.uppercased() == "COMMUNICATE",
           let sentence = request.headers["Sentence"],
           !sentence.isEmpty {
            refs.insert(sentence, at: 0)
        }
        if request.method.uppercased() == "EXECUTE",
           let command = request.headers["Command"],
           !command.isEmpty {
            refs.insert(command, at: 0)
        }
        return refs
    }

    private static func buildShioriHeaders(from request: SSTPRequest, charset: String) -> [String: String] {
        let sender = request.headers["Sender"] ?? "Ourin"
        let securityLevel = ((request.headers["SecurityLevel"] ?? "local").lowercased() == "external") ? "external" : "local"
        let senderType = request.headers["SenderType"] ?? (securityLevel == "local" ? "external,sstp" : "external,sstp,external")

        var headers: [String: String] = [
            "Charset": charset,
            "Sender": sender,
            "SenderType": senderType,
            "SecurityLevel": securityLevel
        ]
        if let securityOrigin = request.headers["SecurityOrigin"], !securityOrigin.isEmpty {
            headers["SecurityOrigin"] = securityOrigin
        }
        return headers
    }

    private struct ShioriMappedResponse {
        let status: Int?
        let script: String?
        let value: String?
        let data: String?
    }

    private static func mapShioriResponse(_ response: String) -> ShioriMappedResponse {
        if !response.uppercased().hasPrefix("SHIORI/") {
            return ShioriMappedResponse(status: nil, script: response, value: nil, data: nil)
        }
        let lines = response.components(separatedBy: "\r\n")
        let statusCode: Int? = {
            guard let first = lines.first else { return nil }
            let parts = first.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { return nil }
            return Int(parts[1])
        }()
        var script: String?
        var value: String?
        var data: String?
        for line in lines.dropFirst() where !line.isEmpty {
            guard let idx = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<idx]).trimmingCharacters(in: .whitespaces).lowercased()
            let val = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "script":
                script = val
            case "value":
                value = val
            case "data":
                data = val
            default:
                continue
            }
        }
        return ShioriMappedResponse(status: statusCode, script: script, value: value, data: data)
    }

    private static func buildResponse(
        version: String,
        status: Int,
        charset: String,
        script: String?,
        data: String?,
        passThru: String?
    ) -> String {
        let statusText = statusText(for: status)
        var lines: [String] = [
            "\(version) \(status) \(statusText)",
            "Charset: \(charset)"
        ]
        if let passThru, !passThru.isEmpty {
            lines.append("X-SSTP-PassThru: \(passThru)")
        }
        if let script, !script.isEmpty {
            lines.append("Script: \(script)")
        }
        if let data, !data.isEmpty {
            lines.append("Data: \(data)")
        }
        lines.append("")
        lines.append("")
        return lines.joined(separator: "\r\n")
    }

    private static func statusText(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 420: return "Refuse"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        default: return "Status"
        }
    }
}
