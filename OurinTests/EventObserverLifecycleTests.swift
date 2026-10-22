import Foundation
import Testing
@testable import Ourin

struct EventObserverLifecycleTests {
    @Test @MainActor
    func timerRestartReestablishesMinuteAndHourEvents() {
        let emitter = TimerEmitter()
        emitter.stop()

        var eventsAfterStop: [ShioriEvent] = []
        emitter.start { eventsAfterStop.append($0) }
        emitter.stop()
        emitter.tick(now: Date(timeIntervalSince1970: 0))
        #expect(eventsAfterStop.isEmpty)

        var restartedEvents: [ShioriEvent] = []
        emitter.start { restartedEvents.append($0) }
        emitter.tick(now: Date())
        emitter.stop()

        #expect(restartedEvents.contains { $0.id == .OnMinuteChange })
        #expect(restartedEvents.contains { $0.id == .OnHourTimeSignal })
    }

    @Test @MainActor
    func idleEventCarriesTimeReferencesIncludingIdleSeconds() {
        let emitter = TimerEmitter()
        emitter.stop()

        var events: [ShioriEvent] = []
        emitter.start { events.append($0) }
        emitter.tick(now: Date())
        emitter.stop()

        let idle = events.first { $0.id == .OnIdle }
        #expect(idle != nil)
        // Reference4 = 放置秒数（OnSecondChange と同じ並び）。数値として読めること。
        let seconds = idle?.params["Reference4"].flatMap(Int.init)
        #expect(seconds != nil && seconds! >= 0)
    }
}
