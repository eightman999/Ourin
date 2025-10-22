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
        // If no name provided, try to boot a random available ghost
        // In a real implementation, this would query FMO for available ghosts
        // For now, we'll send a generic SSTP NOTIFY to localhost
        
        let ghostName = name ?? "default"
        Log.debug("[GhostManager] Attempting to boot ghost: \(ghostName)")
        
        // Send SSTP NOTIFY to localhost
        sendSSTPNotify(event: "OnBoot", references: ["Reference0": ghostName])
    }
    
    /// Boot all ghosts by broadcasting SSTP
    func bootAllGhosts() {
        Log.debug("[GhostManager] Broadcasting boot command to all ghosts")
        
        // Send broadcast SSTP NOTIFY
        sendSSTPNotify(event: "OnBootAll", references: [:])
    }
    
    /// Send an SSTP NOTIFY request
    func sendSSTPNotify(event: String, references: [String: String]) {
        DispatchQueue.global(qos: .utility).async {
            // Construct SSTP NOTIFY request
            var request = "NOTIFY SSTP/1.1\r\n"
            request += "Sender: Ourin\r\n"
            request += "Event: \(event)\r\n"
            request += "Charset: UTF-8\r\n"
            
            // Add references
            for (key, value) in references.sorted(by: { $0.key < $1.key }) {
                request += "\(key): \(value)\r\n"
            }
            request += "\r\n"
            
            // Try to send to localhost:9801 (default SSTP port)
            self.sendSSTPToLocalhost(request: request)
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
    
    /// Display choice dialog when choices are ready
    func showChoiceDialog() {
        guard !pendingChoices.isEmpty else { return }
        
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
            if let timeout = self.choiceTimeout, timeout > 0 {
                let startTime = Date()
                alert.informativeText = String(format: NSLocalizedString("残り時間: %.0f秒", comment: "time remaining"), timeout)
                
                timeoutTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                    let elapsed = Date().timeIntervalSince(startTime)
                    let remaining = max(0, timeout - elapsed)
                    
                    if remaining <= 0 {
                        timer.invalidate()
                        // Auto-select first choice on timeout
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
            
            if buttonIndex >= 0 && buttonIndex < self.pendingChoices.count {
                // User selected a choice
                let choice = self.pendingChoices[buttonIndex]
                
                switch choice.action {
                case .event(let id, _):
                    // Trigger event
                    if let response = self.yayaAdapter?.request(method: "GET", id: id, timeout: 4.0), response.ok {
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
            self.choiceTimeout = nil
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
        
        for option in options {
            let parts = option.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].lowercased()
                let value = String(parts[1])
                switch key {
                case "title": title = value
                case "message", "text": message = value
                case "sound": sound = value.lowercased() != "false"
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

            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    Log.info("[GhostManager] Failed to deliver notification: \(error)")
                } else {
                    Log.debug("[GhostManager] Delivered notification: \(title) - \(message)")
                }
            }
        }
    }
    
    /// Set other ghost talk mode
    func setOtherGhostTalk(mode: String) {
        // Store setting for whether to show other ghosts' conversations
        // Options: true, false, before, after
        Log.debug("[GhostManager] Set other ghost talk mode: \(mode)")
        // TODO: Store in user preferences and implement filtering
    }
    
    /// Set whether to observe other ghosts' surface changes
    func setOtherSurfaceChange(enabled: Bool) {
        Log.debug("[GhostManager] Set other surface change observation: \(enabled)")
        // TODO: Subscribe/unsubscribe from SSTP surface change notifications
    }
    
    /// Execute SNTP time synchronization
    func executeSNTP() {
        Log.debug("[GhostManager] Executing SNTP time synchronization")
        // TODO: Implement SNTP client to sync system time
        DispatchQueue.global(qos: .utility).async {
            // Would connect to NTP server and sync time
            // For now, just log the request
            Log.info("[GhostManager] SNTP sync requested (not yet implemented)")
        }
    }
    
    /// Execute headline (RSS feed check)
    func executeHeadline(name: String) {
        Log.debug("[GhostManager] Executing headline check: \(name)")
        // TODO: Fetch RSS feed specified in headline configuration
        DispatchQueue.global(qos: .utility).async {
            // Would fetch RSS/Atom feed and trigger OnHeadline event
            Log.info("[GhostManager] Headline check for '\(name)' (not yet implemented)")
        }
    }
    
    /// Execute mail check (biff)
    func executeBiff() {
        Log.debug("[GhostManager] Executing mail check (biff)")
        // TODO: Check configured mail accounts for new messages
        DispatchQueue.global(qos: .utility).async {
            // Would check POP3/IMAP servers and trigger OnBIFF event
            Log.info("[GhostManager] Mail check requested (not yet implemented)")
        }
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
        guard let updateURL = ghostConfig?.homeurl else {
            Log.info("[GhostManager] No update URL configured for ghost")
            return
        }
        
        Log.info("[GhostManager] Checking for ghost updates at: \(updateURL)")
        // TODO: Fetch update.txt/updates2.dau, compare versions, download if needed
        // Trigger OnUpdateReady or OnUpdateComplete events
    }
    
    /// Check for platform (Ourin) updates
    func checkPlatformUpdate(options: [String]) {
        Log.info("[GhostManager] Checking for Ourin platform updates")
        // TODO: Check GitHub releases or update server for new Ourin versions
    }
    
    /// Check for updates to all ghosts
    func checkAllGhostsUpdate(options: [String]) {
        Log.info("[GhostManager] Checking for updates to all installed ghosts")
        // TODO: Enumerate all ghosts and check their update URLs
    }
    
    /// Terminate this ghost (vanish)
    func executeVanish() {
        Log.info("[GhostManager] Ghost terminating (vanish)")
        
        DispatchQueue.main.async {
            // Trigger OnVanished event first
            if let yaya = self.yayaAdapter {
                _ = yaya.request(method: "GET", id: "OnVanished")
            }
            
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
    
}
