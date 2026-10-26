import AppKit
import Foundation

/// 花柚（hanayu。りゅう氏作）。ゴーストの過去一週間の起動時間をグラフで表示する。汎用のグラフ表示にも使える。
///
/// - show [スタイル名 [ラベル1, 値1, ラベル2, 値2, ...]]: グラフの窓を開く（ドラッグで移動、ダブルクリックで閉じる）
/// - hide [スタイル名]: 窓を閉じる（開いていなければ 400）
/// 設定は DLL と同じ場所の hanayu.txt（`[スタイル名]` か `スタイル名 { }` で区切る。区切りの前はスタイル名の無い既定）。
/// graph が usetime（既定）なら起動時間、line / bar / radar / radar2 なら引数の値を描く。
/// 起動時間は、このモジュールを読み込んでいた時間（SHIORI と同じ寿命）を hanayud.txt に日ごとに分で記録する。
final class CompatHanayuModule: CompatSaoriModule {
    private let environment: CompatSaoriEnvironment
    private let baseDirectory: URL?
    private let usage: CompatHanayuUsage?
    private var openKeys: Set<String> = []
    private let lock = NSLock()
    /// 窓を見分ける名前の頭（モジュールのインスタンスごと）。
    private let keyPrefix = "hanayu-\(UUID().uuidString)/"

    init(environment: CompatSaoriEnvironment) {
        self.environment = environment
        baseDirectory = environment.moduleDirectory ?? environment.ghostRoot
        usage = environment.hasGhost ? CompatHanayuUsage(file: baseDirectory?.appendingPathComponent("hanayud.txt")) : nil
    }

    func execute(_ arguments: [String], charset: String) -> CompatSaoriResult {
        guard let command = arguments.first?.lowercased(), ["show", "hide"].contains(command) else { return .badRequest }
        let style = arguments.count >= 2 ? arguments[1] : ""
        let key = keyPrefix + style
        if command == "hide" {
            lock.lock(); let wasOpen = openKeys.remove(key) != nil; lock.unlock()
            return CompatSaoriHooks.dismissGraph(key) || wasOpen ? .noContent : .badRequest
        }
        guard environment.hasGhost else { return .ghostRequired }
        let config = CompatHanayuConfig.load(from: baseDirectory?.appendingPathComponent("hanayu.txt"))
        guard let parameters = config.styles[style] ?? (style.isEmpty ? [:] : nil) else { return .badRequest }
        guard let graph = makeGraph(parameters: parameters, arguments: Array(arguments.dropFirst(2))) else { return .badRequest }
        lock.lock(); openKeys.insert(key); lock.unlock()
        CompatSaoriHooks.presentGraph(graph, key)
        return .noContent
    }

    /// 描くもの。usetime なら直近 7 日の起動時間（時間）、それ以外は引数のラベルと値の組。
    func makeGraph(parameters: [String: String], arguments: [String], now: Date = Date()) -> CompatHanayuGraph? {
        let kind = CompatHanayuGraph.Kind(rawValue: parameters["graph"]?.lowercased() ?? "") ?? .usetime
        var graph = CompatHanayuGraph(kind: kind, parameters: parameters, baseDirectory: baseDirectory)
        if kind == .usetime {
            guard let usage else { return nil }
            usage.update(now: now)
            usage.save()
            let days = usage.lastSevenDays(now: now)
            graph.labels = days.map(\.label)
            graph.values = days.map(\.hours)
            graph.fixedRange = 0...24
        } else {
            for index in stride(from: 0, to: arguments.count - 1, by: 2) {
                graph.labels.append(arguments[index])
                graph.values.append(Double(arguments[index + 1].trimmingCharacters(in: .whitespaces)) ?? Double(CompatSaoriHost.leadingInteger(arguments[index + 1])))
            }
        }
        return graph
    }

    func unload() {
        lock.lock()
        let keys = openKeys
        openKeys.removeAll()
        lock.unlock()
        for key in keys { _ = CompatSaoriHooks.dismissGraph(key) }
        usage?.update(now: Date())
        usage?.save()
    }
}

// MARK: - 設定（hanayu.txt）

struct CompatHanayuConfig {
    /// スタイル名 → パラメータ（名前 → 値）。スタイル名の無い既定は "" に入る。
    var styles: [String: [String: String]] = [:]

    static func load(from url: URL?) -> CompatHanayuConfig {
        guard let url, let data = try? Data(contentsOf: url) else { return CompatHanayuConfig() }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) ?? ""
        return parse(text)
    }

    /// bln.txt 形式（`[スタイル名]`）と surfaces.txt 形式（`スタイル名` の次の行から `{` 〜 `}`）の両方を読む。
    static func parse(_ text: String) -> CompatHanayuConfig {
        var config = CompatHanayuConfig()
        var current = ""
        var pendingName: String?
        config.styles[""] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") { continue }
            if line.hasPrefix("[") {
                let end = line.firstIndex(of: "]") ?? line.endIndex
                current = String(line[line.index(after: line.startIndex)..<end]).trimmingCharacters(in: .whitespaces)
                config.styles[current, default: [:]] = config.styles[current] ?? [:]
                pendingName = nil
            } else if line == "{" {
                current = pendingName ?? ""
                config.styles[current, default: [:]] = config.styles[current] ?? [:]
                pendingName = nil
            } else if line == "}" {
                current = ""
            } else if let comma = line.firstIndex(of: ",") {
                let key = line[..<comma].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: comma)...].trimmingCharacters(in: .whitespaces)
                config.styles[current, default: [:]][key] = value
                pendingName = nil
            } else {
                pendingName = line
            }
        }
        return config
    }
}

// MARK: - 起動時間（hanayud.txt）

/// 日ごとの起動時間。原作と同じく、分の整数で数え、hanayud.txt に 6 日前から今日までの 7 行
/// （`yyyyMMdd,分`。改行は CR LF）で保存する。1 分に満たない秒は次に持ち越す。
final class CompatHanayuUsage {
    private let file: URL?
    private(set) var minutes: [String: Int] = [:]
    private var lastUpdate: Date
    private var carriedSeconds: TimeInterval = 0
    private let lock = NSLock()
    private let calendar = Calendar(identifier: .gregorian)

    init(file: URL?, now: Date = Date()) {
        self.file = file
        lastUpdate = now
        guard let file, let data = try? Data(contentsOf: file) else { return }
        let text = String(decoding: data, as: UTF8.self)
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0].count == 8, let value = Int(parts[1]) { minutes[parts[0]] = value }
        }
    }

    func key(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 前回からの経過時間を、日付の境目で分けて足す（分の単位。端数は持ち越す）。
    func update(now: Date) {
        lock.lock(); defer { lock.unlock() }
        var cursor = lastUpdate
        while cursor < now {
            let nextDay = calendar.startOfDay(for: cursor).addingTimeInterval(86_400)
            let end = min(nextDay, now)
            carriedSeconds += end.timeIntervalSince(cursor)
            let whole = Int(carriedSeconds / 60)
            if whole > 0 {
                minutes[key(cursor), default: 0] += whole
                carriedSeconds -= Double(whole * 60)
            }
            cursor = end
        }
        lastUpdate = now
    }

    /// 6 日前から今日まで（ラベルは `月/日`、値は時間）。
    func lastSevenDays(now: Date) -> [(label: String, hours: Double)] {
        lock.lock(); defer { lock.unlock() }
        return (-6...0).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: now)!
            let parts = calendar.dateComponents([.month, .day], from: day)
            return ("\(parts.month ?? 0)/\(parts.day ?? 0)", Double(minutes[key(day)] ?? 0) / 60)
        }
    }

    func save(now: Date = Date()) {
        guard let file else { return }
        lock.lock()
        let lines = (-6...0).map { offset -> String in
            let day = key(calendar.date(byAdding: .day, value: offset, to: now)!)
            return "\(day),\(minutes[day] ?? 0)\r\n"
        }
        lock.unlock()
        try? Data(lines.joined().utf8).write(to: file, options: .atomic)
    }
}

// MARK: - グラフ

struct CompatHanayuGraph {
    enum Kind: String {
        case usetime, line, bar, radar, radar2
    }

    var kind: Kind
    var parameters: [String: String]
    var baseDirectory: URL?
    var labels: [String] = []
    var values: [Double] = []
    var fixedRange: ClosedRange<Double>?

    var size: NSSize { kind == .radar || kind == .radar2 ? NSSize(width: 288, height: 288) : NSSize(width: 450, height: 340) }

    var title: String? { parameters["title"].flatMap { $0.isEmpty ? nil : $0 } }

    /// 値の範囲。usetime は 0〜24、それ以外は値の最小〜最大（棒とレーダーは 0 から）。
    var range: ClosedRange<Double> {
        if let fixedRange { return fixedRange }
        var lower = values.min() ?? 0
        var upper = values.max() ?? 1
        if kind != .line { lower = min(0, lower) }
        if upper <= lower { upper = lower + 1 }
        return lower...upper
    }

    /// `名前.color`（RRGGBB）か `名前.color.r / .g / .b`（0〜255）。無ければ背景は白、ほかは黒（棒は nil = 塗らない）。
    func color(_ name: String) -> NSColor? {
        func component(_ suffix: String) -> CGFloat? {
            parameters["\(name).color.\(suffix)"].flatMap { Double($0) }.map { CGFloat(max(0, min(255, $0))) / 255 }
        }
        if let hex = parameters["\(name).color"]?.trimmingCharacters(in: .whitespaces), hex.count >= 6, let value = UInt32(hex.prefix(6), radix: 16) {
            return NSColor(srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
        let r = component("r"), g = component("g"), b = component("b")
        if r != nil || g != nil || b != nil { return NSColor(srgbRed: r ?? 0, green: g ?? 0, blue: b ?? 0, alpha: 1) }
        switch name {
        case "background": return .white
        case "bar": return nil
        default: return .black
        }
    }

    func width(_ name: String, default value: CGFloat) -> CGFloat {
        parameters["\(name).width"].flatMap { Double($0) }.map { CGFloat($0) } ?? value
    }

    func image(_ name: String) -> NSImage? {
        guard let file = parameters["\(name).filename"], !file.isEmpty, let base = baseDirectory else { return nil }
        return NSImage(contentsOf: base.appendingPathComponent(file.replacingOccurrences(of: "\\", with: "/")))
    }
}

// MARK: - 窓

/// グラフの窓（主スレッドで扱う）。
final class CompatHanayuWindows {
    static let shared = CompatHanayuWindows()
    private var windows: [String: NSWindow] = [:]
    private var known: Set<String> = []
    private let lock = NSLock()

    func show(_ graph: CompatHanayuGraph, key: String) {
        lock.lock(); known.insert(key); lock.unlock()
        DispatchQueue.main.async {
            let view = CompatHanayuGraphView(graph: graph) { [weak self] in _ = self?.close(key: key) }
            if let window = self.windows[key] {
                // 同じスタイルを続けて show したら、窓はそのままで中身を描き直す。
                window.setContentSize(graph.size)
                window.contentView = view
                window.orderFront(nil)
                return
            }
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: graph.size), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.hasShadow = true
            window.contentView = view
            if let screen = NSScreen.main?.visibleFrame {
                window.setFrameTopLeftPoint(NSPoint(x: screen.midX, y: screen.maxY - screen.height / 4))
            }
            window.orderFront(nil)
            self.windows[key] = window
        }
    }

    /// 閉じる。開いていた（開く途中を含む）なら true。
    func close(key: String) -> Bool {
        lock.lock(); let wasKnown = known.remove(key) != nil; lock.unlock()
        DispatchQueue.main.async {
            self.windows.removeValue(forKey: key)?.close()
        }
        return wasKnown
    }
}

/// グラフを描く。原作の配置（450×340 の折れ線・棒、288×288 のレーダー）に合わせる。
final class CompatHanayuGraphView: NSView {
    private let graph: CompatHanayuGraph
    private let onClose: () -> Void

    init(graph: CompatHanayuGraph, onClose: @escaping () -> Void = {}) {
        self.graph = graph
        self.onClose = onClose
        super.init(frame: NSRect(origin: .zero, size: graph.size))
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onClose()
        } else {
            window?.performDrag(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        (graph.color("background") ?? .white).setFill()
        bounds.fill()
        if let background = graph.image("background") {
            let origin = NSPoint(x: (bounds.width - background.size.width) / 2, y: (bounds.height - background.size.height) / 2)
            background.draw(in: NSRect(origin: origin, size: background.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        switch graph.kind {
        case .usetime, .line: drawLine()
        case .bar: drawBar()
        case .radar, .radar2: drawRadar()
        }
        drawTitle()
    }

    private var fontAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: graph.color("font") ?? .black]
    }

    private func drawText(_ text: String, centeredAt point: NSPoint) {
        let string = NSAttributedString(string: text, attributes: fontAttributes)
        let size = string.size()
        string.draw(at: NSPoint(x: point.x - size.width / 2, y: point.y))
    }

    /// タイトルは右端に縦書き。
    private func drawTitle() {
        guard let title = graph.title, let context = NSGraphicsContext.current?.cgContext else { return }
        let string = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: graph.color("font") ?? .black])
        context.saveGState()
        context.translateBy(x: bounds.width - 22, y: 40)
        context.rotate(by: .pi / 2)
        string.draw(at: .zero)
        context.restoreGState()
    }

    private func drawFrame() {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 60, y: 48))
        path.line(to: NSPoint(x: 60, y: 260))
        path.line(to: NSPoint(x: 420, y: 260))
        path.lineWidth = graph.width("frame", default: 2)
        (graph.color("frame") ?? .black).setStroke()
        path.stroke()
    }

    private func columns() -> (step: CGFloat, x: (Int) -> CGFloat) {
        let count = max(1, graph.values.count)
        let step = 360 / CGFloat(count)
        return (step, { 60 + CGFloat($0) * step + step / 2 })
    }

    private func drawLabels() {
        let layout = columns()
        for (index, label) in graph.labels.enumerated() { drawText(label, centeredAt: NSPoint(x: layout.x(index), y: 266)) }
    }

    private func drawLine() {
        drawFrame()
        drawLabels()
        let layout = columns()
        let range = graph.range
        let y = { (value: Double) -> CGFloat in 220 - CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * 168 }
        let points = graph.values.enumerated().map { NSPoint(x: layout.x($0.offset), y: y($0.element)) }
        if points.count >= 2 {
            let path = NSBezierPath()
            path.move(to: points[0])
            for point in points.dropFirst() { path.line(to: point) }
            path.lineWidth = graph.width("line", default: 2)
            path.lineJoinStyle = .round
            (graph.color("line") ?? .black).setStroke()
            path.stroke()
        }
        let low = graph.values.min(), high = graph.values.max()
        for (index, point) in points.enumerated() {
            let value = graph.values[index]
            let mark = value == low ? graph.image("mark0") : value == high ? graph.image("mark2") : graph.image("mark1")
            if let mark = mark ?? graph.image("mark1") {
                mark.draw(in: NSRect(x: point.x - mark.size.width / 2, y: point.y - mark.size.height / 2, width: mark.size.width, height: mark.size.height),
                          from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            } else {
                (graph.color("line") ?? .black).setFill()
                NSBezierPath(ovalIn: NSRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)).fill()
            }
        }
    }

    private func drawBar() {
        drawFrame()
        drawLabels()
        let layout = columns()
        let range = graph.range
        let barWidth = graph.width("bar", default: 16)
        for (index, value) in graph.values.enumerated() {
            let top = 260 - CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * 208
            let rect = NSRect(x: layout.x(index) - barWidth / 2, y: top, width: barWidth, height: 260 - top)
            if let fill = graph.color("bar") {
                fill.setFill()
                rect.fill()
            }
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = graph.width("line", default: 2) / 2
            (graph.color("line") ?? .black).setStroke()
            outline.stroke()
        }
    }

    /// radar2 は目盛りの多角形つきの普通のレーダーチャート、radar は目盛りを省いて内側を塗る（AI グラフ風味）。
    private func drawRadar() {
        let count = graph.values.count
        guard count > 0 else { return }
        let center = NSPoint(x: 144, y: 150)
        let radius: CGFloat = 96
        let upper = max(graph.range.upperBound, 0.000_001)
        let point = { (index: Int, scale: CGFloat) -> NSPoint in
            let angle = -CGFloat.pi / 2 + 2 * .pi * CGFloat(index) / CGFloat(count)
            return NSPoint(x: center.x + cos(angle) * radius * scale, y: center.y + sin(angle) * radius * scale)
        }
        let frameColor = graph.color("frame") ?? .black
        frameColor.setStroke()
        let rings: [CGFloat] = graph.kind == .radar2 ? [0.25, 0.5, 0.75, 1] : [1]
        for ring in rings {
            let path = NSBezierPath()
            for index in 0..<count {
                index == 0 ? path.move(to: point(index, ring)) : path.line(to: point(index, ring))
            }
            path.close()
            path.lineWidth = graph.width("frame", default: 2) / (ring < 1 ? 2 : 1)
            path.stroke()
        }
        for index in 0..<count {
            let spoke = NSBezierPath()
            spoke.move(to: center)
            spoke.line(to: point(index, 1))
            spoke.lineWidth = graph.width("frame", default: 2) / 2
            spoke.stroke()
            let label = point(index, 1.18)
            drawText(graph.labels.indices.contains(index) ? graph.labels[index] : "", centeredAt: NSPoint(x: label.x, y: label.y - 7))
        }
        let data = NSBezierPath()
        for (index, value) in graph.values.enumerated() {
            let scaled = point(index, CGFloat(max(0, value) / upper))
            index == 0 ? data.move(to: scaled) : data.line(to: scaled)
        }
        data.close()
        let lineColor = graph.color("line") ?? .black
        if graph.kind == .radar {
            lineColor.withAlphaComponent(0.35).setFill()
            data.fill()
        }
        data.lineWidth = graph.width("line", default: 2)
        lineColor.setStroke()
        data.stroke()
    }
}
