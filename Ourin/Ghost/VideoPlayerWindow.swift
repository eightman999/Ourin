import AppKit
import AVFoundation
import AVKit

struct SoundPlaybackOptions: Equatable {
    var volume: Float?
    var balance: Float?
    var rate: Float?
    var showWindow: Bool?
    var soundOnly: Bool?

    static func parse(_ options: [String]) -> SoundPlaybackOptions {
        var parsed = SoundPlaybackOptions()
        for option in options {
            guard option.hasPrefix("--") else { continue }
            let body = String(option.dropFirst(2))
            let key: String
            let value: String?
            if let eq = body.firstIndex(of: "=") {
                key = String(body[..<eq]).lowercased()
                value = String(body[body.index(after: eq)...])
            } else {
                key = body.lowercased()
                value = nil
            }

            switch key {
            case "volume":
                if let raw = value, let number = Float(raw) {
                    parsed.volume = max(0, min(100, number)) / 100.0
                }
            case "balance":
                if let raw = value, let number = Float(raw) {
                    parsed.balance = max(-100, min(100, number)) / 100.0
                }
            case "rate":
                if let raw = value, let number = Float(raw) {
                    parsed.rate = max(1, min(10_000, number)) / 100.0
                }
            case "window":
                if let boolean = parseBool(value) {
                    parsed.showWindow = boolean
                }
            case "sound-only":
                if let boolean = parseBool(value) {
                    parsed.soundOnly = boolean
                }
            default:
                continue
            }
        }
        return parsed
    }

    private static func parseBool(_ value: String?) -> Bool? {
        guard let value else { return true }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }
}

final class VideoPlayerWindow: NSWindowController, NSWindowDelegate {
    private var player: AVPlayer?
    private var playerView: AVPlayerView?
    private var endObserver: NSObjectProtocol?
    private var playbackRate: Float = 1.0
    private var loops = false
    private var shouldShowWindow = true
    private var soundOnly = false
    private var didStop = false
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        cleanupPlayer()
    }

    @discardableResult
    func play(url: URL, loop: Bool, soundOnly: Bool, showWindow: Bool, volume: Float, rate: Float, balance: Float? = nil) -> Bool {
        cleanupPlayer()
        didStop = false
        loops = loop
        self.soundOnly = soundOnly
        shouldShowWindow = showWindow
        playbackRate = max(0.01, rate)

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = max(0, min(1, volume))
        self.player = player
        playerView?.player = player

        if balance != nil {
            Log.info("[VideoPlayerWindow] --balance is parsed but not applied; AVPlayer has no simple public stereo balance control")
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.handlePlaybackEnded()
        }

        updateWindowVisibility(for: url)
        player.playImmediately(atRate: playbackRate)
        return true
    }

    func pause() {
        player?.pause()
    }

    func resume() {
        player?.playImmediately(atRate: playbackRate)
    }

    func stop() {
        performStop(closeWindow: true)
    }

    func apply(options: SoundPlaybackOptions) {
        if let volume = options.volume {
            player?.volume = max(0, min(1, volume))
        }
        if let rate = options.rate {
            playbackRate = max(0.01, rate)
            if let player, player.rate != 0 {
                player.rate = playbackRate
            }
        }
        if options.balance != nil {
            Log.info("[VideoPlayerWindow] --balance is parsed but not applied; AVPlayer has no simple public stereo balance control")
        }
        if let soundOnly = options.soundOnly {
            self.soundOnly = soundOnly
        }
        if let showWindow = options.showWindow {
            shouldShowWindow = showWindow
        }
        updateWindowVisibility(for: nil)
    }

    func estimatedRemainingDuration() -> TimeInterval {
        guard !loops,
              let player,
              player.rate != 0,
              let item = player.currentItem else {
            return 0
        }
        let duration = CMTimeGetSeconds(item.duration)
        let current = CMTimeGetSeconds(item.currentTime())
        guard duration.isFinite, current.isFinite, duration > current else {
            return 0
        }
        return max(0, duration - current) / Double(max(0.01, playbackRate))
    }

    func windowWillClose(_ notification: Notification) {
        performStop(closeWindow: false)
    }

    private func handlePlaybackEnded() {
        guard loops, let player else {
            stop()
            return
        }
        player.seek(to: .zero) { [weak self] _ in
            guard let self else { return }
            player.playImmediately(atRate: self.playbackRate)
        }
    }

    private func updateWindowVisibility(for url: URL?) {
        guard !soundOnly, shouldShowWindow else {
            window?.orderOut(nil)
            return
        }
        ensureWindow(url: url)
        window?.orderFront(nil)
    }

    private func ensureWindow(url: URL?) {
        guard window == nil else { return }

        let contentRect = NSRect(x: 0, y: 0, width: 640, height: 360)
        let playerView = AVPlayerView(frame: contentRect)
        playerView.autoresizingMask = [.width, .height]
        playerView.controlsStyle = .default
        playerView.player = player

        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = url?.lastPathComponent ?? "Video"
        window.contentView = playerView
        window.backgroundColor = .black
        window.isOpaque = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.center()

        self.playerView = playerView
        self.window = window
    }

    private func performStop(closeWindow: Bool) {
        guard !didStop else { return }
        didStop = true
        cleanupPlayer()
        if closeWindow {
            window?.delegate = nil
            close()
        }
        onClose()
    }

    private func cleanupPlayer() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerView?.player = nil
        player = nil
    }
}
