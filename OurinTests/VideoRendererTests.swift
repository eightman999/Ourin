import Foundation
import Testing
@testable import Ourin

// GhostManager の init は PropertyManager.shared の差し替え・ResourceManager のファイルI/O・
// オブザーバ登録など共有状態に触れるため、並列実行するとフレークする。直列化して実行する。
@Suite(.serialized)
@MainActor
struct VideoRendererTests {
    @Test
    func videoExtensionSupportSeparatesRenderableAndFallbackFormats() async throws {
        #expect(GhostManager.isVideoFile("movie.MP4"))
        #expect(GhostManager.isVideoFile("intro.mov"))
        #expect(GhostManager.isVideoFile("legacy.avi"))
        #expect(!GhostManager.isVideoFile("voice.wav"))
        #expect(!GhostManager.isVideoFile("README"))

        #expect(GhostManager.videoFileSupport(for: "movie.m4v") == .renderable)
        #expect(GhostManager.videoFileSupport(for: "legacy.wmv") == .unsupported)
        #expect(GhostManager.videoFileSupport(for: "se.ogg") == .notVideo)
    }

    @Test
    func soundPlaybackOptionsParseAndClampValues() async throws {
        let options = SoundPlaybackOptions.parse([
            "--volume=125",
            "--balance=-150",
            "--rate=250",
            "--window=false",
            "--sound-only=on"
        ])

        #expect(options.volume == 1.0)
        #expect(options.balance == -1.0)
        #expect(options.rate == 2.5)
        #expect(options.showWindow == false)
        #expect(options.soundOnly == true)
    }

    @Test
    func soundPlaybackOptionsTreatBareBooleanFlagAsTrue() async throws {
        let options = SoundPlaybackOptions.parse(["--window", "--sound-only"])

        #expect(options.showWindow == true)
        #expect(options.soundOnly == true)
    }

    @Test
    func audioBalanceGainsClampAndMuteOppositeChannel() async throws {
        let left = AudioBalanceGains(balance: -2)
        let leftBoundary = AudioBalanceGains(balance: -1)
        let center = AudioBalanceGains(balance: 0)
        let rightBoundary = AudioBalanceGains(balance: 1)
        let right = AudioBalanceGains(balance: 2)

        #expect(left.left == 1 && left.right == 0)
        #expect(leftBoundary.left == 1 && leftBoundary.right == 0)
        #expect(center.left == 1 && center.right == 1)
        #expect(rightBoundary.left == 0 && rightBoundary.right == 1)
        #expect(right.left == 0 && right.right == 1)
    }

    @Test
    func videoPathResolvesRelativeToGhostMaster() async throws {
        let root = URL(fileURLWithPath: "/tmp/ourin-video-ghost", isDirectory: true)
        let manager = GhostManager(ghostURL: root)

        let resolved = manager.resolveVideoPath(filename: "movie/test.mp4")

        #expect(resolved.path == "/tmp/ourin-video-ghost/ghost/master/movie/test.mp4")
    }

    @Test
    func videoPathKeepsAbsolutePath() async throws {
        let root = URL(fileURLWithPath: "/tmp/ourin-video-ghost", isDirectory: true)
        let manager = GhostManager(ghostURL: root)

        let resolved = manager.resolveVideoPath(filename: "/tmp/source/test.mov")

        #expect(resolved.path == "/tmp/source/test.mov")
    }

    @Test
    func playVideoOnUnsupportedCodecDoesNotCrashAndSkipsPlayback() async throws {
        let root = URL(fileURLWithPath: "/tmp/ourin-video-ghost-unsupported", isDirectory: true)
        let manager = GhostManager(ghostURL: root)

        // 非対応コーデック(.wmv)はAVPlayer側の再生を試みず、失敗通知のみで即返る。
        manager.playVideo(filename: "legacy.wmv")

        #expect(GhostManager.videoFileSupport(for: "legacy.wmv") == .unsupported)
    }

    @Test
    func playVideoOnMissingFileDoesNotCrash() async throws {
        let root = URL(fileURLWithPath: "/tmp/ourin-video-ghost-missing", isDirectory: true)
        let manager = GhostManager(ghostURL: root)

        // 対応拡張子だがファイルが存在しないケース。
        manager.playVideo(filename: "does-not-exist.mp4")
    }

    // MARK: - sound,load 動画プリロード

    @Test
    func soundPlaybackOptionsMergePrefersPlayOverLoadAndKeepsUnspecifiedLoad() async throws {
        let load = SoundPlaybackOptions.parse([
            "--volume=50", "--balance=-100", "--rate=200", "--seektime=1000", "--window=false"
        ])
        let play = SoundPlaybackOptions.parse([
            "--volume=100", "--seektime=@+2"
        ])
        let merged = load.merging(play)

        // play 側で指定されたフィールドは play 優先
        #expect(merged.volume == 1.0)
        // play 未指定のフィールドは load 設定を保持
        #expect(merged.balance == -1.0)
        #expect(merged.rate == 2.0)
        #expect(merged.showWindow == false)
        switch merged.seektime {
        case .relative(let delta):
            #expect(abs(delta - 2) < 0.0001)
        default:
            Issue.record("Expected relative seek, got \(String(describing: merged.seektime))")
        }

        // play 側が空なら load 設定がそのまま残る
        let unchanged = load.merging(.parse([]))
        #expect(unchanged == load)
    }

    @Test
    func videoPreloadPlayerHoldsAVAssetsUntilConsumed() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("preload-\(UUID().uuidString).mp4")
        let preloaded = VideoPreloadPlayer(filename: "preload.mp4", url: url, options: .parse(["--volume=50", "--seektime=1000"]))

        #expect(preloaded.filename == "preload.mp4")
        #expect(preloaded.asset.url == url)
        // 生成した AVPlayerItem は生成した AVPlayer のみに接続されている
        #expect(preloaded.player.currentItem === preloaded.item)
        #expect(preloaded.options.volume == 0.5)
        #expect(preloaded.options.seektime != nil)
        #expect(!preloaded.isConsumed)

        preloaded.markConsumed()
        #expect(preloaded.isConsumed)

        // consumed 済みの discard は移管済みプレイヤーを破棄しない
        preloaded.discard()
        #expect(preloaded.isConsumed)
    }

    @Test
    func loadVideoStoresPreloadAndRejectsMissingUnsupportedNonVideo() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ourin-video-load-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let master = root.appendingPathComponent("ghost/master", isDirectory: true)
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        try Data("not real video".utf8).write(to: master.appendingPathComponent("clip.mp4"))

        let manager = GhostManager(ghostURL: root)

        // 存在するファイル → プリロード生成（オプションはプリロードに保持される）
        manager.loadVideo(filename: "clip.mp4", options: ["--volume=50", "--seektime=1000"])
        #expect(manager.preloadedVideos["clip.mp4"]?.count == 1)
        #expect(manager.preloadedVideos["clip.mp4"]?.first?.options.volume == 0.5)

        // 同一 filename の複数 load はスタックされる
        manager.loadVideo(filename: "clip.mp4")
        #expect(manager.preloadedVideos["clip.mp4"]?.count == 2)

        // 存在しないファイル → プリロードなし
        manager.loadVideo(filename: "missing.mp4")
        #expect(manager.preloadedVideos["missing.mp4"] == nil)

        // 非対応形式 → プリロードなし
        manager.loadVideo(filename: "clip.avi")
        #expect(manager.preloadedVideos["clip.avi"] == nil)

        // 動画以外 → プリロードなし
        manager.loadVideo(filename: "clip.txt")
        #expect(manager.preloadedVideos["clip.txt"] == nil)

        manager.stopAllVideos()
        #expect(manager.preloadedVideos.isEmpty)
    }

    @Test
    func stopVideoAndStopAllVideosDiscardVideoPreloads() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ourin-video-stop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let master = root.appendingPathComponent("ghost/master", isDirectory: true)
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        try Data("not real video".utf8).write(to: master.appendingPathComponent("clip.mp4"))

        let manager = GhostManager(ghostURL: root)
        manager.loadVideo(filename: "clip.mp4")
        #expect(manager.preloadedVideos["clip.mp4"]?.count == 1)

        // 再生中でなくても stopVideo は該当 filename のプリロードを破棄する
        manager.stopVideo(filename: "clip.mp4")
        #expect(manager.preloadedVideos["clip.mp4"] == nil)

        manager.loadVideo(filename: "clip.mp4")
        manager.loadVideo(filename: "clip.mp4")
        #expect(manager.preloadedVideos["clip.mp4"]?.count == 2)

        manager.stopAllVideos()
        #expect(manager.preloadedVideos.isEmpty)
    }

    @Test
    func playVideoConsumesPreloadedInstanceAndFallsBackToDirectPlay() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ourin-video-play-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let master = root.appendingPathComponent("ghost/master", isDirectory: true)
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        try Data("not real video".utf8).write(to: master.appendingPathComponent("clip.mp4"))

        let manager = GhostManager(ghostURL: root)

        // プリロードしてから play → 1つ消費される
        manager.loadVideo(filename: "clip.mp4")
        #expect(manager.preloadedVideos["clip.mp4"]?.count == 1)
        // --sound-only でウィンドウ生成を避けて再生経路のみ確認する
        manager.playVideo(filename: "clip.mp4", options: ["--sound-only=true"])
        #expect(manager.preloadedVideos["clip.mp4"] == nil)
        #expect(manager.videoPlayers["clip.mp4"] != nil)

        // 2回目はプリロードが無いため従来どおり URL から再生する
        manager.playVideo(filename: "clip.mp4", options: ["--sound-only=true"])
        #expect(manager.videoPlayers["clip.mp4"] != nil)

        manager.stopAllVideos()
        #expect(manager.videoPlayers.isEmpty)
        #expect(manager.preloadedVideos.isEmpty)
    }

    @Test
    func soundLoadScriptRoutesVideoToVideoPreload() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ourin-video-script-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let master = root.appendingPathComponent("ghost/master", isDirectory: true)
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        try Data("not real video".utf8).write(to: master.appendingPathComponent("clip.mp4"))

        let manager = GhostManager(ghostURL: root)
        manager.runScript(#"\![sound,load,clip.mp4]"#)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(manager.preloadedVideos["clip.mp4"]?.count == 1)
        manager.stopAllVideos()
        #expect(manager.preloadedVideos.isEmpty)
    }
}
