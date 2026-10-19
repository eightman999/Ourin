import Foundation
import CoreGraphics

// TimerEmitter.swift
// Periodic timers for OnIdle and OnMinuteChange events

final class TimerEmitter {
    static let shared = TimerEmitter()
    private var isTesting = false

    // The production path uses `shared`; an internal initializer keeps the
    // timer lifecycle independently testable without sharing mutable state
    // between concurrently scheduled test cases.
    init() {}

    private var timer: DispatchSourceTimer?
    private var lastMinute: Int?
    private var lastHour: Int?
    private var handler: ((ShioriEvent) -> Void)?

    /// Start emitting timer based events
    func start(_ handler: @escaping (ShioriEvent) -> Void) {
        self.handler = handler

        // Listen for test scenario notifications
//        NotificationCenter.default.addObserver(self, selector: #selector(testScenarioStarted), name: .testScenarioStarted, object: nil)
//        NotificationCenter.default.addObserver(self, selector: #selector(testScenarioStopped), name: .testScenarioStopped, object: nil)

        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        self.timer = timer
    }

    /// Stop timers
    func stop() {
        timer?.cancel(); timer = nil
        handler = nil
        lastMinute = nil
        lastHour = nil
        isTesting = false
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func testScenarioStarted() {
        isTesting = true
    }

    @objc private func testScenarioStopped() {
        isTesting = false
    }

    /// Emit one timer tick. The optional date keeps lifecycle behaviour deterministic in tests.
    func tick(now: Date = Date()) {
        // stop 中（handler が nil）はイベント発火だけでなく分・時トラッキングも更新しない。
        // 更新してしまうと、停止中の tick が次回 start 後の比較基準を汚染し、
        // 再起動直後に OnMinuteChange / OnHourTimeSignal が発火しなくなる。
        guard let handler else { return }
        // UKADOC: OnSecondChange / OnMinuteChange / OnHourTimeSignal の Reference
        //   Reference0: OS 連続起動時間 (hour)
        //   Reference1: 見切れフラグ / Reference2: 重なりフラグ
        //   Reference3: トーク再生可否 (EventBridge がセッション毎に設定し GET/NOTIFY を切り替える)
        //   Reference4: 放置時間 (秒) [SSP拡張]
        let params = Self.timeEventReferences()

        if !isTesting {
            handler(ShioriEvent(id: .OnIdle, params: [:]))
            handler(ShioriEvent(id: .OnSecondChange, refs: params))
        }

        let cal = Calendar.current
        let minute = cal.component(.minute, from: now)
        if minute != lastMinute {
            lastMinute = minute
            handler(ShioriEvent(id: .OnMinuteChange, refs: params))
        }
        let hour = cal.component(.hour, from: now)
        if hour != lastHour {
            lastHour = hour
            handler(ShioriEvent(id: .OnHourTimeSignal, refs: params))
        }
    }

    /// 時刻系イベント共通の Reference を意味ラベルで組み立てる（表駆動: ShioriEvent(id:refs:) で ReferenceN に変換）。
    /// mikire（見切れ）/ kasanari（重なり）/ canTalk（Reference3）は EventBridge がセッション毎に上書きする。
    /// ここでは安全な既定値（空文字列 = 該当なし）を入れておく。
    static func timeEventReferences() -> [String: String] {
        let uptimeHours = Int(ProcessInfo.processInfo.systemUptime / 3600)
        return [
            "uptimeHours": String(uptimeHours),
            "mikire": "",
            "kasanari": "",
            // canTalk (Reference3) は EventBridge が各ゴーストの状態から設定する
            "idleSecondsSSP": String(Self.systemIdleSeconds())
        ]
    }

    /// 最後のユーザー入力からの経過秒数（システム全体）
    private static func systemIdleSeconds() -> Int {
        // kCGAnyInputEventType (~0) で全入力イベントを対象にする
        guard let anyInput = CGEventType(rawValue: ~UInt32(0)) else { return 0 }
        let secs = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        guard secs.isFinite, secs >= 0 else { return 0 }
        return Int(secs)
    }
}
