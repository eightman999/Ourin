import SwiftUI
import AppKit
import CoreImage
import Combine
import UserNotifications


// MARK: - Display Settings and Desktop Alignment

extension GhostManager {
    // MARK: - Ghost Configuration Application

    /// Apply ghost configuration settings loaded from descript.txt
    func applyGhostConfiguration(_ config: GhostConfiguration, ghostRoot: URL) {
        Log.debug("[GhostManager] Applying ghost configuration...")

        // Store homeurl in ResourceManager if specified
        if let homeurl = config.homeurl {
            resourceManager.homeurl = homeurl
            Log.debug("[GhostManager]   - Set homeurl: \(homeurl)")
        }

        // Apply default surface positions if specified
        if let sakuraX = config.sakuraDefaultX {
            resourceManager.sakuraDefaultX = sakuraX
        }
        if let sakuraY = config.sakuraDefaultY {
            resourceManager.sakuraDefaultY = sakuraY
        }
        if let keroX = config.keroDefaultX {
            resourceManager.keroDefaultX = keroX
        }
        if let keroY = config.keroDefaultY {
            resourceManager.keroDefaultY = keroY
        }

        // Apply default display positions if specified and alignment is free
        let sakuraAlignmentIsFree = (config.sakuraAlignment ?? config.alignmentToDesktop) == .free
        let keroAlignmentIsFree = (config.keroAlignment ?? config.alignmentToDesktop) == .free

        if sakuraAlignmentIsFree {
            if let left = config.sakuraDefaultLeft {
                resourceManager.sakuraDefaultLeft = left
            }
            if let top = config.sakuraDefaultTop {
                resourceManager.sakuraDefaultTop = top
            }
        }

        if keroAlignmentIsFree {
            if let left = config.keroDefaultLeft {
                resourceManager.keroDefaultLeft = left
            }
            if let top = config.keroDefaultTop {
                resourceManager.keroDefaultTop = top
            }
        }

        // Apply additional character positions
        for (charNum, x) in config.charDefaultX {
            if let key = "char\(charNum).defaultx" as String? {
                resourceManager.set(key, value: String(x))
            }
        }
        for (charNum, y) in config.charDefaultY {
            if let key = "char\(charNum).defaulty" as String? {
                resourceManager.set(key, value: String(y))
            }
        }
        for (charNum, left) in config.charDefaultLeft {
            resourceManager.setCharDefaultLeft(scope: charNum, value: left)
        }
        for (charNum, top) in config.charDefaultTop {
            resourceManager.setCharDefaultTop(scope: charNum, value: top)
        }

        // Note: Other configuration values are used directly when needed:
        // - SHIORI settings (shiori, shioriVersion, etc.) are used by adapter loading
        // - Surface defaults are used by SERIKO engine
        // - SSTP settings are used by SSTP server
        // - UI settings (cursors, icons) are applied when creating UI elements
        // - Balloon settings are used by balloon system

        Log.debug("[GhostManager] Ghost configuration applied successfully")
    }

    // MARK: - Configuration Dialog

    func showNameInputDialog() {
        let alert = NSAlert()
        alert.messageText = "あなたのお名前は？"
        alert.informativeText = "お名前を入力してください"
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = "名前"

        // Load existing name from UserDefaults if available
        let defaults = UserDefaults.standard
        if let savedName = defaults.string(forKey: "OurinUserName") {
            textField.stringValue = savedName
        }

        alert.accessoryView = textField
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "キャンセル")

        alert.window.initialFirstResponder = textField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let userName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !userName.isEmpty {
                // Save to both UserDefaults (legacy) and ResourceManager
                defaults.set(userName, forKey: "OurinUserName")
                resourceManager.username = userName
                sakuraEngine.envExpander.username = userName
                Log.info("[GhostManager] User name set to: \(userName)")

                // Notify YAYA of the name change via NOTIFY OnNameChanged
                EventBridge.shared.notify(.OnNameChanged, params: ["Reference0": userName])

                // After OnNameChanged is sent, start timer events (OnIdle, SecondChange)
                startEventBridgeIfNeeded(enableAutoEvents: true)
            }
        }
    }
    
    // MARK: - Sound Playback
    
    /// Play a sound file from the ghost's sound directory
    func playSound(filename: String) {
        guard !filename.isEmpty else { return }
        
        // Resolve sound file path relative to ghost directory
        let soundPath = ghostURL.appendingPathComponent("sound").appendingPathComponent(filename)
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: soundPath.path) else {
            Log.info("[GhostManager] Sound file not found: \(soundPath.path)")
            return
        }
        
        // Play sound using NSSound
        DispatchQueue.global(qos: .userInitiated).async {
            if let sound = NSSound(contentsOf: soundPath, byReference: false) {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.currentSounds.append(sound)
                    sound.play()
                    Log.debug("[GhostManager] Playing sound: \(filename)")
                }
            } else {
                Log.info("[GhostManager] Failed to load sound: \(filename)")
            }
        }
    }
    
    /// Stop all currently playing sounds
    func stopAllSounds() {
        for sound in currentSounds {
            if sound.isPlaying {
                sound.stop()
            }
        }
        currentSounds.removeAll()
        Log.debug("[GhostManager] Stopped all sounds")
    }
    
    // MARK: - URL and Email Handling
    
    /// Open a URL in the default browser
    func openURL(_ urlString: String) {
        guard !urlString.isEmpty else {
            Log.info("[GhostManager] Empty URL string")
            return
        }
        
        // Ensure URL has a scheme
        var finalURL = urlString
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            finalURL = "https://" + urlString
        }
        
        guard let url = URL(string: finalURL) else {
            Log.info("[GhostManager] Invalid URL: \(urlString)")
            return
        }
        
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
            Log.debug("[GhostManager] Opened URL: \(finalURL)")
        }
    }
    
    /// Open email client with the specified email address
    func openEmail(_ emailAddress: String) {
        guard !emailAddress.isEmpty else {
            Log.info("[GhostManager] Empty email address")
            return
        }
        
        // Create mailto URL
        let mailtoString = emailAddress.hasPrefix("mailto:") ? emailAddress : "mailto:\(emailAddress)"
        
        guard let url = URL(string: mailtoString) else {
            Log.info("[GhostManager] Invalid email address: \(emailAddress)")
            return
        }
        
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
            Log.debug("[GhostManager] Opened email client for: \(emailAddress)")
        }
    }
    
    // MARK: - Desktop Alignment
    
    /// Enforce desktop alignment constraints
    func enforceDesktopAlignment(for scope: Int) {
        guard let vm = characterViewModels[scope],
              let window = characterWindows[scope] else {
            return
        }
        
        guard vm.alignment != .free else {
            // No constraint, allow free positioning
            return
        }
        
        DispatchQueue.main.async {
            guard let screen = window.screen ?? NSScreen.main else { return }
            
            let visibleFrame = screen.visibleFrame // Excludes menu bar and dock
            var newOrigin = window.frame.origin
            
            switch vm.alignment {
            case .top:
                newOrigin.y = visibleFrame.maxY - window.frame.height - 20 // 20pt offset from top
                
            case .bottom:
                newOrigin.y = visibleFrame.minY + 20 // 20pt offset from bottom
                
            case .left:
                newOrigin.x = visibleFrame.minX + 20 // 20pt offset from left
                
            case .right:
                newOrigin.x = visibleFrame.maxX - window.frame.width - 20 // 20pt offset from right
                
            case .free:
                break // Already handled above
            }
            
            window.setFrameOrigin(newOrigin)
            Log.debug("[GhostManager] Applied \(vm.alignment) alignment to scope \(scope)")
        }
    }
    
    /// Setup screen change observation for alignment enforcement
    func setupScreenChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            
            // Re-apply alignment constraints when screen configuration changes
            for scope in self.characterViewModels.keys {
                self.enforceDesktopAlignment(for: scope)
            }
        }
    }
}
