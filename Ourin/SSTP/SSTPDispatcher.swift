import Foundation

/// SSTP メソッドを受け取り SHIORI ブリッジへ振り分けるディスパッチャ
public enum SSTPDispatcher {
    private static let passThruPrefix = "x-sstp-passthru-"
    private static let maxPayloadBytes = 1024 * 1024

    /// SSTP リクエストを処理して応答文字列を返す。
    /// securityLocalOnly: 外部サーバ経路のローカル限定ポリシー。nil の場合は環境変数
    /// OURIN_SSTP_LOCAL_ONLY に従う（既定: 制限なし）。
    public static func dispatch(request: SSTPRequest, securityLocalOnly: Bool? = nil) -> String {
        dispatch(
            request: request,
            securityLocalOnly: securityLocalOnly,
            host: LiveSstpDispatcherHost.live,
            bridge: ShioriBridgeContext.shared
        )
    }

    /// 外部SSTP受信口からのリクエストを処理する。
    /// localhost 由来でも外部アプリ/他ゴースト経由なので、SHIORI へは external として渡す。
    static func dispatchExternal(request: SSTPRequest, securityLocalOnly: Bool? = nil, origin: String? = nil) -> String {
        dispatchExternal(
            request: request,
            securityLocalOnly: securityLocalOnly,
            origin: origin,
            host: LiveSstpDispatcherHost.live,
            bridge: ShioriBridgeContext.shared
        )
    }

    /// テスト用: SHIORI ブリッジを明示的に注入する内部入口。host は実運用(.live)を使う。
    /// 各テストは fresh な ShioriBridgeContext を渡し、global な .shared へ触れない。
    static func dispatch(request: SSTPRequest, securityLocalOnly: Bool? = nil, bridge: ShioriBridge, routingRegistry: SstpRoutingRegistry = LiveSstpRoutingRegistry.live, breakPolicy: SstpBreakPolicy = LiveSstpBreakPolicy.live) -> String {
        dispatch(
            request: request,
            securityLocalOnly: securityLocalOnly,
            host: LiveSstpDispatcherHost.live,
            bridge: bridge,
            routingRegistry: routingRegistry,
            breakPolicy: breakPolicy
        )
    }

    /// テスト用: origin と bridge を明示的に注入する外部受信口エントリ。
    static func dispatchExternal(request: SSTPRequest, securityLocalOnly: Bool? = nil, origin: String? = nil, bridge: ShioriBridge, routingRegistry: SstpRoutingRegistry = LiveSstpRoutingRegistry.live, breakPolicy: SstpBreakPolicy = LiveSstpBreakPolicy.live) -> String {
        dispatchExternal(
            request: request,
            securityLocalOnly: securityLocalOnly,
            origin: origin,
            host: LiveSstpDispatcherHost.live,
            bridge: bridge,
            routingRegistry: routingRegistry,
            breakPolicy: breakPolicy
        )
    }

    /// テスト用: host と bridge を両方明示的に注入する内部入口。
    static func dispatch(request: SSTPRequest, securityLocalOnly: Bool? = nil, host: SstpDispatcherHost, bridge: ShioriBridge, routingRegistry: SstpRoutingRegistry = LiveSstpRoutingRegistry.live, breakPolicy: SstpBreakPolicy = LiveSstpBreakPolicy.live) -> String {
        dispatch(
            request: request,
            securityLocalOnly: securityLocalOnly,
            shioriSecurityContext: nil,
            transportAllowsOwned: true,
            host: host,
            bridge: bridge,
            routingRegistry: routingRegistry,
            breakPolicy: breakPolicy
        )
    }

    static func dispatchExternal(request: SSTPRequest, securityLocalOnly: Bool? = nil, origin: String? = nil, host: SstpDispatcherHost, bridge: ShioriBridge, routingRegistry: SstpRoutingRegistry = LiveSstpRoutingRegistry.live, breakPolicy: SstpBreakPolicy = LiveSstpBreakPolicy.live) -> String {
        // loopback TCP/XPC（Originなし）とlocalhost OriginだけOwnedを許可する。
        // 外部HTTP OriginはIDが一致してもSecurityLevelをlocalへ昇格させない。
        let transportAllowsOwned = origin.map(isLocalOrigin)
            ?? true
        return dispatch(
            request: request,
            securityLocalOnly: securityLocalOnly,
            shioriSecurityContext: ShioriSecurityContext.external(origin: origin),
            transportAllowsOwned: transportAllowsOwned,
            host: host,
            bridge: bridge,
            routingRegistry: routingRegistry,
            breakPolicy: breakPolicy
        )
    }

    private static func dispatch(
        request: SSTPRequest,
        securityLocalOnly: Bool?,
        shioriSecurityContext: ShioriSecurityContext?,
        transportAllowsOwned: Bool,
        host: SstpDispatcherHost,
        bridge: ShioriBridge,
        routingRegistry: SstpRoutingRegistry,
        breakPolicy: SstpBreakPolicy = LiveSstpBreakPolicy.live
    ) -> String {
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
        let isOwned = transportAllowsOwned && routingRegistry.matches(
            id: request.headerValue("ID"),
            receiverGhostName: request.receiverGhostName
        )
        let effectiveSecurityContext: ShioriSecurityContext = isOwned
            ? .local
            : (shioriSecurityContext ?? securityContextFromRequest(request))
        let localOnly = securityLocalOnly
            ?? (ProcessInfo.processInfo.environment["OURIN_SSTP_LOCAL_ONLY"] == "1")
        // local-onlyはクライアントがexternalと申告した要求を拒否するポリシー。
        // 外部受信口がSHIORIへ安全側のexternal文脈を付けること自体は拒否しない。
        // 正当に照合できたOwned要求だけは仕様どおりlocalへ昇格して通す。
        if localOnly, !isOwned, resolveSecurityLevel(from: request.headers) == "external" {
            EventBridge.shared.notify(.OnSSTPBlacklisting, refs: [
                "ipAddress": request.headerValue("Sender") ?? "ExternalSSTP",
                "securityOrigin": request.headerValue("SecurityOrigin") ?? "security_local_only"
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
        SstpSessionStore.shared.mergeEntries(request.entry)
        let effectiveNotify = request.options.contains(.notify) && request.method.uppercased() == "SEND"
        let methodName = effectiveNotify ? "NOTIFY" : request.method.uppercased()
        switch methodName {
        case "SEND":
            return routeToShiori(request: request, method: .send, securityContext: effectiveSecurityContext, isOwned: isOwned, host: host, bridge: bridge, routingRegistry: routingRegistry, breakPolicy: breakPolicy)
        case "NOTIFY":
            return handleNotify(request, securityContext: effectiveSecurityContext, isOwned: isOwned, host: host, bridge: bridge, routingRegistry: routingRegistry, breakPolicy: breakPolicy)
        case "COMMUNICATE":
            return handleCommunicate(request, securityContext: effectiveSecurityContext, isOwned: isOwned, host: host, bridge: bridge, routingRegistry: routingRegistry)
        case "EXECUTE":
            return handleExecute(request, securityContext: effectiveSecurityContext, isOwned: isOwned, host: host, bridge: bridge, routingRegistry: routingRegistry)
        case "GIVE":
            return handleGive(request, securityContext: effectiveSecurityContext, isOwned: isOwned, host: host, bridge: bridge, routingRegistry: routingRegistry)
        case "INSTALL":
            return handleInstall(request, securityContext: effectiveSecurityContext, isOwned: isOwned, host: host, bridge: bridge, routingRegistry: routingRegistry)
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

    private static func routeToShiori(
        request: SSTPRequest,
        method: DispatchMethod,
        securityContext: ShioriSecurityContext,
        isOwned: Bool,
        host: SstpDispatcherHost,
        bridge: ShioriBridge,
        routingRegistry: SstpRoutingRegistry,
        breakPolicy: SstpBreakPolicy = LiveSstpBreakPolicy.live
    ) -> String {
        let version = request.version.isEmpty ? "SSTP/1.4" : request.version
        let charset = request.headerValue("Charset") ?? "UTF-8"
        let options = request.options
        if request.receiverGhostName != nil,
           !routingRegistry.hasGhosts() {
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
           routingRegistry.hasGhosts(),
           !routingRegistry.contains(ghostName: normalizeGhostNameForCompatibility(receiver)) {
            return buildResponse(
                version: version,
                status: 404,
                charset: charset,
                script: nil,
                data: nil,
                responseHeaders: collectPassThruHeaders(from: request.headers)
            )
        }
        if options.contains(.nobreak), method == .send || method == .notify,
           breakPolicy.isBusy() {
            // UKADOC SSTP/1.x: nobreak = 「現在実行中のスクリプトを中断せず、終わるまで待つ」。
            // 実行中スクリプトを打ち切らず、busy が解消するまでこの要求を待機させる。
            EventBridge.shared.notify(.OnSSTPBreak, refs: [
                "script": request.headerValue("Sender") ?? "ExternalSSTP",
                "scope": "queued"
            ])
            let didClear = breakPolicy.waitWhileBusy()
            if !didClear {
                // タイムアウト時だけ409を返す。210 Breakは実行中スクリプトを
                // 実際に中断した場合の応答なので、ここでは使用しない。
                EventBridge.shared.notify(.OnSSTPBreak, refs: [
                    "script": request.headerValue("Sender") ?? "ExternalSSTP",
                    "scope": "busy"
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
            // busy が解消した場合は、待機していた要求を通常経路で実行する。
        }
        // Event 無しの SEND は SHIORI を介さず Script ヘッダを直接バルーン再生する（SSTP の基本動作）。
        // IfGhost がある場合は UKADOC の振り分けルールに従う。
        if method == .send, (request.headerValue("Event") ?? "").isEmpty {
            let identity = currentGhostIdentity(routingRegistry: routingRegistry)
            let script = resolveScript(
                forGhost: request.receiverGhostName ?? identity.sakura,
                keroName: identity.kero,
                request: request,
                shioriScript: nil
            )
            var responseScript = script
            if !options.contains(.nodescript) {
                responseScript = playScriptOnGhosts(
                    request: request,
                    shioriScript: nil,
                    securityContext: securityContext,
                    isOwned: isOwned
                ) ?? script
            }
            var responseHeaders = collectPassThruHeaders(from: request.headers)
            if let entryHeader = SstpSessionStore.shared.allEntriesHeaderValue() {
                responseHeaders["Entry"] = entryHeader
            }
            return buildResponse(
                version: version,
                status: 200,
                charset: charset,
                script: responseScript,
                data: nil,
                responseHeaders: responseHeaders
            )
        }

        let refs = extractReferences(from: request)
        let event = resolveEvent(request: request, method: method)
        let shioriHeaders = buildShioriHeaders(
            from: request,
            charset: charset,
            options: options,
            securityContext: securityContext
        )
        if let status = shioriHeaders["Status"] {
            ShioriStatusStore.shared.update(status: status)
        }

        let shioriMethod = method == .notify ? "NOTIFY" : "GET"
        let raw = bridge.handleResponse(
            event: event,
            references: refs,
            headers: shioriHeaders,
            method: shioriMethod
        )
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

        // nodescript はバルーン再生のみ抑止する。応答の Script ヘッダや
        // イベント処理（SHIORI送出）には影響しない（UKADOC spec_sstp）
        let suppressBalloon = options.contains(.nodescript) || scriptOptionTokens.contains("nodescript")
        let identity = currentGhostIdentity(routingRegistry: routingRegistry)
        let finalScript = resolveScript(
            forGhost: request.receiverGhostName ?? identity.sakura,
            keroName: identity.kero,
            request: request,
            shioriScript: scriptForSstp
        )
        var responseScript = finalScript
        if !suppressBalloon {
            if method == .notify {
                // NOTIFY 由来の ValueNotify スクリプトは通知系再生（runNotifyScript）でバルーンに適用する。
                // 可視テキストを含まない場合は現バルーンを保持してコマンドのみ適用（UKADOC ValueNotify サブセット）。
                if let script = scriptForSstp,
                   !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    responseScript = playScriptOnGhosts(
                        request: request,
                        shioriScript: script,
                        notify: true,
                        scriptOptions: scriptOptionTokens,
                        securityContext: securityContext,
                        isOwned: isOwned
                    ) ?? finalScript
                }
            } else {
                responseScript = playScriptOnGhosts(
                    request: request,
                    shioriScript: scriptForSstp,
                    notify: false,
                    scriptOptions: scriptOptionTokens,
                    securityContext: securityContext,
                    isOwned: isOwned
                ) ?? finalScript
            }
        }

        let data = mapped.data
        var responseHeaders = collectPassThruHeaders(from: request.headers)
        responseHeaders.merge(mapped.responseHeaders) { _, rhs in rhs }
        // Optionally advertise ukatec compatibility to callers
        if responseHeaders["X-UKATEC-Spec"] == nil {
            responseHeaders["X-UKATEC-Spec"] = "1"
        }
        // Apply SSP-compatible side effects from SHIORI headers (Surface/Balloon/BalloonOffset/Icon)
        // 宛先は ReceiverGhostName で解決する（マルチゴースト対応、未指定はプライマリ）。
        // 具体的な UI 操作は SstpDispatcherHost へ型付き効果として委譲し、ここでは解析・検証と
        // 効果生成のみを行う（NSApp/AppDelegate/GhostManager の直接参照を排除）。
        let requestHeaders = request.headers
        if let surfaceStr = mapped.responseHeaders["Surface"], let surface = Int(surfaceStr) {
            host.apply(SstpUIEffect(.updateSurface(id: surface), requestHeaders: requestHeaders))
        }
        if let balloonName = mapped.responseHeaders["Balloon"], !balloonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            host.apply(SstpUIEffect(.switchBalloon(name: balloonName), requestHeaders: requestHeaders))
        }
        // Apply BalloonOffset if present: format "x,y"
        if let offsetStr = mapped.responseHeaders["BalloonOffset"], !offsetStr.isEmpty {
            let comps = offsetStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if comps.count >= 2 {
                let x = String(comps[0])
                let y = String(comps[1])
                host.apply(SstpUIEffect(.balloonOffset(x: x, y: y, isRelative: false), requestHeaders: requestHeaders))
            }
        }

        // Apply Icon header: set dock/tray icon to specified file under ghost root
        if let iconSpec = mapped.responseHeaders["Icon"], !iconSpec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parts = iconSpec.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            let filename = parts.first.map(String.init) ?? iconSpec
            let text = parts.count > 1 ? String(parts[1]) : ""
            host.apply(SstpUIEffect(.setTaskTrayIcon(filename: filename, text: text), requestHeaders: requestHeaders))
        }

        if let entryHeader = SstpSessionStore.shared.allEntriesHeaderValue() {
            responseHeaders["Entry"] = entryHeader
        }
        return buildResponse(
            version: version,
            status: status,
            charset: charset,
            script: responseScript,
            data: data,
            responseHeaders: responseHeaders
        )
    }

    private static func handleNotify(_ request: SSTPRequest, securityContext: ShioriSecurityContext, isOwned: Bool, host: SstpDispatcherHost, bridge: ShioriBridge, routingRegistry: SstpRoutingRegistry, breakPolicy: SstpBreakPolicy = LiveSstpBreakPolicy.live) -> String {
        routeToShiori(request: request, method: .notify, securityContext: securityContext, isOwned: isOwned, host: host, bridge: bridge, routingRegistry: routingRegistry, breakPolicy: breakPolicy)
    }

    private static func handleCommunicate(_ request: SSTPRequest, securityContext: ShioriSecurityContext, isOwned: Bool, host: SstpDispatcherHost, bridge: ShioriBridge, routingRegistry: SstpRoutingRegistry) -> String {
        routeToShiori(request: request, method: .communicate, securityContext: securityContext, isOwned: isOwned, host: host, bridge: bridge, routingRegistry: routingRegistry)
    }

    private static func handleExecute(_ request: SSTPRequest, securityContext: ShioriSecurityContext, isOwned: Bool, host: SstpDispatcherHost, bridge: ShioriBridge, routingRegistry: SstpRoutingRegistry) -> String {
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
            requestHeaders: request.headers,
            host: host,
            routingRegistry: routingRegistry
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
        return routeToShiori(request: request, method: .execute, securityContext: securityContext, isOwned: isOwned, host: host, bridge: bridge, routingRegistry: routingRegistry)
    }

    private static func handleExtendedExecuteCommand(
        commandKey: String,
        commandArgs: [String],
        sender: String,
        version: String,
        charset: String,
        requestHeaders: [String: String],
        host: SstpDispatcherHost,
        routingRegistry: SstpRoutingRegistry
    ) -> String? {
        let property = PropertyManager.shared
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
                ?? routingRegistry.allGhostNames().first
                ?? "Ourin"
            return success(value)
        case "getnames", "getnamelist":
            return success(routingRegistry.allGhostNames().joined(separator: ","))
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
            let payload = buildGetFmoPayload(host: host)
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
            return success(routingRegistry.allGhostNames().joined(separator: ","))
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
            host.apply(SstpUIEffect(.dumpSurface(params: commandArgs), requestHeaders: requestHeaders))
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
            host.apply(SstpUIEffect(.moveWindowAsync(scope: scope, x: x, y: y, time: time, method: method, ignoreSticky: ignoreSticky), requestHeaders: requestHeaders))
            return success(nil)
        case "settrayicon", "settasktrayicon":
            guard let filename = commandArgs.first, !filename.isEmpty else { return badRequest() }
            let text = commandArgs.count > 1 ? commandArgs[1] : ""
            host.apply(SstpUIEffect(.setTaskTrayIcon(filename: filename, text: text), requestHeaders: requestHeaders))
            return success(nil)
        case "settrayballoon":
            host.apply(SstpUIEffect(.setTrayBalloon(options: commandArgs), requestHeaders: requestHeaders))
            return success(nil)
        default:
            return nil
        }
    }

    private static func buildGetFmoPayload(host: SstpDispatcherHost) -> String {
        let records = host.collectFmoRecords()
        return FmoManager.buildSnapshot(records: records)
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

    private static func handleGive(_ request: SSTPRequest, securityContext: ShioriSecurityContext, isOwned: Bool, host: SstpDispatcherHost, bridge: ShioriBridge, routingRegistry: SstpRoutingRegistry) -> String {
        routeToShiori(request: request, method: .give, securityContext: securityContext, isOwned: isOwned, host: host, bridge: bridge, routingRegistry: routingRegistry)
    }

    private static func handleInstall(_ request: SSTPRequest, securityContext: ShioriSecurityContext, isOwned: Bool, host: SstpDispatcherHost, bridge: ShioriBridge, routingRegistry: SstpRoutingRegistry) -> String {
        routeToShiori(request: request, method: .install, securityContext: securityContext, isOwned: isOwned, host: host, bridge: bridge, routingRegistry: routingRegistry)
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

    private static func referenceMap(from request: SSTPRequest) -> [Int: String] {
        var source: [Int: String] = [:]
        for i in 0..<32 {
            if let ref = request.headerValue("Reference\(i)") {
                source[i] = ref
            }
        }
        if request.method.uppercased() == "COMMUNICATE" {
            // UKADOC OnCommunicate:
            //   Reference0 = 送信元ゴースト名 (Sender ヘッダ)
            //   Reference1 = 発言内容 (Sentence ヘッダ)
            //   Reference2+ = SSTP の ReferenceN（Reference0,1,... を 2 つシフト）
            var shifted: [Int: String] = [
                0: request.headerValue("Sender") ?? "",
                1: request.headerValue("Sentence") ?? ""
            ]
            for (index, value) in source {
                shifted[index + 2] = value
            }
            return shifted
        }
        if request.method.uppercased() == "EXECUTE",
           let command = request.headerValue("Command"),
           !command.isEmpty {
            var shifted: [Int: String] = [0: command]
            for (index, value) in source {
                shifted[index + 1] = value
            }
            return shifted
        }
        return source
    }

    /// 既存runtime配列APIへ渡せる連続prefixだけを返す。
    /// 欠番以降は`buildShioriHeaders`の疎Referenceとして保持する。
    private static func extractReferences(from request: SSTPRequest) -> [String] {
        let map = referenceMap(from: request)
        var refs: [String] = []
        while let value = map[refs.count] {
            refs.append(value)
        }
        return refs
    }

    /// OnTranslate Reference3用。欠番は空要素として位置を保持する。
    private static func referencesPreservingGaps(from request: SSTPRequest) -> [String] {
        let map = referenceMap(from: request)
        guard let highest = map.keys.max() else { return [] }
        return (0...highest).map { map[$0] ?? "" }
    }

    private static func addSparseReferenceHeaders(from request: SSTPRequest, to headers: inout [String: String]) {
        let map = referenceMap(from: request)
        var prefixCount = 0
        while map[prefixCount] != nil { prefixCount += 1 }
        for index in map.keys.sorted() where index >= prefixCount {
            headers["Reference\(index)"] = map[index]
        }
    }

    private static func buildShioriHeaders(
        from request: SSTPRequest,
        charset: String,
        options: Set<SSTPRequest.Option>,
        securityContext: ShioriSecurityContext?
    ) -> [String: String] {
        let sender = request.headerValue("Sender") ?? "Ourin"
        let security = securityContext ?? securityContextFromRequest(request)
        let senderType = request.headerValue("SenderType") ?? "external,sstp"

        var headers: [String: String] = [
            "Charset": charset,
            "Sender": sender,
            "SenderType": senderType,
            "SecurityLevel": security.level
        ]
        if let origin = security.origin, !origin.isEmpty {
            headers["SecurityOrigin"] = origin
        }
        if let status = request.headerValue("Status"), !status.isEmpty {
            headers["Status"] = status
        } else {
            headers["Status"] = ShioriStatusStore.shared.currentStatus
        }
        if headers["SecurityOrigin"] == nil,
           let securityOrigin = request.headerValue("SecurityOrigin"),
           !securityOrigin.isEmpty {
            headers["SecurityOrigin"] = securityOrigin
        }
        copyIfPresent("BaseID", from: request, to: &headers)
        copyIfPresent("Marker", from: request, to: &headers)
        copyIfPresent("ErrorLevel", from: request, to: &headers)
        copyIfPresent("ErrorDescription", from: request, to: &headers)
        // COMMUNICATE は送信元が現在の Surface を付加できる。受信側の SHIORI
        // はこのヘッダを OnCommunicate の文脈として参照するため、応答側の
        // Surface 処理だけでなく入力経路にも保持して渡す。
        copyIfPresent("Surface", from: request, to: &headers)
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
        headers.merge(collectPassThruHeaders(from: request.headers)) { lhs, _ in lhs }
        addSparseReferenceHeaders(from: request, to: &headers)
        return headers
    }

    private static func securityContextFromRequest(_ request: SSTPRequest) -> ShioriSecurityContext {
        if let origin = request.headerValue("SecurityOrigin"),
           !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return isLocalOrigin(origin) ? .local : ShioriSecurityContext.external(origin: origin)
        }
        let raw = request.headerValue("SecurityLevel")?.lowercased() ?? "local"
        return raw == "external" ? ShioriSecurityContext.external(origin: nil) : .local
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
            case "age":
                responseHeaders["Age"] = val
            case "markersend":
                responseHeaders["MarkerSend"] = val
            default:
                if key.hasPrefix("reference"),
                   let index = Int(key.dropFirst("reference".count)), index >= 0 {
                    responseHeaders["Reference\(index)"] = val
                } else if key == "x-sstp-passthru" || key.hasPrefix(passThruPrefix) {
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

    /// UKADOC「IfGhostによるスクリプト振り分け」でデフォルトゴースト（さくら）扱いとなる名前。
    /// これらの Script はデフォルトスクリプトとしても機能する。
    private static let defaultGhostAliases: Set<String> = ["さくら", "エミリ", "えみりぃ"]

    /// 再生・応答に使うスクリプトを決定する。
    /// IfGhost と Script は出現順で対応付けられ、最初の IfGhost より前の Script はデフォルトスクリプト。
    /// IfGhost 一致 > SHIORI 応答スクリプト > デフォルトスクリプト（Script ヘッダ）の順で採用する。
    private static func resolveScript(
        forGhost ghostName: String?,
        keroName: String? = nil,
        request: SSTPRequest,
        shioriScript: String?
    ) -> String? {
        let bindings = request.scriptBindings
        let shiori = (shioriScript?.isEmpty == false) ? shioriScript : nil
        let defaultScript = bindings.first { binding in
            guard let ifGhost = binding.ifGhost else { return true }
            return defaultGhostAliases.contains(sakuraName(of: ifGhost).lowercased())
        }?.script
        guard bindings.contains(where: { $0.ifGhost != nil }) else {
            // IfGhost 無し: SHIORI 応答を優先し、無ければ Script ヘッダを保険として使う
            return shiori ?? defaultScript
        }
        if let target = ghostName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !target.isEmpty,
           let matched = bindings.first(where: { binding in
               guard let ifGhost = binding.ifGhost else { return false }
               return ifGhostMatches(ifGhost, sakuraName: target, keroName: keroName)
           }),
           !matched.script.isEmpty {
            return matched.script
        }
        return shiori ?? defaultScript
    }

    /// IfGhost の名前が対象ゴーストのキャラクター名と一致するか判定する。
    /// UKADOC: `\0側名,\1側名` のペア指定では両方の名前が一致する必要がある。
    private static func ifGhostMatches(_ ifGhost: String, sakuraName: String, keroName: String?) -> Bool {
        let names = ifGhost.split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let expectedSakura = names.first,
              expectedSakura.caseInsensitiveCompare(sakuraName) == .orderedSame else {
            return false
        }
        guard names.count > 1 else { return true }
        guard let expectedKero = names.dropFirst().first,
              !expectedKero.isEmpty,
              let keroName,
              expectedKero.caseInsensitiveCompare(keroName) == .orderedSame else {
            return false
        }
        return true
    }

    /// IfGhost ヘッダから \0 側名を取り出す（デフォルトゴースト判定用）。
    private static func sakuraName(of ifGhost: String) -> String {
        ifGhost.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ifGhost
    }

    private static func currentGhostIdentity(routingRegistry: SstpRoutingRegistry) -> (sakura: String?, kero: String?) {
        let sakura = PropertyManager.shared.get("currentghost.scope(0).name")
            ?? PropertyManager.shared.get("currentghost.sakuraname")
            ?? PropertyManager.shared.get("currentghost.name")
            ?? routingRegistry.allGhostNames().first
        let kero = PropertyManager.shared.get("currentghost.scope(1).name")
            ?? PropertyManager.shared.get("currentghost.keroname")
        return (sakura, kero)
    }

    /// 確定したスクリプトをバルーンで再生する。IfGhost がある場合はゴースト毎に振り分ける。
    /// - Parameter notify: true の場合は通知系再生（runNotifyScript）を行う。
    @discardableResult
    private static func playScriptOnGhosts(
        request: SSTPRequest,
        shioriScript: String?,
        notify: Bool = false,
        scriptOptions: Set<String> = [],
        securityContext: ShioriSecurityContext,
        isOwned: Bool
    ) -> String? {
        var reasons: Set<String> = []
        switch request.method.uppercased() {
        case "SEND": reasons.insert("sstp-send")
        case "COMMUNICATE": reasons.insert("communicate")
        default: break
        }
        if securityContext.level == "external" {
            reasons.insert("remote")
        }
        if isOwned {
            reasons.insert("owned")
        }
        if request.options.contains(.notranslate) || scriptOptions.contains("notranslate") {
            reasons.insert("notranslate")
        }
        let context = ScriptTranslationContext(
            reasons: reasons,
            eventID: request.headerValue("Event"),
            references: referencesPreservingGaps(from: request),
            isSSTP: true,
            sender: request.headerValue("Sender") ?? "Ourin",
            securityLevel: securityContext.level,
            securityOrigin: securityContext.origin
        )
        return EventBridge.shared.playTranslatedScriptOnGhostsResolving(
            ghostName: request.receiverGhostName,
            notify: notify,
            translationContext: context
        ) { manager in
            let sakuraName = manager.ghostConfig?.sakuraName ?? manager.ghostConfig?.name
            return resolveScript(
                forGhost: sakuraName ?? request.receiverGhostName,
                keroName: manager.ghostConfig?.keroName,
                request: request,
                shioriScript: shioriScript
            )
        }
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
