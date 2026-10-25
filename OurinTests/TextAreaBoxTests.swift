import AppKit
import Foundation
import Testing
@testable import Ourin

@MainActor
struct TextAreaBoxTests {
    @Test
    func submitUsesOnTextAreaInputOrTheOnPrefixedID() {
        let plain = GhostManager.textAreaInputEvent(id: "感想", value: "一行目\n二行目", references: ["extra"])
        #expect(plain.eventID == "OnTextAreaInput")
        #expect(plain.references == ["感想", "一行目\u{1}二行目", "", "extra"])

        // ID が On 始まりなら、その名前のイベントで R0 に入力が入り、以降は1つずつ前へずれる。
        let custom = GhostManager.textAreaInputEvent(id: "OnDiaryInput", value: "a\r\nb", references: ["r"])
        #expect(custom.eventID == "OnDiaryInput")
        #expect(custom.references == ["a\u{1}b", "", "r"])
    }

    @Test
    func cancelAlwaysUsesOnTextAreaInputCancel() {
        let closed = GhostManager.textAreaCancelEvent(id: "OnDiaryInput", timedOut: false, value: "途中\n", references: [])
        #expect(closed.eventID == "OnTextAreaInputCancel")
        #expect(closed.references == ["OnDiaryInput", "close", "途中\u{1}"])

        let timeout = GhostManager.textAreaCancelEvent(id: "memo", timedOut: true, value: "", references: ["x", "y"])
        #expect(timeout.references == ["memo", "timeout", "", "x", "y"])
    }

    @Test
    func initialTextAndPlaceholderUseByteOneAsNewline() {
        #expect(GhostManager.textAreaLines(from: "a\u{1}b\u{1}c") == "a\nb\nc")
        #expect(GhostManager.textAreaWireText("a\rb\r\nc\nd") == "a\u{1}b\u{1}c\u{1}d")
    }

    @Test
    func limitCountsNewlinesAsOneCharacter() {
        let view = TextAreaInputView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        view.limit = 3
        view.string = "a\n"
        // "a\n" は2文字。あと1文字は入るが、2文字は入らない。
        #expect(view.shouldChangeText(in: NSRange(location: 2, length: 0), replacementString: "b"))
        #expect(!view.shouldChangeText(in: NSRange(location: 2, length: 0), replacementString: "bc"))
    }

    @Test
    func controlOrCommandReturnSubmitsAndPlainReturnDoesNot() throws {
        let view = TextAreaInputView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        var submitted = 0
        view.onSubmit = { submitted += 1 }

        func returnKey(_ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
            ))
        }
        view.keyDown(with: try returnKey(.control))
        view.keyDown(with: try returnKey(.command))
        #expect(submitted == 2)
        view.keyDown(with: try returnKey([]))
        #expect(submitted == 2)
    }
}
