import AppKit

class CloseConfirmationDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let alert = NSAlert()
        alert.messageText = "終了しますか?"
        alert.informativeText = "アプリを終了するか最小化するか選択してください。"
        alert.addButton(withTitle: "終了")
        alert.addButton(withTitle: "最小化")
        alert.addButton(withTitle: "キャンセル")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            NSApplication.shared.terminate(nil)
            return false
        case .alertSecondButtonReturn:
            sender.miniaturize(nil)
            return false
        default:
            return false
        }
    }
}
