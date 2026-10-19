// PowerObserver.swift
// 電源状態・バッテリー状態・サーマル情報を監視する
import Foundation
import IOKit.ps

/// IOPowerSources のスナップショットを SHIORI の Battery イベントへ変換するための値。
/// 辞書の読み取りと閾値判定を分離しておくことで、ハードウェアがない環境でも
/// 変換規則をテストでき、イベント発火側に固定値を持ち込まない。
struct PowerSnapshot: Equatable {
    let source: String
    let powerState: String
    let percent: Int?
    let remainingMinutes: Int
    let isCharging: Bool
    let hasBattery: Bool
    let lowPowerMode: Bool

    var isCritical: Bool {
        guard let percent else { return false }
        return percent <= 5
    }

    var isLow: Bool {
        guard let percent else { return false }
        return percent <= 33
    }

    var status: String {
        guard hasBattery else { return "no_battery" }
        var values: [String] = []
        if isCritical {
            values.append("critical")
        } else if isLow {
            values.append("low")
        } else {
            values.append("high")
        }
        if isCharging { values.append("charging") }
        if lowPowerMode { values.append("power_saving") }
        return values.joined(separator: ",")
    }

    /// OnBattery* 共通の Reference0～3。
    var batteryReferences: [String: String] {
        [
            "percent": percent.map(String.init) ?? "",
            "remainingMinutes": String(remainingMinutes),
            "powerState": powerState,
            "status": status
        ]
    }

    /// IOPowerSources の辞書を標準化する。辞書キーは IOPSKeys.h の公開文字列を使用する。
    static func make(descriptions: [[String: Any]],
                     providingPowerSource: String,
                     lowPowerMode: Bool) -> PowerSnapshot {
        let source: String
        let powerState: String
        switch providingPowerSource {
        case "AC Power":
            source = "AC"
            powerState = "online"
        case "UPS Power":
            source = "UPS"
            powerState = "backup"
        default:
            source = "Battery"
            powerState = "offline"
        }

        let present = descriptions.filter { dictionary in
            let isPresent = (dictionary["Is Present"] as? NSNumber)?.boolValue ?? true
            return isPresent
        }
        let batterySources = present.filter { dictionary in
            let transport = dictionary["Transport Type"] as? String
            let state = dictionary["Power Source State"] as? String
            let hasCapacity = dictionary["Current Capacity"] != nil && dictionary["Max Capacity"] != nil
            return transport == "Internal" || state == "Battery Power" || hasCapacity
        }

        let capacities: [(current: Int, maximum: Int)] = batterySources.compactMap { dictionary in
            guard let current = (dictionary["Current Capacity"] as? NSNumber)?.intValue,
                  let maximum = (dictionary["Max Capacity"] as? NSNumber)?.intValue,
                  maximum > 0 else { return nil }
            return (current, maximum)
        }
        let percent: Int?
        if capacities.isEmpty {
            percent = nil
        } else {
            let current = capacities.reduce(0) { $0 + $1.current }
            let maximum = capacities.reduce(0) { $0 + $1.maximum }
            percent = maximum > 0 ? Int((Double(current) * 100.0 / Double(maximum)).rounded()) : nil
        }

        let isCharging = batterySources.contains {
            ($0["Is Charging"] as? NSNumber)?.boolValue == true
        }
        let timeKey = isCharging ? "Time to Full Charge" : "Time to Empty"
        let remainingMinutes = batterySources
            .compactMap { ($0[timeKey] as? NSNumber)?.intValue }
            .first(where: { $0 >= 0 }) ?? -1

        return PowerSnapshot(
            source: source,
            powerState: powerState,
            percent: percent,
            remainingMinutes: remainingMinutes,
            isCharging: isCharging,
            hasBattery: !batterySources.isEmpty,
            lowPowerMode: lowPowerMode
        )
    }
}

final class PowerObserver {
    static let shared = PowerObserver()
    private init() {}

    private var rl: CFRunLoopSource?
    private var handler: ((ShioriEvent)->Void)?
    private var lastSnapshot: PowerSnapshot?

    /// 監視を開始する。
    func start(_ handler: @escaping (ShioriEvent) -> Void) {
        stop()
        self.handler = handler
        lastSnapshot = nil

        let cb: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let me = Unmanaged<PowerObserver>.fromOpaque(context).takeUnretainedValue()
            me.emit(initial: false)
        }
        let ctx = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        rl = IOPSNotificationCreateRunLoopSource(cb, ctx)?.takeRetainedValue()
        if let rl {
            CFRunLoopAddSource(CFRunLoopGetMain(), rl, .defaultMode)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateChanged),
            name: Notification.Name("NSProcessInfoPowerStateDidChangeNotification"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )

        emit(initial: true)
        thermalChanged()
    }

    /// 監視を停止する。
    func stop() {
        if let rl {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), rl, .defaultMode)
            self.rl = nil
        }
        NotificationCenter.default.removeObserver(self, name: Notification.Name("NSProcessInfoPowerStateDidChangeNotification"), object: nil)
        NotificationCenter.default.removeObserver(self, name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        handler = nil
        lastSnapshot = nil
    }

    private func readSnapshot() -> PowerSnapshot? {
        guard let unmanagedInfo = IOPSCopyPowerSourcesInfo() else { return nil }
        let info = unmanagedInfo.takeRetainedValue()

        var descriptions: [[String: Any]] = []
        if let unmanagedList = IOPSCopyPowerSourcesList(info) {
            let list = unmanagedList.takeRetainedValue()
            let nsList = list as NSArray
            for source in nsList {
                let dictionary = IOPSGetPowerSourceDescription(info, source as CFTypeRef).takeUnretainedValue()
                descriptions.append((dictionary as NSDictionary) as? [String: Any] ?? [:])
            }
        }

        let provider = IOPSGetProvidingPowerSourceType(info).map {
            $0.takeUnretainedValue() as String
        } ?? ""
        let lowPowerMode: Bool
        if #available(macOS 12.0, *) {
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        } else {
            lowPowerMode = false
        }
        return PowerSnapshot.make(
            descriptions: descriptions,
            providingPowerSource: provider,
            lowPowerMode: lowPowerMode
        )
    }

    private func emit(initial: Bool) {
        guard let snapshot = readSnapshot() else { return }
        let previous = lastSnapshot
        lastSnapshot = snapshot
        let delivery: ShioriEventDelivery = initial ? .notify : .get

        if previous == nil || previous?.source != snapshot.source {
            handler?(ShioriEvent(
                id: .OnPowerSourceChanged,
                refs: ["source": snapshot.source],
                delivery: delivery,
                ignoreResponseScript: initial
            ))
        }

        guard snapshot.hasBattery || previous?.hasBattery == true else { return }
        if previous == nil || previous != snapshot {
            emitBattery(id: .OnBatteryNotify, snapshot: snapshot, delivery: delivery, ignoreResponseScript: initial)
        }
        guard let previous else { return }

        if snapshot.isLow && !previous.isLow {
            emitBattery(id: .OnBatteryLow, snapshot: snapshot, delivery: .get, ignoreResponseScript: false)
        }
        if snapshot.isCritical && !previous.isCritical {
            emitBattery(id: .OnBatteryCritical, snapshot: snapshot, delivery: .get, ignoreResponseScript: false)
        }
        if snapshot.isCharging != previous.isCharging {
            emitBattery(
                id: snapshot.isCharging ? .OnBatteryChargingStart : .OnBatteryChargingStop,
                snapshot: snapshot,
                delivery: .get,
                ignoreResponseScript: false
            )
        }
    }

    private func emitBattery(id: EventID,
                             snapshot: PowerSnapshot,
                             delivery: ShioriEventDelivery,
                             ignoreResponseScript: Bool) {
        handler?(ShioriEvent(
            id: id,
            refs: snapshot.batteryReferences,
            delivery: delivery,
            ignoreResponseScript: ignoreResponseScript
        ))
    }

    @objc private func powerStateChanged() {
        emit(initial: false)
    }

    /// サーマル状態の変化を受け取って通知する。
    @objc private func thermalChanged() {
        let state: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: state = "nominal"
        case .fair: state = "fair"
        case .serious: state = "serious"
        case .critical: state = "critical"
        @unknown default: state = "unknown"
        }
        handler?(ShioriEvent(id: .OnThermalStateChanged, refs: ["state": state]))
    }
}
