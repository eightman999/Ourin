import AppKit

class OwnerDrawMenuView: NSView {
    var config: OwnerDrawMenuConfig
    var items: [OwnerDrawMenuItem]
    var onAction: (String) -> Void
    
    private var hoveredIndex: Int? = nil
    private var keyboardIndex: Int? = nil
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
    }

    required init?(coder: NSCoder) {
        // メニューの内容・設定は呼び出し時に構成するため、coder からは復元しない。
        return nil
    }

    override func updateTrackingAreas() {
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        super.updateTrackingAreas()
        let newArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newArea)
        trackingArea = newArea
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override var acceptsFirstResponder: Bool {
        true
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
        
        // 1. 背景画像を描画（アンカー位置に配置して bounds でクリップ）
        if let bgImage = config.backgroundImage {
            drawImage(bgImage, in: bounds, clippedTo: bounds, alignment: config.backgroundAlignment)
        } else {
            // デフォルト背景
            NSColor.controlBackgroundColor.setFill()
            bounds.fill()
        }
        
        // 2. サイドバー画像を左側に描画
        if let sidebarImage = config.sidebarImage {
            let sidebarRect = NSRect(x: 0, y: 0, width: config.sidebarWidth, height: bounds.height)
            drawImage(sidebarImage, in: sidebarRect, clippedTo: sidebarRect, alignment: config.sidebarAlignment)
        }
        
        // 3. メニュー項目を描画
        drawMenuItems()
        
        // 4. 区切り線を描画
        drawSeparators()
        
        context.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()
    }
    
    // MARK: - Image Drawing
    
    private func drawImage(_ image: NSImage, in anchorRect: NSRect, clippedTo clipRect: NSRect, alignment: MenuAlignment) {
        // 画像の配置は anchorRect、表示範囲だけを clipRect とする。
        // これにより、全体画像の前景を各メニュー行のスライスとして描画できる。
        guard let graphicsContext = NSGraphicsContext.current else { return }
        let cgContext = graphicsContext.cgContext
        cgContext.saveGState()
        defer { cgContext.restoreGState() }
        cgContext.clip(to: clipRect)

        // 画像のサイズが anchorRect より小さい場合、端の色で塗り潰す
        if image.size.width < anchorRect.width || image.size.height < anchorRect.height {
            let edgeColor = image.getEdgeColor(at: alignment)
            edgeColor.setFill()
            NSBezierPath(rect: anchorRect).fill()
        }
        
        // 配置に基づいて画像を描画（unflipped AppKit座標: top = rect.maxY - height, bottom = rect.minY）
        var imageRect = NSRect(origin: anchorRect.origin, size: image.size)
        switch alignment {
        case .leftTop, .top:
            imageRect.origin = CGPoint(x: anchorRect.minX, y: anchorRect.maxY - image.size.height)
        case .leftBottom, .bottom:
            imageRect.origin = CGPoint(x: anchorRect.minX, y: anchorRect.minY)
        case .rightTop:
            imageRect.origin = CGPoint(x: anchorRect.maxX - image.size.width, y: anchorRect.maxY - image.size.height)
        case .rightBottom:
            imageRect.origin = CGPoint(x: anchorRect.maxX - image.size.width, y: anchorRect.minY)
        case .centerTop:
            imageRect.origin = CGPoint(x: anchorRect.midX - image.size.width / 2, y: anchorRect.maxY - image.size.height)
        case .centerBottom:
            imageRect.origin = CGPoint(x: anchorRect.midX - image.size.width / 2, y: anchorRect.minY)
        case .left:
            imageRect.origin = CGPoint(x: anchorRect.minX, y: anchorRect.midY - image.size.height / 2)
        case .center:
            imageRect.origin = CGPoint(x: anchorRect.midX - image.size.width / 2, y: anchorRect.midY - image.size.height / 2)
        case .right:
            imageRect.origin = CGPoint(x: anchorRect.maxX - image.size.width, y: anchorRect.midY - image.size.height / 2)
        }

        image.draw(in: imageRect)
    }
    
    // MARK: - Menu Items
    
    private func drawMenuItems() {
        for (row, index) in visibleRowIndices().enumerated() {
            let item = items[index]
            let itemRect = rowRect(forRow: row)
            
            // その項目がホバーまたはキーボード選択中の場合のみ前景画像をオーバーレイ
            let isHighlighted = (hoveredIndex == index || keyboardIndex == index) && item.enabled
            if isHighlighted, let fgImage = config.foregroundImage {
                drawImage(fgImage, in: bounds, clippedTo: itemRect, alignment: config.foregroundAlignment)
            }

            // テキストを描画
            drawItemText(item, in: itemRect, isHighlighted: isHighlighted)
            
            // ショートカットキーを描画
            if let shortcut = item.shortcut {
                drawShortcut(shortcut, in: itemRect, isHighlighted: isHighlighted)
            }
            
            // サブメニューインジケーターを描画
            if case .submenu = item.type {
                drawSubmenuIndicator(in: itemRect, isHighlighted: isHighlighted)
            }
        }
    }
    
    private func drawItemText(_ item: OwnerDrawMenuItem, in rect: NSRect, isHighlighted: Bool) {
        let textColor: NSColor = item.enabled ? (isHighlighted ? config.foregroundColor : config.backgroundColor) : config.disabledColor
        
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
    
    private func drawShortcut(_ shortcut: Character, in rect: NSRect, isHighlighted: Bool) {
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
            .foregroundColor: isHighlighted ? config.foregroundColor : config.backgroundColor,
            .paragraphStyle: paragraphStyle
        ]
        
        text.draw(in: textRect, withAttributes: attributes)
    }
    
    private func drawSubmenuIndicator(in rect: NSRect, isHighlighted: Bool) {
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
        
        (isHighlighted ? config.foregroundColor : config.backgroundColor).setFill()
        path.fill()
    }
    
    // MARK: - Separators
    
    private func drawSeparators() {
        for (row, index) in visibleRowIndices().enumerated() {
            let item = items[index]
            
            if case .separator = item.type {
                let sepRect = NSRect(
                    x: config.sidebarWidth,
                    y: rowRect(forRow: row).minY - config.separatorHeight,
                    width: bounds.width - config.sidebarWidth,
                    height: config.separatorHeight
                )
                
                config.separatorColor.setFill()
                NSBezierPath(rect: sepRect).fill()
            }
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
            if let char = event.characters?.first,
               let index = items.firstIndex(where: { $0.visible && $0.enabled && $0.shortcut == char }) {
                handleItemClick(items[index], at: index)
            } else {
                super.keyDown(with: event)
            }
        }
    }
    
    private func navigateMenu(direction: Int) {
        let enabledIndices = items.enumerated().compactMap { index, item in
            item.visible && item.enabled ? index : nil
        }
        
        // 循環ナビゲーション
        if enabledIndices.isEmpty {
            return
        }

        if let currentIndex = keyboardIndex ?? hoveredIndex,
           let currentPosition = enabledIndices.firstIndex(of: currentIndex) {
            let nextPosition = (currentPosition + direction + enabledIndices.count) % enabledIndices.count
            keyboardIndex = enabledIndices[nextPosition]
        } else {
            keyboardIndex = direction > 0 ? enabledIndices[0] : enabledIndices[enabledIndices.count - 1]
        }

        hoveredIndex = nil
        needsDisplay = true
    }
    
    // MARK: - Helper Methods
    
    /// 描画・ヒットテスト・itemRect で共通の可視行マッピング
    private func visibleRowIndices() -> [Int] {
        items.indices.filter { items[$0].visible }
    }

    private func rowRect(forRow row: Int) -> NSRect {
        NSRect(x: 0, y: bounds.height - config.itemHeight * CGFloat(row + 1), width: bounds.width, height: config.itemHeight)
    }

    private func visibleIndex(forRow row: Int) -> Int? {
        let rows = visibleRowIndices()
        guard row >= 0, row < rows.count else { return nil }
        return rows[row]
    }

    private func itemIndex(at location: CGPoint) -> Int? {
        let row = Int((bounds.height - location.y) / config.itemHeight)
        return visibleIndex(forRow: row)
    }
    
    private func handleItemClick(_ item: OwnerDrawMenuItem, at index: Int) {
        guard item.enabled else { return }
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
        guard let row = visibleRowIndices().firstIndex(of: index) else {
            return NSRect(x: 0, y: 0, width: bounds.width, height: config.itemHeight)
        }
        return rowRect(forRow: row)
    }
    
    func closeMenu() {
        window?.close()
    }
    
    // MARK: - Animation
    
    func startFadeIn() {
        animationTimer?.invalidate()
        isFadingIn = true
        animationProgress = 0.0
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.updateAnimation()
        }
    }
    
    func startFadeOut(completion: @escaping () -> Void) {
        animationTimer?.invalidate()
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
        
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return NSColor.black }

        // アンカーとは反対側のエッジ色をサンプリング（塗り潰し領域と隣接する側）
        var x: Int = width / 2
        var y: Int = height / 2
        
        switch alignment {
        case .leftTop, .top:
            x = width / 2
            y = 0
        case .leftBottom, .bottom:
            x = width / 2
            y = height - 1
        case .rightTop:
            x = 0
            y = 0
        case .rightBottom:
            x = 0
            y = height - 1
        case .centerTop:
            x = width / 2
            y = 0
        case .centerBottom:
            x = width / 2
            y = height - 1
        case .left:
            x = width - 1
            y = height / 2
        case .center:
            x = width / 2
            y = height / 2
        case .right:
            x = 0
            y = height / 2
        }
        
        guard let color = bitmap.colorAt(x: min(x, width - 1), y: min(y, height - 1)) else {
            return NSColor.black
        }
        return color
    }
}
