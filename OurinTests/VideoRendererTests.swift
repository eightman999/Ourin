import Foundation
import Testing
@testable import Ourin

// GhostManager の init は PropertyManager.shared の差し替え・ResourceManager のファイルI/O・
// オブザーバ登録など共有状態に触れるため、並列実行するとフレークする。直列化して実行する。
@Suite(.serialized)
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
}
