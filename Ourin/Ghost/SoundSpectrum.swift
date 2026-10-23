import Accelerate
import AVFoundation
import Foundation

// \![sound,play,...,--spectrum=間隔] の OnSoundSpectrum（UKADOC 2.9.18〜2.9.20）。
//
// 再生中の波形を約85ミリ秒の窓で FFT し、ISO 標準数の中心周波数で分けた帯域ごとの音量レベル
// （-60dB を 0、0dB を 100）を一定間隔で通知する。複数チャンネルは平均した1本の音として帯域を解析し、
// 全体のレベルはチャンネルごとに求める。

/// ISO 標準数の中心周波数による帯域（5/10/15/31 帯域）。
enum SpectrumBands {
    static let supportedCounts = [0, 5, 10, 15, 31]

    private static let centers5: [Double] = [63, 250, 1000, 4000, 16000]
    private static let centers10: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    private static let centers15: [Double] = [25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000]
    private static let centers31: [Double] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250,
        1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
    ]

    /// 指定の数に最も近い帯域数（0・5・10・15・31）。16 なら 15、20 なら 15、64 なら 31。
    static func nearestSupported(_ requested: Int) -> Int {
        supportedCounts.min { abs($0 - requested) < abs($1 - requested) } ?? 10
    }

    static func centers(count: Int) -> [Double] {
        switch count {
        case 5: return centers5
        case 15: return centers15
        case 31: return centers31
        case 10: return centers10
        default: return []
        }
    }

    /// 帯域の範囲（Hz）。隣り合う中心周波数の幾何平均を境目とし、両端は外側へ同じ倍率で延ばす。
    static func ranges(count: Int) -> [(low: Double, high: Double)] {
        let c = centers(count: count)
        guard c.count >= 2 else { return [] }
        var edges: [Double] = [c[0] / (c[1] / c[0]).squareRoot()]
        for index in 1..<c.count { edges.append((c[index - 1] * c[index]).squareRoot()) }
        edges.append(c[c.count - 1] * (c[c.count - 1] / c[c.count - 2]).squareRoot())
        return (0..<c.count).map { (edges[$0], edges[$0 + 1]) }
    }
}

enum SpectrumAnalyzer {
    /// 解析窓の点数。サンプルレートに合わせて約 85 ミリ秒（44.1kHz・48kHz では 4096 点）。
    static func windowSize(sampleRate: Double) -> Int {
        var size = 256
        while Double(size) < sampleRate * 0.085 && size < 16_384 { size *= 2 }
        return size
    }

    /// 振幅（振幅 1.0 の正弦波を満点とする値）を 0〜100 のレベルへ。-60dB を 0、0dB を 100。
    static func level(amplitude: Double) -> Double {
        guard amplitude > 0 else { return 0 }
        let decibels = 20 * log10(amplitude)
        return max(0, min(100, (decibels + 60) / 60 * 100))
    }

    /// チャンネルごとの全体のレベル。窓全体の二乗平均から、正弦波の振幅に換算する。
    static func channelLevels(channels: [[Float]]) -> [Double] {
        channels.map { samples in
            guard !samples.isEmpty else { return 0 }
            var meanSquare: Float = 0
            vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(samples.count))
            return level(amplitude: (2 * Double(meanSquare)).squareRoot())
        }
    }

    /// 帯域ごとのレベル。チャンネルは平均した 1 本の音として扱う。
    /// - Parameter channels: チャンネルごとのサンプル。窓の点数（`windowSize`）に揃えて渡す。
    static func bandLevels(channels: [[Float]], sampleRate: Double, bandCount: Int) -> [Double] {
        let ranges = SpectrumBands.ranges(count: bandCount)
        guard !ranges.isEmpty, let first = channels.first, !first.isEmpty else {
            return Array(repeating: 0, count: ranges.count)
        }
        let size = first.count
        let log2n = vDSP_Length(log2(Double(size)).rounded())
        guard size == 1 << Int(log2n), let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return Array(repeating: 0, count: ranges.count)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        // 平均した 1 本の音に、ハン窓を掛ける。
        var mono = [Float](repeating: 0, count: size)
        for channel in channels where channel.count == size { vDSP_vadd(mono, 1, channel, 1, &mono, 1, vDSP_Length(size)) }
        var divisor = Float(channels.count)
        vDSP_vsdiv(mono, 1, &divisor, &mono, 1, vDSP_Length(size))
        var hann = [Float](repeating: 0, count: size)
        for index in 0..<size { hann[index] = 0.5 * (1 - cos(2 * Float.pi * Float(index) / Float(size))) }
        vDSP_vmul(mono, 1, hann, 1, &mono, 1, vDSP_Length(size))
        var windowEnergy: Float = 0
        vDSP_svesq(hann, 1, &windowEnergy, vDSP_Length(size))

        let half = size / 2
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var power = [Double](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                mono.withUnsafeBufferPointer { pointer in
                    pointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                for bin in 1..<half {
                    // vDSP の実数 FFT は真の DFT の 2 倍の値を返す。
                    let re = Double(realPointer[bin]) / 2
                    let im = Double(imaginaryPointer[bin]) / 2
                    power[bin] = re * re + im * im
                }
            }
        }

        let nyquist = sampleRate / 2
        let binWidth = sampleRate / Double(size)
        return ranges.map { range in
            // ナイキスト周波数より上に範囲の半分以上がかかる帯域は 0。
            let covered = min(range.high, nyquist) - range.low
            guard covered > 0, covered >= (range.high - range.low) / 2 else { return 0 }
            var energy = 0.0
            for bin in 1..<half {
                let frequency = Double(bin) * binWidth
                if frequency >= range.low && frequency < range.high { energy += power[bin] }
            }
            // 片側スペクトルの合計エネルギー → 窓で補正した二乗平均 → 正弦波の振幅。
            let meanSquare = 2 * energy / Double(size) / Double(windowEnergy)
            return level(amplitude: (2 * meanSquare).squareRoot())
        }
    }
}

/// 値は上がるときは即座に反映し、下がるときは 100 から 0 まで 500 ミリ秒の速さで落とす。
/// ピークは、現在の値がピークを超えるたびに上げてホールド時間を数え直し、ホールド時間のあいだ動かず、
/// それを過ぎると 1 秒で 100 の速さで落ちる（途中で現在の値に追いつかれたら、そこからまた同じ動きを始める）。
struct SpectrumLevelTracker {
    static let fallPerSecond = 100.0 / 0.5
    static let peakFallPerSecond = 100.0

    var holdSeconds: Double
    private(set) var levels: [Double] = []
    private(set) var peaks: [Double] = []
    private var holdUntil: [Double] = []
    private var lastTime: Double?

    init(holdMilliseconds: Int = 500) {
        holdSeconds = Double(max(0, min(10_000, holdMilliseconds))) / 1000
    }

    mutating func update(measured: [Double], at time: Double) {
        let dt = lastTime.map { max(0, time - $0) } ?? 0
        lastTime = time
        if levels.count != measured.count {
            levels = Array(repeating: 0, count: measured.count)
            peaks = Array(repeating: 0, count: measured.count)
            holdUntil = Array(repeating: 0, count: measured.count)
        }
        for index in measured.indices {
            levels[index] = max(measured[index], levels[index] - Self.fallPerSecond * dt)
            if holdSeconds == 0 {
                peaks[index] = levels[index]
            } else if levels[index] >= peaks[index] {
                peaks[index] = levels[index]
                holdUntil[index] = time + holdSeconds
            } else if time > holdUntil[index] {
                peaks[index] = max(levels[index], peaks[index] - Self.peakFallPerSecond * dt)
            }
        }
    }

    mutating func reset() {
        levels = levels.map { _ in 0 }
        peaks = peaks.map { _ in 0 }
        lastTime = nil
    }
}

struct SpectrumReport: Equatable {
    var filename: String
    var bandCount: Int
    var channelLevels: [Int]
    var channelPeaks: [Int]
    var bandLevels: [Int]
    var bandPeaks: [Int]
    var positionMilliseconds: Int

    /// OnSoundSpectrum の ReferenceN。配列はバイト値1区切り。帯域なしのときは R4・R5 が空。
    var references: [String: String] {
        let separator = "\u{1}"
        func join(_ values: [Int]) -> String { values.map(String.init).joined(separator: separator) }
        return [
            "Reference0": filename,
            "Reference1": String(bandCount),
            "Reference2": join(channelLevels),
            "Reference3": join(channelPeaks),
            "Reference4": join(bandLevels),
            "Reference5": join(bandPeaks),
            "Reference6": String(positionMilliseconds)
        ]
    }
}

/// 1 つのサウンドの、スペクトラム通知の設定と解析。
final class SoundSpectrumEngine {
    static let minimumInterval = 20
    static let maximumInterval = 1000
    static let maximumChannels = 8

    let filename: String
    private let fileURL: URL?
    private let position: () -> TimeInterval
    private let isPlaying: () -> Bool
    private let report: (SpectrumReport) -> Void

    private(set) var interval: Int?
    private(set) var bandCount = 10
    private var channelTracker = SpectrumLevelTracker()
    private var bandTracker = SpectrumLevelTracker()
    private var timer: DispatchSourceTimer?
    private var file: AVAudioFile?
    private var lastChannelCount = 1
    private var lastPosition = 0
    private var startedAt = Date()

    /// - Parameters:
    ///   - fileURL: 解析する音声ファイル。nil（ストリーミングなど）では、帯域なしのときの再生位置だけ通知する。
    ///   - position: 現在の再生位置（秒）。
    ///   - isPlaying: 再生中か（一時停止中は通知しない）。
    ///   - report: 通知の送出先（メインキューで呼ぶ）。
    init(filename: String,
         fileURL: URL?,
         position: @escaping () -> TimeInterval,
         isPlaying: @escaping () -> Bool,
         report: @escaping (SpectrumReport) -> Void) {
        self.filename = filename
        self.fileURL = fileURL
        self.position = position
        self.isPlaying = isPlaying
        self.report = report
    }

    deinit { timer?.cancel() }

    /// `--spectrum=間隔`（20〜1000 に丸める。0 なら止める）、`--spectrum-bands`、`--spectrum-hold`。
    func configure(interval requestedInterval: Int?, bands: Int?, holdMilliseconds: Int?) {
        if let bands { bandCount = SpectrumBands.nearestSupported(bands) }
        if let holdMilliseconds {
            channelTracker.holdSeconds = Double(max(0, min(10_000, holdMilliseconds))) / 1000
            bandTracker.holdSeconds = channelTracker.holdSeconds
        }
        guard let requestedInterval else { return }
        if requestedInterval <= 0 {
            stop(sendZero: true)
            interval = nil
            return
        }
        let clamped = max(Self.minimumInterval, min(Self.maximumInterval, requestedInterval))
        interval = clamped
        startTimer(milliseconds: clamped)
    }

    /// 停止・終了・`--spectrum=0` のとき。通知中だったなら、全レベル 0 の通知を 1 回送る。
    func stop(sendZero: Bool) {
        let wasRunning = timer != nil
        timer?.cancel()
        timer = nil
        guard wasRunning, sendZero else { return }
        emit(channels: Array(repeating: 0, count: lastChannelCount), bands: Array(repeating: 0, count: bandCount), position: lastPosition, resetTrackers: true)
    }

    private func startTimer(milliseconds: Int) {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(milliseconds), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
        startedAt = Date()
    }

    private func tick() {
        guard isPlaying() else { return }
        let seconds = position()
        let positionMs = Int((seconds * 1000).rounded())
        lastPosition = positionMs
        guard let measured = measure(at: seconds) else {
            // 波形を取り出せない音は、帯域なしのときだけ再生位置を通知する（音量は 0）。
            if bandCount == 0 {
                emit(channels: Array(repeating: 0, count: lastChannelCount), bands: [], position: positionMs, resetTrackers: false)
            }
            return
        }
        lastChannelCount = measured.channels.count
        emit(channels: measured.channels, bands: measured.bands, position: positionMs, resetTrackers: false)
    }

    private func measure(at seconds: TimeInterval) -> (channels: [Double], bands: [Double])? {
        guard let fileURL else { return nil }
        if file == nil { file = try? AVAudioFile(forReading: fileURL) }
        guard let file else { return nil }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let size = SpectrumAnalyzer.windowSize(sampleRate: sampleRate)
        // 窓は現在の再生位置で終わる。ファイルの先頭付近は足りない分を無音で埋める（開始直後は小さめに出る）。
        let end = max(0, Int(seconds * sampleRate))
        let start = max(0, end - size)
        let available = max(0, min(size, end - start))
        guard available > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(size)) else {
            return (Array(repeating: 0, count: min(Int(format.channelCount), Self.maximumChannels)), Array(repeating: 0, count: bandCount))
        }
        file.framePosition = AVAudioFramePosition(start)
        do { try file.read(into: buffer, frameCount: AVAudioFrameCount(available)) } catch { return nil }
        guard let data = buffer.floatChannelData else { return nil }
        let channelCount = min(Int(format.channelCount), Self.maximumChannels)
        let frames = Int(buffer.frameLength)
        var channels: [[Float]] = []
        for channel in 0..<channelCount {
            var samples = [Float](repeating: 0, count: size)
            // 窓の末尾（現在位置）に合わせて詰め、手前は無音のまま。
            for index in 0..<min(frames, size) { samples[size - frames + index] = data[channel][index] }
            channels.append(samples)
        }
        let channelLevels = SpectrumAnalyzer.channelLevels(channels: channels)
        let bands = bandCount == 0 ? [] : SpectrumAnalyzer.bandLevels(channels: channels, sampleRate: sampleRate, bandCount: bandCount)
        return (channelLevels, bands)
    }

    private func emit(channels: [Double], bands: [Double], position: Int, resetTrackers: Bool) {
        let now = Date().timeIntervalSince(startedAt)
        if resetTrackers {
            channelTracker.reset()
            bandTracker.reset()
            report(SpectrumReport(
                filename: filename, bandCount: bandCount,
                channelLevels: channels.map { Int($0.rounded()) }, channelPeaks: channels.map { Int($0.rounded()) },
                bandLevels: bands.map { Int($0.rounded()) }, bandPeaks: bands.map { Int($0.rounded()) },
                positionMilliseconds: position
            ))
            return
        }
        channelTracker.update(measured: channels, at: now)
        bandTracker.update(measured: bands, at: now)
        report(SpectrumReport(
            filename: filename, bandCount: bandCount,
            channelLevels: channelTracker.levels.map { Int($0.rounded()) },
            channelPeaks: channelTracker.peaks.map { Int($0.rounded()) },
            bandLevels: bandTracker.levels.map { Int($0.rounded()) },
            bandPeaks: bandTracker.peaks.map { Int($0.rounded()) },
            positionMilliseconds: position
        ))
    }
}
