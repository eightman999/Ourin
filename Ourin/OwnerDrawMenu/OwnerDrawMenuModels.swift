import AppKit

/// メニュー配置オプション
public enum MenuAlignment: String {
    case leftTop = "lefttop"
    case leftBottom = "leftbottom"
    case rightTop = "righttop"
    case rightBottom = "rightbottom"
}

/// メニュー項目タイプ
public enum MenuItemType {
    case button(action: String)
    case submenu(items: [OwnerDrawMenuItem], action: String?)
    case separator
}

/// メニュー項目
public struct OwnerDrawMenuItem {
    public let type: MenuItemType
    public let caption: String
    public var visible: Bool = true
    public var enabled: Bool = true
    public var shortcut: Character? = nil
    public var indentation: Int = 0
}

/// オーナードローメニュー設定
public struct OwnerDrawMenuConfig {
    // 画像
    public var backgroundImage: NSImage?
    public var foregroundImage: NSImage?
    public var sidebarImage: NSImage?
    
    // 配置
    public var backgroundAlignment: MenuAlignment = .leftTop
    public var foregroundAlignment: MenuAlignment = .leftTop
    public var sidebarAlignment: MenuAlignment = .leftBottom
    
    // 色（RGB: 0-255）
    public var backgroundColor: NSColor = NSColor(red: 0, green: 0, blue: 0, alpha: 1)
    public var foregroundColor: NSColor = NSColor(red: 0, green: 0, blue: 255, alpha: 1)
    public var separatorColor: NSColor = NSColor(red: 0, green: 0, blue: 0, alpha: 1)
    public var disabledColor: NSColor = NSColor(red: 120, green: 120, blue: 120, alpha: 1)
    public var frameColor: NSColor? = nil
    
    // フォント
    public var font: NSFont = NSFont.systemFont(ofSize: 13)
    
    // レイアウト
    public var itemHeight: CGFloat = 24
    public var sidebarWidth: CGFloat = 0
    public var textMarginLeft: CGFloat = 10
    public var textMarginRight: CGFloat = 20
    public var separatorHeight: CGFloat = 2
}
