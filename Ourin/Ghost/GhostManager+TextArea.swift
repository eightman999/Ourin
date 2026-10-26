import AppKit

// MARK: - textareabox（\![open,textareabox] / \![close,textareabox]、UKADOC 2.9.10）
//
// 決定: ID が On 始まりなら ID 名のイベント（R0=入力 R1=空 R2～=--reference）、
//       それ以外は OnTextAreaInput（R0=ID R1=入力 R2=空 R3～=--reference）。
// 取消: 常に OnTextAreaInputCancel（R0=ID R1=timeout/close R2=閉じるまでの入力 R3～=--reference）。
//       OnUserInputCancel と違い、タイムアウト時に決定イベントへ投げ直さない。
// 入力・初期テキスト・placeholder の改行はバイト値1で表す。Enter は改行、Ctrl+Enter（⌘+Enter）で決定。
extension GhostManager {

    /// 改行（CRLF / CR / LF）をバイト値1へ置き換える。
    static func textAreaWireText(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\u{1}")
            .replacingOccurrences(of: "\n", with: "\u{1}")
            .replacingOccurrences(of: "\r", with: "\u{1}")
    }

    /// スクリプト側のバイト値1区切りを改行に戻す。
    static func textAreaLines(from wire: String) -> String {
        wire.replacingOccurrences(of: "\u{1}", with: "\n")
    }

    /// 決定時のイベント名と Reference。
    static func textAreaInputEvent(id: String, value: String, references: [String]) -> (eventID: String, references: [String]) {
        let wire = textAreaWireText(value)
        if id.lowercased().hasPrefix("on") {
            return (id, [wire, ""] + references)
        }
        return ("OnTextAreaInput", [id, wire, ""] + references)
    }

    /// 閉じた・タイムアウトしたときのイベント名と Reference。
    static func textAreaCancelEvent(id: String, timedOut: Bool, value: String, references: [String]) -> (eventID: String, references: [String]) {
        ("OnTextAreaInputCancel", [id, timedOut ? "timeout" : "close", textAreaWireText(value)] + references)
    }

    /// `\![close,textareabox,ID]`。`__SYSTEM_ALL_INPUT__` はすべて閉じる。
    @discardableResult
    func closeTextAreaDialog(id: String) -> Bool {
        guard let alert = activeTextAreaAlert,
              let activeID = activeTextAreaID,
              id == "__SYSTEM_ALL_INPUT__" || activeID.caseInsensitiveCompare(id) == .orderedSame else {
            return false
        }
        textAreaCloseRequested = true
        alert.window.close()
        NSApp.abortModal()
        return true
    }

    func showTextAreaBoxDialog(id: String,
                               timeoutMs: Int?,
                               initialText: String,
                               placeholder: String,
                               options: InputDialogOptions = .none) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Input", comment: "input dialog title")
        alert.informativeText = NSLocalizedString("Enter text. Press Control+Return to submit.", comment: "textarea dialog message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))
        if let balloonID = options.balloonID, let index = Int(balloonID),
           let image = balloonImageLoader?.loadSurface(index: index, type: "c") {
            alert.icon = image
        }

        let size = NSSize(width: 400, height: 160)
        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: size))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let textView = TextAreaInputView(frame: NSRect(origin: .zero, size: size))
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = options.limited(initialText)
        textView.placeholder = placeholder
        textView.limit = options.limit
        textView.onSubmit = { [weak alert] in
            alert?.buttons.first?.performClick(nil)
        }
        scrollView.documentView = textView
        alert.accessoryView = scrollView
        alert.window.initialFirstResponder = textView

        activeTextAreaAlert = alert
        activeTextAreaID = id
        textAreaCloseRequested = false
        defer {
            activeTextAreaAlert = nil
            activeTextAreaID = nil
            textAreaCloseRequested = false
        }

        while true {
            var timedOut = false
            let timer = scheduleModalTimeout(timeoutMs: timeoutMs) { timedOut = true }
            let response = alert.runModal()
            timer?.invalidate()

            if textAreaCloseRequested { break }

            if response == .alertFirstButtonReturn {
                let event = Self.textAreaInputEvent(id: id, value: options.limited(textView.string), references: options.references)
                _ = requestDialogEvent(eventID: event.eventID, references: event.references)
                guard options.noClose else { break }
                if !options.noClear { textView.string = "" }
            } else {
                let event = Self.textAreaCancelEvent(id: id, timedOut: timedOut, value: textView.string, references: options.references)
                _ = requestDialogEvent(eventID: event.eventID, references: event.references)
                break
            }
        }
    }
}

/// textareabox の入力欄。Ctrl+Return（⌘+Return）で決定し、--limit を改行込みで数え、空欄に placeholder を出す。
final class TextAreaInputView: NSTextView {
    var onSubmit: (() -> Void)?
    var limit: Int?
    var placeholder: String = "" {
        didSet { needsDisplay = true }
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if isReturn, modifiers.contains(.control) || modifiers.contains(.command) {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard super.shouldChangeText(in: affectedCharRange, replacementString: replacementString) else { return false }
        guard let limit, let replacementString else { return true }
        let current = string as NSString
        let next = current.replacingCharacters(in: affectedCharRange, with: replacementString)
        return next.count <= limit
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let inset = textContainerInset
        let padding = textContainer?.lineFragmentPadding ?? 0
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        (placeholder as NSString).draw(
            in: NSRect(x: inset.width + padding, y: inset.height,
                       width: bounds.width - inset.width * 2 - padding * 2,
                       height: bounds.height - inset.height * 2),
            withAttributes: attributes
        )
    }
}
