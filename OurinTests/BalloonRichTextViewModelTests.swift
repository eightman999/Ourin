import AppKit
import Foundation
import Testing
@testable import Ourin

struct BalloonRichTextViewModelTests {
    @Test
    func fontCommandsApplyAlignmentAndVerticalAlignmentAttributes() throws {
        let model = BalloonRichTextViewModel()
        model.processText("abc")

        model.handleAlignCommand("right")
        model.handleValignCommand("center")

        let paragraph = try #require(
            model.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        )
        #expect(paragraph.alignment == .right)
        #expect(model.verticalAlignment == .center)
        #expect(
            model.attributedString.attribute(.ourinVerticalAlignment, at: 0, effectiveRange: nil) as? String == "center"
        )

        model.handleValignCommand("bottom")
        #expect(model.verticalAlignment == .bottom)
        #expect(
            model.attributedString.attribute(.ourinVerticalAlignment, at: 0, effectiveRange: nil) as? String == "bottom"
        )
    }

    @Test
    func subscriptAndSuperscriptUseScaledFontAndBaselineOffset() throws {
        let model = BalloonRichTextViewModel()
        model.processText("H2")
        let baseFont = try #require(model.attributedString.attribute(.font, at: 1, effectiveRange: nil) as? NSFont)

        model.handleSupCommand(true)
        let superscriptFont = try #require(model.attributedString.attribute(.font, at: 1, effectiveRange: nil) as? NSFont)
        let superscriptOffset = try #require(
            model.attributedString.attribute(.baselineOffset, at: 1, effectiveRange: nil) as? NSNumber
        )
        #expect(superscriptFont.pointSize < baseFont.pointSize)
        #expect(superscriptOffset.doubleValue > 0)

        model.handleSubCommand(true)
        let subscriptOffset = try #require(
            model.attributedString.attribute(.baselineOffset, at: 1, effectiveRange: nil) as? NSNumber
        )
        #expect(subscriptOffset.doubleValue < 0)

        model.handleSubCommand(false)
        #expect(model.attributedString.attribute(.baselineOffset, at: 1, effectiveRange: nil) == nil)
    }

    @Test
    func styleResetAndFontFallbackDoNotLeaveStaleAttributes() throws {
        let model = BalloonRichTextViewModel()
        model.processText("text")
        model.handleUnderlineCommand(true)
        model.handleShadowColorCommand(.red)
        #expect(model.attributedString.attribute(.underlineStyle, at: 0, effectiveRange: nil) != nil)
        #expect(model.attributedString.attribute(.shadow, at: 0, effectiveRange: nil) != nil)

        model.handleDefaultCommand()
        #expect(model.attributedString.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil)
        #expect(model.attributedString.attribute(.shadow, at: 0, effectiveRange: nil) == nil)

        model.handleFontCommand("font-that-is-not-installed,another-missing-font")
        let font = try #require(model.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize > 0)
    }
}
