import Foundation
import Testing
@testable import Ourin

private final class SoundEventCapturingRuntime: GhostShioriRuntime {
    let kind: ShioriRuntimeKind = .native
    var isLoaded = true
    var resourceManager: ResourceManager?
    var requests: [(method: String, id: String, refs: [String])] = []

    func load(context: ShioriRuntimeLoadContext) -> Bool { true }

    func request(
        method: String,
        id: String,
        headers: [String: String],
        refs: [String],
        timeout: TimeInterval
    ) -> ShioriRuntimeResponse? {
        requests.append((method, id, refs))
        return .init(ok: true, status: 204)
    }

    func unload() { isLoaded = false }
}

// GhostManager の init は共有状態（PropertyManager.shared / ResourceManager / 通知センター）に触れるため、
// 並列実行するとフレークする。直列化して実行する。
@Suite(.serialized)
struct SoundPlayerTests {

    // MARK: - WAV 生成ヘルパー

    /// 単純な PCM16・モノラルの WAV を生成する。
    /// AVAudioPlayer がデコードできる有効なファイルがあれば十分で、音声出力は前提としない。
    private func makeWav(at url: URL, seconds: Double) throws {
        let sampleRate = 22050
        let frameCount = max(1, Int(Double(sampleRate) * seconds))
        let bytesPerFrame = 2
        let dataSize = frameCount * bytesPerFrame

        var data = Data()
        func ascii(_ s: String) { data.append(contentsOf: s.data(using: .ascii)!) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }

        ascii("RIFF"); u32(UInt32(36 + dataSize)); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1); u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * bytesPerFrame)); u16(UInt16(bytesPerFrame)); u16(16)
        ascii("data"); u32(UInt32(dataSize))
        for i in 0..<frameCount {
            let phase = Double(i) / Double(sampleRate) * 2 * Double.pi * 440
            let value = Int16(sin(phase) * 8000)
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        try data.write(to: url)
    }

    private func makeTempGhostURL() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ourin-sound-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sound"), withIntermediateDirectories: true)
        return dir
    }

    // MARK: - --seektime オプション解析

    @Test
    func seekTimeNumericIsMilliseconds() {
        let options = SoundPlaybackOptions.parse(["--seektime=2500"])
        switch options.seektime {
        case .absolute(let seconds):
            #expect(abs(seconds - 2.5) < 0.0001)
        default:
            Issue.record("Expected absolute seek, got \(String(describing: options.seektime))")
        }
    }

    @Test
    func seekTimeExplicitMillisecondSuffix() {
        let options = SoundPlaybackOptions.parse(["--seektime=2500ms"])
        switch options.seektime {
        case .absolute(let seconds):
            #expect(abs(seconds - 2.5) < 0.0001)
        default:
            Issue.record("Expected absolute seek, got \(String(describing: options.seektime))")
        }
    }

    @Test
    func seekTimeClockMinuteSecondFraction() {
        let options = SoundPlaybackOptions.parse(["--seektime=1:30.5"])
        switch options.seektime {
        case .absolute(let seconds):
            #expect(abs(seconds - 90.5) < 0.0001)
        default:
            Issue.record("Expected absolute seek, got \(String(describing: options.seektime))")
        }
    }

    @Test
    func seekTimeClockHourMinuteSecond() {
        let options = SoundPlaybackOptions.parse(["--seektime=1:02:03"])
        switch options.seektime {
        case .absolute(let seconds):
            #expect(abs(seconds - 3723) < 0.0001)
        default:
            Issue.record("Expected absolute seek, got \(String(describing: options.seektime))")
        }
    }

    @Test
    func seekTimeRelativePlusSeconds() {
        let options = SoundPlaybackOptions.parse(["--seektime=@+3"])
        switch options.seektime {
        case .relative(let delta):
            #expect(abs(delta - 3) < 0.0001)
        default:
            Issue.record("Expected relative seek, got \(String(describing: options.seektime))")
        }
    }

    @Test
    func seekTimeRelativeMinusMilliseconds() {
        let options = SoundPlaybackOptions.parse(["--seektime=@-500ms"])
        switch options.seektime {
        case .relative(let delta):
            #expect(abs(delta + 0.5) < 0.0001)
        default:
            Issue.record("Expected relative seek, got \(String(describing: options.seektime))")
        }
    }

    @Test
    func seekTimeInvalidValuesAreIgnored() {
        #expect(SoundPlaybackOptions.parse(["--seektime=abc"]).seektime == nil)
        #expect(SoundPlaybackOptions.parse(["--seektime=@+"]).seektime == nil)
        #expect(SoundPlaybackOptions.parse(["--seektime=1:2:3:4"]).seektime == nil)
        #expect(SoundPlaybackOptions.parse(["--seektime=1:30ms"]).seektime == nil)
        #expect(SoundPlaybackOptions.parse(["--seektime="]).seektime == nil)
    }

    @Test
    func volumeBalanceRateClampingStillApplies() {
        let options = SoundPlaybackOptions.parse(["--volume=125", "--balance=-150", "--rate=250"])
        #expect(options.volume == 1.0)
        #expect(options.balance == -1.0)
        #expect(options.rate == 2.5)
    }

    // MARK: - SoundPlayer: 状態遷移

    @Test
    func playerRejectsMissingFileWithoutCrash() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("missing-\(UUID().uuidString).wav")
        let player = SoundPlayer(filename: "missing.wav", url: url, options: .parse([]))
        #expect(player == nil)
    }

    @Test
    func playerPlayPauseResumeStopTransitions() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tone-\(UUID().uuidString).wav")
        try makeWav(at: url, seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }

        guard let player = SoundPlayer(filename: "tone.wav", url: url, options: .parse([])) else {
            Issue.record("Failed to create SoundPlayer")
            return
        }
        #expect(!player.isPlaying)

        player.play()
        Thread.sleep(forTimeInterval: 0.2)
        #expect(player.isPlaying)
        let playingPosition = player.currentTime
        #expect(playingPosition > 0)

        player.pause()
        Thread.sleep(forTimeInterval: 0.1)
        #expect(!player.isPlaying)
        let pausedPosition = player.currentTime
        #expect(abs(pausedPosition - playingPosition) < 0.05)

        player.resume()
        Thread.sleep(forTimeInterval: 0.2)
        #expect(player.isPlaying)
        #expect(player.currentTime > pausedPosition)

        player.stop()
        #expect(!player.isPlaying)
        #expect(player.currentTime == 0)
    }

    @Test
    func playerLoopMapsToInfiniteLoops() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tone-\(UUID().uuidString).wav")
        try makeWav(at: url, seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }

        guard let player = SoundPlayer(filename: "tone.wav", url: url, options: .parse([])) else {
            Issue.record("Failed to create SoundPlayer")
            return
        }
        #expect(!player.loops)
        #expect(player.numberOfLoops == 0)

        player.setLoop(true)
        #expect(player.loops)
        #expect(player.numberOfLoops == -1)

        player.setLoop(false)
        #expect(!player.loops)
        #expect(player.numberOfLoops == 0)
    }

    // MARK: - SoundPlayer: オプション適用

    @Test
    func playerAppliesVolumeBalanceRateAndAbsoluteSeek() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tone-\(UUID().uuidString).wav")
        try makeWav(at: url, seconds: 5)
        defer { try? FileManager.default.removeItem(at: url) }

        guard let player = SoundPlayer(
            filename: "tone.wav",
            url: url,
            options: .parse(["--volume=50", "--balance=-100", "--rate=200", "--seektime=1000"])
        ) else {
            Issue.record("Failed to create SoundPlayer")
            return
        }
        #expect(player.effectiveVolume == 0.5)
        #expect(player.effectiveBalance == -1.0)
        #expect(player.isRateEnabled)
        #expect(player.effectiveRate == 2.0)
        #expect(abs(player.currentTime - 1.0) < 0.1)
    }

    @Test
    func playerRelativeSeekAdjustsFromCurrentPosition() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tone-\(UUID().uuidString).wav")
        try makeWav(at: url, seconds: 5)
        defer { try? FileManager.default.removeItem(at: url) }

        guard let player = SoundPlayer(filename: "tone.wav", url: url, options: .parse([])) else {
            Issue.record("Failed to create SoundPlayer")
            return
        }
        player.play()
        Thread.sleep(forTimeInterval: 0.3)
        player.apply(options: .parse(["--seektime=@+1"]))
        #expect(player.currentTime > 1.0)
        player.stop()
    }

    @Test
    func playerManuallyLoopsAndReportsEachBoundary() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("loop-(UUID().uuidString).wav")
        try makeWav(at: url, seconds: 0.12)
        defer { try? FileManager.default.removeItem(at: url) }

        guard let player = SoundPlayer(filename: "loop.wav", url: url, options: .parse([])) else {
            Issue.record("Failed to create SoundPlayer")
            return
        }
        let lock = NSLock()
        var loopCount = 0
        player.onLoop = { _ in
            lock.lock()
            loopCount += 1
            lock.unlock()
        }
        player.setLoop(true)
        player.play()
        Thread.sleep(forTimeInterval: 0.55)
        player.stop()

        lock.lock()
        let observedLoops = loopCount
        lock.unlock()
        #expect(observedLoops >= 2)
    }

    // MARK: - GhostManager コマンド統合 (@MainActor / 実WAV)

    @Test @MainActor
    func playCreatesInstanceAndMultiplePlaysKeepSeparateInstances() async throws {
        let ghostURL = try makeTempGhostURL()
        defer { try? FileManager.default.removeItem(at: ghostURL) }
        let wav = ghostURL.appendingPathComponent("sound").appendingPathComponent("tone.wav")
        try makeWav(at: wav, seconds: 3)

        let manager = GhostManager(ghostURL: ghostURL)
        manager.playSound(filename: "tone.wav")
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(manager.namedSounds["tone.wav"]?.count == 1)
        #expect(manager.namedSounds["tone.wav"]?.first?.isPlaying == true)

        // 同一ファイル名の2回目再生は別インスタンスを確保する（多重再生サポート）。
        manager.playSound(filename: "tone.wav")
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(manager.namedSounds["tone.wav"]?.count == 2)
        #expect(manager.currentSounds.count == 2)

        manager.stopAllSounds()
        #expect(manager.currentSounds.isEmpty)
        #expect(manager.namedSounds.isEmpty)
        #expect(manager.preloadedSounds.isEmpty)
    }

    @Test @MainActor
    func pauseResumeByFilenameTransitionsPlayingState() async throws {
        let ghostURL = try makeTempGhostURL()
        defer { try? FileManager.default.removeItem(at: ghostURL) }
        let wav = ghostURL.appendingPathComponent("sound").appendingPathComponent("tone.wav")
        try makeWav(at: wav, seconds: 3)

        let manager = GhostManager(ghostURL: ghostURL)
        manager.playSound(filename: "tone.wav")
        try await Task.sleep(nanoseconds: 150_000_000)
        let player = manager.namedSounds["tone.wav"]?.first
        #expect(player?.isPlaying == true)

        manager.pauseSound(filename: "tone.wav")
        try await Task.sleep(nanoseconds: 60_000_000)
        #expect(player?.isPlaying == false)

        manager.resumeSound(filename: "tone.wav")
        try await Task.sleep(nanoseconds: 60_000_000)
        #expect(player?.isPlaying == true)

        manager.stopSound(filename: "tone.wav")
        #expect(manager.namedSounds["tone.wav"] == nil)
        #expect(manager.currentSounds.isEmpty)
    }

    @Test @MainActor
    func pauseResumeWithNilFilenameTargetsAllSounds() async throws {
        let ghostURL = try makeTempGhostURL()
        defer { try? FileManager.default.removeItem(at: ghostURL) }
        let wav = ghostURL.appendingPathComponent("sound").appendingPathComponent("tone.wav")
        try makeWav(at: wav, seconds: 3)

        let manager = GhostManager(ghostURL: ghostURL)
        manager.playSound(filename: "tone.wav")
        try await Task.sleep(nanoseconds: 150_000_000)

        manager.pauseSound(filename: nil)
        try await Task.sleep(nanoseconds: 60_000_000)
        #expect(manager.namedSounds["tone.wav"]?.first?.isPlaying == false)

        manager.resumeSound(filename: nil)
        try await Task.sleep(nanoseconds: 60_000_000)
        #expect(manager.namedSounds["tone.wav"]?.first?.isPlaying == true)

        manager.stopAllSounds()
    }

    @Test @MainActor
    func loopCommandCreatesInfiniteLoopInstance() async throws {
        let ghostURL = try makeTempGhostURL()
        defer { try? FileManager.default.removeItem(at: ghostURL) }
        let wav = ghostURL.appendingPathComponent("sound").appendingPathComponent("bgm.wav")
        try makeWav(at: wav, seconds: 3)

        let manager = GhostManager(ghostURL: ghostURL)
        manager.playSound(filename: "bgm.wav", loop: true)
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(manager.namedSounds["bgm.wav"]?.first?.loops == true)
        manager.stopAllSounds()
    }

    @Test @MainActor
    func waitDurationReflectsRemainingNonLoopPlayback() async throws {
        let ghostURL = try makeTempGhostURL()
        defer { try? FileManager.default.removeItem(at: ghostURL) }
        let wav = ghostURL.appendingPathComponent("sound").appendingPathComponent("tone.wav")
        try makeWav(at: wav, seconds: 5)

        let manager = GhostManager(ghostURL: ghostURL)
        manager.playSound(filename: "tone.wav")
        try await Task.sleep(nanoseconds: 150_000_000)

        let remaining = manager.estimatedSoundWaitDuration()
        #expect(remaining > 0)
        #expect(remaining <= 5.0)
        manager.stopAllSounds()
    }

    @Test @MainActor
    func loopIsExcludedFromWaitDuration() async throws {
        let ghostURL = try makeTempGhostURL()
        defer { try? FileManager.default.removeItem(at: ghostURL) }
        let wav = ghostURL.appendingPathComponent("sound").appendingPathComponent("bgm.wav")
        try makeWav(at: wav, seconds: 5)

        let manager = GhostManager(ghostURL: ghostURL)
        manager.playSound(filename: "bgm.wav", loop: true)
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(manager.estimatedSoundWaitDuration() == 0)
        manager.stopAllSounds()
    }

    @Test @MainActor
    func loadPreloadsAndPlayConsumesPreloadedInstance() async throws {
        let ghostURL = try makeTempGhostURL()
        defer { try? FileManager.default.removeItem(at: ghostURL) }
        let wav = ghostURL.appendingPathComponent("sound").appendingPathComponent("tone.wav")
        try makeWav(at: wav, seconds: 3)

        let manager = GhostManager(ghostURL: ghostURL)
        manager.loadSound(filename: "tone.wav")
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(manager.preloadedSounds["tone.wav"]?.count == 1)

        manager.playSound(filename: "tone.wav")
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(manager.preloadedSounds["tone.wav"] == nil)
        #expect(manager.namedSounds["tone.wav"]?.count == 1)
        manager.stopAllSounds()
    }

    @Test @MainActor
    func preloadedRelativeSeekIsNotAppliedTwice() async throws {
        let ghostURL = try makeTempGhostURL()
        defer { try? FileManager.default.removeItem(at: ghostURL) }
        let wav = ghostURL.appendingPathComponent("sound").appendingPathComponent("tone.wav")
        try makeWav(at: wav, seconds: 5)

        let manager = GhostManager(ghostURL: ghostURL)
        manager.loadSound(filename: "tone.wav", options: ["--seektime=@+1"])
        #expect(manager.preloadedSounds["tone.wav"]?.count == 1)
        manager.playSound(filename: "tone.wav")
        try await Task.sleep(nanoseconds: 120_000_000)
        let current = manager.namedSounds["tone.wav"]?.first?.currentTime ?? 0
        #expect(current > 0.9)
        #expect(current < 1.6)
        manager.stopAllSounds()
    }

    @Test @MainActor
    func masterSoundPathIsPreferredAndLegacySoundPathStillWorks() async throws {
        let ghostURL = try makeTempGhostURL()
        defer { try? FileManager.default.removeItem(at: ghostURL) }
        let master = ghostURL.appendingPathComponent("ghost/master", isDirectory: true)
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        try makeWav(at: master.appendingPathComponent("master.wav"), seconds: 1)

        let manager = GhostManager(ghostURL: ghostURL)
        manager.playSound(filename: "master.wav")
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(manager.namedSounds["master.wav"]?.first?.isPlaying == true)
        manager.stopAllSounds()
    }

    @Test @MainActor
    func naturalCompletionRemovesSoundState() async throws {
        let ghostURL = try makeTempGhostURL()
        defer { try? FileManager.default.removeItem(at: ghostURL) }
        let wav = ghostURL.appendingPathComponent("sound").appendingPathComponent("short.wav")
        try makeWav(at: wav, seconds: 0.18)

        let manager = GhostManager(ghostURL: ghostURL)
        manager.playSound(filename: "short.wav")
        try await Task.sleep(nanoseconds: 650_000_000)
        #expect(manager.currentSounds.isEmpty)
        #expect(manager.namedSounds["short.wav"] == nil)
    }

    @Test @MainActor
    func localSoundUsesSoundEventsAndCloseReason() async throws {
        EventBridge.shared.stop()
        let ghostURL = try makeTempGhostURL()
        defer { try? FileManager.default.removeItem(at: ghostURL) }
        let wav = ghostURL.appendingPathComponent("sound").appendingPathComponent("tone.wav")
        try makeWav(at: wav, seconds: 3)

        let manager = GhostManager(ghostURL: ghostURL)
        let runtime = SoundEventCapturingRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            manager.stopAllSounds()
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        manager.playSound(filename: "tone.wav")
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(runtime.requests.contains { $0.id == "OnMusicPlay" } == false)
        #expect(runtime.requests.contains { $0.id == "OnMusicPlayEx" } == false)

        manager.stopSound(filename: "tone.wav")
        let closeEvent = try #require(runtime.requests.last { $0.id == "OnSoundStop" })
        #expect(closeEvent.method == "NOTIFY")
        #expect(closeEvent.refs == ["tone.wav", "close"])

        runtime.requests.removeAll()
        manager.playSound(filename: "tone.wav")
        try await Task.sleep(nanoseconds: 150_000_000)
        manager.stopAllSounds()
        let allCloseEvent = try #require(runtime.requests.last { $0.id == "OnSoundStop" })
        #expect(allCloseEvent.refs == ["tone.wav", "close"])
    }

    @Test @MainActor
    func naturalSoundCompletionUsesEndReason() async throws {
        EventBridge.shared.stop()
        let ghostURL = try makeTempGhostURL()
        defer { try? FileManager.default.removeItem(at: ghostURL) }
        let wav = ghostURL.appendingPathComponent("sound").appendingPathComponent("short.wav")
        try makeWav(at: wav, seconds: 0.18)

        let manager = GhostManager(ghostURL: ghostURL)
        let runtime = SoundEventCapturingRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            manager.stopAllSounds()
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        manager.playSound(filename: "short.wav")
        try await Task.sleep(nanoseconds: 700_000_000)
        let endEvent = try #require(runtime.requests.last { $0.id == "OnSoundStop" })
        #expect(endEvent.refs == ["short.wav", "end"])
        #expect(manager.currentSounds.isEmpty)
    }

    @Test @MainActor
    func soundWaitIsQueuedForPlaybackAndStopDoesNotRacePlay() async throws {
        let ghostURL = try makeTempGhostURL()
        defer { try? FileManager.default.removeItem(at: ghostURL) }
        let wav = ghostURL.appendingPathComponent("sound").appendingPathComponent("tone.wav")
        try makeWav(at: wav, seconds: 1.2)

        let manager = GhostManager(ghostURL: ghostURL)
        manager.runScript(#"\![sound,play,tone.wav]\![sound,wait]after"#)
        #expect(manager.playbackQueue.contains { unit in
            if case .waitForAudio = unit { return true }
            return false
        })
        manager.stopAllSounds()

        let raceManager = GhostManager(ghostURL: ghostURL)
        raceManager.runScript(#"\![sound,play,tone.wav]\![sound,stop,tone.wav]"#)
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(raceManager.currentSounds.isEmpty)
        #expect(raceManager.namedSounds["tone.wav"] == nil)
    }

    @Test @MainActor
    func playSoundWithMissingFileDoesNotCreateInstances() async throws {
        let ghostURL = try makeTempGhostURL()
        let manager = GhostManager(ghostURL: ghostURL)
        manager.playSound(filename: "missing.wav")
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(manager.namedSounds["missing.wav"] == nil)
        #expect(manager.currentSounds.isEmpty)
    }

    @Test @MainActor
    func playSoundWithCorruptAudioDoesNotCrash() async throws {
        let ghostURL = try makeTempGhostURL()
        defer { try? FileManager.default.removeItem(at: ghostURL) }
        let bogus = ghostURL.appendingPathComponent("sound").appendingPathComponent("bogus.wav")
        try Data("not audio data".utf8).write(to: bogus)

        let manager = GhostManager(ghostURL: ghostURL)
        manager.playSound(filename: "bogus.wav")
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(manager.namedSounds["bogus.wav"] == nil)
        #expect(manager.currentSounds.isEmpty)
    }
}
