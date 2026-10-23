import AVFoundation
import Foundation
import Testing
@testable import Ourin

private func sine(frequency: Double, amplitude: Double, sampleRate: Double, count: Int) -> [Float] {
    (0..<count).map { Float(amplitude * sin(2 * Double.pi * frequency * Double($0) / sampleRate)) }
}

struct SpectrumBandsTests {
    @Test
    func rangesFollowTheDocumentedTables() {
        func rounded(_ count: Int) -> [[Int]] {
            SpectrumBands.ranges(count: count).map { [Int($0.low.rounded()), Int($0.high.rounded())] }
        }
        // UKADOC の表: 5 帯域 32～125、125～500 … / 10 帯域 23～45、45～89 … 11314～22627。
        #expect(rounded(5).first == [32, 125])
        #expect(rounded(5).last == [8000, 32000])
        #expect(rounded(10).first == [23, 45])
        #expect(rounded(10)[1] == [45, 89])
        #expect(rounded(10)[5] == [707, 1414])
        #expect(rounded(10).last == [11314, 22627])
        #expect(rounded(15).first == [20, 32])
        #expect(rounded(15).last == [12649, 20239])
        #expect(rounded(31).count == 31)
        #expect(rounded(31).first == [18, 22])
        #expect(rounded(31).last == [17889, 22361])
        #expect(SpectrumBands.ranges(count: 0).isEmpty)
        // 帯域どうしの間に隙間も重なりもない。
        let ranges = SpectrumBands.ranges(count: 31)
        for index in 1..<ranges.count { #expect(abs(ranges[index].low - ranges[index - 1].high) < 1e-9) }
    }

    @Test
    func requestedBandCountIsRoundedToTheNearestSupportedOne() {
        #expect(SpectrumBands.nearestSupported(16) == 15)
        #expect(SpectrumBands.nearestSupported(20) == 15)
        #expect(SpectrumBands.nearestSupported(64) == 31)
        #expect(SpectrumBands.nearestSupported(0) == 0)
        #expect(SpectrumBands.nearestSupported(7) == 5)
        #expect(SpectrumBands.nearestSupported(10) == 10)
    }
}

struct SpectrumAnalyzerTests {
    @Test
    func windowIsAbout85MillisecondsAsAPowerOfTwo() {
        #expect(SpectrumAnalyzer.windowSize(sampleRate: 44_100) == 4096)
        #expect(SpectrumAnalyzer.windowSize(sampleRate: 48_000) == 4096)
        #expect(SpectrumAnalyzer.windowSize(sampleRate: 22_050) == 2048)
    }

    @Test
    func levelScaleMapsMinus60dBToZeroAndFullScaleToOneHundred() {
        #expect(SpectrumAnalyzer.level(amplitude: 1.0) == 100)
        #expect(SpectrumAnalyzer.level(amplitude: 0.001) == 0)
        #expect(SpectrumAnalyzer.level(amplitude: 0) == 0)
        // 振幅 0.5（-6dB）は約 90。
        #expect(abs(SpectrumAnalyzer.level(amplitude: 0.5) - 90) < 0.2)
        #expect(SpectrumAnalyzer.level(amplitude: 5) == 100)
    }

    @Test
    func aSineLandsInItsBandWithTheSameLevelRegardlessOfBandWidth() {
        let rate = 44_100.0
        let size = SpectrumAnalyzer.windowSize(sampleRate: rate)
        let wave = sine(frequency: 1000, amplitude: 0.5, sampleRate: rate, count: size)

        let tenBands = SpectrumAnalyzer.bandLevels(channels: [wave], sampleRate: rate, bandCount: 10)
        #expect(tenBands.count == 10)
        // 1kHz は 10 帯域の 5 番（707～1414Hz）。振幅 0.5 → 約 90。
        #expect(abs(tenBands[5] - 90) < 3)
        for (index, value) in tenBands.enumerated() where index != 5 { #expect(value < 45, "band \(index) = \(value)") }

        // 帯域の幅が違っても、同じ振幅の正弦波なら同じレベル。
        let fiveBands = SpectrumAnalyzer.bandLevels(channels: [wave], sampleRate: rate, bandCount: 5)
        #expect(abs(fiveBands[2] - tenBands[5]) < 1)
        let thirtyOne = SpectrumAnalyzer.bandLevels(channels: [wave], sampleRate: rate, bandCount: 31)
        #expect(abs((thirtyOne.max() ?? 0) - 90) < 3)

        // 振幅 1.0 の正弦波は満点付近。
        let loud = SpectrumAnalyzer.bandLevels(channels: [sine(frequency: 4000, amplitude: 1.0, sampleRate: rate, count: size)], sampleRate: rate, bandCount: 10)
        #expect(abs(loud[7] - 100) < 3)
    }

    @Test
    func channelsAreAveragedForBandsAndMeasuredSeparatelyForOverallLevel() {
        let rate = 44_100.0
        let size = SpectrumAnalyzer.windowSize(sampleRate: rate)
        let left = sine(frequency: 1000, amplitude: 0.5, sampleRate: rate, count: size)
        let right = [Float](repeating: 0, count: size)

        let overall = SpectrumAnalyzer.channelLevels(channels: [left, right])
        #expect(abs(overall[0] - 90) < 1)
        #expect(overall[1] == 0)
        // 帯域は左右を平均した 1 本の音で測るので、片側だけの音は半分の振幅（約 -6dB）になる。
        let bands = SpectrumAnalyzer.bandLevels(channels: [left, right], sampleRate: rate, bandCount: 10)
        #expect(abs(bands[5] - 80) < 3)
    }

    @Test
    func silenceIsZeroAndBandsAboveNyquistAreAlwaysZero() {
        let silent = [Float](repeating: 0, count: 4096)
        #expect(SpectrumAnalyzer.bandLevels(channels: [silent], sampleRate: 44_100, bandCount: 10).allSatisfy { $0 == 0 })
        #expect(SpectrumAnalyzer.channelLevels(channels: [silent]) == [0])

        // サンプルレート 22.05kHz のファイルでは、約 11kHz より上の帯域（11314～22627Hz）が 0。
        let rate = 22_050.0
        let size = SpectrumAnalyzer.windowSize(sampleRate: rate)
        let wave = sine(frequency: 5000, amplitude: 0.8, sampleRate: rate, count: size)
        let bands = SpectrumAnalyzer.bandLevels(channels: [wave], sampleRate: rate, bandCount: 10)
        #expect(bands[9] == 0)
        #expect(bands[7] > 70)
    }
}

struct SpectrumLevelTrackerTests {
    @Test
    func levelsRiseImmediatelyAndFallInHalfASecond() {
        var tracker = SpectrumLevelTracker(holdMilliseconds: 0)
        tracker.update(measured: [100], at: 0)
        #expect(tracker.levels == [100])
        tracker.update(measured: [0], at: 0.25)
        #expect(abs(tracker.levels[0] - 50) < 1e-6)
        tracker.update(measured: [0], at: 0.5)
        #expect(abs(tracker.levels[0]) < 1e-6)
        tracker.update(measured: [80], at: 0.6)
        #expect(tracker.levels == [80])
        // ホールド 0 ならピークは現在の値と同じ。
        #expect(tracker.peaks == tracker.levels)
    }

    @Test
    func peakHoldsThenFallsOneHundredPerSecond() {
        var tracker = SpectrumLevelTracker(holdMilliseconds: 500)
        tracker.update(measured: [100], at: 0)
        tracker.update(measured: [0], at: 0.4)
        // ホールド時間（0.5 秒）のあいだ、ピークは動かない。
        #expect(tracker.peaks == [100])
        tracker.update(measured: [0], at: 0.5)
        #expect(tracker.peaks == [100])
        // それを過ぎると、1 秒で 100 の速さで落ちる。
        tracker.update(measured: [0], at: 0.7)
        #expect(abs(tracker.peaks[0] - 80) < 1e-6)
        // 落ちている途中で現在の値が上回ったら、そこからまたホールドする。
        tracker.update(measured: [90], at: 0.8)
        #expect(tracker.peaks == [90])
        tracker.update(measured: [10], at: 1.2)
        #expect(tracker.peaks == [90])
    }
}

struct SpectrumOptionTests {
    @Test
    func optionsAreParsedAndClamped() {
        let parsed = SoundPlaybackOptions.parse(["--spectrum=5", "--spectrum-bands=16", "--spectrum-hold=20000"])
        #expect(parsed.spectrum == 20)
        #expect(parsed.spectrumBands == 15)
        #expect(parsed.spectrumHold == 10_000)
        #expect(!parsed.isEmpty)
        #expect(SoundPlaybackOptions.parse(["--spectrum=5000"]).spectrum == 1000)
        // 0 は通知を止める。
        #expect(SoundPlaybackOptions.parse(["--spectrum=0"]).spectrum == 0)
        #expect(SoundPlaybackOptions.parse(["--spectrum-bands=0"]).spectrumBands == 0)
        #expect(SoundPlaybackOptions.parse(["--volume=50"]).spectrum == nil)
    }

    @Test
    func reportReferencesJoinChannelsAndBandsWithByteOne() {
        let report = SpectrumReport(filename: "a.wav", bandCount: 5, channelLevels: [60, 55], channelPeaks: [70, 65],
                                    bandLevels: [1, 2, 3, 4, 5], bandPeaks: [6, 7, 8, 9, 10], positionMilliseconds: 1234)
        #expect(report.references["Reference0"] == "a.wav")
        #expect(report.references["Reference1"] == "5")
        #expect(report.references["Reference2"] == "60\u{1}55")
        #expect(report.references["Reference3"] == "70\u{1}65")
        #expect(report.references["Reference4"] == "1\u{1}2\u{1}3\u{1}4\u{1}5")
        #expect(report.references["Reference5"] == "6\u{1}7\u{1}8\u{1}9\u{1}10")
        #expect(report.references["Reference6"] == "1234")
        let noBands = SpectrumReport(filename: "b.wav", bandCount: 0, channelLevels: [0], channelPeaks: [0], bandLevels: [], bandPeaks: [], positionMilliseconds: 0)
        #expect(noBands.references["Reference4"] == "")
        #expect(noBands.references["Reference5"] == "")
    }
}

/// 位置と再生状態を差し替えて、音声出力の有無に左右されずにエンジンの流れを確かめる。
@Suite(.serialized)
struct SoundSpectrumEngineTests {
    /// 左 1kHz（振幅 0.5）・右 1kHz（振幅 0.25）のステレオ WAV。
    static func makeWAV(seconds: Double = 2) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ourin-spectrum-\(UUID().uuidString).wav")
        let rate = 44_100.0
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: false))
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let left = sine(frequency: 1000, amplitude: 0.5, sampleRate: rate, count: Int(frames))
        let right = sine(frequency: 1000, amplitude: 0.25, sampleRate: rate, count: Int(frames))
        for index in 0..<Int(frames) {
            buffer.floatChannelData![0][index] = left[index]
            buffer.floatChannelData![1][index] = right[index]
        }
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false
        ])
        try file.write(from: buffer)
        return url
    }

    /// 条件が揃うまで待つ。主スレッドのタイマーは、他のテストの負荷で遅れることがある。
    @MainActor
    private func wait(timeout: TimeInterval = 10, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private final class Recorder {
        var reports: [SpectrumReport] = []
        var position: TimeInterval = 0.8
        var playing = true
    }

    @MainActor
    private func makeEngine(url: URL?, recorder: Recorder) -> SoundSpectrumEngine {
        SoundSpectrumEngine(
            filename: "tone.wav",
            fileURL: url,
            position: { recorder.position },
            isPlaying: { recorder.playing },
            report: { recorder.reports.append($0) }
        )
    }

    @Test @MainActor
    func reportsLevelsPerChannelAndBandAndASingleZeroReportOnStop() async throws {
        let url = try Self.makeWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let recorder = Recorder()
        let engine = makeEngine(url: url, recorder: recorder)
        engine.configure(interval: 50, bands: 10, holdMilliseconds: 0)
        try await wait { recorder.reports.filter { $0.channelLevels.contains { $0 > 0 } }.count >= 3 }

        let live = recorder.reports.filter { $0.channelLevels.contains { $0 > 0 } }
        #expect(live.count >= 3)
        let last = try #require(live.last)
        #expect(last.bandCount == 10)
        #expect(last.channelLevels.count == 2)
        // 左は振幅 0.5（約 90）、右は 0.25（-12dB で約 80）。
        #expect(abs(last.channelLevels[0] - 90) <= 3)
        #expect(abs(last.channelLevels[1] - 80) <= 3)
        #expect(last.bandLevels.count == 10)
        // 1kHz は 10 帯域の 5 番。
        #expect(last.bandLevels.firstIndex(of: last.bandLevels.max() ?? 0) == 5)
        #expect(last.positionMilliseconds == 800)

        // 停止すると、全レベル 0 の通知を 1 回だけ送り、以降は止まる。
        engine.stop(sendZero: true)
        let before = recorder.reports.count
        let zero = try #require(recorder.reports.last)
        #expect(zero.channelLevels == [0, 0])
        #expect(zero.bandLevels == Array(repeating: 0, count: 10))
        #expect(zero.bandPeaks == Array(repeating: 0, count: 10))
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(recorder.reports.count == before)
        // 2 回目の stop では、止まっているので何も送らない。
        engine.stop(sendZero: true)
        #expect(recorder.reports.count == before)
    }

    @Test @MainActor
    func startOfFileIsPaddedWithSilenceSoTheFirstValuesAreSmaller() async throws {
        let url = try Self.makeWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let recorder = Recorder()
        recorder.position = 0.02 // 窓（約 93 ミリ秒）の 4 分の 1 ほどしか音が無い。
        let engine = makeEngine(url: url, recorder: recorder)
        engine.configure(interval: 50, bands: 10, holdMilliseconds: 0)
        try await wait { recorder.reports.contains { $0.channelLevels.contains { $0 > 0 } } }
        engine.stop(sendZero: false)
        let early = try #require(recorder.reports.first { $0.channelLevels.contains { $0 > 0 } })
        // 窓の一部しか音が無いので、全体のレベルは満たされた窓（約 90）より小さい。
        #expect(early.channelLevels[0] < 85)
        #expect(early.channelLevels[0] > 0)
    }

    @Test @MainActor
    func zeroBandsReportsOnlyOverallLevelAndPositionAndZeroIntervalStops() async throws {
        let url = try Self.makeWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let recorder = Recorder()
        let engine = makeEngine(url: url, recorder: recorder)
        engine.configure(interval: 40, bands: 0, holdMilliseconds: 0)
        try await wait { recorder.reports.contains { $0.channelLevels.contains { $0 > 0 } } }

        let first = try #require(recorder.reports.last { $0.channelLevels.contains { $0 > 0 } })
        #expect(first.bandCount == 0)
        #expect(first.bandLevels.isEmpty && first.bandPeaks.isEmpty)
        #expect(first.channelLevels.count == 2)
        #expect(first.references["Reference4"] == "")

        // --spectrum=0 は、全レベル 0 の通知を 1 回送って止める。
        engine.configure(interval: 0, bands: nil, holdMilliseconds: nil)
        let stoppedCount = recorder.reports.count
        #expect(recorder.reports.last?.channelLevels.allSatisfy { $0 == 0 } == true)
        try await Task.sleep(nanoseconds: 250_000_000)
        #expect(recorder.reports.count == stoppedCount)

        // 再生中でもいつでも再開でき、間隔は 20〜1000 に丸められる。
        engine.configure(interval: 5, bands: nil, holdMilliseconds: nil)
        #expect(engine.interval == 20)
        engine.configure(interval: 99_999, bands: nil, holdMilliseconds: nil)
        #expect(engine.interval == 1000)
        engine.configure(interval: 40, bands: 16, holdMilliseconds: nil)
        #expect(engine.bandCount == 15)
        try await wait { recorder.reports.count > stoppedCount }
        engine.stop(sendZero: false)
        #expect(recorder.reports.count > stoppedCount)
    }

    @Test @MainActor
    func pausedSoundsDoNotNotifyAndSoundsWithoutAWaveformReportPositionWhenBandsAreZero() async throws {
        let recorder = Recorder()
        recorder.playing = false
        // 波形を取り出せない音（ファイルなし）。帯域ありでは何も通知しない。
        let engine = makeEngine(url: nil, recorder: recorder)
        engine.configure(interval: 30, bands: 10, holdMilliseconds: nil)
        try await Task.sleep(nanoseconds: 250_000_000)
        #expect(recorder.reports.isEmpty)
        recorder.playing = true
        try await Task.sleep(nanoseconds: 250_000_000)
        #expect(recorder.reports.isEmpty)

        // 帯域なしなら、音量は 0 のまま再生位置だけ通知する。
        engine.configure(interval: 30, bands: 0, holdMilliseconds: nil)
        try await wait { !recorder.reports.isEmpty }
        let report = try #require(recorder.reports.first)
        #expect(report.bandCount == 0)
        #expect(report.channelLevels == [0])
        #expect(report.positionMilliseconds == 800)
        engine.stop(sendZero: false)
    }
}

/// 実際の再生と、SoundPlayer への組み込み。音声出力が使えない環境（並行実行の競合など）ではスキップする。
@Suite(.serialized)
struct SoundSpectrumPlaybackTests {
    @Test @MainActor
    func soundPlayerReportsSpectrumWhileItPlaysAndZeroWhenItStops() async throws {
        let url = try SoundSpectrumEngineTests.makeWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let options = SoundPlaybackOptions.parse(["--spectrum=50", "--spectrum-bands=10", "--spectrum-hold=0", "--seektime=800"])
        let player = try #require(SoundPlayer(filename: "tone.wav", url: url, options: options))
        var reports: [SpectrumReport] = []
        player.onSpectrum = { _, report in reports.append(report) }
        player.play()
        guard player.isPlaying else {
            print("[skip] audio output is unavailable; skipping the real playback test")
            return
        }
        let deadline = Date().addingTimeInterval(10)
        while reports.filter({ $0.channelLevels.contains { $0 > 0 } }).count < 3, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let live = reports.filter { $0.channelLevels.contains { $0 > 0 } }
        #expect(live.count >= 3, "reports=\(reports) playing=\(player.isPlaying) time=\(player.currentTime)")
        let last = try #require(live.last)
        #expect(abs(last.channelLevels[0] - 90) <= 3)
        #expect(last.positionMilliseconds >= 700)

        let before = reports.count
        player.stop()
        #expect(reports.count == before + 1)
        #expect(reports.last?.channelLevels.allSatisfy { $0 == 0 } == true)
    }

    @Test @MainActor
    func applyingSpectrumOptionsToAPlayingSoundStartsAndStopsNotifications() async throws {
        let url = try SoundSpectrumEngineTests.makeWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = try #require(SoundPlayer(filename: "tone.wav", url: url, options: SoundPlaybackOptions()))
        var reports: [SpectrumReport] = []
        player.onSpectrum = { _, report in reports.append(report) }
        player.play()
        guard player.isPlaying else {
            print("[skip] audio output is unavailable; skipping the real playback test")
            return
        }
        defer { player.stop() }
        try await Task.sleep(nanoseconds: 200_000_000)
        // --spectrum を指定しなければ通知しない。
        #expect(reports.isEmpty)
        player.apply(options: SoundPlaybackOptions.parse(["--spectrum=40"]))
        let deadline = Date().addingTimeInterval(10)
        while reports.isEmpty, Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        #expect(!reports.isEmpty)
        player.apply(options: SoundPlaybackOptions.parse(["--spectrum=0"]))
        let stopped = reports.count
        #expect(reports.last?.channelLevels.allSatisfy { $0 == 0 } == true)
        try await Task.sleep(nanoseconds: 250_000_000)
        #expect(reports.count == stopped)
    }
}
