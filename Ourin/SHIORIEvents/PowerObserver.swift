// PowerObserver.swift
import Foundation
import IOKit.ps

final class PowerObserver {
    static let shared = PowerObserver()
    private init() {}
    private var rl: CFRunLoopSource?
    private var handler: ((ShioriEvent)->Void)?

    func start(_ handler: @escaping (ShioriEvent)->Void) {
        self.handler = handler
        var ctx = IOPowerSourceContext(version: 0, info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), retain: nil, release: nil, copyDescription: nil)
        let cb: IOPowerSourceCallbackType = { context in
            let me = Unmanaged<PowerObserver>.fromOpaque(context!).takeUnretainedValue()
            me.emit()
        }
        rl = IOPSNotificationCreateRunLoopSource(cb, &ctx)?.takeRetainedValue()
        if let rl = rl {
            CFRunLoopAddSource(CFRunLoopGetMain(), rl, .defaultMode)
        }
        emit() // initial
        // Thermal (M-Add)
        NotificationCenter.default.addObserver(self, selector: #selector(thermalChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
    }

    func stop() {
        if let rl = rl { CFRunLoopRemoveSource(CFRunLoopGetMain(), rl, .defaultMode); self.rl = nil }
        NotificationCenter.default.removeObserver(self, name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
    }

    private func emit() {
        if let ps = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() {
            // Simple AC/Battery flag via adapter presence
            let ac = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() != nil
            handler?(ShioriEvent(id: "OnPowerSourceChanged", params: ["Source": ac ? "AC" : "Battery"]))
        }
    }

    @objc private func thermalChanged() {
        let state: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: state = "nominal"
        case .fair: state = "fair"
        case .serious: state = "serious"
        case .critical: state = "critical"
        @unknown default: state = "unknown"
        }
        handler?(ShioriEvent(id: "OnThermalStateChanged", params: ["State": state]))
    }
}
