import SwiftUI
import AppKit
import CoreImage
import Combine
import UserNotifications


// MARK: - System Commands and Ghost Booting

extension GhostManager {
    // Note: This extension uses the following properties declared in the main GhostManager class:
    // - pendingChoices, choiceHasCancelOption, choiceTimeout


    // MARK: - Ghost Booting via SSTP
    
    /// Boot another ghost using SSTP NOTIFY command
    func bootOtherGhost(name: String? = nil) {
        let installedGhosts = NarRegistry.shared.installedGhosts()
        let currentGhostName = ghostConfig?.name
        let candidates = installedGhosts.filter { $0 != currentGhostName }
        let provided = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ghostName = provided.isEmpty
            ? (candidates.randomElement() ?? currentGhostName ?? "default")
            : provided
        Log.debug("[GhostManager] Attempting to boot ghost: \(ghostName)")
        
        sendSSTPNotify(event: "OnBoot", references: ["Reference0": ghostName])
        EventBridge.shared.notify(.OnOtherGhostBooted, params: ["Reference0": ghostName])
    }
    
    /// Boot all ghosts by broadcasting SSTP
    func bootAllGhosts() {
        let installedGhosts = NarRegistry.shared.installedGhosts()
        let currentGhostName = ghostConfig?.name
        let targets = installedGhosts.filter { $0 != currentGhostName }
        Log.debug("[GhostManager] Broadcasting boot command to ghosts: \(targets)")
        if targets.isEmpty {
            sendSSTPNotify(event: "OnBootAll", references: [:])
            return
        }
        for target in targets {
            sendSSTPNotify(event: "OnBoot", references: ["Reference0": target], receiverGhostName: target)
            EventBridge.shared.notify(.OnOtherGhostBooted, params: ["Reference0": target])
        }
    }
    
    /// Send an SSTP NOTIFY request
    func sendSSTPNotify(event: String, references: [String: String], receiverGhostName: String? = nil) {
        DispatchQueue.global(qos: .utility).async {
            // Construct SSTP NOTIFY request
            var request = "NOTIFY SSTP/1.1\r\n"
            request += "Sender: Ourin\r\n"
            request += "Event: \(event)\r\n"
            request += "Charset: UTF-8\r\n"
            if let receiverGhostName, !receiverGhostName.isEmpty {
                request += "ReceiverGhostName: \(receiverGhostName)\r\n"
            }
            
            // Add references
            for (key, value) in references.sorted(by: { $0.key < $1.key }) {
                request += "\(key): \(value)\r\n"
            }
            request += "\r\n"
            
            // Try to send to localhost:9801 (default SSTP port)
            self.sendSSTPToLocalhost(request: request)
        }
    }

    func raiseOtherGhostEvent(ghostSpec: String, event: String, references: [String], notifyOnly: Bool) {
        let targets = parseGhostTargets(ghostSpec)
        guard !targets.isEmpty else {
            Log.info("[GhostManager] raiseother/notifyother ignored: empty ghost target")
            return
        }

        let referenceMap = Dictionary(uniqueKeysWithValues: references.enumerated().map { ("Reference\($0.offset)", $0.element) })
        for target in targets {
            if target == "__SYSTEM_ALL_GHOST__" {
                sendSSTPNotify(event: event, references: referenceMap)
            } else {
                sendSSTPNotify(event: event, references: referenceMap, receiverGhostName: target)
            }
        }

        let mode = notifyOnly ? "notifyother" : "raiseother"
        Log.debug("[GhostManager] \(mode) dispatched: event=\(event), targets=\(targets)")
    }

    func scheduleTimerRaiseOther(intervalMs: Int, repeatSpec: String, ghostSpec: String, event: String, references: [String], notifyOnly: Bool) {
        let timerKey = remoteEventTimerKey(ghostSpec: ghostSpec, event: event, notifyOnly: notifyOnly)

        DispatchQueue.main.async {
            if let existing = self.remoteEventTimers.removeValue(forKey: timerKey) {
                existing.invalidate()
            }
        }

        guard intervalMs > 0 else {
            Log.debug("[GhostManager] remote timer canceled: key=\(timerKey)")
            return
        }

        let shouldRepeat = isRepeatingTimerSpec(repeatSpec)
        let interval = TimeInterval(intervalMs) / 1000.0

        if shouldRepeat {
            DispatchQueue.main.async {
                let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    self.raiseOtherGhostEvent(ghostSpec: ghostSpec, event: event, references: references, notifyOnly: notifyOnly)
                }
                self.remoteEventTimers[timerKey] = timer
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
                self?.raiseOtherGhostEvent(ghostSpec: ghostSpec, event: event, references: references, notifyOnly: notifyOnly)
            }
        }
    }

    private func parseGhostTargets(_ raw: String) -> [String] {
        return raw
            .split(separator: "\u{1}")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func isRepeatingTimerSpec(_ repeatSpec: String) -> Bool {
        if let intValue = Int(repeatSpec.trimmingCharacters(in: .whitespacesAndNewlines)) {
            // ukadoc: 0=repeat, 1以上=one-shot
            return intValue == 0
        }
        let normalized = repeatSpec.lowercased()
        return normalized == "repeat" || normalized == "loop" || normalized == "true" || normalized == "yes"
    }

    private func remoteEventTimerKey(ghostSpec: String, event: String, notifyOnly: Bool) -> String {
        let mode = notifyOnly ? "notifyother" : "raiseother"
        return "\(mode)|\(ghostSpec.lowercased())|\(event.lowercased())"
    }

    private func localEventTimerKey(event: String, notifyOnly: Bool) -> String {
        let mode = notifyOnly ? "timernotify" : "timerraise"
        return "\(mode)|\(event.lowercased())"
    }

    private func pluginEventTimerKey(pluginSpec: String, event: String, notifyOnly: Bool) -> String {
        let mode = notifyOnly ? "timernotifyplugin" : "timerraiseplugin"
        return "\(mode)|\(pluginSpec.lowercased())|\(event.lowercased())"
    }

    private func currentPluginRegistry() -> PluginRegistry? {
        (NSApp.delegate as? AppDelegate)?.pluginRegistry
    }

    func dispatchPluginEvent(pluginSpec: String, event: String, references: [String], notifyOnly: Bool) {
        guard let registry = currentPluginRegistry() else {
            Log.info("[GhostManager] Plugin registry unavailable")
            return
        }
        let bridge = OurinPluginEventBridge(
            registry: registry,
            runScript: { [weak self] script in
                DispatchQueue.main.async {
                    self?.sakuraEngine.run(script: script)
                }
            },
            emitEvent: { eventName, refs in
                if let eventID = EventID(rawValue: eventName) {
                    EventBridge.shared.notify(eventID, params: refs)
                } else {
                    EventBridge.shared.notifyCustom(eventName, params: refs)
                }
            }
        )
        bridge.dispatch(pluginSpec: pluginSpec, event: event, references: references, notifyOnly: notifyOnly)
    }

    func scheduleTimerPluginEvent(intervalMs: Int, repeatSpec: String, pluginSpec: String, event: String, references: [String], notifyOnly: Bool) {
        let timerKey = pluginEventTimerKey(pluginSpec: pluginSpec, event: event, notifyOnly: notifyOnly)
        DispatchQueue.main.async {
            if let existing = self.pluginEventTimers.removeValue(forKey: timerKey) {
                existing.invalidate()
            }
            guard intervalMs > 0 else {
                Log.debug("[GhostManager] plugin timer canceled: key=\(timerKey)")
                return
            }
            let shouldRepeat = self.isRepeatingTimerSpec(repeatSpec)
            let interval = TimeInterval(intervalMs) / 1000.0
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: shouldRepeat) { [weak self] _ in
                guard let self else { return }
                self.dispatchPluginEvent(pluginSpec: pluginSpec, event: event, references: references, notifyOnly: notifyOnly)
                if !shouldRepeat {
                    self.pluginEventTimers.removeValue(forKey: timerKey)
                }
            }
            self.pluginEventTimers[timerKey] = timer
        }
    }
    
    /// Send SSTP request to localhost
    func sendSSTPToLocalhost(request: String) {
        let host = "127.0.0.1"
        let port = 9801
        
        var sock: Int32 = -1
        var hints = addrinfo()
        var result: UnsafeMutablePointer<addrinfo>?
        
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        
        let portString = String(port)
        guard getaddrinfo(host, portString, &hints, &result) == 0 else {
            Log.info("[GhostManager] Failed to resolve SSTP host: \(host):\(port)")
            return
        }
        
        defer {
            if let result = result {
                freeaddrinfo(result)
            }
            if sock >= 0 {
                close(sock)
            }
        }
        
        guard let addr = result else {
            Log.info("[GhostManager] No address info for SSTP")
            return
        }
        
        sock = socket(addr.pointee.ai_family, addr.pointee.ai_socktype, addr.pointee.ai_protocol)
        guard sock >= 0 else {
            Log.info("[GhostManager] Failed to create socket for SSTP")
            return
        }
        
        // Set timeout
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        guard connect(sock, addr.pointee.ai_addr, addr.pointee.ai_addrlen) >= 0 else {
            Log.debug("[GhostManager] No SSTP server at \(host):\(port) - this is normal if no other ghosts are running")
            return
        }
        
        // Send request
        let data = request.data(using: .utf8) ?? Data()
        let sent = data.withUnsafeBytes { ptr in
            send(sock, ptr.baseAddress, data.count, 0)
        }
        
        if sent > 0 {
            Log.debug("[GhostManager] Sent SSTP request to \(host):\(port)")
        } else {
            Log.info("[GhostManager] Failed to send SSTP request")
        }
    }
    
    // MARK: - Choice Command Support
    
    // Choice state and type are defined on GhostManager (main file)
    
    /// Handle choice command - \q[title,ID] or variants
    func handleChoiceCommand(args: [String]) {
        guard args.count >= 2 else {
            Log.info("[GhostManager] Invalid choice command: insufficient arguments")
            return
        }
        
        let title = args[0]
        let idOrScript = args[1]
        
        // Check if this is a script: format
        if idOrScript.hasPrefix("script:") {
            let script = String(idOrScript.dropFirst(7)) // Remove "script:" prefix
            Log.debug("[GhostManager] Choice '\(title)' will execute script: \(script)")
            pendingChoices.append((title: title, action: .script(script)))
        } else {
            // Event ID format
            let eventID = idOrScript
            let references = Array(args.dropFirst(2))
            Log.debug("[GhostManager] Choice '\(title)' will trigger event: \(eventID) with refs: \(references)")
            pendingChoices.append((title: title, action: .event(id: eventID, references: references)))
        }
    }

    /// Handle queued choice command - \__q[id0,id1,...]
    func handleQueuedChoiceCommand(args: [String]) {
        guard !args.isEmpty else {
            Log.info("[GhostManager] Invalid __q command: no arguments")
            return
        }

        for id in args where !id.isEmpty {
            pendingChoices.append((title: id, action: .event(id: id, references: [])))
        }
    }

    /// Execute an embedded event and inline its script result.
    /// ukadoc: \![embed,event,ref0,ref1,...]
    func executeEmbeddedEvent(event: String, references: [String]) {
        guard let response = yayaAdapter?.request(method: "GET", id: event, refs: references, timeout: 4.0),
              response.ok,
              let script = response.value,
              !script.isEmpty else {
            Log.info("[GhostManager] embed event failed or returned empty: \(event)")
            return
        }

        let embeddedTokens = sakuraEngine.parse(script: script)
        for token in embeddedTokens {
            sakuraEngine(sakuraEngine, didEmit: token)
        }
    }

    func dispatchLocalEvent(event: String, references: [String], notifyOnly: Bool) {
        let params = Dictionary(uniqueKeysWithValues: references.enumerated().map { ("Reference\($0.offset)", $0.element) })
        if notifyOnly {
            EventBridge.shared.notifyCustom(event, params: params, ignoreResponseScript: true)
            return
        }
        if let eventID = EventID(rawValue: event) {
            EventBridge.shared.notify(eventID, params: params)
        } else {
            EventBridge.shared.notifyCustom(event, params: params)
        }
    }

    /// Schedule delayed local event dispatch.
    /// ukadoc: \![timerraise|timernotify,ms,repeat,event,ref0,ref1,...]
    func scheduleLocalEventTimer(intervalMs: Int, repeatSpec: String, event: String, references: [String], notifyOnly: Bool) {
        let timerKey = localEventTimerKey(event: event, notifyOnly: notifyOnly)

        DispatchQueue.main.async {
            if let existing = self.localEventTimers.removeValue(forKey: timerKey) {
                existing.invalidate()
            }

            guard intervalMs > 0 else {
                Log.debug("[GhostManager] local timer canceled: key=\(timerKey)")
                return
            }

            let shouldRepeat = self.isRepeatingTimerSpec(repeatSpec)
            let interval = TimeInterval(intervalMs) / 1000.0
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: shouldRepeat) { [weak self] _ in
                guard let self else { return }
                self.dispatchLocalEvent(event: event, references: references, notifyOnly: notifyOnly)
                if !shouldRepeat {
                    self.localEventTimers.removeValue(forKey: timerKey)
                }
            }
            self.localEventTimers[timerKey] = timer
        }
    }
    
    /// Display choice dialog when choices are ready
    func showChoiceDialog() {
        guard !pendingChoices.isEmpty else { return }
        EventBridge.shared.notify(.OnChoiceEnter, params: ["Reference0": String(pendingChoices.count)])
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("選択してください", comment: "Please choose")
            alert.alertStyle = .informational
            
            // Add choice buttons in order
            for choice in self.pendingChoices {
                alert.addButton(withTitle: choice.title)
            }
            
            // Add cancel button if \z was present
            if self.choiceHasCancelOption {
                alert.addButton(withTitle: NSLocalizedString("キャンセル", comment: "Cancel"))
            }
            
            // Handle timeout if specified
            var timeoutTimer: Timer? = nil
            var didTimeout = false
            if let timeout = self.choiceTimeout, timeout > 0 {
                let startTime = Date()
                alert.informativeText = String(format: NSLocalizedString("残り時間: %.0f秒", comment: "time remaining"), timeout)
                
                timeoutTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                    let elapsed = Date().timeIntervalSince(startTime)
                    let remaining = max(0, timeout - elapsed)
                    
                    if remaining <= 0 {
                        timer.invalidate()
                        didTimeout = true
                        NSApp.abortModal()
                    } else {
                        alert.informativeText = String(format: NSLocalizedString("残り時間: %.0f秒", comment: "time remaining"), remaining)
                    }
                }
            }
            
            // Show dialog
            let response = alert.runModal()
            timeoutTimer?.invalidate()

            // Process response
            let buttonIndex = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue

            if didTimeout {
                _ = self.requestDialogEvent(eventID: "OnChoiceTimeout", references: [String(self.pendingChoices.count)])
            } else if buttonIndex >= 0 && buttonIndex < self.pendingChoices.count {
                // User selected a choice
                let choice = self.pendingChoices[buttonIndex]

                // Trigger OnChoiceSelect event
                let params: [String: String] = [
                    "Reference0": choice.title,
                    "Reference\(buttonIndex + 1)": choice.title
                ]
                EventBridge.shared.notifyCustom("OnChoiceSelect", params: params)
                EventBridge.shared.notifyCustom("OnChoiceSelectEx", params: params)

                // Trigger OnChoiceHover event when choice is made
                EventBridge.shared.notifyCustom("OnChoiceHover", params: params)

                switch choice.action {
                case .event(let id, let references):
                    // Trigger event
                    if let response = self.yayaAdapter?.request(method: "GET", id: id, refs: references, timeout: 4.0), response.ok {
                        if let script = response.value {
                            self.sakuraEngine.run(script: script)
                        }
                    }

                case .script(let script):
                    // Execute inline script
                    self.sakuraEngine.run(script: script)
                }
            } else {
                // Cancel was selected
                if let response = self.yayaAdapter?.request(method: "GET", id: "OnChoiceCancel", timeout: 4.0), response.ok {
                    if let script = response.value {
                        self.sakuraEngine.run(script: script)
                    }
                }
            }

            // Clear choice state
            self.pendingChoices.removeAll()
            self.choiceHasCancelOption = false
        }
    }
    
    // MARK: - System Commands Implementation
    
    /// Set desktop wallpaper
    func setWallpaper(filename: String, options: String) {
        let wallpaperURL = ghostURL.appendingPathComponent(filename)
        
        guard FileManager.default.fileExists(atPath: wallpaperURL.path) else {
            Log.info("[GhostManager] Wallpaper file not found: \(filename)")
            return
        }
        
        DispatchQueue.main.async {
            do {
                let workspace = NSWorkspace.shared
                if let screen = NSScreen.main {
                    try workspace.setDesktopImageURL(wallpaperURL, for: screen, options: [:])
                    Log.debug("[GhostManager] Set wallpaper: \(filename)")
                }
            } catch {
                Log.info("[GhostManager] Failed to set wallpaper: \(error)")
            }
        }
    }
    
    /// Set task tray (dock) icon
    func setTaskTrayIcon(filename: String, text: String) {
        let iconURL = ghostURL.appendingPathComponent(filename)
        
        DispatchQueue.main.async {
            if let image = NSImage(contentsOf: iconURL) {
                NSApp.applicationIconImage = image
                Log.debug("[GhostManager] Set dock icon: \(filename)")
            } else {
                Log.info("[GhostManager] Failed to load icon: \(filename)")
            }
        }
    }
    
    /// Set tray balloon (notification)
    func setTrayBalloon(options: [String]) {
        // Parse options like title=..., message=..., icon=...
        var title = "Ourin"
        var message = ""
        var sound = true
        var timeoutSeconds: Double = 5
        
        for option in options {
            let parts = option.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].lowercased()
                let value = String(parts[1])
                switch key {
                case "title": title = value
                case "message", "text": message = value
                case "sound": sound = value.lowercased() != "false"
                case "timeout", "time":
                    if let raw = Double(value) {
                        timeoutSeconds = raw > 1000 ? raw / 1000.0 : raw
                    }
                default: break
                }
            } else {
                // If no key, assume it's the message
                if message.isEmpty {
                    message = option
                }
            }
        }
        
        DispatchQueue.main.async {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = message
            if sound {
                content.sound = .default
            }
            content.userInfo = [
                "ourinTrayBalloon": "1",
                "title": title,
                "message": message
            ]

            let identifier = "ourin.tray.\(UUID().uuidString)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    Log.info("[GhostManager] Failed to deliver notification: \(error)")
                } else {
                    Log.debug("[GhostManager] Delivered notification: \(title) - \(message)")
                }
            }

            if timeoutSeconds > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) {
                    EventBridge.shared.notify(.OnTrayBalloonTimeout, params: [
                        "Reference0": identifier,
                        "Reference1": title
                    ])
                }
            }
        }
    }
    
    /// Set other ghost talk mode
    func setOtherGhostTalk(mode: String) {
        let normalized = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed: Set<String> = ["true", "false", "before", "after"]
        guard allowed.contains(normalized) else {
            Log.info("[GhostManager] Invalid other ghost talk mode: \(mode)")
            return
        }
        UserDefaults.standard.set(normalized, forKey: "OurinOtherGhostTalkMode")
        Log.debug("[GhostManager] Set other ghost talk mode: \(normalized)")
    }
    
    /// Set whether to observe other ghosts' surface changes
    func setOtherSurfaceChange(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "OurinObserveOtherSurfaceChange")
        Log.debug("[GhostManager] Set other surface change observation: \(enabled)")
    }
    
    /// Execute SNTP time synchronization
    func executeSNTP() {
        Log.debug("[GhostManager] Executing SNTP time synchronization")
        EventBridge.shared.notifyCustom("OnSNTPBegin", params: [:])
        guard let url = URL(string: "https://worldtimeapi.org/api/ip") else {
            Log.info("[GhostManager] Failed to build SNTP fallback URL")
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                Log.info("[GhostManager] SNTP fallback request failed: \(error)")
                EventBridge.shared.notifyCustom("OnSNTPFailure", params: ["Reference0": error.localizedDescription])
                return
            }

            guard let data = data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Log.info("[GhostManager] SNTP fallback returned invalid payload")
                EventBridge.shared.notifyCustom("OnSNTPFailure", params: ["Reference0": "invalid_payload"])
                return
            }

            let dateTime = object["datetime"] as? String ?? ""
            let timezone = object["timezone"] as? String ?? ""
            let parsedDate = ISO8601DateFormatter().date(from: dateTime)
            self.lastSntpServerDate = parsedDate
            self.lastSntpServerDateTime = dateTime
            self.lastSntpTimezone = timezone
            Log.debug("[GhostManager] SNTP fallback succeeded: \(dateTime) \(timezone)")
            EventBridge.shared.notifyCustom("OnSNTPCompare", params: [
                "Reference0": dateTime,
                "Reference1": timezone
            ])
            EventBridge.shared.notifyCustom("OnSNTP", params: [
                "Reference0": dateTime,
                "Reference1": timezone
            ])
        }
        task.resume()
    }

    /// Execute SNTP correction action for `\6`.
    /// On macOS app sandbox, system clock modification requires privileged operations,
    /// so we emit adjustment info and keep behavior explicit.
    func executeSNTPApply() {
        guard let serverDate = lastSntpServerDate else {
            Log.info("[GhostManager] SNTP apply requested without cached server time; starting sync first")
            executeSNTP()
            return
        }

        let localDate = Date()
        let deltaSec = serverDate.timeIntervalSince(localDate)
        let deltaMs = Int(deltaSec * 1000.0)
        EventBridge.shared.notifyCustom("OnSNTPAdjust", params: [
            "Reference0": String(deltaMs),
            "Reference1": lastSntpServerDateTime ?? "",
            "Reference2": lastSntpTimezone ?? ""
        ])
        Log.info("[GhostManager] SNTP apply simulated (deltaMs=\(deltaMs)); system clock is not modified by baseware")
    }
    
    /// Execute headline (RSS feed check)
    func executeHeadline(name: String) {
        Log.debug("[GhostManager] Executing headline check: \(name)")
        let feedURLString: String
        if name.hasPrefix("http://") || name.hasPrefix("https://") {
            feedURLString = name
        } else if let base = ghostConfig?.homeurl, !base.isEmpty {
            feedURLString = base
        } else {
            Log.info("[GhostManager] No headline URL available")
            EventBridge.shared.notifyCustom("OnHeadlineCheckFailure", params: ["Reference0": "missing_url"])
            return
        }

        guard let url = URL(string: feedURLString) else {
            Log.info("[GhostManager] Invalid headline URL: \(feedURLString)")
            EventBridge.shared.notifyCustom("OnHeadlineCheckFailure", params: ["Reference0": "invalid_url"])
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                Log.info("[GhostManager] Headline fetch failed: \(error)")
                EventBridge.shared.notifyCustom("OnHeadlineCheckFailure", params: ["Reference0": error.localizedDescription])
                return
            }

            guard let data = data, let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else {
                Log.info("[GhostManager] Headline fetch returned unreadable content")
                EventBridge.shared.notifyCustom("OnHeadlineCheckFailure", params: ["Reference0": "unreadable_content"])
                return
            }

            let titles = content.matches(for: "<title>(.*?)</title>").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let firstHeadline = titles.dropFirst().first ?? titles.first ?? ""
            EventBridge.shared.notifyCustom("OnHeadlineCheck", params: [
                "Reference0": firstHeadline,
                "Reference1": url.absoluteString
            ])
            Log.debug("[GhostManager] Headline check completed: \(firstHeadline)")
        }
        task.resume()
    }
    
    /// Execute mail check (biff)
    func executeBiff() {
        Log.debug("[GhostManager] Executing mail check (biff)")
        let mailRunning = NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == "com.apple.mail"
        }

        let state = mailRunning ? "running" : "not_running"
        EventBridge.shared.notifyCustom("OnBIFF", params: [
            "Reference0": state
        ])
        Log.debug("[GhostManager] BIFF check completed: \(state)")
    }

    /// Execute HTTP commands for `\![execute,http-*]`.
    func executeHTTP(subcommand: String, params: [String]) {
        guard let rawURL = params.first, let url = URL(string: rawURL) else {
            EventBridge.shared.notifyCustom("OnExecuteHTTPFailure", params: ["Reference0": "invalid_url"])
            EventBridge.shared.notifyCustom("OnExecuteHTTPProgress", params: ["Reference0": "failed", "Reference1": "0"])
            return
        }
        let methodSuffix = String(subcommand.dropFirst("http-".count)).uppercased()
        let supported = Set(["GET", "POST", "HEAD", "PUT", "DELETE", "PATCH", "OPTIONS"])
        let method = supported.contains(methodSuffix) ? methodSuffix : "GET"

        var request = URLRequest(url: url)
        request.httpMethod = method
        let parsed = parseCommandArguments(Array(params.dropFirst()))
        let body = parsed.options["body"] ?? parsed.positionals.first ?? ""
        if !body.isEmpty, method != "GET", method != "HEAD" {
            request.httpBody = body.data(using: .utf8)
            request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        applyRequestOptions(parsed, to: &request)

        if url.scheme?.lowercased() == "https" {
            EventBridge.shared.notifyCustom("OnExecuteHTTPSSLInfo", params: [
                "Reference0": url.host ?? "",
                "Reference1": url.absoluteString
            ])
        }
        EventBridge.shared.notifyCustom("OnExecuteHTTPProgress", params: [
            "Reference0": "running",
            "Reference1": "0",
            "Reference2": method,
            "Reference3": url.absoluteString
        ])

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                EventBridge.shared.notifyCustom("OnExecuteHTTPFailure", params: [
                    "Reference0": error.localizedDescription,
                    "Reference1": url.absoluteString,
                    "Reference2": method
                ])
                EventBridge.shared.notifyCustom("OnExecuteHTTPProgress", params: [
                    "Reference0": "failed",
                    "Reference1": "100",
                    "Reference2": method,
                    "Reference3": url.absoluteString
                ])
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = data.flatMap { String(data: $0, encoding: .utf8) ?? String(data: $0, encoding: .shiftJIS) } ?? ""
            EventBridge.shared.notifyCustom("OnExecuteHTTPComplete", params: [
                "Reference0": String(statusCode),
                "Reference1": body,
                "Reference2": url.absoluteString,
                "Reference3": method
            ])
            EventBridge.shared.notifyCustom("OnExecuteHTTPProgress", params: [
                "Reference0": "completed",
                "Reference1": "100",
                "Reference2": method,
                "Reference3": url.absoluteString
            ])
        }.resume()
    }

    /// Execute RSS commands for `\![execute,rss-*]`.
    func executeRSS(subcommand: String, params: [String]) {
        guard let rawURL = params.first, let url = URL(string: rawURL) else {
            EventBridge.shared.notifyCustom("OnExecuteRSSFailure", params: ["Reference0": "invalid_url"])
            return
        }
        let methodSuffix = String(subcommand.dropFirst("rss-".count)).uppercased()
        let method = Set(["GET", "POST"]).contains(methodSuffix) ? methodSuffix : "GET"
        var request = URLRequest(url: url)
        request.httpMethod = method
        let parsed = parseCommandArguments(Array(params.dropFirst()))
        if method == "POST" {
            let body = parsed.options["body"] ?? parsed.positionals.first ?? ""
            if !body.isEmpty {
                request.httpBody = body.data(using: .utf8)
                request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            }
        }
        applyRequestOptions(parsed, to: &request)

        if url.scheme?.lowercased() == "https" {
            EventBridge.shared.notifyCustom("OnExecuteRSS_SSLInfo", params: [
                "Reference0": url.host ?? "",
                "Reference1": url.absoluteString
            ])
        }

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                EventBridge.shared.notifyCustom("OnExecuteRSSFailure", params: [
                    "Reference0": error.localizedDescription,
                    "Reference1": url.absoluteString,
                    "Reference2": method
                ])
                return
            }

            guard let data = data,
                  let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else {
                EventBridge.shared.notifyCustom("OnExecuteRSSFailure", params: [
                    "Reference0": "unreadable_content",
                    "Reference1": url.absoluteString
                ])
                return
            }

            let title = xml.matches(for: "<title>(.*?)</title>")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? ""
            EventBridge.shared.notifyCustom("OnExecuteRSSComplete", params: [
                "Reference0": title,
                "Reference1": url.absoluteString,
                "Reference2": method
            ])
        }.resume()
    }
    
    /// Execute update check
    func executeUpdate(target: String, options: [String]) {
        Log.debug("[GhostManager] Executing update check for: \(target)")
        
        DispatchQueue.global(qos: .utility).async {
            // Determine what to update
            switch target.lowercased() {
            case "self", "ghost":
                // Check for updates to this ghost
                self.checkGhostUpdate(options: options)
            case "platform", "baseware":
                // Check for updates to Ourin itself
                self.checkPlatformUpdate(options: options)
            case "other", "all":
                // Check for updates to all installed ghosts
                self.checkAllGhostsUpdate(options: options)
            default:
                Log.info("[GhostManager] Unknown update target: \(target)")
            }
        }
    }
    
    /// Check for ghost updates
    func checkGhostUpdate(options: [String]) {
        emitUpdateBegin(targetType: "ghost")
        emitUpdatePipelineEvent(base: "OnUpdate", stage: "OnDownloadBegin", params: [
            "Reference0": ghostConfig?.homeurl ?? "",
            "Reference1": ghostURL.path
        ])
        guard let updateURL = ghostConfig?.homeurl else {
            Log.info("[GhostManager] No update URL configured for ghost")
            EventBridge.shared.notify(.OnUpdateFailure, params: [
                "Reference0": "paramerror",
                "Reference1": "",
                "Reference3": "ghost"
            ])
            emitUpdatePipelineEvent(base: "OnUpdate", stage: "OnMD5CompareFailure", params: ["Reference0": "missing_url"])
            emitUpdateResultEvents(
                target: "ghost",
                reason: "paramerror",
                fileList: "",
                explorerPath: ghostURL.path
            )
            EventBridge.shared.notifyCustom("OnUpdateCheckFailure", params: ["Reference0": "missing_url"])
            return
        }

        Log.info("[GhostManager] Checking for ghost updates at homeurl: \(updateURL)")
        NarInstaller().checkUpdates(homeURLString: updateURL) { result in
            switch result {
            case .success(let entries):
                let fileList = entries.map(\.lastPathComponent).joined(separator: ",")
                let reason = entries.isEmpty ? "none" : "changed"
                self.emitUpdatePipelineEvent(base: "OnUpdate", stage: "OnMD5CompareBegin", params: [
                    "Reference0": updateURL,
                    "Reference1": String(entries.count)
                ])
                self.emitUpdatePipelineEvent(base: "OnUpdate", stage: "OnMD5CompareComplete", params: [
                    "Reference0": updateURL,
                    "Reference1": String(entries.count)
                ])
                EventBridge.shared.notify(.OnUpdateReady, params: [
                    "Reference0": fileList,
                    "Reference3": "ghost"
                ])
                EventBridge.shared.notify(.OnUpdateComplete, params: [
                    "Reference0": reason,
                    "Reference1": fileList,
                    "Reference3": "ghost"
                ])
                let first = entries.first?.absoluteString ?? ""
                EventBridge.shared.notifyCustom("OnUpdateCheckComplete", params: [
                    "Reference0": "ghost",
                    "Reference1": first,
                    "Reference2": String(entries.count),
                    "Reference3": options.joined(separator: ",")
                ])
                self.emitUpdateResultEvents(
                    target: "ghost",
                    reason: reason,
                    fileList: fileList,
                    explorerPath: self.ghostURL.path
                )
                Log.debug("[GhostManager] Ghost update check completed entries=\(entries.count)")
            case .failure(let error):
                Log.info("[GhostManager] Ghost update check failed: \(error)")
                let reason = self.normalizeUpdateFailureReason(error)
                self.emitUpdatePipelineEvent(base: "OnUpdate", stage: "OnMD5CompareFailure", params: [
                    "Reference0": updateURL,
                    "Reference1": reason
                ])
                EventBridge.shared.notify(.OnUpdateFailure, params: [
                    "Reference0": reason,
                    "Reference1": "",
                    "Reference3": "ghost"
                ])
                self.emitUpdateResultEvents(
                    target: "ghost",
                    reason: reason,
                    fileList: "",
                    explorerPath: self.ghostURL.path
                )
                EventBridge.shared.notifyCustom("OnUpdateCheckFailure", params: ["Reference0": reason])
            }
        }
    }
    
    /// Check for platform (Ourin) updates
    func checkPlatformUpdate(options: [String]) {
        Log.info("[GhostManager] Checking for Ourin platform updates")
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        EventBridge.shared.notify(.OnBasewareUpdating, params: ["Reference0": currentVersion])
        emitUpdateBegin(targetType: "baseware")
        emitUpdatePipelineEvent(base: "OnUpdate", stage: "OnDownloadBegin", params: [
            "Reference0": "baseware",
            "Reference1": currentVersion
        ])
        emitUpdatePipelineEvent(base: "OnUpdate", stage: "OnMD5CompareBegin", params: [
            "Reference0": "baseware",
            "Reference1": currentVersion
        ])
        emitUpdatePipelineEvent(base: "OnUpdate", stage: "OnMD5CompareComplete", params: [
            "Reference0": "baseware",
            "Reference1": currentVersion
        ])
        EventBridge.shared.notify(.OnUpdateReady, params: [
            "Reference0": "",
            "Reference3": "baseware"
        ])
        EventBridge.shared.notify(.OnUpdateComplete, params: [
            "Reference0": "none",
            "Reference1": "",
            "Reference3": "baseware"
        ])
        EventBridge.shared.notify(.OnBasewareUpdated, params: ["Reference0": currentVersion])
        EventBridge.shared.notifyCustom("OnUpdateCheckComplete", params: [
            "Reference0": "platform",
            "Reference1": currentVersion,
            "Reference2": options.joined(separator: ",")
        ])
        emitUpdateResultEvents(
            target: "baseware",
            reason: "none",
            fileList: "",
            explorerPath: Bundle.main.bundlePath
        )
    }
    
    /// Check for updates to all ghosts
    func checkAllGhostsUpdate(options: [String]) {
        Log.info("[GhostManager] Checking for updates to all installed ghosts")
        emitUpdateBegin(targetType: "ghost")
        EventBridge.shared.notify(.OnUpdateOtherBegin, params: [
            "Reference0": "",
            "Reference1": "",
            "Reference3": "ghost"
        ])
        emitUpdatePipelineEvent(base: "OnUpdateOther", stage: "OnDownloadBegin", params: [
            "Reference0": "all",
            "Reference1": "ghost"
        ])
        emitUpdatePipelineEvent(base: "OnUpdateOther", stage: "OnMD5CompareBegin", params: [
            "Reference0": "all",
            "Reference1": "ghost"
        ])
        EventBridge.shared.notify(.OnUpdateReady, params: [
            "Reference0": "",
            "Reference3": "ghost"
        ])
        EventBridge.shared.notify(.OnUpdateOtherReady, params: [
            "Reference0": "",
            "Reference1": "",
            "Reference3": "ghost"
        ])
        EventBridge.shared.notify(.OnUpdateComplete, params: [
            "Reference0": "none",
            "Reference1": "",
            "Reference3": "ghost"
        ])
        EventBridge.shared.notify(.OnUpdateOtherComplete, params: [
            "Reference0": "none",
            "Reference1": "",
            "Reference3": "ghost"
        ])
        emitUpdatePipelineEvent(base: "OnUpdateOther", stage: "OnMD5CompareComplete", params: [
            "Reference0": "all",
            "Reference1": "ghost"
        ])
        let ghosts = NarRegistry.shared.installedGhosts()
        EventBridge.shared.notifyCustom("OnUpdateCheckComplete", params: [
            "Reference0": "all",
            "Reference1": String(ghosts.count),
            "Reference2": options.joined(separator: ",")
        ])
        emitUpdateResultEvents(
            target: "other",
            reason: "none",
            fileList: ghosts.joined(separator: ","),
            explorerPath: ((try? OurinPaths.baseDirectory().appendingPathComponent("ghost", isDirectory: true).path) ?? ghostURL.path)
        )
    }

    private func emitUpdateBegin(targetType: String) {
        EventBridge.shared.notify(.OnUpdateBegin, params: [
            "Reference0": ghostConfig?.name ?? ghostURL.lastPathComponent,
            "Reference1": ghostURL.path,
            "Reference3": targetType
        ])
    }

    private func emitUpdatePipelineEvent(base: String, stage: String, params: [String: String]) {
        EventBridge.shared.notifyCustom("\(base).\(stage)", params: params)
    }

    private func emitUpdateResultEvents(target: String, reason: String, fileList: String, explorerPath: String) {
        EventBridge.shared.notify(.OnUpdateResult, params: [
            "Reference0": reason,
            "Reference1": fileList,
            "Reference2": target
        ])
        EventBridge.shared.notify(.OnUpdateResultEx, params: [
            "Reference0": reason,
            "Reference1": fileList,
            "Reference2": target,
            "Reference3": explorerPath
        ])
        EventBridge.shared.notify(.OnUpdateResultExplorer, params: [
            "Reference0": explorerPath,
            "Reference1": target
        ])
    }

    private func normalizeUpdateFailureReason(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "timeout"
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return "404"
            default:
                break
            }
        }

        let lower = error.localizedDescription.lowercased()
        if lower.contains("timed out") {
            return "timeout"
        }
        if lower.contains("404") {
            return "404"
        }
        if lower.isEmpty {
            return "paramerror"
        }
        return error.localizedDescription
    }
    
    /// Terminate this ghost (vanish)
    func executeVanish() {
        Log.info("[GhostManager] Ghost terminating (vanish)")
        let currentName = ghostConfig?.name ?? ghostURL.lastPathComponent
        
        DispatchQueue.main.async {
            // Trigger OnVanished event first
            if let yaya = self.yayaAdapter {
                _ = yaya.request(method: "GET", id: "OnVanished")
            }
            EventBridge.shared.notify(.OnOtherGhostClosed, params: ["Reference0": currentName])
            EventBridge.shared.notify(.OnOtherGhostVanished, params: ["Reference0": currentName])
            
            // Close all windows
            for window in self.characterWindows.values {
                window.close()
            }
            for window in self.balloonWindows.values {
                window.close()
            }
            
            // Clean up resources
            self.characterWindows.removeAll()
            self.balloonWindows.removeAll()
            self.playbackQueue.removeAll()
            self.isPlaying = false
            
            Log.debug("[GhostManager] Ghost vanished successfully")
        }
    }

    func executeExtractArchive(params: [String]) {
        guard params.count >= 2 else {
            EventBridge.shared.notifyCustom("OnArchiveFailure", params: ["Reference0": "extract", "Reference1": "missing_args"])
            EventBridge.shared.notifyCustom("OnExtractArchiveFailure", params: ["Reference0": "missing_args"])
            return
        }
        let archive = resolvedPath(params[0])
        let destination = resolvedPath(params[1])
        EventBridge.shared.notifyCustom("OnExtractArchiveBegin", params: [
            "Reference0": archive.path,
            "Reference1": destination.path
        ])
        runProcess(path: "/usr/bin/ditto", arguments: ["-x", "-k", archive.path, destination.path]) { output, ok in
            let payload: [String: String] = [
                "Reference0": "extract",
                "Reference1": archive.path,
                "Reference2": destination.path,
                "Reference3": output
            ]
            EventBridge.shared.notifyCustom(ok ? "OnArchiveComplete" : "OnArchiveFailure", params: payload)
            EventBridge.shared.notifyCustom(ok ? "OnExtractArchiveComplete" : "OnExtractArchiveFailure", params: payload)
        }
    }

    func executeCompressArchive(params: [String]) {
        guard params.count >= 2 else {
            EventBridge.shared.notifyCustom("OnArchiveFailure", params: ["Reference0": "compress", "Reference1": "missing_args"])
            EventBridge.shared.notifyCustom("OnCompressArchiveFailure", params: ["Reference0": "missing_args"])
            return
        }
        let source = resolvedPath(params[0])
        let output = resolvedPath(params[1])
        EventBridge.shared.notifyCustom("OnCompressArchiveBegin", params: [
            "Reference0": source.path,
            "Reference1": output.path
        ])
        runProcess(path: "/usr/bin/ditto", arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, output.path]) { result, ok in
            let payload: [String: String] = [
                "Reference0": "compress",
                "Reference1": source.path,
                "Reference2": output.path,
                "Reference3": result
            ]
            EventBridge.shared.notifyCustom(ok ? "OnArchiveComplete" : "OnArchiveFailure", params: payload)
            EventBridge.shared.notifyCustom(ok ? "OnCompressArchiveComplete" : "OnCompressArchiveFailure", params: payload)
        }
    }

    func executeDumpSurface(params: [String]) {
        guard let image = characterViewModels[currentScope]?.image else {
            EventBridge.shared.notifyCustom("OnDumpSurfaceFailure", params: ["Reference0": "missing_surface"])
            return
        }
        let output = params.first.map(resolvedPath) ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ourin_surface_\(currentScope).png")
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            EventBridge.shared.notifyCustom("OnDumpSurfaceFailure", params: ["Reference0": "encode_failed"])
            return
        }
        do {
            try png.write(to: output)
            EventBridge.shared.notifyCustom("OnDumpSurfaceComplete", params: ["Reference0": output.path])
        } catch {
            EventBridge.shared.notifyCustom("OnDumpSurfaceFailure", params: ["Reference0": error.localizedDescription])
        }
    }

    func executeInstall(params: [String]) {
        guard let first = params.first else {
            EventBridge.shared.notifyCustom("OnInstallFailure", params: ["Reference0": "missing_target"])
            return
        }
        if first.lowercased() == "url", params.count >= 2 {
            guard let url = URL(string: params[1]) else {
                EventBridge.shared.notifyCustom("OnInstallFailure", params: ["Reference0": "invalid_url"])
                return
            }
            URLSession.shared.downloadTask(with: url) { localURL, _, error in
                if let error {
                    EventBridge.shared.notifyCustom("OnInstallFailure", params: ["Reference0": error.localizedDescription])
                    return
                }
                guard let localURL else {
                    EventBridge.shared.notifyCustom("OnInstallFailure", params: ["Reference0": "download_failed"])
                    return
                }
                self.installNarFile(localURL)
            }.resume()
            return
        }

        let pathArg = first.lowercased() == "path" && params.count >= 2 ? params[1] : first
        installNarFile(resolvedPath(pathArg))
    }

    func executeCreateNar() {
        let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(ghostURL.lastPathComponent).nar")
        EventBridge.shared.notify(.OnNarCreating, params: ["Reference0": output.path])
        runProcess(path: "/usr/bin/ditto", arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", ghostURL.path, output.path]) { result, ok in
            let payload: [String: String] = [
                "Reference0": output.path,
                "Reference1": result
            ]
            EventBridge.shared.notifyCustom(ok ? "OnCreateNarComplete" : "OnCreateNarFailure", params: payload)
            if ok {
                EventBridge.shared.notify(.OnNarCreated, params: payload)
            }
        }
    }

    func executeCreateUpdateData() {
        let updatePath = ghostURL.appendingPathComponent("updates2.dau")
        EventBridge.shared.notify(.OnUpdatedataCreating, params: ["Reference0": updatePath.path])
        let lines = [
            "; generated by Ourin",
            "version=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")",
            "url=\(resourceManager.homeurl ?? ghostConfig?.homeurl ?? "")"
        ].joined(separator: "\n")
        do {
            try lines.data(using: .utf8)?.write(to: updatePath)
            EventBridge.shared.notifyCustom("OnCreateUpdateDataComplete", params: ["Reference0": updatePath.path])
            EventBridge.shared.notify(.OnUpdatedataCreated, params: ["Reference0": updatePath.path])
        } catch {
            EventBridge.shared.notifyCustom("OnCreateUpdateDataFailure", params: ["Reference0": error.localizedDescription])
        }
    }

    func executeEmptyRecycleBin() {
        let trash = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash", isDirectory: true)
        do {
            let items = try FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)
            for item in items {
                try? FileManager.default.removeItem(at: item)
            }
            EventBridge.shared.notifyCustom("OnEmptyRecycleBinComplete", params: ["Reference0": String(items.count)])
        } catch {
            EventBridge.shared.notifyCustom("OnEmptyRecycleBinFailure", params: ["Reference0": error.localizedDescription])
        }
    }

    func executePing(params: [String]) {
        let host = params.first ?? "localhost"
        EventBridge.shared.notify(.OnPingProgress, params: [
            "Reference0": host,
            "Reference1": "0"
        ])
        runProcess(path: "/sbin/ping", arguments: ["-c", "1", host]) { output, ok in
            if ok {
                EventBridge.shared.notify(.OnPingComplete, params: [
                    "Reference0": host,
                    "Reference1": output
                ])
            } else {
                EventBridge.shared.notifyCustom("OnPingFailure", params: [
                    "Reference0": host,
                    "Reference1": output
                ])
            }
            EventBridge.shared.notify(.OnPingProgress, params: [
                "Reference0": host,
                "Reference1": "100",
                "Reference2": ok ? "ok" : "failed"
            ])
        }
    }

    func executeNslookup(params: [String]) {
        let host = params.first ?? "localhost"
        runProcess(path: "/usr/bin/nslookup", arguments: [host]) { output, ok in
            EventBridge.shared.notify(ok ? .OnNSLookupComplete : .OnNSLookupFailure, params: [
                "Reference0": host,
                "Reference1": output
            ])
        }
    }

    private func applyRequestOptions(_ parsed: (positionals: [String], options: [String: String], flags: Set<String>), to request: inout URLRequest) {
        if let timeoutStr = parsed.options["timeout"], let timeout = TimeInterval(timeoutStr), timeout > 0 {
            request.timeoutInterval = timeout
        }

        if let headerLine = parsed.options["header"], let separator = headerLine.firstIndex(of: ":") {
            let key = String(headerLine[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(headerLine[headerLine.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        if let headers = parsed.options["headers"] {
            for pair in headers.split(separator: "|") {
                let token = String(pair)
                guard let separator = token.firstIndex(of: ":") else { continue }
                let key = String(token[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(token[token.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
        }
    }

    func executeCreateShortcut(params: [String]) {
        guard params.count >= 2 else {
            EventBridge.shared.notifyCustom("OnCreateShortcutFailure", params: ["Reference0": "missing_args"])
            return
        }
        let target = resolvedPath(params[0])
        let link = resolvedPath(params[1])
        do {
            try? FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            EventBridge.shared.notifyCustom("OnCreateShortcutComplete", params: ["Reference0": link.path])
        } catch {
            EventBridge.shared.notifyCustom("OnCreateShortcutFailure", params: ["Reference0": error.localizedDescription])
        }
    }

    func executeReloadSurface() {
        let current = characterViewModels[currentScope]?.currentSurfaceID ?? 0
        updateSurface(id: current)
        EventBridge.shared.notifyCustom("OnSurfaceReloaded", params: ["Reference0": String(current)])
    }

    func executeReload(target: String, params: [String]) {
        switch target.lowercased() {
        case "descript":
            let parsed = parseCommandArguments(params)
            let descriptorTarget = (parsed.positionals.first ?? parsed.options["target"] ?? "ghost").lowercased()
            let ghostRoot = ghostURL.appendingPathComponent("ghost/master", isDirectory: true)

            if descriptorTarget == "ghost" || descriptorTarget == "all" {
                if let config = GhostConfiguration.load(from: ghostRoot) {
                    ghostConfig = config
                    applyGhostConfiguration(config, ghostRoot: ghostRoot)
                }
            }

            if descriptorTarget == "shell" || descriptorTarget == "all" {
                executeReloadSurface()
            }

            if descriptorTarget == "balloon" || descriptorTarget == "all" {
                let baseBalloonDir = ghostURL.appendingPathComponent("balloon", isDirectory: true)
                let preferred = parsed.options["name"] ?? parsed.options["balloon"] ?? ""
                let balloonDir = preferred.isEmpty ? baseBalloonDir : baseBalloonDir.appendingPathComponent(preferred, isDirectory: true)
                let descriptPath = balloonDir.appendingPathComponent("descript.txt").path
                if let config = BalloonConfig.load(from: descriptPath) {
                    balloonConfig = config
                    balloonImageLoader = BalloonImageLoader(balloonPath: balloonDir.path)
                }
            }
            EventBridge.shared.notifyCustom("OnDescriptReloaded", params: ["Reference0": descriptorTarget, "Reference1": params.joined(separator: ",")])
        case "shell", "balloon", "ghost", "aigraph":
            executeReloadSurface()
        case "shiori", "makoto":
            executeLoad(target: target)
        default:
            break
        }
    }

    func executeUnload(target: String) {
        let lowered = target.lowercased()
        if lowered == "shiori" || lowered == "makoto" {
            yayaAdapter?.unload()
            yayaAdapter = nil
            EventBridge.shared.notifyCustom("OnShioriUnloaded", params: ["Reference0": lowered])
        }
    }

    func executeLoad(target: String) {
        let lowered = target.lowercased()
        guard lowered == "shiori" || lowered == "makoto" else { return }
        guard yayaAdapter == nil else { return }
        let ghostRoot = ghostURL.appendingPathComponent("ghost/master", isDirectory: true)
        let dics = (try? FileManager.default.contentsOfDirectory(at: ghostRoot, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "dic" }
            .map(\.lastPathComponent) ?? []
        guard let adapter = YayaAdapter() else {
            EventBridge.shared.notifyCustom("OnShioriLoadFailure", params: ["Reference0": lowered])
            return
        }
        if adapter.load(ghostRoot: ghostRoot, dics: dics) {
            yayaAdapter = adapter
            EventBridge.shared.notifyCustom("OnShioriLoaded", params: ["Reference0": lowered, "Reference1": String(dics.count)])
        } else {
            EventBridge.shared.notifyCustom("OnShioriLoadFailure", params: ["Reference0": lowered])
        }
    }

    func decodeScalarLiteral(_ raw: String?) -> UnicodeScalar? {
        guard var token = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else { return nil }
        if token.hasPrefix("0x") || token.hasPrefix("0X") {
            token = String(token.dropFirst(2))
        }
        guard let value = UInt32(token, radix: 16) else { return nil }
        return UnicodeScalar(value)
    }

    private func installNarFile(_ narURL: URL) {
        do {
            let installed = try NarInstaller().install(fromNar: narURL)
            EventBridge.shared.notifyCustom("OnInstallComplete", params: ["Reference0": installed.path])
        } catch {
            EventBridge.shared.notifyCustom("OnInstallFailure", params: ["Reference0": error.localizedDescription])
        }
    }

    private func runProcess(path: String, arguments: [String], completion: @escaping (String, Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            do {
                try process.run()
                process.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                completion(text, process.terminationStatus == 0)
            } catch {
                completion(error.localizedDescription, false)
            }
        }
    }

    private func resolvedPath(_ rawPath: String) -> URL {
        if rawPath.hasPrefix("/") {
            return URL(fileURLWithPath: rawPath)
        }
        return ghostURL.appendingPathComponent(rawPath)
    }

    func postSystemMessage(title: String, body: String, level: String) {
        let finalTitle = title.isEmpty ? NSLocalizedString("System Message", comment: "system message title") : title
        let content = UNMutableNotificationContent()
        content.title = finalTitle
        content.body = body
        content.userInfo = [
            "ourinSystemMessage": "1",
            "level": level
        ]
        let request = UNNotificationRequest(identifier: "ourin.system.\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.info("[GhostManager] Failed to post system message: \(error.localizedDescription)")
            }
        }
        EventBridge.shared.notifyCustom("OnSystemMessage", params: [
            "Reference0": finalTitle,
            "Reference1": body,
            "Reference2": level
        ])
    }

    func setClipboardText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        EventBridge.shared.notifyCustom("OnClipboardWrite", params: ["Reference0": text])
    }

    func getClipboardText() -> String {
        let pasteboard = NSPasteboard.general
        return pasteboard.string(forType: .string) ?? ""
    }

    func clearClipboard() {
        NSPasteboard.general.clearContents()
        EventBridge.shared.notifyCustom("OnClipboardClear", params: [:])
    }

    // MARK: - Change / Open Command Helpers

    func parseCommandArguments(_ args: [String]) -> (positionals: [String], options: [String: String], flags: Set<String>) {
        var positionals: [String] = []
        var options: [String: String] = [:]
        var flags: Set<String> = []

        for arg in args {
            let trimmed = arg.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("--") {
                let body = String(trimmed.dropFirst(2))
                if let eq = body.firstIndex(of: "=") {
                    let key = String(body[..<eq]).lowercased()
                    let value = String(body[body.index(after: eq)...])
                    options[key] = value
                } else {
                    flags.insert(body.lowercased())
                }
            } else {
                positionals.append(trimmed)
            }
        }

        return (positionals, options, flags)
    }

    func switchGhost(named target: String, options: [String]) {
        let normalized = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let parsed = parseCommandArguments(options)
        let raiseEvent = parsed.options["option"]?.lowercased() == "raise-event" || parsed.flags.contains("option=raise-event")

        let previous = ghostConfig?.name ?? ""
        if raiseEvent {
            EventBridge.shared.notify(.OnGhostChanging, params: [
                "Reference0": normalized,
                "Reference1": previous
            ])
        }

        switch normalized.lowercased() {
        case "random":
            bootOtherGhost(name: nil)
        case "sequential":
            // Sequential order is baseware-managed; fallback to standard boot trigger.
            bootOtherGhost(name: nil)
        default:
            bootOtherGhost(name: normalized)
        }

        EventBridge.shared.notify(.OnGhostChanged, params: [
            "Reference0": previous,
            "Reference1": normalized
        ])
        EventBridge.shared.notify(.OnOtherGhostChanged, params: [
            "Reference0": previous,
            "Reference1": normalized
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.executeVanish()
        }
    }

    func callGhost(named target: String, options: [String]) {
        let normalized = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let parsed = parseCommandArguments(options)
        let raiseEvent = parsed.options["option"]?.lowercased() == "raise-event" || parsed.flags.contains("option=raise-event")

        if raiseEvent {
            EventBridge.shared.notify(.OnGhostCalling, params: ["Reference0": normalized])
        }

        switch normalized.lowercased() {
        case "random":
            bootOtherGhost(name: nil)
        default:
            bootOtherGhost(name: normalized)
        }

        EventBridge.shared.notify(.OnGhostCalled, params: ["Reference0": normalized])
        EventBridge.shared.notify(.OnGhostCallComplete, params: ["Reference0": normalized])
    }

    // MARK: - Dialog Commands

    func handleGhostTermsConsent() {
        let ghostName = ghostConfig?.name ?? ghostURL.lastPathComponent
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("利用規約", comment: "ghost terms title")
        alert.informativeText = NSLocalizedString("このゴーストの利用規約を確認しますか？", comment: "ghost terms message")
        alert.addButton(withTitle: NSLocalizedString("同意して開く", comment: "accept terms"))
        alert.addButton(withTitle: NSLocalizedString("拒否", comment: "decline terms"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            EventBridge.shared.notify(.OnGhostTermsAccept, params: ["Reference0": ghostName])
            openFilePath("terms.txt")
        } else {
            EventBridge.shared.notify(.OnGhostTermsDecline, params: ["Reference0": ghostName])
        }
    }

    func showInputBoxDialog(id: String, timeoutMs: Int?, initialText: String) {
        _ = requestDialogEvent(eventID: "OnInputbox.autocomplete", references: [id, initialText])
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Input", comment: "input dialog title")
        alert.informativeText = NSLocalizedString("Please enter text.", comment: "input dialog message")
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.stringValue = initialText
        alert.accessoryView = textField
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))

        var timedOut = false
        let timer = scheduleModalTimeout(timeoutMs: timeoutMs) { timedOut = true }
        let response = alert.runModal()
        timer?.invalidate()

        if response == .alertFirstButtonReturn {
            let value = textField.stringValue
            emitUserInput(id: id, value: value)
        } else {
            emitUserInputCancel(id: id, timedOut: timedOut)
        }
    }

    func showPasswordInputDialog(id: String, timeoutMs: Int?, initialText: String) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Password Input", comment: "password input title")
        alert.informativeText = NSLocalizedString("Please enter password.", comment: "password input message")
        alert.alertStyle = .informational

        let textField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.stringValue = initialText
        alert.accessoryView = textField
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))

        var timedOut = false
        let timer = scheduleModalTimeout(timeoutMs: timeoutMs) { timedOut = true }
        let response = alert.runModal()
        timer?.invalidate()

        if response == .alertFirstButtonReturn {
            emitUserInput(id: id, value: textField.stringValue)
        } else {
            emitUserInputCancel(id: id, timedOut: timedOut)
        }
    }

    func showDateInputDialog(id: String, timeoutMs: Int?, year: Int?, month: Int?, day: Int?) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Date Input", comment: "date input title")
        alert.alertStyle = .informational

        let now = Date()
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: now)
        comps.year = year ?? comps.year
        comps.month = month ?? comps.month
        comps.day = day ?? comps.day
        let date = Calendar.current.date(from: comps) ?? now

        let datePicker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.yearMonthDay]
        datePicker.dateValue = date
        alert.accessoryView = datePicker
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))

        var timedOut = false
        let timer = scheduleModalTimeout(timeoutMs: timeoutMs) { timedOut = true }
        let response = alert.runModal()
        timer?.invalidate()

        if response == .alertFirstButtonReturn {
            let selectedComps = Calendar.current.dateComponents([.year, .month, .day], from: datePicker.dateValue)
            let value = "\(selectedComps.year ?? 0),\(selectedComps.month ?? 0),\(selectedComps.day ?? 0)"
            emitUserInput(id: id, value: value)
        } else {
            emitUserInputCancel(id: id, timedOut: timedOut)
        }
    }

    func showSliderInputDialog(id: String, timeoutMs: Int?, initial: Double?, min: Double?, max: Double?) {
        let minValue = min ?? 0
        let maxValue = max ?? 100
        let startValue = initial ?? minValue

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Slider Input", comment: "slider input title")
        alert.alertStyle = .informational

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 56))
        let slider = NSSlider(value: startValue, minValue: minValue, maxValue: maxValue, target: nil, action: nil)
        slider.frame = NSRect(x: 0, y: 24, width: 320, height: 24)
        let valueLabel = NSTextField(labelWithString: String(format: "%.2f", startValue))
        valueLabel.frame = NSRect(x: 0, y: 0, width: 320, height: 20)
        slider.target = valueLabel
        slider.action = #selector(NSTextField.takeDoubleValueFrom(_:))
        container.addSubview(slider)
        container.addSubview(valueLabel)
        alert.accessoryView = container

        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))

        var timedOut = false
        let timer = scheduleModalTimeout(timeoutMs: timeoutMs) { timedOut = true }
        let response = alert.runModal()
        timer?.invalidate()

        if response == .alertFirstButtonReturn {
            emitUserInput(id: id, value: String(slider.doubleValue))
        } else {
            emitUserInputCancel(id: id, timedOut: timedOut)
        }
    }

    func showTimeInputDialog(id: String, timeoutMs: Int?, hour: Int?, minute: Int?, second: Int?) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Time Input", comment: "time input title")
        alert.alertStyle = .informational

        let now = Date()
        var comps = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
        comps.hour = hour ?? comps.hour
        comps.minute = minute ?? comps.minute
        comps.second = second ?? comps.second
        let date = Calendar.current.date(from: comps) ?? now

        let timePicker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        timePicker.datePickerStyle = .textFieldAndStepper
        timePicker.datePickerElements = [.hourMinuteSecond]
        timePicker.dateValue = date
        alert.accessoryView = timePicker
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))

        var timedOut = false
        let timer = scheduleModalTimeout(timeoutMs: timeoutMs) { timedOut = true }
        let response = alert.runModal()
        timer?.invalidate()

        if response == .alertFirstButtonReturn {
            let selectedComps = Calendar.current.dateComponents([.hour, .minute, .second], from: timePicker.dateValue)
            let value = "\(selectedComps.hour ?? 0),\(selectedComps.minute ?? 0),\(selectedComps.second ?? 0)"
            emitUserInput(id: id, value: value)
        } else {
            emitUserInputCancel(id: id, timedOut: timedOut)
        }
    }

    func showIPInputDialog(id: String, timeoutMs: Int?, initialText: String) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("IP Input", comment: "ip input title")
        alert.informativeText = NSLocalizedString("Please enter IP address.", comment: "ip input message")
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.stringValue = initialText
        alert.accessoryView = textField
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))

        var timedOut = false
        let timer = scheduleModalTimeout(timeoutMs: timeoutMs) { timedOut = true }
        let response = alert.runModal()
        timer?.invalidate()

        if response == .alertFirstButtonReturn {
            emitUserInput(id: id, value: textField.stringValue)
        } else {
            emitUserInputCancel(id: id, timedOut: timedOut)
        }
    }

    func showChoiceInputDialog(id: String, timeoutMs: Int?, choices: [String]) {
        let sanitized = choices.filter { !$0.isEmpty }
        guard !sanitized.isEmpty else {
            emitUserInputCancel(id: id, timedOut: false)
            return
        }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Choice Input", comment: "choice input title")
        alert.alertStyle = .informational
        for item in sanitized {
            alert.addButton(withTitle: item)
        }
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))

        var timedOut = false
        let timer = scheduleModalTimeout(timeoutMs: timeoutMs) { timedOut = true }
        let response = alert.runModal()
        timer?.invalidate()

        let buttonIndex = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if buttonIndex >= 0 && buttonIndex < sanitized.count {
            emitUserInput(id: id, value: sanitized[buttonIndex])
        } else {
            emitUserInputCancel(id: id, timedOut: timedOut)
        }
    }

    func showSystemDialog(type: String, parameters: [String]) {
        let parsed = parseCommandArguments(parameters)
        let eventID = parsed.options["id"] ?? ""

        switch type {
        case "open", "folder":
            let panel = NSOpenPanel()
            panel.canChooseFiles = (type == "open")
            panel.canChooseDirectories = (type == "folder")
            panel.allowsMultipleSelection = false
            if let title = parsed.options["title"] { panel.title = title }
            if let path = parsed.options["dir"] { panel.directoryURL = URL(fileURLWithPath: path) }
            if panel.runModal() == .OK, let url = panel.url {
                emitSystemDialog(type: type, eventID: eventID, value: url.path)
            } else {
                emitSystemDialogCancel(type: type, eventID: eventID)
            }
        case "save":
            let panel = NSSavePanel()
            if let title = parsed.options["title"] { panel.title = title }
            if let path = parsed.options["dir"] { panel.directoryURL = URL(fileURLWithPath: path) }
            if let name = parsed.options["name"] { panel.nameFieldStringValue = name }
            if panel.runModal() == .OK, let url = panel.url {
                emitSystemDialog(type: type, eventID: eventID, value: url.path)
            } else {
                emitSystemDialogCancel(type: type, eventID: eventID)
            }
        case "color":
            let panel = NSColorPanel.shared
            if let colorSpec = parsed.options["color"] {
                let rgb = colorSpec.split(separator: " ").compactMap { Double($0) }
                if rgb.count == 3 {
                    panel.color = NSColor(red: rgb[0] / 255.0, green: rgb[1] / 255.0, blue: rgb[2] / 255.0, alpha: 1.0)
                }
            }
            panel.makeKeyAndOrderFront(nil)
            let rgb = panel.color.usingColorSpace(.deviceRGB) ?? panel.color
            let value = "\(Int(rgb.redComponent * 255)),\(Int(rgb.greenComponent * 255)),\(Int(rgb.blueComponent * 255))"
            emitSystemDialog(type: type, eventID: eventID, value: value)
        default:
            Log.info("[GhostManager] Unsupported system dialog type: \(type)")
        }
    }

    func showTeachBoxDialog() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Teach", comment: "teachbox title")
        alert.informativeText = NSLocalizedString("Enter text to teach.", comment: "teachbox message")
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        alert.accessoryView = textField
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let value = textField.stringValue
            requestDialogEvent(eventID: "OnTeach", references: [value])
        } else {
            requestDialogEvent(eventID: "OnTeachInputCancel", references: [])
        }
    }

    func showCommunicateBoxDialog(timeoutMs: Int?, initialText: String) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Communicate", comment: "communicatebox title")
        alert.informativeText = NSLocalizedString("Enter text to communicate.", comment: "communicatebox message")
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.stringValue = initialText
        alert.accessoryView = textField
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))

        var timedOut = false
        let timer = scheduleModalTimeout(timeoutMs: timeoutMs) { timedOut = true }
        let response = alert.runModal()
        timer?.invalidate()

        if response == .alertFirstButtonReturn {
            _ = requestDialogEvent(eventID: "OnCommunicate", references: [textField.stringValue])
        } else {
            emitCommunicateInputCancel(timedOut: timedOut)
        }
    }

    func emitUserInput(id: String, value: String) {
        if id.lowercased().hasPrefix("on") {
            _ = requestDialogEvent(eventID: id, references: [value])
        } else {
            _ = requestDialogEvent(eventID: "OnUserInput", references: [id, value])
        }
    }

    func emitUserInputCancel(id: String, timedOut: Bool) {
        let handled = requestDialogEvent(eventID: "OnUserInputCancel", references: [id])
        if timedOut && !handled {
            _ = requestDialogEvent(eventID: "OnUserInput", references: [id, "timeout"])
        }
    }

    func emitSystemDialog(type: String, eventID: String, value: String) {
        let refs = [type, eventID, value]
        if eventID.lowercased().hasPrefix("on") {
            _ = requestDialogEvent(eventID: eventID, references: refs)
        } else {
            _ = requestDialogEvent(eventID: "OnSystemDialog", references: refs)
        }
    }

    func emitSystemDialogCancel(type: String, eventID: String) {
        let refs = [type, eventID]
        if eventID.lowercased().hasPrefix("on") {
            _ = requestDialogEvent(eventID: eventID, references: refs)
        } else {
            _ = requestDialogEvent(eventID: "OnSystemDialogCancel", references: refs)
        }
    }

    func emitCommunicateInputCancel(timedOut: Bool) {
        let handled = requestDialogEvent(eventID: "OnCommunicateInputCancel", references: [])
        if timedOut && !handled {
            _ = requestDialogEvent(eventID: "OnCommunicate", references: ["timeout"])
        }
    }

    func enterSelectMode(params: [String]) {
        selectModeActive = true
        var payload: [String: String] = [:]
        for (index, value) in params.enumerated() {
            payload["Reference\(index)"] = value
        }
        EventBridge.shared.notify(.OnSelectModeBegin, params: payload)
    }

    func leaveSelectMode(params: [String]) {
        guard selectModeActive else {
            EventBridge.shared.notify(.OnSelectModeCancel, params: [:])
            return
        }
        selectModeActive = false
        var payload: [String: String] = ["Reference0": "0,0,0,0"]
        for (index, value) in params.enumerated() {
            payload["Reference\(index + 1)"] = value
        }
        EventBridge.shared.notify(.OnSelectModeComplete, params: payload)
    }

    func enterCollisionMode() {
        collisionModeActive = true
    }

    func leaveCollisionMode() {
        collisionModeActive = false
    }

    func enterPassiveMode() {
        passiveModeActive = true
        EventBridge.shared.notifyCustom("OnPassiveModeBegin", params: [:])
    }

    func leavePassiveMode() {
        passiveModeActive = false
        EventBridge.shared.notifyCustom("OnPassiveModeEnd", params: [:])
    }

    func enterInductionMode(params: [String]) {
        inductionModeActive = true
        var payload: [String: String] = [:]
        for (index, value) in params.enumerated() {
            payload["Reference\(index)"] = value
        }
        EventBridge.shared.notifyCustom("OnInductionModeBegin", params: payload)
    }

    func leaveInductionMode() {
        inductionModeActive = false
        EventBridge.shared.notifyCustom("OnInductionModeEnd", params: [:])
    }

    func enterNoUserBreakMode() {
        noUserBreakModeActive = true
        EventBridge.shared.notifyCustom("OnNoUserBreakModeBegin", params: [:])
    }

    func leaveNoUserBreakMode() {
        noUserBreakModeActive = false
        EventBridge.shared.notifyCustom("OnNoUserBreakModeEnd", params: [:])
    }

    func setBalloonMarker(_ marker: String) {
        DispatchQueue.main.async {
            guard let vm = self.balloonViewModels[self.currentScope] else { return }
            vm.balloonMarkerText = marker
        }
    }

    func setBalloonNumberDisplay(enabled: Bool) {
        DispatchQueue.main.async {
            guard let vm = self.balloonViewModels[self.currentScope] else { return }
            vm.balloonNumberVisible = enabled
        }
    }

    func setSerikoTalk(mode: String) {
        let enabled = mode.lowercased() == "1" || mode.lowercased() == "true" || mode.lowercased() == "on"
        UserDefaults.standard.set(enabled, forKey: "OurinSerikoTalkEnabled")
        EventBridge.shared.notifyCustom("OnSerikoTalkChanged", params: ["Reference0": enabled ? "1" : "0"])
    }

    func openDeveloperTool(_ tool: String) {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.showDevTools()
            NotificationCenter.default.post(name: .devToolsReload, object: tool)
        }
    }

    @discardableResult
    func requestDialogEvent(eventID: String, references: [String]) -> Bool {
        guard !eventID.isEmpty else { return false }
        if let response = yayaAdapter?.request(method: "GET", id: eventID, refs: references, timeout: 4.0),
           response.ok,
           let script = response.value,
           !script.isEmpty {
            runNotifyScript(script)
            return true
        } else {
            var params: [String: String] = [:]
            for (index, value) in references.enumerated() {
                params["Reference\(index)"] = value
            }
            EventBridge.shared.notifyCustom(eventID, params: params)
            return false
        }
    }

    private func scheduleModalTimeout(timeoutMs: Int?, onTimeout: @escaping () -> Void) -> Timer? {
        guard let timeoutMs, timeoutMs > 0 else { return nil }
        let timeoutSec = TimeInterval(timeoutMs) / 1000.0
        return Timer.scheduledTimer(withTimeInterval: timeoutSec, repeats: false) { _ in
            onTimeout()
            NSApp.abortModal()
        }
    }
    
}

private extension String {
    func matches(for pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let nsrange = NSRange(startIndex..., in: self)
        return regex.matches(in: self, options: [], range: nsrange).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: self) else {
                return nil
            }
            return String(self[range])
        }
    }
}
