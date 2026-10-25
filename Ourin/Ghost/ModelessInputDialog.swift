import AppKit

/// 入力ボックスをモーダルにせずに表示する。SSP の入力ボックスはゴーストの動き（スクリプトの再生・
/// SSTP・タイマー）を止めず、結果は後からイベントで返る。NSAlert の見た目をそのまま使い、
/// ボタンの押下とタイムアウトを handler へ渡す。
final class ModelessInputDialog: NSObject {
    enum Outcome: Equatable {
        /// 押されたボタンの番号（追加した順、0 始まり）。
        case button(Int)
        case timeout
    }

    let id: String
    let alert: NSAlert
    /// 閉じたとき（どの経路でも 1 回）に呼ぶ。
    var onClose: (() -> Void)?

    private var handler: ((Outcome) -> Bool)?
    private var timeoutMs: Int?
    private var timer: Timer?
    private var cleanups: [() -> Void] = []

    init(id: String, alert: NSAlert) {
        self.id = id
        self.alert = alert
    }

    var isOpen: Bool { handler != nil }

    /// handler は結果を受け、true を返したら閉じる。タイムアウトのときは戻り値によらず閉じる。
    func present(timeoutMs: Int?, handler: @escaping (Outcome) -> Bool) {
        self.handler = handler
        self.timeoutMs = timeoutMs
        alert.layout()
        for (index, button) in alert.buttons.enumerated() {
            button.tag = index
            button.target = self
            button.action = #selector(buttonPressed(_:))
        }
        let window = alert.window
        window.level = .floating
        window.center()
        restartTimeout()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if let field = alert.accessoryView, field.acceptsFirstResponder {
            window.makeFirstResponder(field)
        }
    }

    /// 閉じるときに一緒に片付けるもの（通知の監視など）。
    func addCleanup(_ cleanup: @escaping () -> Void) {
        cleanups.append(cleanup)
    }

    /// 結果のイベントを送らずに閉じる（`\![close,inputbox]`、同じ ID の入力ボックスを開き直すときなど）。
    func dismiss() {
        guard handler != nil else { return }
        handler = nil
        timer?.invalidate()
        timer = nil
        alert.window.orderOut(nil)
        cleanups.forEach { $0() }
        cleanups.removeAll()
        onClose?()
        onClose = nil
    }

    /// テストと内部用: ボタンを押したのと同じ結果を返す。
    func respond(_ outcome: Outcome) {
        guard let handler else { return }
        let shouldClose = handler(outcome)
        if shouldClose || outcome == .timeout {
            dismiss()
        } else {
            // 閉じずに続ける（--option=noclose）ときは、タイムアウトを数え直す。
            restartTimeout()
        }
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        respond(.button(sender.tag))
    }

    private func restartTimeout() {
        timer?.invalidate()
        timer = nil
        guard let timeoutMs, timeoutMs > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(timeoutMs) / 1000.0, repeats: false) { [weak self] _ in
            self?.respond(.timeout)
        }
    }
}
