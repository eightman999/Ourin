import AppKit
import AVFoundation
import AVKit
import MediaToolbox

/// --seektime の値。絶対シーク（ミリ秒または H:MM:SS(.fraction)）と
/// @+/@− による現在位置からの相対シーク（秒、`ms` 接尾辞でミリ秒）を表す。
enum SeekTime: Equatable {
    case absolute(TimeInterval)
    case relative(TimeInterval)
}

struct SoundPlaybackOptions: Equatable {
    var volume: Float?
    var balance: Float?
    var rate: Float?
    var seektime: SeekTime?
    var showWindow: Bool?
    var soundOnly: Bool?

    var isEmpty: Bool {
        volume == nil && balance == nil && rate == nil && seektime == nil
            && showWindow == nil && soundOnly == nil
    }

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
            case "seektime":
                if let raw = value {
                    parsed.seektime = parseSeekTime(raw)
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

    /// --seektime の値を解釈する。
    /// - 数値のみ: ミリ秒（例: 2500 → 2.5 秒）
    /// - `ms` 接尾辞: 明示的なミリ秒（例: 2500ms → 2.5 秒）
    /// - `H:MM:SS(.fraction)` 相当: コロン区切りの絶対時刻（例: 1:30.5 → 90.5 秒）
    /// - `@+` / `@-`: 現在位置からの相対シーク（秒、`ms` 接尾辞でミリ秒）
    static func parseSeekTime(_ rawValue: String) -> SeekTime? {
        var raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        var milliseconds = false
        if raw.lowercased().hasSuffix("ms") {
            milliseconds = true
            raw = String(raw.dropLast(2))
        }

        if raw.hasPrefix("@") {
            let body = String(raw.dropFirst())
            guard !body.isEmpty else { return nil }
            let sign = body.first
            let magnitude = sign == "+" || sign == "-" ? String(body.dropFirst()) : body
            guard let amount = Double(magnitude) else { return nil }
            let delta = amount * (milliseconds ? 0.001 : 1.0)
            return .relative(sign == "-" ? -delta : delta)
        }

        let parts = raw.split(separator: ":").map(String.init)
        // ms suffix is defined for scalar values and relative offsets only;
        // accepting it on a clock-form value would silently produce seconds.
        if milliseconds && parts.count > 1 { return nil }
        switch parts.count {
        case 1:
            guard let number = Double(parts[0]) else { return nil }
            // 数値は常にミリ秒として解釈する。
            return .absolute(number * 0.001)
        case 2:
            guard let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
            return .absolute(minutes * 60 + seconds)
        case 3:
            guard let hours = Double(parts[0]), let minutes = Double(parts[1]), let seconds = Double(parts[2]) else { return nil }
            return .absolute(hours * 3600 + minutes * 60 + seconds)
        default:
            return nil
        }
    }

    /// プリロード時（load）と再生時（play）のオプションをフィールド単位でマージする。
    /// `newer`（play 側）で指定されたフィールドを優先し、未指定フィールドは
    /// `self`（load 側）の設定を保持する。動画のプリロード→再生で1回だけ適用するため、
    /// 相対 --seektime の二重適用は発生しない。
    func merging(_ newer: SoundPlaybackOptions) -> SoundPlaybackOptions {
        var merged = self
        if let value = newer.volume { merged.volume = value }
        if let value = newer.balance { merged.balance = value }
        if let value = newer.rate { merged.rate = value }
        if let value = newer.seektime { merged.seektime = value }
        if let value = newer.showWindow { merged.showWindow = value }
        if let value = newer.soundOnly { merged.soundOnly = value }
        return merged
    }
}

/// Normalized stereo balance gains. -1 is full left, 0 is centered, and +1 is full right.
struct AudioBalanceGains: Equatable {
    let left: Float
    let right: Float

    init(balance: Float) {
        let value = max(-1, min(1, balance))
        left = value > 0 ? 1 - value : 1
        right = value < 0 ? 1 + value : 1
    }
}

private final class AudioBalanceTapContext {
    let gains: AudioBalanceGains
    var format = AudioStreamBasicDescription()

    init(balance: Float) {
        self.gains = AudioBalanceGains(balance: balance)
    }

    func prepare(_ format: AudioStreamBasicDescription) {
        self.format = format
    }
}

private func audioBalanceTapInit(
    _ tap: MTAudioProcessingTap,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    tapStorageOut.pointee = clientInfo
}

private func audioBalanceTapFinalize(_ tap: MTAudioProcessingTap) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<AudioBalanceTapContext>.fromOpaque(storage).release()
}

private func audioBalanceTapPrepare(
    _ tap: MTAudioProcessingTap,
    _ maxFrames: CMItemCount,
    _ processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<AudioBalanceTapContext>.fromOpaque(storage).takeUnretainedValue()
    context.prepare(processingFormat.pointee)
}

private func audioBalanceTapUnprepare(_ tap: MTAudioProcessingTap) {}

private func audioBalanceTapProcess(
    _ tap: MTAudioProcessingTap,
    _ numberFrames: CMItemCount,
    _ flags: MTAudioProcessingTapFlags,
    _ bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    _ numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    var sourceFlags = MTAudioProcessingTapFlags(0)
    var sourceFrames = CMItemCount(0)
    let status = MTAudioProcessingTapGetSourceAudio(
        tap,
        numberFrames,
        bufferListInOut,
        &sourceFlags,
        nil,
        &sourceFrames
    )
    guard status == noErr else {
        numberFramesOut.pointee = 0
        flagsOut.pointee = sourceFlags
        return
    }

    numberFramesOut.pointee = sourceFrames
    flagsOut.pointee = sourceFlags

    let context = Unmanaged<AudioBalanceTapContext>.fromOpaque(
        MTAudioProcessingTapGetStorage(tap)
    ).takeUnretainedValue()
    let format = context.format
    guard format.mFormatID == kAudioFormatLinearPCM,
          format.mChannelsPerFrame == 2,
          sourceFrames > 0 else {
        return
    }

    let buffers = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    let isNonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
    let isFloat32 = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        && format.mBitsPerChannel == 32
    let isInt16 = (format.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
        && format.mBitsPerChannel == 16
    let frameCount = Int(sourceFrames)

    if isFloat32 {
        if isNonInterleaved {
            guard buffers.count >= 2,
                  let leftData = buffers[0].mData,
                  let rightData = buffers[1].mData else { return }
            let leftFrames = min(frameCount, Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.stride)
            let rightFrames = min(frameCount, Int(buffers[1].mDataByteSize) / MemoryLayout<Float>.stride)
            let frames = min(leftFrames, rightFrames)
            let left = leftData.assumingMemoryBound(to: Float.self)
            let right = rightData.assumingMemoryBound(to: Float.self)
            for index in 0..<frames {
                left[index] *= context.gains.left
                right[index] *= context.gains.right
            }
        } else {
            guard let data = buffers.first?.mData else { return }
            let bytesPerFrame = max(Int(format.mBytesPerFrame), MemoryLayout<Float>.stride * 2)
            let frames = min(frameCount, Int(buffers[0].mDataByteSize) / bytesPerFrame)
            let samples = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frames {
                samples[frame * 2] *= context.gains.left
                samples[frame * 2 + 1] *= context.gains.right
            }
        }
    } else if isInt16 {
        if isNonInterleaved {
            guard buffers.count >= 2,
                  let leftData = buffers[0].mData,
                  let rightData = buffers[1].mData else { return }
            let leftFrames = min(frameCount, Int(buffers[0].mDataByteSize) / MemoryLayout<Int16>.stride)
            let rightFrames = min(frameCount, Int(buffers[1].mDataByteSize) / MemoryLayout<Int16>.stride)
            let frames = min(leftFrames, rightFrames)
            let left = leftData.assumingMemoryBound(to: Int16.self)
            let right = rightData.assumingMemoryBound(to: Int16.self)
            for index in 0..<frames {
                left[index] = scalePCM16(left[index], by: context.gains.left)
                right[index] = scalePCM16(right[index], by: context.gains.right)
            }
        } else {
            guard let data = buffers.first?.mData else { return }
            let bytesPerFrame = max(Int(format.mBytesPerFrame), MemoryLayout<Int16>.stride * 2)
            let frames = min(frameCount, Int(buffers[0].mDataByteSize) / bytesPerFrame)
            let samples = data.assumingMemoryBound(to: Int16.self)
            for frame in 0..<frames {
                samples[frame * 2] = scalePCM16(samples[frame * 2], by: context.gains.left)
                samples[frame * 2 + 1] = scalePCM16(samples[frame * 2 + 1], by: context.gains.right)
            }
        }
    }
}

private func scalePCM16(_ sample: Int16, by gain: Float) -> Int16 {
    let scaled = (Float(sample) * gain).rounded()
    return Int16(max(Float(Int16.min), min(Float(Int16.max), scaled)))
}

/// \![sound,load] で事前生成される動画プリロード。
/// AVURLAsset / AVPlayerItem / AVPlayer を保持し、play 時にそのまま移管することで
/// 再生開始までの動画準備コストを load 時点へ前倒しする。
/// AVPlayerItem は同時に1つの AVPlayer にしか接続できないため、play へ移管後は
/// `isConsumed` を立てて再使用しない。オプション適用は play 時にマージして1回だけ
/// 行うため、load 段階では保持のみとする（--seektime の二重適用を避ける）。
final class VideoPreloadPlayer {
    let filename: String
    let options: SoundPlaybackOptions
    let asset: AVURLAsset
    let item: AVPlayerItem
    let player: AVPlayer
    private(set) var isConsumed = false

    init(filename: String, url: URL, options: SoundPlaybackOptions) {
        self.filename = filename
        self.options = options
        let asset = AVURLAsset(url: url)
        self.asset = asset
        let item = AVPlayerItem(asset: asset)
        self.item = item
        self.player = AVPlayer(playerItem: item)
    }

    /// play に移管済みであることを記録する。移管後はこのインスタンスを停止してはならない。
    func markConsumed() {
        isConsumed = true
    }

    /// 未消費のプリロードを破棄し、AVPlayer が保持するデコードリソースを解放する。
    func discard() {
        guard !isConsumed else { return }
        player.pause()
        player.replaceCurrentItem(with: nil)
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
        // このコントローラは再生時にウィンドウとプレイヤービューを生成する。
        // nib/storyboard から復元できる状態を持たないため、非対応の復元をクラッシュさせず拒否する。
        return nil
    }

    deinit {
        cleanupPlayer()
    }

    /// 通常再生。既存の公開契約（引数・戻り値）を維持する。
    @discardableResult
    func play(url: URL, loop: Bool, soundOnly: Bool, showWindow: Bool, volume: Float, rate: Float, balance: Float? = nil) -> Bool {
        var options = SoundPlaybackOptions()
        options.volume = volume
        options.rate = rate
        options.balance = balance
        options.soundOnly = soundOnly
        options.showWindow = showWindow
        return play(url: url, loop: loop, options: options)
    }

    /// オプション一式を適用する通常再生。--seektime は再生開始前に適用する。
    @discardableResult
    func play(url: URL, loop: Bool, options: SoundPlaybackOptions) -> Bool {
        preparePlayback(loop: loop, soundOnly: options.soundOnly ?? false, showWindow: options.showWindow ?? true)
        playbackRate = max(0.01, options.rate ?? 1.0)

        let item = AVPlayerItem(url: url)
        if let balance = options.balance, let audioMix = makeAudioMix(for: item, balance: balance) {
            item.audioMix = audioMix
        }
        let player = AVPlayer(playerItem: item)
        player.volume = max(0, min(1, options.volume ?? 1.0))
        installPlayer(player: player, item: item)
        updateWindowVisibility(for: url)
        beginPlayback(seektime: options.seektime)
        return true
    }

    /// プリロード済みプレイヤーを移管して再生する。
    /// load 時オプションと play 時オプションをフィールド単位でマージし、play 時指定を優先して
    /// 再生開始前に適用する。プリロード段階ではオプション未適用のため、マージ結果を
    /// ここで1回だけ適用する（--seektime の二重適用は発生しない）。
    @discardableResult
    func play(preloaded: VideoPreloadPlayer, loop: Bool, options: SoundPlaybackOptions) -> Bool {
        let merged = preloaded.options.merging(options)
        preparePlayback(loop: loop, soundOnly: merged.soundOnly ?? false, showWindow: merged.showWindow ?? true)
        playbackRate = max(0.01, merged.rate ?? 1.0)

        let player = preloaded.player
        let item = preloaded.item
        player.volume = max(0, min(1, merged.volume ?? 1.0))
        if let balance = merged.balance, let audioMix = makeAudioMix(for: item, balance: balance) {
            item.audioMix = audioMix
        }
        installPlayer(player: player, item: item)
        preloaded.markConsumed()
        updateWindowVisibility(for: preloaded.asset.url)
        beginPlayback(seektime: merged.seektime)
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
        if let balance = options.balance,
           let item = player?.currentItem,
           let audioMix = makeAudioMix(for: item, balance: balance) {
            item.audioMix = audioMix
        }
        if let seektime = options.seektime {
            applySeek(seektime)
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

    private func preparePlayback(loop: Bool, soundOnly: Bool, showWindow: Bool) {
        cleanupPlayer()
        didStop = false
        loops = loop
        self.soundOnly = soundOnly
        shouldShowWindow = showWindow
    }

    private func installPlayer(player: AVPlayer, item: AVPlayerItem) {
        self.player = player
        playerView?.player = player
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.handlePlaybackEnded()
        }
    }

    private func beginPlayback(seektime: SeekTime?) {
        guard let player else { return }
        if let seektime {
            // 再生開始前にシークを完了させてから再生を始める。
            applySeek(seektime) { [weak self] _ in
                guard let self, let player = self.player else { return }
                player.playImmediately(atRate: self.playbackRate)
            }
        } else {
            player.playImmediately(atRate: playbackRate)
        }
    }

    /// --seektime（絶対/相対）を適用する。再生開始前の適用は beginPlayback が
    /// シーク完了を待ってから再生を開始する。相対シークは現在位置基準。
    private func applySeek(_ target: SeekTime, completion: ((Bool) -> Void)? = nil) {
        guard let player else { return }
        let duration = player.currentItem?.duration ?? .invalid
        let durationSeconds = duration.isNumeric ? CMTimeGetSeconds(duration) : TimeInterval.greatestFiniteMagnitude
        let clamped = { (value: TimeInterval) -> TimeInterval in
            guard durationSeconds.isFinite else { return max(0, value) }
            return max(0, min(value, durationSeconds))
        }
        let time: CMTime
        switch target {
        case .absolute(let seconds):
            time = CMTime(seconds: clamped(seconds), preferredTimescale: 600)
        case .relative(let delta):
            let current = CMTimeGetSeconds(player.currentTime())
            let base = current.isFinite ? current : 0
            time = CMTime(seconds: clamped(base + delta), preferredTimescale: 600)
        }
        if let completion {
            player.seek(to: time, completionHandler: completion)
        } else {
            player.seek(to: time)
        }
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

    private func makeAudioMix(for item: AVPlayerItem, balance: Float) -> AVAudioMix? {
        guard let track = item.asset.tracks(withMediaType: .audio).first else {
            return nil
        }

        let context = AudioBalanceTapContext(balance: balance)
        let clientInfo = Unmanaged.passRetained(context).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientInfo,
            init: audioBalanceTapInit,
            finalize: audioBalanceTapFinalize,
            prepare: audioBalanceTapPrepare,
            unprepare: audioBalanceTapUnprepare,
            process: audioBalanceTapProcess
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tap
        )
        guard status == noErr, let tap else {
            Unmanaged<AudioBalanceTapContext>.fromOpaque(clientInfo).release()
            Log.info("[VideoPlayerWindow] Failed to create audio balance processor; preserving original audio")
            return nil
        }

        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [parameters]
        return audioMix
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
