import AppKit
import Foundation

/// SSTP メソッドを受け取り SHIORI ブリッジへ振り分けるディスパッチャ
public enum SSTPDispatcher {
    private static let passThruPrefix = "x-sstp-passthru-"
    private static let maxPayloadBytes = 1024 * 1024

    public static func dispatch(request: SSTPRequest) -> String {
        let version = request.version.isEmpty ? "SSTP/1.4" : request.version
        let charset = request.headerValue("Charset") ?? "UTF-8"
        guard isSupportedVersion(version) else {
            return buildResponse(
                version: version,
                status: 505,
                charset: charset,
                script: nil,
                data: nil,
                responseHeaders: collectPassThruHeaders(from: request.headers)
            )
        }
        guard requestSize(request) <= maxPayloadBytes else {
            return buildResponse(
                version: version,
                status: 413,
                charset: charset,
                script: nil,
                data: nil,
                responseHeaders: collectPassThruHeaders(from: request.headers)
            )
        }
        SstpSessionStore.shared.mergeEntries(request.entry)
        let effectiveNotify = request.options.contains(.notify) && request.method.uppercased() == "SEND"
        let methodName = effectiveNotify ? "NOTIFY" : request.method.uppercased()
        switch methodName {
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
                status: 501,
                charset: charset,
                script: nil,
                data: nil,
                responseHeaders: collectPassThruHeaders(from: request.headers)
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
        let charset = request.headerValue("Charset") ?? "UTF-8"
        let options = request.options
        let securityLevel = (request.headerValue("SecurityLevel") ?? "local").lowercased()
        let localOnly = ProcessInfo.processInfo.environment["OURIN_SSTP_LOCAL_ONLY"] == "1"
        if localOnly && securityLevel == "external" {
            EventBridge.shared.notify(.OnSSTPBlacklisting, params: [
                "Reference0": request.headerValue("Sender") ?? "ExternalSSTP",
                "Reference1": "security_local_only"
            ])
            return buildResponse(
                version: version,
                status: 420,
                charset: charset,
                script: nil,
                data: nil,
                responseHeaders: collectPassThruHeaders(from: request.headers)
            )
        }
        if request.receiverGhostName != nil,
           !GhostRegistry.shared.hasEntries() {
            return buildResponse(
                version: version,
                status: 512,
                charset: charset,
                script: nil,
                data: nil,
                responseHeaders: collectPassThruHeaders(from: request.headers)
            )
        }
        if let receiver = request.receiverGhostName,
           GhostRegistry.shared.hasEntries(),
           !GhostRegistry.shared.contains(name: normalizeGhostNameForCompatibility(receiver)) {
            return buildResponse(
                version: version,
                status: 404,
                charset: charset,
                script: nil,
                data: nil,
                responseHeaders: collectPassThruHeaders(from: request.headers)
            )
        }
        if options.contains(.nobreak), method == .send || method == .notify {
            let shioriStatus = ShioriStatusStore.shared.currentStatus.lowercased()
            if shioriStatus == "busy" {
                EventBridge.shared.notify(.OnSSTPBreak, params: [
                    "Reference0": request.headerValue("Sender") ?? "ExternalSSTP",
                    "Reference1": "busy"
                ])
                return buildResponse(
                    version: version,
                    status: 409,
                    charset: charset,
                    script: nil,
                    data: nil,
                    responseHeaders: collectPassThruHeaders(from: request.headers)
                )
            }
            EventBridge.shared.notify(.OnSSTPBreak, params: [
                "Reference0": request.headerValue("Sender") ?? "ExternalSSTP",
                "Reference1": "nobreak"
            ])
            return buildResponse(
                version: version,
                status: 210,
                charset: charset,
                script: nil,
                data: nil,
                responseHeaders: collectPassThruHeaders(from: request.headers)
            )
        }
        let refs = extractReferences(from: request)
        let event = resolveEvent(request: request, method: method)
        let shioriHeaders = buildShioriHeaders(from: request, charset: charset, options: options)
        if let status = shioriHeaders["Status"] {
            ShioriStatusStore.shared.update(status: status)
        }

        let raw = BridgeToSHIORI.handle(event: event, references: refs, headers: shioriHeaders)
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, method != .notify {
            return buildResponse(
                version: version,
                status: 503,
                charset: charset,
                script: nil,
                data: nil,
                responseHeaders: collectPassThruHeaders(from: request.headers)
            )
        }
        let mapped = mapShioriResponse(raw)
        if let statusHeader = mapped.statusHeader {
            ShioriStatusStore.shared.update(status: statusHeader)
        }

        let status: Int
        if method == .notify {
            if let mappedStatus = mapped.status {
                status = mappedStatus
            } else if mapped.valueNotify != nil {
                status = 200
            } else {
                status = 204
            }
        } else {
            status = mapped.status ?? 200
        }

        let scriptForSstp: String?
        if method == .notify {
            scriptForSstp = mapped.valueNotify
        } else if let script = mapped.script, !script.isEmpty {
            scriptForSstp = script
        } else if let value = mapped.value, !value.isEmpty {
            scriptForSstp = value
        } else {
            scriptForSstp = nil
        }

        // Respect ScriptOption from SHIORI response (e.g., nodescript)
        let responseScriptOption = mapped.responseHeaders["ScriptOption"]?.lowercased() ?? ""
        let scriptOptionTokens: Set<String> = Set(responseScriptOption
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })

        let finalScript: String?
        if options.contains(.nodescript) || scriptOptionTokens.contains("nodescript") {
            finalScript = nil
        } else {
            finalScript = resolveIfGhostScript(request: request, fallback: scriptForSstp)
        }

        let data = mapped.data
        var responseHeaders = collectPassThruHeaders(from: request.headers)
        responseHeaders.merge(mapped.responseHeaders) { _, rhs in rhs }
        // Optionally advertise ukatec compatibility to callers
        if responseHeaders["X-UKATEC-Spec"] == nil {
            responseHeaders["X-UKATEC-Spec"] = "1"
        }
        // Apply SSP-compatible side effects from SHIORI headers (Surface/Balloon)
        if let surfaceStr = mapped.responseHeaders["Surface"], let surface = Int(surfaceStr) {
            DispatchQueue.main.async {
                let appDelegate = NSApp.delegate as? AppDelegate
                appDelegate?.ghostManager?.updateSurface(id: surface)
            }
        }
        if let balloonName = mapped.responseHeaders["Balloon"], !balloonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DispatchQueue.main.async {
                let appDelegate = NSApp.delegate as? AppDelegate
                if let gm = appDelegate?.ghostManager {
                    _ = gm.switchBalloon(named: balloonName, scope: gm.currentScope, raiseEvent: true)
                }
            }
        }
        // Apply BalloonOffset if present: format "x,y"
        if let offsetStr = mapped.responseHeaders["BalloonOffset"], !offsetStr.isEmpty {
            let comps = offsetStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if comps.count >= 2 {
                let x = String(comps[0])
                let y = String(comps[1])
                DispatchQueue.main.async {
                    let appDelegate = NSApp.delegate as? AppDelegate
                    appDelegate?.ghostManager?.handleBalloonOffset(x: x, y: y, isRelative: false)
                }
            }
        }

        // Apply Icon header: set dock/tray icon to specified file under ghost root
        if let iconSpec = mapped.responseHeaders["Icon"], !iconSpec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parts = iconSpec.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            let filename = parts.first.map(String.init) ?? iconSpec
            let text = parts.count > 1 ? String(parts[1]) : ""
            DispatchQueue.main.async {
                let appDelegate = NSApp.delegate as? AppDelegate
                appDelegate?.ghostManager?.setTaskTrayIcon(filename: filename, text: text)
            }
        }

        if let entryHeader = SstpSessionStore.shared.allEntriesHeaderValue() {
            responseHeaders["Entry"] = entryHeader
        }
        return buildResponse(
            version: version,
            status: status,
            charset: charset,
            script: finalScript,
            data: data,
            responseHeaders: responseHeaders
        )
    }

    private static func handleNotify(_ request: SSTPRequest) -> String {
        routeToShiori(request: request, method: .notify)
    }

    private static func handleCommunicate(_ request: SSTPRequest) -> String {
        routeToShiori(request: request, method: .communicate)
    }

    private static func handleExecute(_ request: SSTPRequest) -> String {
        let charset = request.headerValue("Charset") ?? "UTF-8"
        let version = request.version.isEmpty ? "SSTP/1.4" : request.version
        guard let command = request.headerValue("Command"), !command.isEmpty else {
            return buildResponse(
                version: version,
                status: 400,
                charset: charset,
                script: nil,
                data: nil,
                responseHeaders: collectPassThruHeaders(from: request.headers)
            )
        }
        let sender = request.headerValue("Sender") ?? "Ourin"
        let refs = extractReferences(from: request)
        let commandKey = command.lowercased()
        let commandArgs = Array(refs.dropFirst())

        if let commandResponse = handleExtendedExecuteCommand(
            commandKey: commandKey,
            commandArgs: commandArgs,
            sender: sender,
            version: version,
            charset: charset,
            requestHeaders: request.headers
        ) {
            return commandResponse
        }

        if commandKey == "setcookie" {
            let name = refs.count > 1 ? refs[1] : request.headerValue("Reference0")
            let value = refs.count > 2 ? refs[2] : request.headerValue("Reference1")
            if let name, let value, !name.isEmpty {
                SstpSessionStore.shared.setCookie(sender: sender, name: name, value: value)
                return buildResponse(
                    version: version,
                    status: 200,
                    charset: charset,
                    script: nil,
                    data: nil,
                    responseHeaders: collectPassThruHeaders(from: request.headers)
                )
            }
            return buildResponse(
                version: version,
                status: 400,
                charset: charset,
                script: nil,
                data: nil,
                responseHeaders: collectPassThruHeaders(from: request.headers)
            )
        }
        if commandKey == "getcookie" {
            let name = refs.count > 1 ? refs[1] : request.headerValue("Reference0")
            guard let name, !name.isEmpty else {
                return buildResponse(
                    version: version,
                    status: 400,
                    charset: charset,
                    script: nil,
                    data: nil,
                    responseHeaders: collectPassThruHeaders(from: request.headers)
                )
            }
            let value = SstpSessionStore.shared.getCookie(sender: sender, name: name) ?? ""
            var responseHeaders = collectPassThruHeaders(from: request.headers)
            responseHeaders["Reference0"] = value
            return buildResponse(
                version: version,
                status: 200,
                charset: charset,
                script: nil,
                data: value,
                responseHeaders: responseHeaders
            )
        }
        return routeToShiori(request: request, method: .execute)
    }

    private static func handleExtendedExecuteCommand(
        commandKey: String,
        commandArgs: [String],
        sender: String,
        version: String,
        charset: String,
        requestHeaders: [String: String]
    ) -> String? {
        let property = PropertyManager.shared
        let appDelegate = NSApp.delegate as? AppDelegate
        var responseHeaders = collectPassThruHeaders(from: requestHeaders)
        let success: (String?) -> String = { data in
            if let data {
                responseHeaders["Reference0"] = data
            }
            return buildResponse(
                version: version,
                status: 200,
                charset: charset,
                script: nil,
                data: data,
                responseHeaders: responseHeaders
            )
        }
        let badRequest: () -> String = {
            buildResponse(
                version: version,
                status: 400,
                charset: charset,
                script: nil,
                data: nil,
                responseHeaders: responseHeaders
            )
        }

        switch commandKey {
        case "getname", "getghostname":
            let value = property.get("currentghost.name")
                ?? GhostRegistry.shared.allNames().first
                ?? "Ourin"
            return success(value)
        case "getnames", "getnamelist":
            return success(GhostRegistry.shared.allNames().joined(separator: ","))
        case "getfmo":
            let securityLevel = resolveSecurityLevel(from: requestHeaders)
            guard securityLevel == "local" else {
                return buildResponse(
                    version: version,
                    status: 420,
                    charset: charset,
                    script: nil,
                    data: nil,
                    responseHeaders: responseHeaders
                )
            }
            let payload = buildGetFmoPayload(appDelegate: appDelegate)
            return success(payload)
        case "getshellname":
            return success(
                property.get("currentghost.shelllist.current.name")
                ?? property.get("currentghost.shell.name")
                ?? ""
            )
        case "getballoonname":
            return success(property.get("balloonlist.index(0).name") ?? "")
        case "getghostnamelist":
            return success(GhostRegistry.shared.allNames().joined(separator: ","))
        case "getshellnamelist":
            return success(listPropertyValues(prefix: "currentghost.shelllist.index", key: "name", countKey: "currentghost.shelllist.count"))
        case "getballoonnamelist":
            return success(listPropertyValues(prefix: "balloonlist.index", key: "name", countKey: "balloonlist.count"))
        case "getheadlinenamelist":
            return success(listPropertyValues(prefix: "headlinelist.index", key: "name", countKey: "headlinelist.count"))
        case "getpluginnamelist":
            return success(listPropertyValues(prefix: "pluginlist.index", key: "name", countKey: "pluginlist.count"))
        case "getversion":
            let versionString = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
                ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                ?? "unknown"
            return success(versionString)
        case "getshortversion":
            let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            return success(shortVersion)
        case "quiet":
            SstpSessionStore.shared.setQuietMode(true)
            ShioriStatusStore.shared.update(status: "quiet")
            return success("1")
        case "restore":
            SstpSessionStore.shared.setQuietMode(false)
            ShioriStatusStore.shared.update(status: "talking")
            return success("0")
        case "setproperty":
            guard commandArgs.count >= 2 else { return badRequest() }
            let key = commandArgs[0]
            let value = commandArgs[1]
            return property.set(key, value: value) ? success(value) : badRequest()
        case "getproperty":
            guard let key = commandArgs.first else { return badRequest() }
            return success(property.get(key) ?? "")
        case "setcookie":
            guard commandArgs.count >= 2 else { return badRequest() }
            SstpSessionStore.shared.setCookie(sender: sender, name: commandArgs[0], value: commandArgs[1])
            return success(nil)
        case "getcookie":
            guard let name = commandArgs.first, !name.isEmpty else { return badRequest() }
            let value = SstpSessionStore.shared.getCookie(sender: sender, name: name) ?? ""
            return success(value)
        case "dumpsurface":
            let params = commandArgs
            DispatchQueue.main.async {
                appDelegate?.ghostManager?.executeDumpSurface(params: params)
            }
            return success(nil)
        case "moveasync":
            guard commandArgs.count >= 5,
                  let scope = Int(commandArgs[0]),
                  let x = Int(commandArgs[1]),
                  let y = Int(commandArgs[2]),
                  let time = Int(commandArgs[3]) else {
                return badRequest()
            }
            let method = commandArgs[4]
            let ignoreSticky = commandArgs.count > 5 ? commandArgs[5].lowercased() == "true" || commandArgs[5] == "1" : false
            DispatchQueue.main.async {
                appDelegate?.ghostManager?.moveWindowAsync(scope: scope, x: x, y: y, time: time, method: method, ignoreStickyWindow: ignoreSticky)
            }
            return success(nil)
        case "settrayicon", "settasktrayicon":
            guard let filename = commandArgs.first, !filename.isEmpty else { return badRequest() }
            let text = commandArgs.count > 1 ? commandArgs[1] : ""
            DispatchQueue.main.async {
                appDelegate?.ghostManager?.setTaskTrayIcon(filename: filename, text: text)
            }
            return success(nil)
        case "settrayballoon":
            DispatchQueue.main.async {
                appDelegate?.ghostManager?.setTrayBalloon(options: commandArgs)
            }
            return success(nil)
        default:
            return nil
        }
    }

    private static func buildGetFmoPayload(appDelegate: AppDelegate?) -> String {
        var pairs: [String] = []
        let processInfo = ProcessInfo.processInfo
        let bundle = Bundle.main
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Ourin"
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let appPath = bundle.bundleURL.path

        pairs.append("baseware.name=\(appName)")
        pairs.append("baseware.version=\(appVersion)")
        pairs.append("baseware.pid=\(processInfo.processIdentifier)")
        pairs.append("baseware.path=\(appPath)")

        let ghosts = GhostRegistry.shared.allEntries().sorted(by: { $0.key < $1.key })
        for (name, path) in ghosts {
            pairs.append("ghost.\(name)=\(path)")
        }

        if let fmo = appDelegate?.fmo {
            if let sharedData = try? fmo.memory.read(mutex: fmo.mutex), !sharedData.isEmpty {
                if let utf8 = String(data: sharedData, encoding: .utf8), !utf8.isEmpty {
                    pairs.append("fmo.shared.utf8=\(utf8)")
                }
                pairs.append("fmo.shared.base64=\(sharedData.base64EncodedString())")
            }
        }

        return pairs.joined(separator: ";")
    }

    private static func resolveSecurityLevel(from headers: [String: String]) -> String {
        if let origin = headerValue("SecurityOrigin", in: headers),
           !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return isLocalOrigin(origin) ? "local" : "external"
        }
        let raw = headerValue("SecurityLevel", in: headers)?.lowercased() ?? "local"
        return raw == "external" ? "external" : "local"
    }

    private static func headerValue(_ key: String, in headers: [String: String]) -> String? {
        if let value = headers[key] {
            return value
        }
        return headers.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    private static func listPropertyValues(prefix: String, key: String, countKey: String) -> String {
        guard let countRaw = PropertyManager.shared.get(countKey), let count = Int(countRaw), count > 0 else {
            return ""
        }
        var values: [String] = []
        for index in 0..<count {
            if let value = PropertyManager.shared.get("\(prefix)(\(index)).\(key)"), !value.isEmpty {
                values.append(value)
            }
        }
        return values.joined(separator: ",")
    }

    private static func handleGive(_ request: SSTPRequest) -> String {
        routeToShiori(request: request, method: .give)
    }

    private static func handleInstall(_ request: SSTPRequest) -> String {
        routeToShiori(request: request, method: .install)
    }

    private static func resolveEvent(request: SSTPRequest, method: DispatchMethod) -> String {
        if let event = request.headerValue("Event"), !event.isEmpty {
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
            if let ref = request.headerValue("Reference\(i)") {
                refs.append(ref)
            } else {
                break
            }
        }
        if request.method.uppercased() == "COMMUNICATE",
           let sentence = request.headerValue("Sentence"),
           !sentence.isEmpty {
            refs.insert(sentence, at: 0)
        }
        if request.method.uppercased() == "EXECUTE",
           let command = request.headerValue("Command"),
           !command.isEmpty {
            refs.insert(command, at: 0)
        }
        return refs
    }

    private static func buildShioriHeaders(from request: SSTPRequest, charset: String, options: Set<SSTPRequest.Option>) -> [String: String] {
        let sender = request.headerValue("Sender") ?? "Ourin"
        let securityLevel: String = {
            if let origin = request.headerValue("SecurityOrigin"),
               !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return isLocalOrigin(origin) ? "local" : "external"
            }
            return ((request.headerValue("SecurityLevel") ?? "local").lowercased() == "external") ? "external" : "local"
        }()
        let senderType = request.headerValue("SenderType") ?? "external,sstp"

        var headers: [String: String] = [
            "Charset": charset,
            "Sender": sender,
            "SenderType": senderType,
            "SecurityLevel": securityLevel
        ]
        if let status = request.headerValue("Status"), !status.isEmpty {
            headers["Status"] = status
        } else {
            headers["Status"] = ShioriStatusStore.shared.currentStatus
        }
        if let securityOrigin = request.headerValue("SecurityOrigin"), !securityOrigin.isEmpty {
            headers["SecurityOrigin"] = securityOrigin
        }
        copyIfPresent("BaseID", from: request, to: &headers)
        copyIfPresent("Marker", from: request, to: &headers)
        copyIfPresent("ErrorLevel", from: request, to: &headers)
        copyIfPresent("ErrorDescription", from: request, to: &headers)
        copyIfPresent("BalloonOffset", from: request, to: &headers)
        copyIfPresent("Age", from: request, to: &headers)
        copyIfPresent("MarkerSend", from: request, to: &headers)
        copyIfPresent("ReceiverGhostName", from: request, to: &headers)
        copyIfPresent("ReceiverGhostHWnd", from: request, to: &headers)
        copyIfPresent("X-UKATEC-Spec", from: request, to: &headers)
        if let hWnd = request.headerValue("HWnd"), !hWnd.isEmpty {
            headers["HWnd"] = hWnd
        } else if let hWnd = request.hWnd {
            headers["HWnd"] = String(hWnd)
        }
        if options.contains(.notranslate) {
            headers["NoTranslate"] = "1"
        }
        headers.merge(collectPassThruHeaders(from: request.headers)) { lhs, _ in lhs }
        return headers
    }

    private struct ShioriMappedResponse {
        let status: Int?
        let script: String?
        let value: String?
        let valueNotify: String?
        let data: String?
        let statusHeader: String?
        let responseHeaders: [String: String]
    }

    private static func mapShioriResponse(_ response: String) -> ShioriMappedResponse {
        if !response.uppercased().hasPrefix("SHIORI/") {
            return ShioriMappedResponse(
                status: nil,
                script: response,
                value: nil,
                valueNotify: nil,
                data: nil,
                statusHeader: nil,
                responseHeaders: [:]
            )
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
        var valueNotify: String?
        var data: String?
        var statusHeader: String?
        var responseHeaders: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let idx = line.firstIndex(of: ":") else { continue }
            let originalKey = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
            let key = originalKey.lowercased()
            let val = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "script":
                script = val
            case "value":
                value = val
            case "valuenotify":
                valueNotify = val
            case "data":
                data = val
            case "status":
                statusHeader = val
                responseHeaders["Status"] = val
            case "surface":
                responseHeaders["Surface"] = val
            case "balloon":
                responseHeaders["Balloon"] = val
            case "icon":
                responseHeaders["Icon"] = val
            case "scriptoption":
                responseHeaders["ScriptOption"] = val
            case "baseid":
                responseHeaders["BaseID"] = val
            case "marker":
                responseHeaders["Marker"] = val
            case "errorlevel":
                responseHeaders["ErrorLevel"] = val
            case "errordescription":
                responseHeaders["ErrorDescription"] = val
            case "balloonoffset":
                responseHeaders["BalloonOffset"] = val
            case "reference0":
                responseHeaders["Reference0"] = val
            case "age":
                responseHeaders["Age"] = val
            case "markersend":
                responseHeaders["MarkerSend"] = val
            default:
                if key == "x-sstp-passthru" || key.hasPrefix(passThruPrefix) {
                    responseHeaders[originalKey] = val
                }
                continue
            }
        }
        if let valueNotify, !valueNotify.isEmpty {
            responseHeaders["ValueNotify"] = valueNotify
        }
        return ShioriMappedResponse(
            status: statusCode,
            script: script,
            value: value,
            valueNotify: valueNotify,
            data: data,
            statusHeader: statusHeader,
            responseHeaders: responseHeaders
        )
    }

    private static func buildResponse(
        version: String,
        status: Int,
        charset: String,
        script: String?,
        data: String?,
        responseHeaders: [String: String]
    ) -> String {
        var response = SSTPResponse(
            version: version,
            statusCode: status,
            headers: ["Charset": charset]
        )
        response.setScript(script)
        response.setData(data)
        response.setHeaders(responseHeaders)
        return response.toWireFormat()
    }

    private static func collectPassThruHeaders(from headers: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in headers {
            let lower = key.lowercased()
            if lower == "x-sstp-passthru" || lower.hasPrefix(passThruPrefix) {
                result[key] = value
            }
        }
        return result
    }

    private static func copyIfPresent(_ key: String, from request: SSTPRequest, to target: inout [String: String]) {
        if let value = request.headerValue(key), !value.isEmpty {
            target[key] = value
        }
    }

    private static func resolveIfGhostScript(request: SSTPRequest, fallback: String?) -> String? {
        guard !request.ifGhost.isEmpty else { return fallback }
        let receiver = request.receiverGhostName?.lowercased() ?? "*"
        if let matched = request.ifGhost.first(where: { entry in
            let ghost = entry.ghost.lowercased()
            return ghost == "*" || ghost == receiver
        }) {
            let script = matched.sakura.isEmpty ? fallback : matched.sakura
            return script
        }
        return fallback
    }

    private static func isLocalOrigin(_ origin: String) -> Bool {
        guard let url = URL(string: origin), let host = url.host?.lowercased() else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private static func isSupportedVersion(_ version: String) -> Bool {
        let normalized = version.uppercased()
        guard normalized.hasPrefix("SSTP/") else { return false }
        return normalized.hasPrefix("SSTP/1.")
    }

    private static func normalizeGhostNameForCompatibility(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.removingPercentEncoding ?? trimmed
    }

    private static func requestSize(_ request: SSTPRequest) -> Int {
        var total = request.method.utf8.count + request.version.utf8.count + request.body.count
        for (key, value) in request.headers {
            total += key.utf8.count + value.utf8.count + 4
        }
        return total
    }
}
