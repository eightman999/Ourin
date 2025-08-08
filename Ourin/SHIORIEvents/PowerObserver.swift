// PowerObserver.swift
// 電源状態やサーマル情報を監視する
import Foundation
import IOKit.ps

final class PowerObserver {
    static let shared = PowerObserver()
    private init() {}
    private var rl: CFRunLoopSource?
    private var handler: ((ShioriEvent)->Void)?

    /// 監視を開始する
    func start(_ handler: @escaping (ShioriEvent) -> Void) {
        self.handler = handler

        let cb: IOPowerSourceCallbackType = { context in
            let me = Unmanaged<PowerObserver>.fromOpaque(context!).takeUnretainedValue()
            me.emit()
        }
        let ctx = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        rl = IOPSNotificationCreateRunLoopSource(cb, ctx)?.takeRetainedValue()
        if let rl = rl {
            CFRunLoopAddSource(CFRunLoopGetMain(), rl, .defaultMode)
        }

        emit() // 初期値の送出

        // Thermal (M-Add)
        NotificationCenter.default.addObserver(self, selector: #selector(thermalChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
    }

    /// 監視を停止する
    func stop() {
        if let rl = rl { CFRunLoopRemoveSource(CFRunLoopGetMain(), rl, .defaultMode); self.rl = nil }
        NotificationCenter.default.removeObserver(self, name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
    }

    /// 電源情報を取得してイベントを送出
    private func emit() {
        if IOPSCopyPowerSourcesInfo() != nil {
            // アダプタ有無のみで AC/Battery を判定
            let ac = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() != nil
            handler?(ShioriEvent(id: .OnPowerSourceChanged, params: ["Source": ac ? "AC" : "Battery"]))
        }
    }

    /// サーマル状態の変化を受け取って通知する
    @objc private func thermalChanged() {
        let state: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: state = "nominal"
        case .fair: state = "fair"
        case .serious: state = "serious"
        case .critical: state = "critical"
        @unknown default: state = "unknown"
        }
        handler?(ShioriEvent(id: .OnThermalStateChanged, params: ["State": state]))
    }
}
