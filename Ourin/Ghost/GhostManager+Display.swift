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
        alert.messageText = NSLocalizedString("あなたのお名前は？", comment: "Name prompt title")
        alert.informativeText = NSLocalizedString("お名前を入力してください", comment: "Name prompt message")
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = NSLocalizedString("名前", comment: "Name placeholder")

        // Load existing name from UserDefaults if available
        let defaults = UserDefaults.standard
        if let savedName = defaults.string(forKey: "OurinUserName") {
            textField.stringValue = savedName
        }

        alert.accessoryView = textField
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        alert.addButton(withTitle: NSLocalizedString("キャンセル", comment: "Cancel"))

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
                EventBridge.shared.notify(.OnNameChanged, refs: ["userName": userName])

                // After OnNameChanged is sent, start timer events (OnIdle, SecondChange)
                startEventBridgeIfNeeded(enableAutoEvents: true)
            }
        }
    }
    
    // MARK: - Sound Playback

    private func resolveSoundPath(filename: String) -> URL {
        ghostURL.appendingPathComponent("sound").appendingPathComponent(filename)
    }

    enum VideoFileSupport: Equatable {
        case renderable
        case unsupported
        case notVideo
    }

    static func isVideoFile(_ filename: String) -> Bool {
        videoFileSupport(for: filename) != .notVideo
    }

    static func videoFileSupport(for filename: String) -> VideoFileSupport {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        guard !ext.isEmpty else { return .notVideo }
        if ["mp4", "m4v", "mov", "qt"].contains(ext) {
            return .renderable
        }
        if ["avi", "wmv", "mpg", "mpeg", "mpe", "mpv", "mkv", "webm", "flv"].contains(ext) {
            return .unsupported
        }
        return .notVideo
    }

    func resolveVideoPath(filename: String) -> URL {
        let normalized = filename
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        if normalized.hasPrefix("file://"), let url = URL(string: normalized) {
            return url
        }
        if normalized.hasPrefix("/") || normalized.hasPrefix("~") {
            return URL(fileURLWithPath: NSString(string: normalized).expandingTildeInPath)
        }
        return ghostURL
            .appendingPathComponent("ghost/master", isDirectory: true)
            .appendingPathComponent(normalized)
    }
    
    /// Play a sound file from the ghost's sound directory
    func playSound(filename: String, loop: Bool = false, options: [String] = []) {
        guard !filename.isEmpty else { return }
        let playbackOptions = SoundPlaybackOptions.parse(options)
        
        // Resolve sound file path relative to ghost directory
        let soundPath = resolveSoundPath(filename: filename)
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: soundPath.path) else {
            Log.info("[GhostManager] Sound file not found: \(soundPath.path)")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let sound = self.preloadedSounds[filename] ?? NSSound(contentsOf: soundPath, byReference: false)
            guard let sound else {
                Log.info("[GhostManager] Failed to load sound: \(filename)")
                return
            }
            sound.loops = loop
            if let volume = playbackOptions.volume {
                sound.volume = volume
            }
            self.logUnsupportedSoundOptions(playbackOptions, filename: filename)
            self.currentSounds.append(sound)
            self.namedSounds[filename, default: []].append(sound)
            sound.play()
            Log.debug("[GhostManager] Playing sound: \(filename) loop=\(loop)")

            // SHIORI 再生イベント通知。Ourin は音楽/効果音を区別しないため、
            // 再生開始時に OnMusicPlay / OnMusicPlayEx を通知する。
            let refs = ["filename": filename]
            EventBridge.shared.notify(.OnMusicPlay, refs: refs)
            EventBridge.shared.notify(.OnMusicPlayEx, refs: refs)
            if loop {
                EventBridge.shared.notify(.OnSoundLoop, refs: refs)
            }
        }
    }

    /// Preload sound data for faster playback.
    func loadSound(filename: String, options: [String] = []) {
        guard !filename.isEmpty else { return }
        let playbackOptions = SoundPlaybackOptions.parse(options)
        let soundPath = resolveSoundPath(filename: filename)
        guard FileManager.default.fileExists(atPath: soundPath.path) else {
            Log.info("[GhostManager] Sound file not found: \(soundPath.path)")
            return
        }
        DispatchQueue.main.async {
            guard let sound = NSSound(contentsOf: soundPath, byReference: false) else {
                Log.info("[GhostManager] Failed to preload sound: \(filename)")
                return
            }
            if let volume = playbackOptions.volume {
                sound.volume = volume
            }
            self.logUnsupportedSoundOptions(playbackOptions, filename: filename)
            self.preloadedSounds[filename] = sound
            Log.debug("[GhostManager] Preloaded sound: \(filename)")
        }
    }

    func pauseSound(filename: String?) {
        let targets = activeSounds(filename: filename)
        for sound in targets where sound.isPlaying {
            _ = sound.pause()
        }
        Log.debug("[GhostManager] Paused sounds count: \(targets.count)")
    }

    func resumeSound(filename: String?) {
        let targets = activeSounds(filename: filename)
        for sound in targets where !sound.isPlaying {
            sound.play()
        }
        Log.debug("[GhostManager] Resumed sounds count: \(targets.count)")
    }

    func applySoundOptions(filename: String, options: [String]) {
        guard !filename.isEmpty else { return }
        let playbackOptions = SoundPlaybackOptions.parse(options)
        if GhostManager.isVideoFile(filename) {
            applyVideoOptions(filename: filename, options: playbackOptions)
            return
        }
        if let volume = playbackOptions.volume {
            let targets = activeSounds(filename: filename)
            for sound in targets {
                sound.volume = volume
            }
            preloadedSounds[filename]?.volume = volume
            Log.debug("[GhostManager] Updated sound option volume for \(filename): \(volume)")
        }
        logUnsupportedSoundOptions(playbackOptions, filename: filename)
    }

    func estimatedSoundWaitDuration() -> TimeInterval {
        currentSounds.removeAll { !$0.isPlaying }
        var maxRemaining: TimeInterval = 0
        for sound in currentSounds where !sound.loops {
            let remaining = max(0, sound.duration - sound.currentTime)
            maxRemaining = max(maxRemaining, remaining)
        }
        return maxRemaining
    }

    private func activeSounds(filename: String?) -> [NSSound] {
        if let filename, !filename.isEmpty {
            return namedSounds[filename] ?? []
        }
        return currentSounds
    }

    /// Stop sounds by filename
    func stopSound(filename: String) {
        guard let sounds = namedSounds[filename], !sounds.isEmpty else {
            Log.info("[GhostManager] No active sound for filename: \(filename)")
            return
        }
        for sound in sounds where sound.isPlaying {
            sound.stop()
        }
        currentSounds.removeAll { sounds.contains($0) }
        namedSounds[filename] = nil
        preloadedSounds[filename] = nil
        Log.debug("[GhostManager] Stopped sound: \(filename)")
        EventBridge.shared.notify(.OnSoundStop, refs: ["filename": filename])
    }

    // MARK: - Video Playback

    /// Play a video file from the ghost's ghost/master directory.
    func playVideo(filename: String, loop: Bool = false, options: [String] = []) {
        guard !filename.isEmpty else { return }
        let support = GhostManager.videoFileSupport(for: filename)
        guard support != .notVideo else {
            Log.info("[GhostManager] Not a video file: \(filename)")
            return
        }

        let videoPath = resolveVideoPath(filename: filename)
        if support == .unsupported {
            notifyVideoPlayFailure(filename: filename, reason: "unsupported_codec")
            Log.error("[GhostManager] Unsupported video format for AVPlayer renderer: \(filename)")
            return
        }
        guard FileManager.default.fileExists(atPath: videoPath.path) else {
            notifyVideoPlayFailure(filename: filename, reason: "file_not_found")
            Log.error("[GhostManager] Video file not found: \(videoPath.path)")
            return
        }

        let playbackOptions = SoundPlaybackOptions.parse(options)
        let volume = playbackOptions.volume ?? 1.0
        let rate = playbackOptions.rate ?? 1.0
        let soundOnly = playbackOptions.soundOnly ?? false
        let showWindow = playbackOptions.showWindow ?? true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let existing = self.videoPlayers[filename] {
                existing.stop()
            }
            let controller = VideoPlayerWindow { [weak self] in
                self?.videoPlayers[filename] = nil
            }
            self.videoPlayers[filename] = controller
            controller.play(
                url: videoPath,
                loop: loop,
                soundOnly: soundOnly,
                showWindow: showWindow,
                volume: volume,
                rate: rate,
                balance: playbackOptions.balance
            )
            self.notifyVideoPlayRequested(filename: filename, loop: loop)
            Log.debug("[GhostManager] Playing video: \(filename) loop=\(loop) soundOnly=\(soundOnly) showWindow=\(showWindow)")
        }
    }

    func pauseVideo(filename: String?) {
        let targets = activeVideoPlayers(filename: filename)
        for player in targets {
            player.pause()
        }
        Log.debug("[GhostManager] Paused videos count: \(targets.count)")
    }

    func resumeVideo(filename: String?) {
        let targets = activeVideoPlayers(filename: filename)
        for player in targets {
            player.resume()
        }
        Log.debug("[GhostManager] Resumed videos count: \(targets.count)")
    }

    func stopVideo(filename: String?) {
        if let filename, !filename.isEmpty {
            guard let player = videoPlayers.removeValue(forKey: filename) else {
                Log.info("[GhostManager] No active video for filename: \(filename)")
                return
            }
            player.stop()
            Log.debug("[GhostManager] Stopped video: \(filename)")
            return
        }
        stopAllVideos()
    }

    func stopAllVideos() {
        let players = Array(videoPlayers.values)
        videoPlayers.removeAll()
        for player in players {
            player.stop()
        }
        Log.debug("[GhostManager] Stopped all videos")
    }

    func estimatedVideoWaitDuration() -> TimeInterval {
        var maxRemaining: TimeInterval = 0
        for player in videoPlayers.values {
            maxRemaining = max(maxRemaining, player.estimatedRemainingDuration())
        }
        return maxRemaining
    }
    
    /// Stop all currently playing sounds
    func stopAllSounds() {
        for sound in currentSounds {
            if sound.isPlaying {
                sound.stop()
            }
        }
        currentSounds.removeAll()
        namedSounds.removeAll()
        preloadedSounds.removeAll()
        stopAllVideos()
        Log.debug("[GhostManager] Stopped all sounds")
    }

    private func activeVideoPlayers(filename: String?) -> [VideoPlayerWindow] {
        if let filename, !filename.isEmpty {
            return videoPlayers[filename].map { [$0] } ?? []
        }
        return Array(videoPlayers.values)
    }

    private func applyVideoOptions(filename: String, options: SoundPlaybackOptions) {
        guard let player = videoPlayers[filename] else {
            Log.info("[GhostManager] No active video for filename: \(filename)")
            return
        }
        player.apply(options: options)
        Log.debug("[GhostManager] Updated video options for \(filename)")
    }

    private func notifyVideoPlayRequested(filename: String, loop: Bool) {
        EventBridge.shared.notify(.OnVideoPlayEx, refs: [
            "filename": filename,
            "loopMode": loop ? "loop" : "once"
        ])
    }

    private func notifyVideoPlayFailure(filename: String, reason: String) {
        EventBridge.shared.notify(.OnVideoPlayFailure, refs: [
            "filename": filename,
            "reason": reason
        ])
    }

    private func logUnsupportedSoundOptions(_ options: SoundPlaybackOptions, filename: String) {
        if options.rate != nil {
            Log.info("[GhostManager] --rate is not supported for NSSound playback: \(filename)")
        }
        if options.balance != nil {
            Log.info("[GhostManager] --balance is not supported for NSSound playback: \(filename)")
        }
        if options.showWindow != nil {
            Log.info("[GhostManager] --window is ignored for NSSound playback: \(filename)")
        }
        if options.soundOnly != nil {
            Log.info("[GhostManager] --sound-only is ignored for NSSound playback: \(filename)")
        }
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

    /// Open a file path relative to current ghost root (or absolute path).
    func openFilePath(_ path: String) {
        guard !path.isEmpty else { return }
        let resolvedURL = SSPCompat.resolvePath(path, relativeTo: ghostURL)
        if handleSSPCompatExecutableOpen(resolvedURL, rawPath: path) { return }
        DispatchQueue.main.async {
            NSWorkspace.shared.open(resolvedURL)
            Log.debug("[GhostManager] Opened file path: \(resolvedURL.path)")
        }
    }

    /// Open a file path with option parsing used by \![open,file,*].
    /// By default, paths outside ghost root and the public Ourin base folder are denied for safety.
    func openFilePath(path: String, line: Int?, appName: String?, allowExternal: Bool) {
        guard !path.isEmpty else { return }
        let resolvedURL = SSPCompat.resolvePath(path, relativeTo: ghostURL)

        let standardized = resolvedURL.standardizedFileURL.path
        let ghostRoot = ghostURL.standardizedFileURL.path
        let publicRoot = (try? OurinPaths.baseDirectory().standardizedFileURL.path) ?? ""
        let isAllowedPublicResource = !publicRoot.isEmpty && standardized.hasPrefix(publicRoot)
        if !allowExternal && !standardized.hasPrefix(ghostRoot) && !isAllowedPublicResource {
            Log.info("[GhostManager] Refused to open external file path: \(standardized)")
            EventBridge.shared.notifyCustom("OnSecurityWarning", refs: [
                "source": "open_file_denied",
                "detail": standardized
            ])
            return
        }
        if handleSSPCompatExecutableOpen(resolvedURL, rawPath: path) { return }

        DispatchQueue.main.async {
            if let appName, !appName.isEmpty {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open([resolvedURL], withApplicationAt: URL(fileURLWithPath: "/Applications/\(appName).app"), configuration: config) { _, error in
                    if let error {
                        Log.info("[GhostManager] Failed to open file with app \(appName): \(error.localizedDescription)")
                    }
                }
            } else {
                NSWorkspace.shared.open(resolvedURL)
            }
            let lineInfo = line.map { " line=\($0)" } ?? ""
            Log.debug("[GhostManager] Opened file path with options: \(standardized)\(lineInfo)")
        }
    }

    /// Reveal a file or folder in Finder.
    func revealInExplorer(_ path: String) {
        guard !path.isEmpty else { return }
        let resolvedURL = SSPCompat.resolvePath(path, relativeTo: ghostURL)
        DispatchQueue.main.async {
            if FileManager.default.fileExists(atPath: resolvedURL.path) {
                NSWorkspace.shared.activateFileViewerSelecting([resolvedURL])
            } else {
                NSWorkspace.shared.open(resolvedURL.deletingLastPathComponent())
            }
            Log.debug("[GhostManager] Revealed in explorer: \(resolvedURL.path)")
        }
    }

    private func handleSSPCompatExecutableOpen(_ url: URL, rawPath: String) -> Bool {
        guard let kind = SSPCompat.executableKind(for: url) else { return false }
        let dataPath = SSPCompat.dataDirectory()?.path ?? ""
        Log.info("[GhostManager] SSP executable compatibility handled: \(kind.rawValue) raw=\(rawPath)")
        EventBridge.shared.notifyCustom("OnSSPCompatExecutable", refs: [
            "kind": kind.rawValue,
            "rawPath": rawPath,
            "path": url.path,
            "dataPath": dataPath
        ])
        return true
    }

    func openInstalledTypeDirectory(type: String, name: String? = nil) {
        guard let base = try? OurinPaths.baseDirectory() else {
            Log.info("[GhostManager] Failed to resolve base directory for explorer")
            return
        }
        let target = base.appendingPathComponent(type, isDirectory: true)
        let resolved = (name?.isEmpty == false) ? target.appendingPathComponent(name!, isDirectory: true) : target
        DispatchQueue.main.async {
            NSWorkspace.shared.open(resolved)
            Log.debug("[GhostManager] Opened installed type directory: \(resolved.path)")
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
