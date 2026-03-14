import AppKit

class OwnerDrawMenuCoordinator {
    static let shared = OwnerDrawMenuCoordinator()
    private init() {}
    
    private var activeMenu: OwnerDrawMenuPanel?
    private var submenuStack: [OwnerDrawMenuPanel] = []
    
    func showMenu(at point: NSPoint, config: OwnerDrawMenuConfig, items: [OwnerDrawMenuItem], onAction: @escaping (String) -> Void) {
        // 既存のメニューを閉じる
        closeAllMenus()
        
        // メニューのサイズを計算
        let menuHeight = calculateMenuHeight(items: items, config: config)
        let menuWidth = calculateMenuWidth(items: items, config: config)
        
        let menuRect = NSRect(x: point.x, y: point.y - menuHeight, width: menuWidth, height: menuHeight)
        
        let panel = OwnerDrawMenuPanel(contentRect: menuRect, config: config, items: items, onAction: onAction)
        activeMenu = panel
        
        if let screen = NSScreen.main {
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
        
        // サブメニューの位置を計算
        var submenuPoint = CGPoint(x: parentWindowRect.maxX, y: parentWindowRect.maxY - itemRect.minY)
        
        // 画面の右端に近い場合は左側に表示
        if let screen = NSScreen.main, submenuPoint.x + menuWidth > screen.visibleFrame.maxX {
            submenuPoint.x = parentWindowRect.minX - menuWidth
        }
        
        // 下端を超える場合は上側に表示
        if let screen = NSScreen.main, submenuPoint.y - menuHeight < screen.visibleFrame.minY {
            submenuPoint.y = parentWindowRect.maxY - itemRect.maxY
        }
        
        let panel = OwnerDrawMenuPanel(
            contentRect: NSRect(x: submenuPoint.x, y: submenuPoint.y - menuHeight, width: menuWidth, height: menuHeight),
            config: config,
            items: items,
            onAction: { [weak self] action in
                self?.handleSubmenuAction(action)
            }
        )
        
        submenuStack.append(panel)
        
        if let screen = NSScreen.main {
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
    }
    
    private func handleSubmenuAction(_ action: String) {
        // サブメニューのアクションを親に伝播
        // 必要に応じて処理
        NSLog("[OwnerDrawMenuCoordinator] Submenu action: \(action)")
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
