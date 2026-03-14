import AppKit

class OwnerDrawMenuPanel: NSPanel {
    private weak var menuView: OwnerDrawMenuView?
    private var onAction: ((String) -> Void)?
    
    // 非アクティブ化時に自動的に閉じる
    var closesOnDeactivate: Bool = true
    
    init(contentRect: NSRect, config: OwnerDrawMenuConfig, items: [OwnerDrawMenuItem], onAction: @escaping (String) -> Void) {
        self.onAction = onAction
        
        super.init(contentRect: contentRect,
                  styleMask: [.borderless, .nonactivatingPanel],
                  backing: .buffered,
                  defer: false)
        
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        
        setupView(config: config, items: items)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView(config: OwnerDrawMenuConfig, items: [OwnerDrawMenuItem]) {
        let contentView = OwnerDrawMenuView(frame: NSRect(x: 0, y: 0, width: 0, height: 0), config: config, items: items) { [weak self] action in
            self?.handleAction(action)
        }
        
        self.contentView = contentView
        self.menuView = contentView
        
        // フェードインアニメーションを開始
        contentView.startFadeIn()
    }
    
    func show(at point: NSPoint, relativeTo screen: NSScreen) {
        // 画面の境界を考慮して位置を調整
        let adjustedRect = calculatePosition(for: frame, at: point, on: screen)
        setFrame(adjustedRect, display: false)
        
        makeKeyAndOrderFront(nil)
        
        // ファーストレスポンダーにしてキーボードナビゲーションを有効にする
        menuView?.window?.makeFirstResponder(menuView)
    }
    
    private func calculatePosition(for frame: NSRect, at point: NSPoint, on screen: NSScreen) -> NSRect {
        var rect = frame
        rect.origin = point
        
        let visibleFrame = screen.visibleFrame
        
        // 右端を超える場合は左側に表示
        if rect.maxX > visibleFrame.maxX {
            rect.origin.x = visibleFrame.maxX - rect.width
        }
        
        // 下端を超える場合は上側に表示
        if rect.minY < visibleFrame.minY {
            rect.origin.y = visibleFrame.minY
        }
        
        return rect
    }
    
    private func handleAction(_ action: String) {
        close()
        onAction?(action)
    }
    
    override func resignFirstResponder() -> Bool {
        if closesOnDeactivate {
            close()
        }
        return super.resignFirstResponder()
    }
    
    override func close() {
        // フェードアウトアニメーションを実行
        menuView?.startFadeOut { [weak self] in
            self?.performClose()
        }
    }
    
    private func performClose() {
        super.close()
    }
}
