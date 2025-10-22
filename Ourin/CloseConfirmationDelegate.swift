import AppKit

class CloseConfirmationDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("終了しますか?", comment: "Confirm quit title")
        alert.informativeText = NSLocalizedString("アプリを終了するか最小化するか選択してください。", comment: "Confirm quit message")
        alert.addButton(withTitle: NSLocalizedString("終了", comment: "Quit"))
        alert.addButton(withTitle: NSLocalizedString("最小化", comment: "Minimize"))
        alert.addButton(withTitle: NSLocalizedString("キャンセル", comment: "Cancel"))
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
