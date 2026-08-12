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
                // SHIORI の標準ユーザー情報も更新する。
                sendUserInfoNotify()

                // After OnNameChanged is sent, start timer events (OnIdle, SecondChange)
                startEventBridgeIfNeeded(enableAutoEvents: true)
            }
        }
    }
    
    // MARK: - Sound Playback

    private func resolveSoundPath(filename: String) -> URL {
        let normalized = filename
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        if normalized.hasPrefix("file://"), let url = URL(string: normalized) {
            return url
        }
        if normalized.hasPrefix("/") || normalized.hasPrefix("~") {
            return URL(fileURLWithPath: NSString(string: normalized).expandingTildeInPath)
        }

        // UKADOC specifies ghost/master as the base for \\8, \\_v and sound commands.
        // Keep the former ghost/sound lookup as a compatibility fallback for existing
        // Ourin fixtures and older packages.
        let masterPath = ghostURL
            .appendingPathComponent("ghost/master", isDirectory: true)
            .appendingPathComponent(normalized)
        let legacyPath = ghostURL
            .appendingPathComponent("sound", isDirectory: true)
            .appendingPathComponent(normalized)
        if FileManager.default.fileExists(atPath: masterPath.path) {
            return masterPath
        }
        if FileManager.default.fileExists(atPath: legacyPath.path) {
            return legacyPath
        }
        return masterPath
    }

    /// 音声状態は AVAudioPlayer と GhostManager の配列を同一メインキューで管理する。
    /// スクリプトのトークン化中に play/load/stop が連続しても、操作順序を失わない。
    private func performOnMainSync(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    private func configureSoundPlayer(_ player: SoundPlayer) {
        player.onFinish = { [weak self] player, successfully in
            self?.handleSoundFinished(player, successfully: successfully)
        }
        player.onLoop = { [weak self] player in
            self?.handleSoundLoop(player)
        }
        player.onError = { [weak self] player, code, message in
            self?.handleSoundError(player, code: code, message: message)
        }
    }

    private func removeSoundPlayer(_ player: SoundPlayer) {
        currentSounds.removeAll { $0 === player }
        if var sounds = namedSounds[player.filename] {
            sounds.removeAll { $0 === player }
            if sounds.isEmpty {
                namedSounds[player.filename] = nil
            } else {
                namedSounds[player.filename] = sounds
            }
        }
    }

    private func handleSoundFinished(_ player: SoundPlayer, successfully: Bool) {
        guard Thread.isMainThread else {
            performOnMainSync { [weak self] in
                self?.handleSoundFinished(player, successfully: successfully)
            }
            return
        }
        guard currentSounds.contains(where: { $0 === player })
                || namedSounds[player.filename]?.contains(where: { $0 === player }) == true else {
            return
        }
        if !successfully {
            handleSoundError(player, code: -1, message: "playback_failed")
            return
        }
        removeSoundPlayer(player)
        EventBridge.shared.notify(.OnSoundStop, refs: [
            "filename": player.filename,
            "reason": "end"
        ])
    }

    private func handleSoundLoop(_ player: SoundPlayer) {
        guard Thread.isMainThread else {
            performOnMainSync { [weak self] in
                self?.handleSoundLoop(player)
            }
            return
        }
        guard currentSounds.contains(where: { $0 === player }) else { return }
        EventBridge.shared.notify(.OnSoundLoop, refs: ["filename": player.filename])
    }

    private func handleSoundError(_ player: SoundPlayer, code: Int, message: String) {
        guard Thread.isMainThread else {
            performOnMainSync { [weak self] in
                self?.handleSoundError(player, code: code, message: message)
            }
            return
        }
        guard currentSounds.contains(where: { $0 === player })
                || namedSounds[player.filename]?.contains(where: { $0 === player }) == true else {
            return
        }
        removeSoundPlayer(player)
        EventBridge.shared.notify(.OnSoundError, refs: [
            "command": "play",
            "errorCode": String(code),
            "filename": player.filename,
            "message": message
        ])
    }

    func notifySoundError(command: String, filename: String, code: Int, message: String) {
        EventBridge.shared.notify(.OnSoundError, refs: [
            "command": command,
            "errorCode": String(code),
            "filename": filename,
            "message": message
        ])
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
    
    /// Play a sound file relative to ghost/master (with the legacy ghost/sound fallback).
    func playSound(filename: String, loop: Bool = false, options: [String] = []) {
        guard !filename.isEmpty else { return }
        let playbackOptions = SoundPlaybackOptions.parse(options)
        
        // Resolve sound file path relative to ghost directory
        let soundPath = resolveSoundPath(filename: filename)
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: soundPath.path) else {
            Log.info("[GhostManager] Sound file not found: \(soundPath.path)")
            notifySoundError(command: "play", filename: filename, code: -1, message: "file_not_found")
            return
        }

        performOnMainSync { [weak self] in
            guard let self else { return }
            // プリロード済みインスタンスを1つ消費し、なければ新規生成する。
            // 同一ファイル名でも再生ごとに独立インスタンスを確保して多重再生を保証する。
            let player: SoundPlayer
            let wasPreloaded: Bool
            if let preloaded = self.preloadedSounds[filename]?.popLast() {
                player = preloaded
                wasPreloaded = true
                if self.preloadedSounds[filename]?.isEmpty == true {
                    self.preloadedSounds[filename] = nil
                }
            } else if let created = SoundPlayer(filename: filename, url: soundPath, options: playbackOptions) {
                player = created
                wasPreloaded = false
            } else {
                Log.info("[GhostManager] Failed to load sound: \(filename)")
                self.notifySoundError(command: "play", filename: filename, code: -1, message: "audio_load_failed")
                return
            }
            self.configureSoundPlayer(player)
            player.setLoop(loop)
            // load 時に適用済みの相対 seek を play 時に二重適用しない。
            // play 側で明示オプションがある場合だけ上書きする。
            if wasPreloaded && !playbackOptions.isEmpty {
                player.apply(options: playbackOptions)
            }
            self.logIgnoredAudioOptions(playbackOptions, filename: filename)
            self.currentSounds.append(player)
            self.namedSounds[filename, default: []].append(player)
            player.play()
            Log.debug("[GhostManager] Playing sound: \(filename) loop=\(loop)")

            // SHIORI 再生イベント通知。Ourin は音楽/効果音を区別しないため、
            // 再生開始時に OnMusicPlay / OnMusicPlayEx を通知する。
            let refs = ["filename": filename]
            EventBridge.shared.notify(.OnMusicPlay, refs: refs)
            EventBridge.shared.notify(.OnMusicPlayEx, refs: refs)
        }
    }

    /// Preload sound data for faster playback.
    func loadSound(filename: String, options: [String] = []) {
        guard !filename.isEmpty else { return }
        let playbackOptions = SoundPlaybackOptions.parse(options)
        let soundPath = resolveSoundPath(filename: filename)
        guard FileManager.default.fileExists(atPath: soundPath.path) else {
            Log.info("[GhostManager] Sound file not found: \(soundPath.path)")
            notifySoundError(command: "load", filename: filename, code: -1, message: "file_not_found")
            return
        }
        performOnMainSync { [weak self] in
            guard let self else { return }
            guard let player = SoundPlayer(filename: filename, url: soundPath, options: playbackOptions) else {
                Log.info("[GhostManager] Failed to preload sound: \(filename)")
                self.notifySoundError(command: "load", filename: filename, code: -1, message: "audio_load_failed")
                return
            }
            self.configureSoundPlayer(player)
            self.logIgnoredAudioOptions(playbackOptions, filename: filename)
            self.preloadedSounds[filename, default: []].append(player)
            Log.debug("[GhostManager] Preloaded sound: \(filename)")
        }
    }

    func pauseSound(filename: String?) {
        guard Thread.isMainThread else {
            performOnMainSync { [weak self] in self?.pauseSound(filename: filename) }
            return
        }
        let targets = activeSounds(filename: filename)
        for player in targets where player.isPlaying {
            player.pause()
        }
        Log.debug("[GhostManager] Paused sounds count: \(targets.count)")
    }

    func resumeSound(filename: String?) {
        guard Thread.isMainThread else {
            performOnMainSync { [weak self] in self?.resumeSound(filename: filename) }
            return
        }
        let targets = activeSounds(filename: filename)
        for player in targets where player.isPaused {
            player.resume()
        }
        Log.debug("[GhostManager] Resumed sounds count: \(targets.count)")
    }

    func applySoundOptions(filename: String, options: [String]) {
        guard !filename.isEmpty else { return }
        guard Thread.isMainThread else {
            performOnMainSync { [weak self] in self?.applySoundOptions(filename: filename, options: options) }
            return
        }
        let playbackOptions = SoundPlaybackOptions.parse(options)
        if GhostManager.isVideoFile(filename) {
            applyVideoOptions(filename: filename, options: playbackOptions)
            return
        }
        let targets = activeSounds(filename: filename)
        for player in targets {
            player.apply(options: playbackOptions)
        }
        for player in preloadedSounds[filename] ?? [] {
            player.apply(options: playbackOptions)
        }
        logIgnoredAudioOptions(playbackOptions, filename: filename)
        Log.debug("[GhostManager] Updated sound options for \(filename)")
    }

    func estimatedSoundWaitDuration() -> TimeInterval {
        guard Thread.isMainThread else {
            var result = 0.0
            performOnMainSync { [weak self] in
                result = self?.estimatedSoundWaitDuration() ?? 0
            }
            return result
        }
        var maxRemaining: TimeInterval = 0
        for player in currentSounds where !player.loops && player.isPlaying {
            let remaining = max(0, player.duration - player.currentTime)
            maxRemaining = max(maxRemaining, remaining)
        }
        return maxRemaining
    }

    private func activeSounds(filename: String?) -> [SoundPlayer] {
        if let filename, !filename.isEmpty {
            return namedSounds[filename] ?? []
        }
        return currentSounds
    }

    /// Stop sounds by filename
    func stopSound(filename: String) {
        guard Thread.isMainThread else {
            performOnMainSync { [weak self] in self?.stopSound(filename: filename) }
            return
        }
        let sounds = namedSounds[filename] ?? []
        let hasPreloaded = !(preloadedSounds[filename] ?? []).isEmpty
        guard !sounds.isEmpty || hasPreloaded else {
            Log.info("[GhostManager] No active sound for filename: \(filename)")
            return
        }
        for player in sounds {
            player.stop()
        }
        currentSounds.removeAll { sound in sounds.contains(where: { $0 === sound }) }
        namedSounds[filename] = nil
        preloadedSounds[filename] = nil
        if !sounds.isEmpty {
            Log.debug("[GhostManager] Stopped sound: \(filename)")
            EventBridge.shared.notify(.OnSoundStop, refs: [
                "filename": filename,
                "reason": "end"
            ])
        }
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

        performOnMainSync { [weak self] in
            guard let self else { return }
            if let existing = self.videoPlayers[filename] {
                existing.stop()
            }
            let controller = VideoPlayerWindow { [weak self] in
                self?.videoPlayers[filename] = nil
            }
            self.videoPlayers[filename] = controller
            // プリロード済みインスタンスを1つ消費し、なければ従来どおり URL から新規再生する。
            // プリロード時はオプションが load/play でマージされ、play 時指定が優先される。
            if let preloaded = self.preloadedVideos[filename]?.popLast() {
                if self.preloadedVideos[filename]?.isEmpty == true {
                    self.preloadedVideos[filename] = nil
                }
                controller.play(preloaded: preloaded, loop: loop, options: playbackOptions)
                Log.debug("[GhostManager] Playing video from preload: \(filename) loop=\(loop)")
            } else {
                controller.play(url: videoPath, loop: loop, options: playbackOptions)
                Log.debug("[GhostManager] Playing video: \(filename) loop=\(loop) soundOnly=\(playbackOptions.soundOnly ?? false) showWindow=\(playbackOptions.showWindow ?? true)")
            }
            self.notifyVideoPlayRequested(filename: filename, loop: loop)
        }
    }

    /// Preload a video by creating an AVURLAsset/AVPlayerItem/AVPlayer ahead of time.
    /// \![sound,load] の動画分岐。UKADOC には load 成功イベントが存在しないため通知せず、
    /// 失敗時は既存方針どおり OnVideoPlayFailure（file_not_found / unsupported_codec）を通知する。
    func loadVideo(filename: String, options: [String] = []) {
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
        performOnMainSync { [weak self] in
            guard let self else { return }
            let preloaded = VideoPreloadPlayer(filename: filename, url: videoPath, options: playbackOptions)
            self.preloadedVideos[filename, default: []].append(preloaded)
            Log.debug("[GhostManager] Preloaded video: \(filename)")
        }
    }

    func pauseVideo(filename: String?) {
        guard Thread.isMainThread else {
            performOnMainSync { [weak self] in self?.pauseVideo(filename: filename) }
            return
        }
        let targets = activeVideoPlayers(filename: filename)
        for player in targets {
            player.pause()
        }
        Log.debug("[GhostManager] Paused videos count: \(targets.count)")
    }

    func resumeVideo(filename: String?) {
        guard Thread.isMainThread else {
            performOnMainSync { [weak self] in self?.resumeVideo(filename: filename) }
            return
        }
        let targets = activeVideoPlayers(filename: filename)
        for player in targets {
            player.resume()
        }
        Log.debug("[GhostManager] Resumed videos count: \(targets.count)")
    }

    func stopVideo(filename: String?) {
        guard Thread.isMainThread else {
            performOnMainSync { [weak self] in self?.stopVideo(filename: filename) }
            return
        }
        if let filename, !filename.isEmpty {
            discardPreloadedVideos(filename: filename)
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
        guard Thread.isMainThread else {
            performOnMainSync { [weak self] in self?.stopAllVideos() }
            return
        }
        discardAllPreloadedVideos()
        let players = Array(videoPlayers.values)
        videoPlayers.removeAll()
        for player in players {
            player.stop()
        }
        Log.debug("[GhostManager] Stopped all videos")
    }

    private func discardPreloadedVideos(filename: String) {
        let preloaded = preloadedVideos.removeValue(forKey: filename) ?? []
        for player in preloaded {
            player.discard()
        }
    }

    private func discardAllPreloadedVideos() {
        let preloaded = preloadedVideos.values.flatMap { $0 }
        preloadedVideos.removeAll()
        for player in preloaded {
            player.discard()
        }
    }

    func estimatedVideoWaitDuration() -> TimeInterval {
        guard Thread.isMainThread else {
            var result = 0.0
            performOnMainSync { [weak self] in
                result = self?.estimatedVideoWaitDuration() ?? 0
            }
            return result
        }
        var maxRemaining: TimeInterval = 0
        for player in videoPlayers.values {
            maxRemaining = max(maxRemaining, player.estimatedRemainingDuration())
        }
        return maxRemaining
    }
    
    /// Stop all currently playing sounds
    func stopAllSounds() {
        guard Thread.isMainThread else {
            performOnMainSync { [weak self] in self?.stopAllSounds() }
            return
        }
        let stoppedFilenames = Set(namedSounds.keys).sorted()
        for player in currentSounds {
            player.stop()
        }
        currentSounds.removeAll()
        namedSounds.removeAll()
        preloadedSounds.removeAll()
        for filename in stoppedFilenames {
            EventBridge.shared.notify(.OnSoundStop, refs: [
                "filename": filename,
                "reason": "end"
            ])
        }
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

    private func logIgnoredAudioOptions(_ options: SoundPlaybackOptions, filename: String) {
        if options.showWindow != nil {
            Log.info("[GhostManager] --window is ignored for audio playback: \(filename)")
        }
        if options.soundOnly != nil {
            Log.info("[GhostManager] --sound-only is ignored for audio playback: \(filename)")
        }
    }
    
    // MARK: - URL and Email Handling
    
    /// Open a URL in the default browser
    func openURL(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Log.info("[GhostManager] Empty URL string")
            return
        }

        // Preserve an explicitly supplied scheme (mailto:, ftp:, custom schemes, ...).
        // Bare host names are interpreted as HTTPS URLs.
        let finalURL: String
        if let schemeEnd = trimmed.firstIndex(of: ":"),
           schemeEnd > trimmed.startIndex,
           trimmed[..<schemeEnd].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }) {
            finalURL = trimmed
        } else {
            finalURL = "https://" + trimmed
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

    // MARK: - Help and Readme

    /// Execute \![open,help,*] using the SSP-compatible help/event route.
    func openHelp(dialogID: String?) {
        let normalizedID = dialogID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let helpURL = "https://ssp.shillest.net/ukadoc/ssphelp/"

        if normalizedID == "talk" {
            openURL(helpURL)
            return
        }

        if let dialogID,
           !dialogID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           requestDialogEvent(eventID: "OnConfigurationDialogHelp", references: [dialogID]) {
            return
        }

        // With no dialog-specific response, the standard behavior is the help index.
        openURL(helpURL)
    }

    /// Open the readme specified by a ghost/shell/balloon/headline/plugin descriptor.
    ///
    /// The descriptor is read from the component root, so `readme,foo.txt` is not
    /// accidentally resolved relative to the package root.
    func openGhostReadme(type: String? = nil, name: String? = nil) {
        guard let root = readmeRoot(type: type, name: name) else {
            let componentType = type ?? "ghost"
            let componentName = name ?? ""
            Log.info("[GhostManager] Readme component was not found: type=\(componentType) name=\(componentName)")
            return
        }

        let descriptorURL = root.appendingPathComponent("descript.txt")
        let descriptor = LegacyDescriptor.readDictionary(from: descriptorURL) ?? [:]
        let readmeName: String = {
            guard let configured = descriptor["readme"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !configured.isEmpty else {
                return "readme.txt"
            }
            return configured
        }()
        let readmeURL: URL
        if readmeName.hasPrefix("/") {
            readmeURL = URL(fileURLWithPath: readmeName).standardizedFileURL
        } else {
            readmeURL = root.appendingPathComponent(readmeName).standardizedFileURL
        }

        guard FileManager.default.fileExists(atPath: readmeURL.path) else {
            Log.info("[GhostManager] Readme file was not found: \(readmeURL.path)")
            EventBridge.shared.notifyCustom("OnReadmeOpenFailure", refs: [
                "type": type ?? "ghost",
                "name": name ?? "",
                "path": readmeURL.path
            ])
            return
        }

        DispatchQueue.main.async {
            NSWorkspace.shared.open(readmeURL)
            Log.debug("[GhostManager] Opened readme: \(readmeURL.path)")
        }
    }

    private func readmeRoot(type: String?, name: String?) -> URL? {
        let normalizedType = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentGhostRoot = ghostURL.appendingPathComponent("ghost/master", isDirectory: true)

        guard let normalizedType, !normalizedType.isEmpty else {
            return currentGhostRoot
        }

        switch normalizedType {
        case "ghost":
            if normalizedName == nil || normalizedName?.caseInsensitiveCompare(ghostConfig?.name ?? "") == .orderedSame {
                return currentGhostRoot
            }
            return NarRegistry.shared.installedItems(ofType: "ghost")
                .first { $0.name.caseInsensitiveCompare(normalizedName ?? "") == .orderedSame }?
                .path.appendingPathComponent("ghost/master", isDirectory: true)
        case "shell":
            if let normalizedName {
                let embedded = ghostURL.appendingPathComponent("shell", isDirectory: true)
                    .appendingPathComponent(normalizedName, isDirectory: true)
                if FileManager.default.fileExists(atPath: embedded.path) {
                    return embedded
                }
                return NarRegistry.shared.installedItems(ofType: "shell")
                    .first { $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame }?.path
            }
            return loadShellPath()
        case "balloon":
            if let normalizedName {
                let embedded = ghostURL.appendingPathComponent("balloon", isDirectory: true)
                    .appendingPathComponent(normalizedName, isDirectory: true)
                if FileManager.default.fileExists(atPath: embedded.path) {
                    return embedded
                }
                return NarRegistry.shared.installedItems(ofType: "balloon")
                    .first { $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame }?.path
            }
            let current = ghostURL.appendingPathComponent("balloon", isDirectory: true)
            return FileManager.default.fileExists(atPath: current.path) ? current : nil
        case "headline", "plugin":
            return NarRegistry.shared.installedItems(ofType: normalizedType)
                .first { $0.name.caseInsensitiveCompare(normalizedName ?? "") == .orderedSame }?.path
        default:
            Log.info("[GhostManager] Unsupported readme component type: \(normalizedType)")
            return nil
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
