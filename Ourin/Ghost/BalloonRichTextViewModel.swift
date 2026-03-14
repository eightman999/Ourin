import Foundation
import AppKit

/// Text style attributes for balloon rendering
struct BalloonTextStyle {
    var font: NSFont?
    var color: NSColor?
    var backgroundColor: NSColor?
    var underlineStyle: NSUnderlineStyle?
    var strikethroughStyle: Int?
    var alignment: NSTextAlignment?
    var lineSpacing: CGFloat?
    var paragraphSpacing: CGFloat?
    var shadow: NSShadow?
    var isBold: Bool = false
    var isItalic: Bool = false
}

/// ViewModel for rich text balloon rendering with NSAttributedString/CoreText
class BalloonRichTextViewModel: ObservableObject {
    @Published var attributedString: NSAttributedString
    @Published var cursorPosition: CGPoint = .zero
    @Published var selectionRange: NSRange?
    
    private var config: BalloonConfig?
    private var currentStyle: BalloonTextStyle = BalloonTextStyle()
    
    init(config: BalloonConfig? = nil) {
        self.config = config
        self.attributedString = NSAttributedString(string: "")
    }
    
    /// Process text and apply styles from SakuraScript \f[...] commands
    func processText(_ text: String) {
        let mutableString = NSMutableAttributedString(string: text)
        
        // Apply base font from config
        let baseFont = NSFont.systemFont(ofSize: CGFloat(config?.fontHeight ?? 12))
        mutableString.addAttribute(.font, value: baseFont, range: NSRange(location: 0, length: mutableString.length))
        
        // Apply base color from config
        if let fontColor = config?.fontColor {
            mutableString.addAttribute(.foregroundColor, value: fontColor, range: NSRange(location: 0, length: mutableString.length))
        }
        
        self.attributedString = mutableString
    }
    
    /// Apply style attribute to text
    func applyStyle(_ style: BalloonTextStyle, range: NSRange) {
        guard range.location + range.length <= attributedString.length else { return }
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        
        if let font = style.font {
            mutableString.addAttribute(.font, value: font, range: range)
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
            mutableString.addAttribute(.paragraphStyle, value: paragraph, range: range)
        }
        if let shadow = style.shadow {
            mutableString.addAttribute(.shadow, value: shadow, range: range)
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
        default:
            break
        }
    }
    
    func handleValignCommand(_ align: String) {
        // Vertical alignment is handled in paragraph style
        // For now, just log - full implementation requires custom text layout
        NSLog("[BalloonRichTextViewModel] Vertical alignment: \(align)")
    }
    
    func handleFontCommand(_ name: String) {
        let size = CGFloat(config?.fontHeight ?? 12)
        
        if name == "default" {
            currentStyle.font = NSFont.systemFont(ofSize: size)
        } else if name == "disable" {
            currentStyle.font = NSFont.systemFont(ofSize: size)
        } else {
            // Try to load custom font
            if let font = NSFont(name: name, size: size) {
                currentStyle.font = font
            }
        }
    }
    
    func handleHeightCommand(_ height: CGFloat) {
        let currentFont = currentStyle.font ?? NSFont.systemFont(ofSize: 12)
        currentStyle.font = currentFont.withSize(height)
    }
    
    func handleColorCommand(_ color: NSColor) {
        currentStyle.color = color
    }
    
    func handleShadowColorCommand(_ color: NSColor) {
        currentStyle.shadow = NSShadow()
        currentStyle.shadow?.shadowColor = color
    }
    
    func handleShadowStyleCommand(_ style: String) {
        currentStyle.shadow = NSShadow()
        switch style.lowercased() {
        case "offset":
            // Default shadow behavior
            break
        case "outline":
            currentStyle.shadow?.shadowBlurRadius = 0
        default:
            break
        }
    }
    
    func handleOutlineCommand(_ enabled: Bool) {
        if enabled {
            currentStyle.shadow = NSShadow()
            currentStyle.shadow?.shadowColor = .white
            currentStyle.shadow?.shadowBlurRadius = 0
            currentStyle.shadow?.shadowOffset = CGSize(width: 0, height: 0)
        } else {
            currentStyle.shadow = nil
        }
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
        // Subscript - requires custom text layout
        NSLog("[BalloonRichTextViewModel] Subscript: \(enabled)")
    }
    
    func handleSupCommand(_ enabled: Bool) {
        // Superscript - requires custom text layout
        NSLog("[BalloonRichTextViewModel] Superscript: \(enabled)")
    }
    
    func handleCursorCommand(_ position: CGPoint) {
        cursorPosition = position
    }
    
    func handleResetCommand() {
        currentStyle = BalloonTextStyle()
        if let fontColor = config?.fontColor {
            currentStyle.color = fontColor
        }
        let size = CGFloat(config?.fontHeight ?? 12)
        currentStyle.font = NSFont.systemFont(ofSize: size)
    }
    
    func handleDefaultCommand() {
        handleResetCommand()
    }
    
    func handleDisableCommand() {
        // Use default font
        currentStyle.font = NSFont.systemFont(ofSize: 10)
        currentStyle.color = .disabledControlTextColor
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
        currentStyle.font = NSFont(descriptor: descriptor, size: baseFont.pointSize)
    }
}
