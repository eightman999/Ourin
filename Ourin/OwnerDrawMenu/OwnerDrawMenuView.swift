import AppKit

class OwnerDrawMenuView: NSView {
    var config: OwnerDrawMenuConfig
    var items: [OwnerDrawMenuItem]
    var onAction: (String) -> Void
    
    private var hoveredIndex: Int? = nil
    private var selectedIndex: Int? = nil
    private var keyboardIndex: Int? = nil
    private var visibleSubmenuIndex: Int? = nil
    private var animationProgress: CGFloat = 0.0
    private var isFadingIn: Bool = true
    
    // アニメーション用
    private var animationTimer: Timer?
    private var fadeInDuration: TimeInterval = 0.15
    private var fadeOutDuration: TimeInterval = 0.1
    
    private var trackingArea: NSTrackingArea?
    
    init(frame frameRect: NSRect, config: OwnerDrawMenuConfig, items: [OwnerDrawMenuItem], onAction: @escaping (String) -> Void) {
        self.config = config
        self.items = items
        self.onAction = onAction
        
        super.init(frame: frameRect)
        
        setupTracking()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupTracking() {
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }
    
    // MARK: - Draw
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // アルファを適用（フェードイン/アウト）
        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext.current else {
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        
        context.saveGraphicsState()
        context.cgContext.setAlpha(animationProgress)
        
        // 1. 背景画像を描画（タイル状に拡張）
        if let bgImage = config.backgroundImage {
            drawTiledImage(bgImage, in: bounds, alignment: config.backgroundAlignment)
        } else {
            // デフォルト背景
            NSColor.controlBackgroundColor.setFill()
            bounds.fill()
        }
        
        // 2. サイドバー画像を左側に描画
        if let sidebarImage = config.sidebarImage {
            let sidebarRect = NSRect(x: 0, y: 0, width: config.sidebarWidth, height: bounds.height)
            drawTiledImage(sidebarImage, in: sidebarRect, alignment: config.sidebarAlignment)
        }
        
        // 3. メニュー項目を描画
        drawMenuItems()
        
        // 4. 区切り線を描画
        drawSeparators()
        
        context.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()
    }
    
    // MARK: - Image Drawing
    
    private func drawTiledImage(_ image: NSImage, in rect: NSRect, alignment: MenuAlignment) {
        // 画像のサイズが rect より小さい場合、端の色で塗り潰す
        if image.size.width < rect.width || image.size.height < rect.height {
            let edgeColor = image.getEdgeColor(at: alignment)
            edgeColor.setFill()
            NSBezierPath(rect: rect).fill()
        }
        
        // 配置に基づいて画像を描画
        var imageRect = NSRect(origin: .zero, size: image.size)
        switch alignment {
        case .leftTop:
            imageRect.origin = .zero
        case .leftBottom:
            imageRect.origin.y = rect.maxY - image.size.height
        case .rightTop:
            imageRect.origin.x = rect.maxX - image.size.width
        case .rightBottom:
            imageRect.origin = CGPoint(x: rect.maxX - image.size.width, y: rect.maxY - image.size.height)
        }
        
        image.draw(in: imageRect)
    }
    
    // MARK: - Menu Items
    
    private func drawMenuItems() {
        var y = bounds.height - config.itemHeight
        
        for (index, item) in items.enumerated() {
            guard item.visible else { continue }
            
            let itemRect = NSRect(x: 0, y: y, width: bounds.width, height: config.itemHeight)
            
            // ホバーまたはキーボード選択中の場合、前景画像をオーバーレイ
            if (hoveredIndex == index || keyboardIndex == index) && item.enabled,
               let fgImage = config.foregroundImage {
                drawTiledImage(fgImage, in: itemRect, alignment: config.foregroundAlignment)
            }
            
            // テキストを描画
            drawItemText(item, in: itemRect)
            
            // ショートカットキーを描画
            if let shortcut = item.shortcut {
                drawShortcut(shortcut, in: itemRect)
            }
            
            // サブメニューインジケーターを描画
            if case .submenu = item.type {
                drawSubmenuIndicator(in: itemRect)
            }
            
            y -= config.itemHeight
        }
    }
    
    private func drawItemText(_ item: OwnerDrawMenuItem, in rect: NSRect) {
        let textColor: NSColor = item.enabled ? 
            (hoveredIndex != nil || keyboardIndex != nil ? config.foregroundColor : config.backgroundColor) : 
            config.disabledColor
        
        let textRect = NSRect(
            x: config.sidebarWidth + config.textMarginLeft + CGFloat(item.indentation * 20),
            y: rect.minY + (rect.height - config.font.pointSize) / 2,
            width: rect.width - config.textMarginLeft - config.textMarginRight - config.sidebarWidth,
            height: config.font.pointSize
        )
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byTruncatingTail
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: config.font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
        
        item.caption.draw(in: textRect, withAttributes: attributes)
    }
    
    private func drawShortcut(_ shortcut: Character, in rect: NSRect) {
        let text = String(shortcut).uppercased()
        let textRect = NSRect(
            x: rect.maxX - config.textMarginRight - config.textMarginLeft,
            y: rect.minY + (rect.height - config.font.pointSize) / 2,
            width: config.textMarginRight,
            height: config.font.pointSize
        )
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: config.font,
            .foregroundColor: config.foregroundColor,
            .paragraphStyle: paragraphStyle
        ]
        
        text.draw(in: textRect, withAttributes: attributes)
    }
    
    private func drawSubmenuIndicator(in rect: NSRect) {
        let indicatorRect = NSRect(
            x: rect.maxX - 20,
            y: rect.minY + (rect.height - 10) / 2,
            width: 10,
            height: 10
        )
        
        let path = NSBezierPath()
        path.move(to: CGPoint(x: indicatorRect.minX, y: indicatorRect.minY))
        path.line(to: CGPoint(x: indicatorRect.maxX, y: indicatorRect.midY))
        path.line(to: CGPoint(x: indicatorRect.minX, y: indicatorRect.maxY))
        path.close()
        
        config.foregroundColor.setFill()
        path.fill()
    }
    
    // MARK: - Separators
    
    private func drawSeparators() {
        var y = bounds.height - config.itemHeight
        
        for item in items {
            guard item.visible else { continue }
            
            if case .separator = item.type {
                let sepRect = NSRect(
                    x: config.sidebarWidth,
                    y: y - config.separatorHeight,
                    width: bounds.width - config.sidebarWidth,
                    height: config.separatorHeight
                )
                
                config.separatorColor.setFill()
                NSBezierPath(rect: sepRect).fill()
            }
            
            y -= config.itemHeight
        }
    }
    
    // MARK: - Mouse Events
    
    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let newIndex = itemIndex(at: location)
        
        if newIndex != hoveredIndex {
            hoveredIndex = newIndex
            keyboardIndex = nil // マウス操作が優先
            needsDisplay = true
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if let index = itemIndex(at: location), index < items.count {
            let item = items[index]
            guard item.enabled else { return }
            
            handleItemClick(item, at: index)
        }
    }
    
    // MARK: - Keyboard Events
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: // Down Arrow
            navigateMenu(direction: 1)
        case 126: // Up Arrow
            navigateMenu(direction: -1)
        case 36: // Enter
            if let index = keyboardIndex ?? hoveredIndex, index < items.count {
                handleItemClick(items[index], at: index)
            }
        case 53: // Escape
            closeMenu()
        case 48: // Tab
            // Handle tab navigation
            super.keyDown(with: event)
        default:
            if let char = event.characters?.first, items.contains(where: { $0.shortcut == char }) {
                if let index = items.firstIndex(where: { $0.shortcut == char }) {
                    handleItemClick(items[index], at: index)
                }
            } else {
                super.keyDown(with: event)
            }
        }
    }
    
    private func navigateMenu(direction: Int) {
        var newIndex = (keyboardIndex ?? hoveredIndex ?? -1) + direction
        let visibleItems = items.filter { $0.visible }
        let enabledIndices = items.enumerated().compactMap { index, item in
            item.visible && item.enabled ? index : nil
        }
        
        // 循環ナビゲーション
        if enabledIndices.isEmpty {
            return
        }
        
        if newIndex < enabledIndices[0] {
            newIndex = enabledIndices.last!
        } else if newIndex > enabledIndices.last! {
            newIndex = enabledIndices[0]
        }
        
        // 無効な項目をスキップ
        while !enabledIndices.contains(newIndex) {
            newIndex += direction
            if newIndex < enabledIndices[0] || newIndex > enabledIndices.last! {
                return
            }
        }
        
        keyboardIndex = newIndex
        hoveredIndex = nil
        needsDisplay = true
    }
    
    // MARK: - Helper Methods
    
    private func itemIndex(at location: CGPoint) -> Int? {
        let y = bounds.height - location.y
        let index = Int(y / config.itemHeight)
        
        if index >= 0 && index < items.count {
            if items[index].visible {
                return index
            }
        }
        return nil
    }
    
    private func handleItemClick(_ item: OwnerDrawMenuItem, at index: Int) {
        switch item.type {
        case .button(let action):
            onAction(action)
        case .submenu(let subItems, _):
            // Show submenu
            OwnerDrawMenuCoordinator.shared.showSubmenu(for: index, parentPanel: window as? OwnerDrawMenuPanel, items: subItems)
        case .separator:
            break
        }
    }
    
    func itemRect(for index: Int) -> NSRect {
        var y = bounds.height - config.itemHeight
        for i in 0..<index {
            if items[i].visible {
                y -= config.itemHeight
            }
        }
        
        return NSRect(x: 0, y: y, width: bounds.width, height: config.itemHeight)
    }
    
    func closeMenu() {
        window?.close()
    }
    
    // MARK: - Animation
    
    func startFadeIn() {
        isFadingIn = true
        animationProgress = 0.0
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.updateAnimation()
        }
    }
    
    func startFadeOut(completion: @escaping () -> Void) {
        isFadingIn = false
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            self.animationProgress -= 1.0 / (self.fadeOutDuration * 60.0)
            
            if self.animationProgress <= 0 {
                self.animationProgress = 0
                timer.invalidate()
                completion()
            }
            
            self.needsDisplay = true
        }
    }
    
    private func updateAnimation() {
        if isFadingIn {
            animationProgress += 1.0 / (fadeInDuration * 60.0)
            if animationProgress >= 1.0 {
                animationProgress = 1.0
                animationTimer?.invalidate()
            }
        }
        needsDisplay = true
    }
}

// MARK: - NSImage Extension

extension NSImage {
    func getEdgeColor(at alignment: MenuAlignment) -> NSColor {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return NSColor.black
        }
        
        var x: Int = 0
        var y: Int = 0
        
        switch alignment {
        case .leftTop:
            x = Int(size.width) - 1
            y = Int(size.height) - 1
        case .leftBottom:
            x = Int(size.width) - 1
            y = 0
        case .rightTop:
            x = 0
            y = Int(size.height) - 1
        case .rightBottom:
            x = 0
            y = 0
        }
        
        guard let color = bitmap.colorAt(x: x, y: y) else {
            return NSColor.black
        }
        return color
    }
}
