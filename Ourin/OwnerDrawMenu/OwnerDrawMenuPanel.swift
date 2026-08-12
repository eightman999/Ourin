import AppKit

class OwnerDrawMenuPanel: NSPanel {
    private weak var menuView: OwnerDrawMenuView?
    private var onAction: ((String) -> Void)?
    private var isClosing = false
    
    // 非アクティブ化時に自動的に閉じる
    var closesOnDeactivate: Bool = true

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
    
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
        isMovable = false

        setupView(contentSize: contentRect.size, config: config, items: items)
    }
    
    required init?(coder: NSCoder) {
        // メニューの内容・設定は呼び出し時に構成するため、coder からは復元しない。
        return nil
    }
    
    private func setupView(contentSize: NSSize, config: OwnerDrawMenuConfig, items: [OwnerDrawMenuItem]) {
        // コンテンツビューはパネルのコンテンツサイズで初期化する
        let contentView = OwnerDrawMenuView(frame: NSRect(origin: .zero, size: contentSize), config: config, items: items) { [weak self] action in
            self?.handleAction(action)
        }
        
        self.contentView = contentView
        self.menuView = contentView
        
        // フェードインアニメーションを開始
        contentView.startFadeIn()
    }
    
    func show(at point: NSPoint, relativeTo screen: NSScreen) {
        // point はメニューの左上。NSPanel の frame origin は左下なので高さ分だけ下げる。
        let adjustedRect = calculatePosition(for: frame, at: point, on: screen)
        setFrame(adjustedRect, display: false)

        // リサイズ後のビュー全体をトラッキングエリアが覆うようにする
        menuView?.updateTrackingAreas()
        
        makeKeyAndOrderFront(nil)
        
        // ファーストレスポンダーにしてキーボードナビゲーションを有効にする
        menuView?.window?.makeFirstResponder(menuView)
    }
    
    private func calculatePosition(for frame: NSRect, at point: NSPoint, on screen: NSScreen) -> NSRect {
        var rect = frame
        rect.origin = NSPoint(x: point.x, y: point.y - rect.height)
        
        let visibleFrame = screen.visibleFrame
        
        // 右端を超える場合は左側に表示
        if rect.maxX > visibleFrame.maxX {
            rect.origin.x = visibleFrame.maxX - rect.width
        }
        // 左端を超える場合は右側に表示
        if rect.minX < visibleFrame.minX {
            rect.origin.x = visibleFrame.minX
        }

        // 上端を超える場合は下側に表示
        if rect.maxY > visibleFrame.maxY {
            rect.origin.y = visibleFrame.maxY - rect.height
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
    
    override func resignKey() {
        super.resignKey()
        if closesOnDeactivate {
            close()
        }
    }
    
    override func close() {
        guard !isClosing else { return }
        isClosing = true

        // フェードアウトアニメーションを実行
        guard let menuView = menuView else {
            performClose()
            return
        }
        menuView.startFadeOut { [weak self] in
            self?.performClose()
        }
    }
    
    private func performClose() {
        super.close()
    }
}
