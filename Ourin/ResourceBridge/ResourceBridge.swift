import Foundation
import AppKit
import OSLog

private extension String.Encoding {
    /// Windows 互換の Shift_JIS コードページ (CP932)
    static let shiftJIS = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)))
}

/// SHIORI の Resource キーを取得してキャッシュするブリッジ。
/// 仕様は `docs/PROPERTY_Resource_3.0M_SPEC.md` を参照。
/// ResourceBridge does not rely on modern APIs other than logging. Use
/// `CompatLogger` so the class works on older macOS versions as well.
public final class ResourceBridge {
    /// シングルトンインスタンス
    public static let shared = ResourceBridge()
    private init() {}

    /// Cached value with timestamp
    private struct Entry {
        var value: String?
        var time: Date
    }
    private var cache: [String: Entry] = [:]
    /// キャッシュ保持時間（秒）
    private let ttl: TimeInterval = 5
    /// ロガー
    private let logger = CompatLogger(subsystem: "Ourin", category: "ResourceBridge")

    /// Get resource value for given key via SHIORI. Uses cache if valid.
    public func get(_ key: String) -> String? {
        let now = Date()
        if let entry = cache[key], let cachedValue = entry.value,
           now.timeIntervalSince(entry.time) < ttl {
            return cachedValue
        }
        let value = query(key: key)
        if let value = value {
            cache[key] = Entry(value: value, time: now)
        } else {
            cache.removeValue(forKey: key)
        }
        logger.debug("query \(key) -> \(value ?? "nil")")
        return value
    }

    /// Force invalidate all cached values
    public func invalidateAll() {
        cache.removeAll()
    }

    /// 指定キーのみキャッシュを無効化する
    public func invalidate(keys: [String]) {
        for k in keys { cache.removeValue(forKey: k) }
    }

    // MARK: - Parsing helpers
    public func boolValue(for key: String) -> Bool? {
        guard let raw = get(key) else { return nil }
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["1", "true", "on"].contains(lower) ? true : (["0", "false", "off"].contains(lower) ? false : nil)
    }

    public func intValue(for key: String) -> Int? {
        guard let raw = get(key) else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func pointValue(for key: String) -> (Int, Int)? {
        guard let raw = get(key) else { return nil }
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let x = Int(parts[0]), let y = Int(parts[1]) else { return nil }
        return (x, y)
    }

    /// 画面左上基準の座標を AppKit の左下基準に変換して取得する
    public func screenPointValue(for key: String) -> CGPoint? {
        guard let (x, yTop) = pointValue(for: key) else { return nil }
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let convY = Int(union.height) - 1 - yTop
        return CGPoint(x: x, y: convY)
    }

    /// 区切り文字で分割した文字列配列を返す
    public func listValue(for key: String, separator: Character = "|") -> [String]? {
        guard let raw = get(key) else { return nil }
        return raw.split(separator: separator).map { String($0) }
    }

    /// `menu.*.color` 系の RGB 値を NSColor として取得する
    public func colorValue(for prefix: String) -> NSColor? {
        guard let r = intValue(for: "\(prefix).r"),
              let g = intValue(for: "\(prefix).g"),
              let b = intValue(for: "\(prefix).b") else { return nil }
        // 0-255 の範囲に丸めて sRGB 0-1 へ変換
        let rf = min(max(r, 0), 255)
        let gf = min(max(g, 0), 255)
        let bf = min(max(b, 0), 255)
        return NSColor(red: CGFloat(rf) / 255.0,
                       green: CGFloat(gf) / 255.0,
                       blue: CGFloat(bf) / 255.0,
                       alpha: 1)
    }

    /// おすすめ/ポータルサイト一覧を解析する構造体
    public struct RecommendSite {
        public var title: String
        public var url: String
        public var banner: URL?
        public var talk: String
    }

    /// UKADOC のオーナードローメニュー項目キー（接尾辞 `.caption`/`.visible` は別途付与）
    public static let ownerDrawMenuButtonBaseKeys: [String] = [
        "activaterootbutton", "addressbarbutton", "alignrootbutton",
        "alwaysstayontopbutton", "alwaystrayiconvisiblebutton", "balloonhistorybutton",
        "balloonrootbutton", "biffallbutton", "biffbutton",
        "calendarbutton", "callghosthistorybutton", "callghostrootbutton",
        "callsstpsendboxbutton", "char*.recommendsites", "charsetbutton",
        "closeballoonbutton", "closebutton", "collisionvisiblebutton",
        "configurationbutton", "configurationrootbutton", "debugballoonbutton",
        "definedsurfaceonlybutton", "dressuprootbutton", "duibutton",
        "enableballoonmovebutton", "firststaffbutton", "ghostexplorerbutton",
        "ghosthistorybutton", "ghostinstallbutton", "ghostrootbutton",
        "headlinesensehistorybutton", "headlinesenserootbutton", "helpbutton",
        "hidebutton", "historyrootbutton", "inforootbutton",
        "leavepassivebutton", "messengerbutton", "pluginhistorybutton",
        "pluginrootbutton", "portalrootbutton", "purgeghostcachebutton",
        "quitbutton", "rateofuseballoonbutton", "rateofusebutton",
        "rateofuserootbutton", "rateofusetotalbutton", "readmebutton",
        "termsbutton", "recommendrootbutton", "regionenabledbutton",
        "reloadinfobutton", "resetballoonpositionbutton", "resettodefaultbutton",
        "scriptlogbutton", "shellrootbutton", "shellscaleotherbutton",
        "shellscalerootbutton", "sntpbutton", "switchactivatewhentalkbutton",
        "switchactivatewhentalkexceptupdatebutton", "switchautobiffbutton", "switchautoheadlinesensebutton",
        "switchblacklistingbutton", "switchcompatiblemodebutton", "switchconsolealwaysvisiblebutton",
        "switchconsolevisiblebutton", "switchdeactivatebutton", "switchdontactivatebutton",
        "switchdontforcealignbutton", "switchduivisiblebutton", "switchforcealignfreebutton",
        "switchforcealignlimitbutton", "switchignoreserikomovebutton", "switchlocalsstpbutton",
        "switchmovetodefaultpositionbutton", "switchproxybutton", "switchquietbutton",
        "switchreloadbutton", "switchreloadtempghostbutton", "switchremotesstpbutton",
        "switchrootbutton", "switchtalkghostbutton", "systeminfobutton",
        "updatebutton", "updatefmobutton", "updateplatformbutton",
        "utilityrootbutton", "vanishbutton", "aistatebutton",
        "dictationbutton", "texttospeechbutton"
    ]

    public static let defaultRecommendSiteScopes: [String] = [
        "sakura", "kero", "char2", "char3", "char4", "char5", "char6", "char7", "char8", "char9"
    ]

    public static let ownerDrawMenuColorPrefixes: [String] = [
        "menu.background.font.color", "menu.foreground.font.color",
        "menu.background.color", "menu.foreground.color",
        "menu.separator.color", "menu.frame.color", "menu.disable.font.color"
    ]

    public func menuBitmapURLs(base: URL?) -> (sidebar: URL?, background: URL?, foreground: URL?) {
        (
            sidebar: urlValue(for: "menu.sidebar.bitmap.filename", relativeTo: base),
            background: urlValue(for: "menu.background.bitmap.filename", relativeTo: base),
            foreground: urlValue(for: "menu.foreground.bitmap.filename", relativeTo: base)
        )
    }

    public func ownerDrawMenuColorMap() -> [String: NSColor] {
        var result: [String: NSColor] = [:]
        for prefix in Self.ownerDrawMenuColorPrefixes {
            if let color = colorValue(for: prefix) {
                result[prefix] = color
            }
        }
        return result
    }

    public func ownerDrawMenuCaptionKeys(recommendSiteScopes: [String] = ResourceBridge.defaultRecommendSiteScopes) -> [String] {
        expandedOwnerDrawMenuBaseKeys(recommendSiteScopes: recommendSiteScopes).map { "\($0).caption" }
    }

    public func ownerDrawMenuVisibilityKeys(recommendSiteScopes: [String] = ResourceBridge.defaultRecommendSiteScopes) -> [String] {
        expandedOwnerDrawMenuBaseKeys(recommendSiteScopes: recommendSiteScopes).map { "\($0).visible" }
    }

    public func ownerDrawMenuCaptions(recommendSiteScopes: [String] = ResourceBridge.defaultRecommendSiteScopes) -> [String: (title: String, shortcut: Character?, visible: Bool)] {
        var result: [String: (title: String, shortcut: Character?, visible: Bool)] = [:]
        for key in ownerDrawMenuCaptionKeys(recommendSiteScopes: recommendSiteScopes) {
            if let item = menuItem(for: key) {
                result[key] = item
            }
        }
        return result
    }

    public func aiState() -> String? {
        get("getaistate")
    }

    public func aiStateExRaw() -> String? {
        get("getaistateex")
    }

    public func aiStateEx() -> [String]? {
        guard let raw = aiStateExRaw() else { return nil }
        return splitEscaped(raw, separator: "\u{01}").filter { !$0.isEmpty }
    }

    public func tooltipEventName() -> String? {
        get("tooltip")
    }

    public func balloonTooltipEventName() -> String? {
        get("balloon_tooltip")
    }

    public func portalSites(base: URL?) -> [RecommendSite]? {
        recommendSites(for: "sakura.portalsites", base: base)
    }

    public func recommendSites(forCharacter character: String, base: URL?) -> [RecommendSite]? {
        recommendSites(for: "\(character).recommendsites", base: base)
    }

    public func legacyInterfaceEnabled() -> Bool {
        boolValue(for: "legacyinterface") ?? false
    }

    public func otherHomeURLOverride() -> String? {
        get("other_homeurl_override")
    }

    /// `recommendsites` / `portalsites` を配列に展開する
    public func recommendSites(for key: String, base: URL?) -> [RecommendSite]? {
        guard let raw = get(key) else { return nil }
        let records = splitEscaped(raw, separator: "\u{02}")
        return records.compactMap { record in
            if record.isEmpty { return nil }
            let parts = splitEscaped(record, separator: "\u{01}")
            let title = parts.indices.contains(0) ? parts[0] : ""
            let url = parts.indices.contains(1) ? parts[1] : ""
            let bannerRaw = parts.indices.contains(2) ? parts[2] : ""
            let talk = parts.indices.contains(3) ? parts[3] : ""
            let banner = urlValue(fromRaw: bannerRaw, relativeTo: base)
            return RecommendSite(title: title, url: url, banner: banner, talk: talk)
        }
    }

    /// パス系リソースを URL として解釈する（相対パスは基準URLからの相対）
    public func urlValue(for key: String, relativeTo base: URL?) -> URL? {
        guard let raw = get(key) else { return nil }
        return urlValue(fromRaw: raw, relativeTo: base)
    }

    /// 生のパス文字列を URL として解釈する
    private func urlValue(fromRaw raw: String, relativeTo base: URL?) -> URL? {
        if raw.hasPrefix("file://") { return URL(string: raw) }
        if raw.hasPrefix("/") { return URL(fileURLWithPath: raw) }
        // Windows 形式を POSIX に変換
        if raw.contains("\\") || raw.contains(":") {
            let path = raw.replacingOccurrences(of: "\\", with: "/")
            return URL(fileURLWithPath: path)
        }
        guard let base = base else { return URL(fileURLWithPath: raw) }
        return base.appendingPathComponent(raw)
    }

    /// メニューキャプションとショートカット情報をまとめて取得する
    public func menuItem(for captionKey: String) -> (title: String, shortcut: Character?, visible: Bool)? {
        guard var caption = get(captionKey) else { return nil }
        var shortcut: Character? = nil
        if let open = caption.range(of: "(&"), let close = caption[open.upperBound...].firstIndex(of: ")"),
           open.upperBound < close {
            let keyChar = caption[open.upperBound]
            shortcut = keyChar
            caption.replaceSubrange(open.lowerBound...close, with: " \(keyChar)")
        } else if let amp = caption.firstIndex(of: "&"), caption.index(after: amp) < caption.endIndex {
            shortcut = caption[caption.index(after: amp)]
            caption.remove(at: amp)
        }
        caption = caption.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleKey = captionKey.replacingOccurrences(of: ".caption", with: ".visible")
        let visible = boolValue(for: visibleKey) ?? true
        return (caption, shortcut, visible)
    }

    /// 区切り文字をエスケープ考慮で分割する内部ユーティリティ
    private func splitEscaped(_ text: String, separator: Character) -> [String] {
        var result: [String] = []
        var current = ""
        var escape = false
        for ch in text {
            if escape {
                current.append(ch)
                escape = false
            } else if ch == "\\" {
                escape = true
            } else if ch == separator {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current)
        return result
    }

    private func expandedOwnerDrawMenuBaseKeys(recommendSiteScopes: [String]) -> [String] {
        Self.ownerDrawMenuButtonBaseKeys.flatMap { key -> [String] in
            guard key == "char*.recommendsites" else { return [key] }
            return recommendSiteScopes.map { "\($0).recommendsites" }
        }
    }

    // MARK: - Internal query
    /// SHIORI へ Resource 取得を問い合わせる
    private func query(key: String) -> String? {
        let res = BridgeToSHIORI.handle(event: "Resource", references: [key])
        return res.isEmpty ? nil : res
    }
}

// MARK: - Owner Draw Menu Extension
extension ResourceBridge {
    /// オーナードローメニュー設定を取得
    public func ownerDrawMenuConfig(base: URL? = nil) -> OwnerDrawMenuConfig {
        var config = OwnerDrawMenuConfig()
        
        // 背景画像
        if let bgPath = urlValue(for: "menu.background.bitmap.filename", relativeTo: base),
           let bgImage = NSImage(contentsOf: bgPath) {
            config.backgroundImage = bgImage
        }
        
        // 前景画像
        if let fgPath = urlValue(for: "menu.foreground.bitmap.filename", relativeTo: base),
           let fgImage = NSImage(contentsOf: fgPath) {
            config.foregroundImage = fgImage
        }
        
        // サイドバー画像
        if let sbPath = urlValue(for: "menu.sidebar.bitmap.filename", relativeTo: base),
           let sbImage = NSImage(contentsOf: sbPath) {
            config.sidebarImage = sbImage
            config.sidebarWidth = sbImage.size.width
        }
        
        // 色
        if let bgColor = colorValue(for: "menu.background.font.color") ?? colorValue(for: "menu.background.color") {
            config.backgroundColor = bgColor
        }
        
        if let fgColor = colorValue(for: "menu.foreground.font.color") ?? colorValue(for: "menu.foreground.color") {
            config.foregroundColor = fgColor
        }
        
        if let sepColor = colorValue(for: "menu.separator.color") {
            config.separatorColor = sepColor
        }
        
        if let disabledColor = colorValue(for: "menu.disable.font.color") {
            config.disabledColor = disabledColor
        }
        if let frameColor = colorValue(for: "menu.frame.color") {
            config.frameColor = frameColor
        }
        config.customColors = ownerDrawMenuColorMap()
        
        // 配置
        if let bgAlign = get("menu.background.alignment").flatMap(MenuAlignment.init(rawValue:)) {
            config.backgroundAlignment = bgAlign
        }
        
        if let fgAlign = get("menu.foreground.alignment").flatMap(MenuAlignment.init(rawValue:)) {
            config.foregroundAlignment = fgAlign
        }
        
        if let sbAlign = get("menu.sidebar.alignment").flatMap(MenuAlignment.init(rawValue:)) {
            config.sidebarAlignment = sbAlign
        }
        
        return config
    }
    
    /// メニュー項目一覧を取得
    public func menuItems() -> [OwnerDrawMenuItem] {
        var items: [OwnerDrawMenuItem] = []
        
        // ゴースト情報
        if let item = menuItem(caption: "inforootbutton") {
            var menuItem = OwnerDrawMenuItem(type: .button(action: "menu_ghost_info"), caption: item.title)
            menuItem.shortcut = item.shortcut
            menuItem.visible = item.visible
            items.append(menuItem)
        }
        
        // ゴースト切替
        if let item = menuItem(caption: "ghostrootbutton") {
            var menuItem = OwnerDrawMenuItem(
                type: .submenu(items: availableGhostItems(), action: nil),
                caption: item.title
            )
            menuItem.shortcut = item.shortcut
            menuItem.visible = item.visible
            items.append(menuItem)
        }
        
        // シェル切替
        if let item = menuItem(caption: "shellrootbutton") {
            var menuItem = OwnerDrawMenuItem(
                type: .submenu(items: availableShellItems(), action: nil),
                caption: item.title
            )
            menuItem.shortcut = item.shortcut
            menuItem.visible = item.visible
            items.append(menuItem)
        }
        
        // バルーン切替
        if let item = menuItem(caption: "balloonrootbutton") {
            var menuItem = OwnerDrawMenuItem(
                type: .submenu(items: availableBalloonItems(), action: nil),
                caption: item.title
            )
            menuItem.shortcut = item.shortcut
            menuItem.visible = item.visible
            items.append(menuItem)
        }
        
        // 区切り
        items.append(OwnerDrawMenuItem(type: .separator, caption: ""))
        
        // 設定
        if let item = menuItem(caption: "configurationbutton") {
            var menuItem = OwnerDrawMenuItem(type: .button(action: "menu_settings"), caption: item.title)
            menuItem.shortcut = item.shortcut
            menuItem.visible = item.visible
            items.append(menuItem)
        }
        
        // 終了
        if let item = menuItem(caption: "quitbutton") {
            var menuItem = OwnerDrawMenuItem(type: .button(action: "menu_quit"), caption: item.title)
            menuItem.shortcut = item.shortcut
            menuItem.visible = item.visible
            items.append(menuItem)
        }
        
        return items
    }
    
    /// 利用可能なゴースト項目
    private func availableGhostItems() -> [OwnerDrawMenuItem] {
        let ghosts = NarRegistry.shared.installedItems(ofType: "ghost")
            .map(\.name)
            .sorted()
        return ghosts.map { ghost in
            OwnerDrawMenuItem(type: .button(action: "switch_ghost:\(actionSafeIdentifier(ghost))"), caption: ghost)
        }
    }
    
    /// 利用可能なシェル項目
    private func availableShellItems() -> [OwnerDrawMenuItem] {
        var names: Set<String> = []
        if let currentGhostPath = PropertyManager.shared.get("currentghost.path") {
            let shellRoot = URL(fileURLWithPath: currentGhostPath).appendingPathComponent("shell", isDirectory: true)
            names.formUnion(shellNames(in: shellRoot))
        }

        if names.isEmpty {
            let ghostRoots = NarRegistry.shared.installedItems(ofType: "ghost").map(\.path)
            for ghostRoot in ghostRoots {
                names.formUnion(shellNames(in: ghostRoot.appendingPathComponent("shell", isDirectory: true)))
            }
        }

        if names.isEmpty {
            names.formUnion(NarRegistry.shared.installedItems(ofType: "shell").map(\.name))
        }

        return names.sorted().map { shell in
            OwnerDrawMenuItem(type: .button(action: "switch_shell:\(actionSafeIdentifier(shell))"), caption: shell)
        }
    }
    
    /// 利用可能なバルーン項目
    private func availableBalloonItems() -> [OwnerDrawMenuItem] {
        let balloons = NarRegistry.shared.installedItems(ofType: "balloon")
            .map(\.name)
            .sorted()
        return balloons.map { balloon in
            OwnerDrawMenuItem(type: .button(action: "switch_balloon:\(actionSafeIdentifier(balloon))"), caption: balloon)
        }
    }
    
    /// メニューキャプションを取得
    private func menuItem(caption: String) -> (title: String, shortcut: Character?, visible: Bool)? {
        guard let itemInfo = menuItem(for: "\(caption).caption") else { return nil }
        
        let visibleKey = "\(caption).visible"
        let visible = boolValue(for: visibleKey) ?? true
        
        return (itemInfo.title, itemInfo.shortcut, visible)
    }

    private func actionSafeIdentifier(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func shellNames(in root: URL) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries.filter { $0.hasDirectoryPath }.map(\.lastPathComponent)
    }
}
