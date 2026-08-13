import Foundation
import Testing
@testable import Ourin

struct PowerObserverTests {
    @Test
    func convertsBatteryDictionaryToUkadocReferences() {
        let snapshot = PowerSnapshot.make(
            descriptions: [[
                "Transport Type": "Internal",
                "Power Source State": "Battery Power",
                "Current Capacity": NSNumber(value: 25),
                "Max Capacity": NSNumber(value: 100),
                "Time to Empty": NSNumber(value: 90),
                "Is Charging": NSNumber(value: false),
                "Is Present": NSNumber(value: true)
            ]],
            providingPowerSource: "Battery Power",
            lowPowerMode: false
        )

        #expect(snapshot.source == "Battery")
        #expect(snapshot.powerState == "offline")
        #expect(snapshot.batteryReferences == [
            "percent": "25",
            "remainingMinutes": "90",
            "powerState": "offline",
            "status": "low"
        ])
    }

    @Test
    func preservesChargingAndLowPowerFlags() {
        let snapshot = PowerSnapshot.make(
            descriptions: [[
                "Transport Type": "Internal",
                "Power Source State": "AC Power",
                "Current Capacity": NSNumber(value: 100),
                "Max Capacity": NSNumber(value: 100),
                "Time to Full Charge": NSNumber(value: 30),
                "Is Charging": NSNumber(value: true),
                "Is Present": NSNumber(value: true)
            ]],
            providingPowerSource: "AC Power",
            lowPowerMode: true
        )

        #expect(snapshot.batteryReferences["powerState"] == "online")
        #expect(snapshot.batteryReferences["remainingMinutes"] == "30")
        #expect(snapshot.batteryReferences["status"] == "high,charging,power_saving")
    }

    @Test
    func noBatteryIsExplicitAndDoesNotInventCapacity() {
        let snapshot = PowerSnapshot.make(
            descriptions: [],
            providingPowerSource: "AC Power",
            lowPowerMode: false
        )

        #expect(snapshot.percent == nil)
        #expect(snapshot.hasBattery == false)
        #expect(snapshot.batteryReferences["percent"] == "")
        #expect(snapshot.batteryReferences["remainingMinutes"] == "-1")
        #expect(snapshot.batteryReferences["status"] == "no_battery")
    }

    @Test
    func observerEventsDefaultToGetAndCanDeclareStartupNotify() {
        let regular = ShioriEvent(id: .OnDisplayChange, params: [:])
        let startup = ShioriEvent(
            id: .OnDisplayChange,
            params: [:],
            delivery: .notify,
            ignoreResponseScript: true
        )

        #expect(regular.delivery == .get)
        #expect(startup.delivery == .notify)
        #expect(startup.ignoreResponseScript == true)
    }

    @Test
    func systemSleepUsesNotifyForSuspendAndGetForSleep() {
        let events = SleepObserver.willSleepEvents()

        #expect(events.map(\.id) == [.OnSysSuspend, .OnSleep])
        #expect(events[0].delivery == .notify)
        #expect(events[0].ignoreResponseScript)
        #expect(events[1].delivery == .get)
        #expect(!events[1].ignoreResponseScript)
    }
}
