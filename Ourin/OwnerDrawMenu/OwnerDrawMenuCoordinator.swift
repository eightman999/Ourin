import AppKit

class OwnerDrawMenuCoordinator {
    static let shared = OwnerDrawMenuCoordinator()
    private init() {}
    
    private var activeMenu: OwnerDrawMenuPanel?
    private var submenuStack: [OwnerDrawMenuPanel] = []
    private var rootAction: ((String) -> Void)?
    
    func showMenu(at point: NSPoint, config: OwnerDrawMenuConfig, items: [OwnerDrawMenuItem], onAction: @escaping (String) -> Void) {
        // 既存のメニューを閉じる
        closeAllMenus()
        rootAction = onAction
        
        // メニューのサイズを計算
        let menuHeight = calculateMenuHeight(items: items, config: config)
        let menuWidth = calculateMenuWidth(items: items, config: config)
        
        let menuRect = NSRect(x: point.x, y: point.y - menuHeight, width: menuWidth, height: menuHeight)
        
        let panel = OwnerDrawMenuPanel(contentRect: menuRect, config: config, items: items) { [weak self] action in
            self?.handleRootAction(action)
        }
        activeMenu = panel
        
        if let screen = screen(containing: point) {
            panel.show(at: point, relativeTo: screen)
        }
    }
    
    func showSubmenu(for itemIndex: Int, parentPanel: OwnerDrawMenuPanel?, items: [OwnerDrawMenuItem]) {
        guard let parentView = parentPanel?.contentView as? OwnerDrawMenuView else { return }
        
        let itemRect = parentView.itemRect(for: itemIndex)
        guard let parentWindowRect = parentPanel?.frame else { return }
        
        let config = parentView.config
        
        // サブメニューのサイズを計算
        let menuHeight = calculateMenuHeight(items: items, config: config)
        let menuWidth = calculateMenuWidth(items: items, config: config)
        
        // サブメニューの左上を親項目の左上に合わせる。
        let itemTopInScreen = parentWindowRect.minY + itemRect.maxY
        var submenuPoint = CGPoint(x: parentWindowRect.maxX, y: itemTopInScreen)

        closeSubmenus(after: parentPanel)
        parentPanel?.closesOnDeactivate = false

        // 画面の右端に近い場合は左側に表示
        if let screen = screen(containing: submenuPoint), submenuPoint.x + menuWidth > screen.visibleFrame.maxX {
            submenuPoint.x = parentWindowRect.minX - menuWidth
        }
        
        let panel = OwnerDrawMenuPanel(
            contentRect: NSRect(x: submenuPoint.x, y: submenuPoint.y - menuHeight, width: menuWidth, height: menuHeight),
            config: config,
            items: items
        ) { [weak self] action in
            self?.handleRootAction(action)
        }
        
        submenuStack.append(panel)
        
        if let screen = screen(containing: submenuPoint) {
            panel.show(at: submenuPoint, relativeTo: screen)
        }
    }
    
    func closeAllMenus() {
        activeMenu?.close()
        activeMenu = nil
        
        for menu in submenuStack {
            menu.close()
        }
        submenuStack.removeAll()
        rootAction = nil
    }

    private func closeSubmenus(after parentPanel: OwnerDrawMenuPanel?) {
        let keepCount: Int
        if let parentPanel,
           let parentIndex = submenuStack.firstIndex(where: { $0 === parentPanel }) {
            keepCount = parentIndex + 1
        } else {
            keepCount = 0
        }

        for menu in submenuStack.dropFirst(keepCount) {
            menu.close()
        }
        submenuStack.removeSubrange(keepCount..<submenuStack.count)
    }

    private func handleRootAction(_ action: String) {
        let handler = rootAction
        closeAllMenus()
        handler?(action)
    }
    
    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }
    
    private func calculateMenuHeight(items: [OwnerDrawMenuItem], config: OwnerDrawMenuConfig) -> CGFloat {
        var height: CGFloat = 0
        for item in items {
            if item.visible {
                height += config.itemHeight
            }
        }
        return height
    }
    
    private func calculateMenuWidth(items: [OwnerDrawMenuItem], config: OwnerDrawMenuConfig) -> CGFloat {
        var maxWidth: CGFloat = 100 // 最小幅
        
        let font = config.font
        for item in items {
            guard item.visible else { continue }
            
            // テキスト幅を計算
            let textWidth = item.caption.size(withAttributes: [.font: font]).width
            let totalWidth = config.sidebarWidth + config.textMarginLeft + textWidth + config.textMarginRight
            
            if totalWidth > maxWidth {
                maxWidth = totalWidth
            }
        }
        
        // サブメニューインジケーターの幅を追加
        return maxWidth + 30
    }
}
