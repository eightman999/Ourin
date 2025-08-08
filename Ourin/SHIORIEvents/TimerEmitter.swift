import Foundation

// TimerEmitter.swift
// Periodic timers for OnIdle and OnMinuteChange events

final class TimerEmitter {
    static let shared = TimerEmitter()
    private var isTesting = false

    private init() {}

    private var timer: DispatchSourceTimer?
    private var lastMinute: Int?
    private var lastHour: Int?
    private var handler: ((ShioriEvent) -> Void)?

    /// Start emitting timer based events
    func start(_ handler: @escaping (ShioriEvent) -> Void) {
        self.handler = handler

        // Listen for test scenario notifications
        NotificationCenter.default.addObserver(self, selector: #selector(testScenarioStarted), name: .testScenarioStarted, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(testScenarioStopped), name: .testScenarioStopped, object: nil)

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
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func testScenarioStarted() {
        isTesting = true
    }

    @objc private func testScenarioStopped() {
        isTesting = false
    }

    private func tick() {
        if !isTesting {
            handler?(ShioriEvent(id: .OnIdle, params: [:]))
            handler?(ShioriEvent(id: .OnSecondChange, params: [:]))
        }

        let now = Date()
        let cal = Calendar.current
        let minute = cal.component(.minute, from: now)
        if minute != lastMinute {
            lastMinute = minute
            handler?(ShioriEvent(id: .OnMinuteChange, params: [:]))
        }
        let hour = cal.component(.hour, from: now)
        if hour != lastHour {
            lastHour = hour
            handler?(ShioriEvent(id: .OnHourTimeSignal, params: [:]))
        }
    }
}
