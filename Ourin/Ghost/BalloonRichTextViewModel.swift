import Foundation
import AppKit
import Combine

enum BalloonVerticalAlignment: String, Equatable {
    case top
    case center
    case bottom
}

extension NSAttributedString.Key {
    /// Vertical alignment is not represented by NSTextAlignment. Keep the
    /// resolved value on the attributed string so an AppKit/CoreText consumer
    /// can position each line inside the balloon without re-parsing SakuraScript.
    static let ourinVerticalAlignment = NSAttributedString.Key("OurinVerticalAlignment")
}

/// Text style attributes for balloon rendering
struct BalloonTextStyle {
    var font: NSFont?
    var color: NSColor?
    var backgroundColor: NSColor?
    var underlineStyle: NSUnderlineStyle?
    var strikethroughStyle: Int?
    var alignment: NSTextAlignment?
    var verticalAlignment: BalloonVerticalAlignment?
    var lineSpacing: CGFloat?
    var paragraphSpacing: CGFloat?
    var shadow: NSShadow?
    var isBold: Bool = false
    var isItalic: Bool = false
    var isSubscript: Bool = false
    var isSuperscript: Bool = false
}

/// ViewModel for rich text balloon rendering with NSAttributedString/CoreText
class BalloonRichTextViewModel: ObservableObject {
    @Published var attributedString: NSAttributedString
    @Published var cursorPosition: CGPoint = .zero
    @Published var selectionRange: NSRange?
    
    private var config: BalloonConfig?
    private var currentStyle: BalloonTextStyle = BalloonTextStyle()
    @Published private(set) var verticalAlignment: BalloonVerticalAlignment?
    
    init(config: BalloonConfig? = nil) {
        self.config = config
        self.attributedString = NSAttributedString(string: "")
        resetStyleState()
    }
    
    /// Process text and apply styles from SakuraScript \f[...] commands
    func processText(_ text: String) {
        resetStyleState()
        let mutableString = NSMutableAttributedString(string: text)

        // Apply base font from config
        let baseFont = currentStyle.font ?? NSFont.systemFont(ofSize: CGFloat(config?.fontHeight ?? 12))
        mutableString.addAttribute(.font, value: baseFont, range: NSRange(location: 0, length: mutableString.length))

        // Apply base color from config
        if let fontColor = currentStyle.color {
            mutableString.addAttribute(.foregroundColor, value: fontColor, range: NSRange(location: 0, length: mutableString.length))
        }

        self.attributedString = mutableString
        applyCurrentStyleToAllText()
    }
    
    /// Apply style attribute to text
    func applyStyle(_ style: BalloonTextStyle, range: NSRange) {
        guard range.location >= 0,
              range.length >= 0,
              range.location <= attributedString.length,
              range.length <= attributedString.length - range.location else { return }
        let mutableString = NSMutableAttributedString(attributedString: attributedString)

        let font = resolvedFont(for: style)
        mutableString.addAttribute(.font, value: font, range: range)

        for key in [
            NSAttributedString.Key.foregroundColor,
            .backgroundColor,
            .underlineStyle,
            .strikethroughStyle,
            .shadow,
            .paragraphStyle,
            .baselineOffset,
            .ourinVerticalAlignment
        ] {
            mutableString.removeAttribute(key, range: range)
        }
        if let color = style.color {
            mutableString.addAttribute(.foregroundColor, value: color, range: range)
        }
        if let bgColor = style.backgroundColor {
            mutableString.addAttribute(.backgroundColor, value: bgColor, range: range)
        }
        if let underline = style.underlineStyle {
            mutableString.addAttribute(.underlineStyle, value: underline, range: range)
        }
        if let strikethrough = style.strikethroughStyle {
            mutableString.addAttribute(.strikethroughStyle, value: strikethrough, range: range)
        }
        if let alignment = style.alignment {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            if let lineSpacing = style.lineSpacing {
                paragraph.lineSpacing = lineSpacing
            }
            if let paragraphSpacing = style.paragraphSpacing {
                paragraph.paragraphSpacing = paragraphSpacing
            }
            mutableString.addAttribute(.paragraphStyle, value: paragraph, range: range)
        }
        if let shadow = style.shadow {
            mutableString.addAttribute(.shadow, value: shadow, range: range)
        }

        if let verticalAlignment = style.verticalAlignment {
            mutableString.addAttribute(
                .ourinVerticalAlignment,
                value: verticalAlignment.rawValue,
                range: range
            )
        }

        if style.isSubscript || style.isSuperscript {
            let scriptFont = NSFont(
                descriptor: font.fontDescriptor,
                size: max(1, font.pointSize * 0.7)
            ) ?? font
            mutableString.addAttribute(.font, value: scriptFont, range: range)
            let baseline = style.isSuperscript ? font.pointSize * 0.35 : -font.pointSize * 0.2
            mutableString.addAttribute(.baselineOffset, value: baseline, range: range)
        }
        
        self.attributedString = mutableString
    }
    
    // MARK: - Style Command Handlers
    
    func handleAlignCommand(_ align: String) {
        switch align.lowercased() {
        case "left":
            currentStyle.alignment = .left
        case "center":
            currentStyle.alignment = .center
        case "right":
            currentStyle.alignment = .right
        case "default":
            currentStyle.alignment = nil
        default:
            break
        }
        applyCurrentStyleToAllText()
    }

    func handleValignCommand(_ align: String) {
        switch align.lowercased() {
        case "top": currentStyle.verticalAlignment = .top
        case "center": currentStyle.verticalAlignment = .center
        case "bottom": currentStyle.verticalAlignment = .bottom
        default: return
        }
        verticalAlignment = currentStyle.verticalAlignment
        applyCurrentStyleToAllText()
    }

    func handleFontCommand(_ name: String) {
        let size = CGFloat(config?.fontHeight ?? 12)

        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "default":
            currentStyle.font = NSFont.systemFont(ofSize: size)
        case "disable":
            currentStyle.font = NSFont.systemFont(ofSize: size)
        default:
            // SSP allows a comma-separated fallback list. Select the first
            // installed font and fall back to the balloon's default font.
            let candidates = name.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let fontName = candidates.first(where: { NSFont(name: $0, size: size) != nil }),
               let font = NSFont(name: fontName, size: size) {
                currentStyle.font = font
            } else {
                currentStyle.font = NSFont.systemFont(ofSize: size)
            }
        }
        applyCurrentStyleToAllText()
    }

    func handleHeightCommand(_ height: CGFloat) {
        let currentFont = currentStyle.font ?? NSFont.systemFont(ofSize: 12)
        currentStyle.font = currentFont.withSize(max(1, height))
        applyCurrentStyleToAllText()
    }

    func handleColorCommand(_ color: NSColor) {
        currentStyle.color = color
        applyCurrentStyleToAllText()
    }

    func handleShadowColorCommand(_ color: NSColor) {
        let shadow = currentStyle.shadow ?? NSShadow()
        shadow.shadowColor = color
        if shadow.shadowOffset == .zero {
            shadow.shadowOffset = CGSize(width: 1, height: -1)
        }
        currentStyle.shadow = shadow
        applyCurrentStyleToAllText()
    }

    func handleShadowStyleCommand(_ style: String) {
        let shadow = currentStyle.shadow ?? NSShadow()
        switch style.lowercased() {
        case "offset":
            shadow.shadowOffset = CGSize(width: 1, height: -1)
            shadow.shadowBlurRadius = 0
        case "outline":
            shadow.shadowOffset = .zero
            shadow.shadowBlurRadius = 0
        default:
            return
        }
        currentStyle.shadow = shadow
        applyCurrentStyleToAllText()
    }
    
    func handleOutlineCommand(_ enabled: Bool) {
        if enabled {
            let shadow = currentStyle.shadow ?? NSShadow()
            shadow.shadowColor = .white
            shadow.shadowBlurRadius = 0
            shadow.shadowOffset = .zero
            currentStyle.shadow = shadow
        } else {
            currentStyle.shadow = nil
        }
        applyCurrentStyleToAllText()
    }
    
    func handleBoldCommand(_ enabled: Bool) {
        currentStyle.isBold = enabled
        updateFontStyle()
    }
    
    func handleItalicCommand(_ enabled: Bool) {
        currentStyle.isItalic = enabled
        updateFontStyle()
    }
    
    func handleStrikeCommand(_ enabled: Bool) {
        currentStyle.strikethroughStyle = enabled ? 1 : 0
    }
    
    func handleUnderlineCommand(_ enabled: Bool) {
        currentStyle.underlineStyle = enabled ? .single : nil
    }
    
    func handleSubCommand(_ enabled: Bool) {
        currentStyle.isSubscript = enabled
        if enabled { currentStyle.isSuperscript = false }
        applyCurrentStyleToAllText()
    }

    func handleSupCommand(_ enabled: Bool) {
        currentStyle.isSuperscript = enabled
        if enabled { currentStyle.isSubscript = false }
        applyCurrentStyleToAllText()
    }
    
    func handleCursorCommand(_ position: CGPoint) {
        cursorPosition = position
    }
    
    func handleResetCommand() {
        resetStyleState()
        applyCurrentStyleToAllText()
    }
    
    func handleDefaultCommand() {
        handleResetCommand()
    }
    
    func handleDisableCommand() {
        resetStyleState()
        currentStyle.font = NSFont.systemFont(ofSize: 10)
        currentStyle.color = .disabledControlTextColor
        applyCurrentStyleToAllText()
    }
    
    private func updateFontStyle() {
        guard let baseFont = currentStyle.font else { return }
        let fontTraits: NSFontDescriptor.SymbolicTraits
        if currentStyle.isBold && currentStyle.isItalic {
            fontTraits = [.bold, .italic]
        } else if currentStyle.isBold {
            fontTraits = .bold
        } else if currentStyle.isItalic {
            fontTraits = .italic
        } else {
            fontTraits = []
        }
        
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(fontTraits)
        currentStyle.font = NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
        applyCurrentStyleToAllText()
    }

    private func resetStyleState() {
        let size = CGFloat(config?.fontHeight ?? 12)
        currentStyle = BalloonTextStyle()
        currentStyle.font = NSFont.systemFont(ofSize: size)
        currentStyle.color = config?.fontColor
        verticalAlignment = nil
    }

    private func resolvedFont(for style: BalloonTextStyle) -> NSFont {
        let base = style.font ?? NSFont.systemFont(ofSize: CGFloat(config?.fontHeight ?? 12))
        let traits: NSFontDescriptor.SymbolicTraits = {
            switch (style.isBold, style.isItalic) {
            case (true, true): return [.bold, .italic]
            case (true, false): return [.bold]
            case (false, true): return [.italic]
            case (false, false): return []
            }
        }()
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }

    private func applyCurrentStyleToAllText() {
        guard attributedString.length > 0 else { return }
        applyStyle(currentStyle, range: NSRange(location: 0, length: attributedString.length))
    }
}
