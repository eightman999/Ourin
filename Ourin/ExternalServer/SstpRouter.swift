import Foundation
import OSLog

/// Network routing helper with logger compatible to 10.15

/// 解析済みの SSTP メッセージを SHIORI ブリッジへルーティングする。
public final class SstpRouter {
    private let logger = CompatLogger(subsystem: "Ourin", category: "ExternalSSTP")

    public struct Config {
        var securityLocalOnly: Bool = true
        var maxPayloadSize: Int = 1024 * 1024
        var timeout: TimeInterval = 30
    }

    private var config = Config()

    public init() {}

    public func updateConfig(_ config: Config) {
        self.config = config
    }

    public func handle(raw: String) -> String {
        let start = Date()
        guard let msg = SstpParser.parse(raw) else {
            logger.fault("parse failure")
            ServerMetrics.shared.record(duration: 0, error: true)
            return buildErrorResponse(status: 400, version: "1.1")
        }

        let method = msg.method.uppercased()
        let version = msg.version
        let charset = msg.headers["Charset"] ?? "UTF-8"
        let supportedMethods: Set<String> = ["SEND", "NOTIFY", "COMMUNICATE", "EXECUTE", "GIVE", "INSTALL"]
        if !supportedMethods.contains(method) {
            return buildErrorResponse(status: 501, version: version)
        }
        let securityLevel = effectiveSecurityLevel(
            securityLevelHeader: msg.headers["SecurityLevel"],
            securityOrigin: msg.headers["SecurityOrigin"]
        )
        let securityOrigin = msg.headers["SecurityOrigin"] ?? "null"
        let receiverGhost = msg.headers["ReceiverGhostName"] ?? msg.headers["ReceiverGhostHWnd"]
        let options = parseOptions(msg.headers["Option"] ?? "")
        let sender = msg.headers["Sender"] ?? "ExternalSSTP"

        if securityLevel != "local" && config.securityLocalOnly {
            EventBridge.shared.notify(.OnSSTPBlacklisting, params: [
                "Reference0": sender,
                "Reference1": securityOrigin
            ])
            logger.warning("rejected external request")
            ServerMetrics.shared.record(duration: Date().timeIntervalSince(start), error: true)
            return buildErrorResponse(status: 420, version: version)
        }

        if NarRegistry.shared.installedGhosts().isEmpty {
            logger.warning("no visible/installed ghosts")
            ServerMetrics.shared.record(duration: Date().timeIntervalSince(start), error: true)
            return buildErrorResponse(status: 512, version: version)
        }

        if receiverGhost != nil && !isGhostAvailable(receiverGhost!) {
            logger.warning("ghost not found: \(receiverGhost!)")
            ServerMetrics.shared.record(duration: Date().timeIntervalSince(start), error: true)
            return buildErrorResponse(status: 404, version: version)
        }

        let event = resolveEvent(method: method, eventHeader: msg.headers["Event"], commandHeader: msg.headers["Command"])
        var refs: [String] = []
        for i in 0..<16 {
            if let v = msg.headers["Reference\(i)"] { refs.append(v) } else { break }
        }
        if method == "COMMUNICATE", let sentence = msg.headers["Sentence"], !sentence.isEmpty {
            refs.insert(sentence, at: 0)
        }

        let shioriHeaders: [String: String] = [
            "Charset": charset,
            "Sender": sender,
            "SenderType": securityLevel == "local" ? "external,sstp" : "external,sstp,external",
            "SecurityLevel": securityLevel,
            "SecurityOrigin": securityOrigin
        ]

        if options.contains("nodescript") {
            let duration = Date().timeIntervalSince(start)
            let isNotify = method == "NOTIFY"
            let resp: String
            if isNotify {
                resp = buildSuccessResponse(status: 204, version: version, charset: charset, script: "")
            } else {
                resp = buildSuccessResponse(status: 200, version: version, charset: charset, script: "")
            }
            logger.info("event=\(event) duration=\(duration) nodescript=true")
            ServerMetrics.shared.record(duration: duration, error: false)
            return resp
        }

        if options.contains("nobreak"), method == "SEND" || method == "NOTIFY" {
            EventBridge.shared.notify(.OnSSTPBreak, params: [
                "Reference0": sender,
                "Reference1": "nobreak"
            ])
            logger.info("queued by nobreak option")
            ServerMetrics.shared.record(duration: Date().timeIntervalSince(start), error: false)
            return "SSTP/\(version) 210 Break\r\n\r\n"
        }

        if method == "EXECUTE", msg.headers["Command"] == nil {
            return buildErrorResponse(status: 400, version: version)
        }

        if method == "GIVE" {
            return buildSuccessResponse(status: 204, version: version, charset: charset, script: "")
        }

        let scriptFallback = msg.headers["Script"] ?? ""
        let scriptFromShiori = BridgeToSHIORI.handle(event: event, references: refs, headers: shioriHeaders)
        let script = scriptFromShiori.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? scriptFallback : scriptFromShiori
        let isNotify = method == "NOTIFY"
        let duration = Date().timeIntervalSince(start)

        let resp: String
        if isNotify {
            resp = buildSuccessResponse(status: 204, version: version, charset: charset, script: "")
        } else {
            resp = buildSuccessResponse(status: 200, version: version, charset: charset, script: script)
        }

        logger.info("event=\(event) duration=\(duration)")
        ServerMetrics.shared.record(duration: duration, error: false)
        return resp
    }

    private func buildErrorResponse(status: Int, version: String) -> String {
        let statusText: String
        switch status {
        case 400: statusText = "Bad Request"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 420: statusText = "Refuse"
        case 512: statusText = "Invisible"
        case 413: statusText = "Payload Too Large"
        case 501: statusText = "Not Implemented"
        case 505: statusText = "HTTP Version Not Supported"
        default: statusText = "Internal Server Error"
        }
        return "SSTP/\(version) \(status) \(statusText)\r\n\r\n"
    }

    private func buildSuccessResponse(status: Int, version: String, charset: String, script: String) -> String {
        let statusText = status == 200 ? "OK" : "No Content"
        if status == 204 {
            return "SSTP/\(version) \(status) \(statusText)\r\n\r\n"
        }
        let lines = [
            "SSTP/\(version) \(status) \(statusText)",
            "Charset: \(charset)",
            "Sender: Ourin",
            "Script: \(script)",
            "",
            ""
        ]
        return lines.joined(separator: "\r\n")
    }

    private func parseOptions(_ optionStr: String) -> Set<String> {
        return Set(optionStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
    }

    private func effectiveSecurityLevel(securityLevelHeader: String?, securityOrigin: String?) -> String {
        if let origin = securityOrigin?.trimmingCharacters(in: .whitespacesAndNewlines), !origin.isEmpty, origin.lowercased() != "null" {
            return isLocalOrigin(origin) ? "local" : "external"
        }
        return (securityLevelHeader ?? "local").lowercased() == "external" ? "external" : "local"
    }

    private func isLocalOrigin(_ origin: String) -> Bool {
        guard let url = URL(string: origin), let host = url.host?.lowercased() else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private func resolveEvent(method: String, eventHeader: String?, commandHeader: String?) -> String {
        if let eventHeader, !eventHeader.isEmpty {
            return eventHeader
        }
        switch method {
        case "COMMUNICATE":
            return "OnCommunicate"
        case "EXECUTE":
            if let commandHeader, !commandHeader.isEmpty {
                return "OnExecute:\(commandHeader)"
            }
            return "OnExecute"
        case "INSTALL":
            return "OnInstall"
        default:
            return ""
        }
    }

    private func isGhostAvailable(_ name: String) -> Bool {
        let installedGhosts = NarRegistry.shared.installedGhosts()
        return installedGhosts.contains { ghostName in
            ghostName.lowercased() == name.lowercased()
        }
    }
}
