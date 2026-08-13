import SwiftUI
import AppKit
import CoreImage
import Combine
import UserNotifications
import AVFoundation

// MARK: - ViewModels

/// ViewModel for the character view.
class CharacterViewModel: ObservableObject {
    @Published var image: NSImage?
    @Published var currentSurfaceID: Int = 0

    // Visual effects state (persists until ghost terminates)
    @Published var scaleX: Double = 1.0
    @Published var scaleY: Double = 1.0
    @Published var alpha: Double = 1.0  // 0.0 to 1.0

    /// SakuraScript の scaling はユーザー倍率とは別に SERIKO 倍率を持つ。
    /// GhostManager が積算結果を scaleX/scaleY へ反映する。
    var userScaleX: Double = 1.0
    var userScaleY: Double = 1.0

    // Position and alignment state
    @Published var position: CGPoint?  // nil = free movement, set = locked position
    @Published var alignment: DesktopAlignment = .free

    // Rendering control
    @Published var repaintLocked: Bool = false
    @Published var manualRepaintLock: Bool = false
    
    // Balloon state
    @Published var currentBalloonID: Int = 0  // Current balloon style ID
    
    // Surface compositing - overlay surfaces
    @Published var overlays: [SurfaceOverlay] = []
    
    // Effects and filters
    @Published var activeEffects: [EffectConfig] = []
    @Published var activeFilters: [FilterConfig] = []
    
    // Dressup bindings
    var dressupBindings: [String: [String: String]] = [:] // category -> part -> value

    // Dressup parts
    @Published var dressupParts: [DressupPart] = []

    // Text animations
    @Published var textAnimations: [TextAnimationConfig] = []

    // Window stacking
    var zOrderGroup: [Int]? = nil  // nil = default, or array of scope IDs in front-to-back order
    var stickyGroup: [Int]? = nil  // nil = independent, or array of scope IDs that move together

    /// Desktop alignment options
    enum DesktopAlignment {
        case free
        case top
        case bottom
        case left
        case right
    }
}

/// ViewModel for the balloon view.
class BalloonViewModel: ObservableObject {
    static let defaultBalloonTimeout: TimeInterval = 60
    /// \_b[filepath,inline] を本文中で1文字として保持する不可視プレースホルダー。
    static let inlineImagePlaceholder = "\u{FFFC}"

    @Published var text: String = ""
    @Published var balloonID: Int = 0  // Current balloon style ID (0, 2, 4, etc.)

    /// バルーンの実効表示倍率。`balloon.syncscale,true` の場合はシェル倍率と同期する。
    /// 符号は反転表示を保持し、描画領域の計算では絶対値を使用する。
    @Published var scaleX: Double = 1.0
    @Published var scaleY: Double = 1.0

    // Cursor position for \_l[x,y] command
    @Published var cursorX: CGFloat = 0
    @Published var cursorY: CGFloat = 0

    // Balloon offset for \![set,balloonoffset,...] command
    @Published var balloonOffsetX: CGFloat = 0
    @Published var balloonOffsetY: CGFloat = 0
    @Published var useCustomOffset: Bool = false

    // Balloon alignment for \![set,balloonalign,...] command
    @Published var balloonAlignment: BalloonAlignment = .none

    // Font settings for \f[...] commands
    @Published var fontName: String = ""
    @Published var fontSize: CGFloat = 12
    @Published var fontWeight: Font.Weight = .regular
    @Published var fontItalic: Bool = false
    @Published var fontUnderline: Bool = false
    @Published var fontStrike: Bool = false
    @Published var fontSubscript: Bool = false
    @Published var fontSuperscript: Bool = false
    @Published var fontColor: NSColor = .textColor
    @Published var anchorFontColor: NSColor = .linkColor
    @Published var anchorNotSelectFontColor: NSColor = .linkColor
    @Published var anchorVisitedFontColor: NSColor = .linkColor
    @Published var anchorActive: Bool = false

    // アンカー装飾（UKADOC \f[anchorstyle / anchorbrushcolor / anchorpencolor] 系）。
    // 選択中（ホバー）・非選択・訪問済みの3状態を個別に持つ。
    @Published var anchorStyle: AnchorDecorationStyle = .underline
    @Published var anchorBrushColor: NSColor = .clear
    @Published var anchorPenColor: NSColor = .linkColor
    @Published var anchorMethod: AnchorRasterOperation = .none
    @Published var anchornotselectStyle: AnchorDecorationStyle = .underline
    @Published var anchornotselectBrushColor: NSColor = .clear
    @Published var anchornotselectPenColor: NSColor = .linkColor
    @Published var anchornotselectMethod: AnchorRasterOperation = .none
    @Published var anchorvisitedStyle: AnchorDecorationStyle = .underline
    @Published var anchorvisitedBrushColor: NSColor = .clear
    @Published var anchorvisitedPenColor: NSColor = .linkColor
    @Published var anchorvisitedMethod: AnchorRasterOperation = .none
    // 選択肢マーカー（\f[cursor*]）の装飾。選択ダイアログの実ボタンへ反映する。
    @Published var cursorStyle: AnchorDecorationStyle = .square
    @Published var cursorBrushColor: NSColor = .clear
    @Published var cursorPenColor: NSColor = .linkColor
    @Published var cursorFontColor: NSColor = .textColor
    @Published var cursorMethod: AnchorRasterOperation = .none
    @Published var cursorNotSelectStyle: AnchorDecorationStyle = .none
    @Published var cursorNotSelectBrushColor: NSColor = .clear
    @Published var cursorNotSelectPenColor: NSColor = .linkColor
    @Published var cursorNotSelectFontColor: NSColor = .textColor
    @Published var cursorNotSelectMethod: AnchorRasterOperation = .none
    /// `default` に戻すためのバルーン設定値。現在値とは分離して保持する。
    var defaultAnchorMethod: AnchorRasterOperation = .none
    var defaultAnchornotselectMethod: AnchorRasterOperation = .none
    var defaultAnchorvisitedMethod: AnchorRasterOperation = .none
    /// ホバー中（選択中）のアンカーの `anchors` index。nil = 選択中なし。
    @Published var activeAnchorIndex: Int?
    @Published var shadowColor: NSColor = .clear
    @Published var shadowStyle: BalloonShadowStyle = .none
    @Published var outlineWidth: CGFloat = 0
    @Published var textAlign: BalloonTextAlign = .left
    @Published var textVAlign: BalloonTextVAlign = .top

    // Balloon control settings
    @Published var autoscrollEnabled: Bool = true
    /// `\_n` が有効な間は自動折り返しを行わない。
    @Published var wordWrapEnabled: Bool = true
    @Published var balloonTimeout: TimeInterval = BalloonViewModel.defaultBalloonTimeout
    @Published var balloonWaitEnabled: Bool = true
    @Published var balloonWaitMultiplier: Double = 1.0
    @Published var balloonMarkerText: String = ""
    /// `\\![set,balloonnum,file,current,max]` の受信進捗表示。
    /// 引数を空にした場合は全項目を消去する。
    @Published var balloonNumberFileName: String = ""
    @Published var balloonNumberCurrent: String = ""
    @Published var balloonNumberMaximum: String = ""
    @Published var balloonNumberVisible: Bool = false
    @Published var repaintLocked: Bool = false
    @Published var manualRepaintLock: Bool = false
    @Published var balloonMoveLocked: Bool = false
    /// `\![enter,onlinemode]` / `\![leave,onlinemode]` の強制表示状態。
    @Published var onlineModeActive: Bool = false
    /// オンラインマーカー画像の現在フレーム番号。
    @Published var onlineMarkerIndex: Int = 0

    enum BalloonAlignment {
        case none
        case left
        case center
        case right
        case top
        case bottom
    }

    enum BalloonShadowStyle {
        case none
        case offset
        case outline
    }

    enum BalloonTextAlign {
        case left
        case center
        case right
    }

    enum BalloonTextVAlign {
        case top
        case center
        case bottom
    }

    // Balloon images
    struct BalloonImage: Identifiable {
        let id = UUID()
        let filepath: String
        let x: CGFloat
        let y: CGFloat
        let isInline: Bool
        let isOpaque: Bool
        let useSelfAlpha: Bool
        let clipping: CGRect?
        let isForeground: Bool
        let isFixed: Bool
        /// 本文内のUTF-16位置。位置指定 \_b では nil。
        var inlineTextOffset: Int?
        let image: NSImage?
    }
    @Published var balloonImages: [BalloonImage] = []

    /// 現在の本文末尾へ inline 画像の1文字分を予約し、挿入前のUTF-16位置を返す。
    @discardableResult
    func appendInlineImagePlaceholder() -> Int {
        let offset = (text as NSString).length
        text.append(Self.inlineImagePlaceholder)
        return offset
    }

    /// `\n` 可変改行の垂直送り（通常行高に対する倍率）。
    /// `lineAdvances[i]` は i 番目の `\n` 文字に付随する送り。`\n`=1.0, `\n[half]`=0.5, `\n[150]`=1.5, `\n[-250]`=-2.5。
    @Published var lineAdvances: [CGFloat] = []

    /// `\_a[ID,...]...\_a` の範囲アンカー。表示テキスト・文字範囲・クリック時のアクションを保持する。
    @Published var anchors: [BalloonAnchorRange] = []

    /// 新規スクリプト開始時などにバルーン本文を初期化する（改行送り・アンカー範囲も同時にリセット）。
    func resetBalloonContent() {
        text = ""
        // \c / 新規スクリプト開始では、本文に貼り付けた画像も同時に消去する。
        // UKADOC の \c は文字だけでなく \_b で貼り付けた画像も消去対象とする。
        balloonImages.removeAll()
        lineAdvances.removeAll()
        anchors.removeAll()
        anchorActive = false
        activeAnchorIndex = nil
    }

    /// 指定 index のアンカーを訪問済みとして記録する（`\_a` クリック時の `anchorvisited*` 描画用）。
    func markAnchorVisited(at index: Int) {
        guard anchors.indices.contains(index) else { return }
        anchors[index].visited = true
    }

    /// 指定範囲（id + 文字範囲）のアンカーを訪問済みとして記録する。
    func markAnchorVisited(id: String, range: NSRange) {
        guard let index = anchors.firstIndex(where: { $0.id == id && $0.range == range }) else { return }
        anchors[index].visited = true
    }

    /// アンカー1状態の装飾定義を組み立てる（選択中 / 訪問済み / 非選択の優先順）。index が無効なら非選択装飾。
    func decoration(forAnchorAt index: Int?) -> AnchorDecoration {
        guard let index = index else {
            return AnchorDecoration(style: anchornotselectStyle, fontColor: anchorNotSelectFontColor, brushColor: anchornotselectBrushColor, penColor: anchornotselectPenColor, rasterOperation: anchornotselectMethod)
        }
        if activeAnchorIndex == index {
            return AnchorDecoration(style: anchorStyle, fontColor: anchorFontColor, brushColor: anchorBrushColor, penColor: anchorPenColor, rasterOperation: anchorMethod)
        }
        guard anchors.indices.contains(index) else {
            return AnchorDecoration(style: anchornotselectStyle, fontColor: anchorNotSelectFontColor, brushColor: anchornotselectBrushColor, penColor: anchornotselectPenColor, rasterOperation: anchornotselectMethod)
        }
        if anchors[index].visited {
            return AnchorDecoration(style: anchorvisitedStyle, fontColor: anchorVisitedFontColor, brushColor: anchorvisitedBrushColor, penColor: anchorvisitedPenColor, rasterOperation: anchorvisitedMethod)
        }
        return AnchorDecoration(style: anchornotselectStyle, fontColor: anchorNotSelectFontColor, brushColor: anchornotselectBrushColor, penColor: anchornotselectPenColor, rasterOperation: anchornotselectMethod)
    }

    /// バルーン設定（descript.txt）由来のアンカー装飾を既定として反映する。
    func applyBalloonConfigAnchorDefaults(config: BalloonConfig?) {
        guard let config else { return }
        anchorFontColor = config.anchorFontColor
        anchorPenColor = config.anchorPenColor
        anchorStyle = config.anchorStyle
        anchorBrushColor = config.anchorBrushColor
        defaultAnchorMethod = config.anchorBlendMethod
        anchorMethod = defaultAnchorMethod
        anchornotselectStyle = config.anchorNotSelectStyle
        anchorNotSelectFontColor = config.anchorNotSelectFontColor
        anchornotselectPenColor = config.anchorNotSelectPenColor
        anchornotselectBrushColor = config.anchorNotSelectBrushColor
        defaultAnchornotselectMethod = config.anchorNotSelectBlendMethod
        anchornotselectMethod = defaultAnchornotselectMethod
        anchorvisitedStyle = config.anchorVisitedStyle
        anchorVisitedFontColor = config.anchorVisitedFontColor
        anchorvisitedPenColor = config.anchorVisitedPenColor
        anchorvisitedBrushColor = config.anchorVisitedBrushColor
        defaultAnchorvisitedMethod = config.anchorVisitedBlendMethod
        anchorvisitedMethod = defaultAnchorvisitedMethod
        cursorStyle = AnchorDecorationStyle(shape: config.cursorStyle) ?? .square
        cursorBrushColor = config.cursorBrushColor
        cursorPenColor = config.cursorPenColor
        cursorFontColor = config.cursorFontColor
        cursorMethod = AnchorRasterOperation(name: config.cursorBlendMethod) ?? .none
    }

    /// `\n[half]` / `\n[パーセント]` / 通常 `\n` の改行を1つ追加し、垂直送り倍率を記録する。
    func appendNewline(advance: CGFloat) {
        text += "\n"
        lineAdvances.append(advance)
    }

    /// `\n` 系タグの指定文字列（"half" / "150" / "-250" / "150%" 等）から送り倍率を求める。
    /// UKADOC: `\n[half]` は通常の半分、`\n[パーセント]` は行高に対するパーセント（負値は戻る）。
    static func newlineAdvance(for type: String) -> CGFloat {
        let trimmed = type.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "half" { return 0.5 }
        let percent = trimmed.hasSuffix("%") ? String(trimmed.dropLast()) : trimmed
        if let value = Double(percent) {
            return CGFloat(value / 100.0)
        }
        return 1.0
    }

    /// 末尾の指定文字数だけ削除し、改行送り・アンカー範囲を整合させる（`\c[char,N]` 相当）。
    func truncateSuffixCharacters(_ count: Int) {
        guard count > 0, !text.isEmpty else { return }
        let start = text.index(text.endIndex, offsetBy: -min(count, text.count))
        removeText(in: NSRange(start..<text.endIndex, in: text))
    }

    /// 末尾の指定行数だけ削除し、改行送り・アンカー範囲を整合させる（`\c[line,N]` 相当）。
    func truncateSuffixLines(_ count: Int) {
        clearLines(count, start: nil)
    }

    /// 指定位置から文字を削除する。`start == nil` は現在カーソル（本文末尾）からの削除。
    /// start は仕様どおり0オリジンの表示文字位置で、inline画像のプレースホルダーも1文字として扱う。
    func clearCharacters(_ count: Int, start: Int?) {
        guard count > 0, !text.isEmpty else { return }
        guard let start else {
            truncateSuffixCharacters(count)
            return
        }
        guard start >= 0, start < text.count else { return }
        let lower = text.index(text.startIndex, offsetBy: start)
        let upper = text.index(lower, offsetBy: min(count, text.distance(from: lower, to: text.endIndex)))
        removeText(in: NSRange(lower..<upper, in: text))
    }

    /// 指定行から行を削除する。空行は仕様上の行数に含めず、残った行の区切りを保つ。
    func clearLines(_ count: Int, start: Int?) {
        guard count > 0, !text.isEmpty else { return }
        let nsText = text as NSString
        let length = nsText.length
        var lineRanges: [NSRange] = []
        var cursor = 0
        while cursor < length {
            let newline = nsText.range(of: "\n", options: [], range: NSRange(location: cursor, length: length - cursor))
            let end = newline.location == NSNotFound ? length : newline.location
            if end > cursor {
                lineRanges.append(NSRange(location: cursor, length: end - cursor))
            }
            guard newline.location != NSNotFound else { break }
            cursor = newline.location + 1
        }
        guard !lineRanges.isEmpty else { return }

        let firstLine = start.map { max(0, $0) } ?? max(0, lineRanges.count - count)
        guard firstLine < lineRanges.count else { return }
        let lastLine = min(lineRanges.count - 1, firstLine + count - 1)
        let firstRange = lineRanges[firstLine]
        let lastRange = lineRanges[lastLine]
        var deleteStart = firstRange.location
        var deleteEnd = NSMaxRange(lastRange)

        if deleteEnd < length, nsText.character(at: deleteEnd) == 0x0A {
            // 中間の行を消す場合は後続区切りを消し、前後の行を連結する。
            deleteEnd += 1
        } else if deleteStart > 0, nsText.character(at: deleteStart - 1) == 0x0A {
            // 末尾の行を消す場合は直前の区切りを消す。
            deleteStart -= 1
        }
        removeText(in: NSRange(location: deleteStart, length: deleteEnd - deleteStart))
    }

    /// 行 index（0始まり）の直前に適用する垂直送り倍率。先頭行は 1.0。
    func leadingAdvance(forLineIndex index: Int) -> CGFloat {
        guard index > 0 else { return 1.0 }
        let advanceIndex = index - 1
        guard advanceIndex < lineAdvances.count else { return 1.0 }
        return lineAdvances[advanceIndex]
    }

    /// 行 index のテキストを、アンカー範囲 / 非アンカーに分割したセグメントを返す。
    /// アンカーセグメントには所属する `anchors` の index（重複時は最後に追加された方）を添える。
    func anchorSegments(lineIndex: Int) -> [BalloonTextSegment] {
        let lines = text.components(separatedBy: "\n")
        guard lineIndex >= 0, lineIndex < lines.count else { return [] }
        guard !anchors.isEmpty else { return [BalloonTextSegment(text: lines[lineIndex], isAnchor: false, anchorIndex: nil)] }

        let nsLines = lines.map { ($0 as NSString).length }
        var start = 0
        for i in 0..<lineIndex { start += nsLines[i] + 1 }
        let lineLength = nsLines[lineIndex]
        guard lineLength > 0 else { return [] }

        // この行と交差するアンカー範囲（重複時は後のアンカーを優先）をマージした区間境界を構築する。
        var boundaries: [(offset: Int, isAnchorStart: Bool, anchorIndex: Int)] = []
        for (index, anchor) in anchors.enumerated() {
            let aStart = max(anchor.range.location, start)
            let aEnd = min(anchor.range.location + anchor.range.length, start + lineLength)
            guard aEnd > aStart else { continue }
            boundaries.append((aStart - start, true, index))
            boundaries.append((aEnd - start, false, index))
        }
        boundaries.sort { $0.offset < $1.offset }
        guard !boundaries.isEmpty else { return [BalloonTextSegment(text: lines[lineIndex], isAnchor: false, anchorIndex: nil)] }

        // 区間ごとに属するアンカーを決定（深度管理で入れ子対応、同深度競合は後勝ち）。
        var spans: [(start: Int, end: Int, anchorIndex: Int)] = []
        var candidates: [Int] = []
        var cursor = 0
        var idx = 0
        while idx < boundaries.count {
            let offset = boundaries[idx].offset
            if offset > cursor {
                let active = candidates.last ?? -1
                spans.append((cursor, offset, active))
            }
            while idx < boundaries.count && boundaries[idx].offset == offset {
                let boundary = boundaries[idx]
                if boundary.isAnchorStart {
                    candidates.append(boundary.anchorIndex)
                } else if let found = candidates.lastIndex(of: boundary.anchorIndex) {
                    candidates.remove(at: found)
                }
                idx += 1
            }
            cursor = offset
        }
        if cursor < lineLength {
            let active = candidates.last ?? -1
            spans.append((cursor, lineLength, active))
        }

        var segments: [BalloonTextSegment] = []
        for span in spans where span.end > span.start {
            let nsText = (lines[lineIndex] as NSString).substring(with: NSRange(location: span.start, length: span.end - span.start))
            if span.anchorIndex >= 0 {
                segments.append(BalloonTextSegment(text: nsText, isAnchor: true, anchorIndex: span.anchorIndex))
            } else {
                segments.append(BalloonTextSegment(text: nsText, isAnchor: false, anchorIndex: nil))
            }
        }
        return segments.filter { !$0.text.isEmpty }
    }

    /// `\_a` 開始位置（UTF-16）以降のアンカー文字範囲。
    func anchorRange(from textStart: Int) -> NSRange {
        let length = max(0, (text as NSString).length - textStart)
        return NSRange(location: textStart, length: length)
    }

    /// `\_a` 開始位置以降のアンカー表示テキスト。
    func anchorText(in textStart: Int) -> String {
        (text as NSString).substring(from: min(max(0, textStart), (text as NSString).length))
    }

    /// テキスト短縮後に範囲外へ出たアンカーを切り詰め/除去する。
    private func removeText(in range: NSRange) {
        let oldText = text
        let oldLength = (oldText as NSString).length
        guard let safeRange = range.intersection(NSRange(location: 0, length: oldLength)),
              safeRange.length > 0 else { return }

        let deletionEnd = NSMaxRange(safeRange)
        let oldNewlineCount = (oldText as NSString).components(separatedBy: "\n").count - 1
        let oldAdvances = lineAdvances
        let oldNewlineOffsets: [Int] = {
            var offsets: [Int] = []
            var search = 0
            let nsText = oldText as NSString
            while search < oldLength {
                let found = nsText.range(of: "\n", options: [], range: NSRange(location: search, length: oldLength - search))
                guard found.location != NSNotFound else { break }
                offsets.append(found.location)
                search = found.location + 1
            }
            return offsets
        }()

        let mutable = NSMutableString(string: oldText)
        mutable.deleteCharacters(in: safeRange)
        text = mutable as String

        if oldNewlineCount > 0 {
            lineAdvances = oldNewlineOffsets.enumerated().compactMap { index, offset in
                guard offset < safeRange.location || offset >= deletionEnd else { return nil }
                return index < oldAdvances.count ? oldAdvances[index] : 1.0
            }
        } else {
            lineAdvances.removeAll()
        }

        let deletedLength = safeRange.length
        balloonImages = balloonImages.compactMap { image in
            guard let offset = image.inlineTextOffset else { return image }
            if offset >= safeRange.location && offset < deletionEnd { return nil }
            var adjusted = image
            if offset >= deletionEnd {
                adjusted.inlineTextOffset = offset - deletedLength
            }
            return adjusted
        }

        anchors = anchors.compactMap { anchor in
            let oldStart = anchor.range.location
            let oldEnd = NSMaxRange(anchor.range)
            let newStart = transformedBoundary(oldStart, deletion: safeRange)
            let newEnd = transformedBoundary(oldEnd, deletion: safeRange)
            guard newEnd > newStart else { return nil }
            let newRange = NSRange(location: newStart, length: newEnd - newStart)
            let newAnchorText = (text as NSString).substring(with: newRange)
            return BalloonAnchorRange(
                id: anchor.id,
                references: anchor.references,
                text: newAnchorText,
                range: newRange,
                pluginOrigin: anchor.pluginOrigin,
                visited: anchor.visited
            )
        }
    }

    private func transformedBoundary(_ offset: Int, deletion: NSRange) -> Int {
        if offset <= deletion.location { return offset }
        if offset >= NSMaxRange(deletion) { return offset - deletion.length }
        return deletion.location
    }
}

/// `\_a[...]...\_a` の範囲分割でバルーン本文の1セグメントを表す（アンカー/非アンカー）。
struct BalloonTextSegment: Equatable {
    let text: String
    let isAnchor: Bool
    /// 所属する `BalloonViewModel.anchors` の index（非アンカーは nil）。
    let anchorIndex: Int?
}

/// `\f[anchorstyle]` 等で指定するアンカー装飾の形状（UKADOC 形状指定: square / underline / square+underline / none）。
enum AnchorDecorationStyle: Equatable, Sendable {
    case none
    case underline
    case square
    case squareUnderline

    /// 形状指定文字列（大文字小文字・前後空白を許容）を解析する。
    /// `none` / `underline` / `square` / `square+underline` を返し、`default` や未知値は nil。
    init?(shape: String) {
        switch shape.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "none": self = .none
        case "underline": self = .underline
        case "square": self = .square
        case "square+underline": self = .squareUnderline
        default: return nil
        }
    }
}

/// アンカー1状態の装飾定義（形状・塗り色・枠線/下線色）。UKADOC の brush（矩形内塗り）と pen（枠・下線）に対応。
struct AnchorDecoration: Equatable {
    var style: AnchorDecorationStyle
    var fontColor: NSColor
    var brushColor: NSColor
    var penColor: NSColor
    var rasterOperation: AnchorRasterOperation = .none
}

/// `\_a[ID,...]...\_a` の1範囲のアンカー表現。
/// 表示テキストと文字範囲を保持し、クリック時にどのアンカーのアクションを実行するかを決定できる。
struct BalloonAnchorRange: Equatable {
    let id: String
    let references: [String]
    let text: String
    let range: NSRange
    let pluginOrigin: Bool
    /// クリック済み（訪問済み）かどうか。true のとき `anchorvisited*` 装飾で描画する。
    var visited: Bool

    init(id: String, references: [String], text: String, range: NSRange, pluginOrigin: Bool = false, visited: Bool = false) {
        self.id = id
        self.references = references
        self.text = text
        self.range = range
        self.pluginOrigin = pluginOrigin
        self.visited = visited
    }
}


// MARK: - GhostManager

/// 追加ゴーストの起動時に、OnBoot の前に発火するライフサイクル GET。
///
/// `OnGhostCalled` / `OnGhostChanged` は呼出し先・切替先ゴースト自身へ送るイベントのため、
/// EventBridge の全体ブロードキャストではなく、対象 GhostManager のロード処理へ渡す。
struct GhostBootRequest {
    let eventID: EventID
    let references: [String]
}

struct GhostBootResult {
    let eventID: String
    let script: String
    let shellName: String
    let succeeded: Bool
    let isNewBoot: Bool

    init(
        eventID: String,
        script: String,
        shellName: String,
        succeeded: Bool,
        isNewBoot: Bool = true
    ) {
        self.eventID = eventID
        self.script = script
        self.shellName = shellName
        self.succeeded = succeeded
        self.isNewBoot = isNewBoot
    }
}

/// Manages the lifecycle and display of a single ghost.
class GhostManager: NSObject, SakuraScriptEngineDelegate {

    struct CachedRuntime {
        let runtime: GhostShioriRuntime
        let context: ShioriRuntimeLoadContext
    }

    // MARK: - Properties

    let ghostURL: URL
    /// SHIORIへ`uniqueid`として通知し、Owned SSTPの照合に使うセッション固有ID。
    let sstpUniqueID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    /// FMO全行の接頭辞に使う、ゴースト単位のセッション固有ID。
    let fmoID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    /// 現在ロード中のSHIORIランタイム。YAYAは後方互換用の yayaAdapter からも参照できる。
    var shioriRuntime: GhostShioriRuntime?
    var yayaAdapter: YayaAdapter?
    var ghostMakotoTranslator: MakotoTranslator?
    var shellMakotoTranslator: MakotoTranslator?
    let sakuraEngine = SakuraScriptEngine()
    var eventToken: UUID?
    private var didShutdown = false
    // SHIORI Resource はゴースト別名前空間で保持する（複数ゴースト同時起動時の汚染防止）。
    // lazy: ghostURL 確定後（init 完了後）の初回アクセスで生成する。
    lazy var resourceManager = ResourceManager(ghostKey: ghostURL.lastPathComponent)
    var ghostConfig: GhostConfiguration?
    var activeShellName: String = "master"
    var lastSntpServerDate: Date?
    var lastSntpServerDateTime: String?
    var lastSntpTimezone: String?
    var lastBiffUnreadCounts: [String: Int] = [:]

    /// 追加ゴーストの起動スクリプト再生完了時に呼び出すコールバック。
    private var bootCompletion: ((GhostManager, GhostBootResult) -> Void)?
    private var pendingBootResult: GhostBootResult?

    // Window management
    var characterWindows: [Int: NSWindow] = [:] // Support multiple scopes (0=master, 1=partner)
    var balloonWindows: [Int: NSWindow] = [:]
    /// `resetballoonpos` のプログラム移動をユーザー移動として保存しない。
    var isResettingBalloonPositions = false
    /// `save,wallpaper` と `restore,wallpaper` の同一セッション内バックアップ。
    var savedWallpaperURLs: [String: URL] = [:]
    var surfaceTestWindow: NSWindow?
    /// SakuraScript が開く補助ウィンドウ（ログ／アドレスバー／ビューア等）。
    /// ゴーストごとに保持し、再度開いたときは既存ウィンドウを再利用する。
    var utilityWindows: [String: NSWindow] = [:]
    /// `set,tasktrayicon` が所有するゴースト単位のメニューバーアイコン。
    /// Dock のアプリアイコンを書き換えるのではなく、macOS の通知領域相当へ表示する。
    var taskTrayStatusItem: NSStatusItem?
    var taskTrayAnimationTimer: Timer?
    /// TeachBox はスクリプトから閉じられる必要があるため、NSAlert の
    /// ブロッキングモーダルではなく専用ウィンドウとして保持する。
    var teachBoxTextField: NSTextField?
    var teachBoxProgrammaticClose = false
    /// 現在表示中のInputBox/CommunicateBoxをスクリプトから閉じるためのモーダル参照。
    var activeInputAlert: NSAlert?
    var activeInputDialogID: String?
    var inputDialogCloseRequested = false
    var activeCommunicateAlert: NSAlert?
    var communicateDialogCloseRequested = false

    /// `open,backlogviewer` 用の発言履歴。ゴースト単位で上限付き保持する。
    var backlogEntries: [GhostBacklogEntry] = []

    /// 使用率ストアのセッションが開始済みか。テストやロード前の表示は統計へ混入させない。
    var usageSessionStarted = false

    // ViewModels
    var characterViewModels: [Int: CharacterViewModel] = [:] // One per scope
    var balloonViewModels: [Int: BalloonViewModel] = [:]

    // Balloon configuration and image loader
    var balloonConfig: BalloonConfig?
    var balloonImageLoader: BalloonImageLoader?

    var currentScope: Int = 0
    var balloonTextCancellables: [Int: AnyCancellable] = [:]

    // Context tracking for URL/email commands
    fileprivate var pendingURL: String?
    fileprivate var pendingEmail: String?

    // Typing playback state
    enum PlaybackUnit {
        case textToken(String)
        case text(Character)
        case textChunk(String)
        case speak(String)
        case speakTextToken(String)
        case startAnimation(id: Int, wait: Bool)
        case newline
        case newlineVariation(String)
        case scope(Int)
        case surface(Int)
        case balloonImage([String])
        case wait(TimeInterval)
        case waitUntil(TimeInterval) // seconds from precise base
        case waitForAudio
        case waitForHTTP(UUID)
        case waitForSyncObject(name: String, timeout: TimeInterval, generation: UInt64)
        case waitForVisualEffect(String)
        case waitAnimation(Int) // wait until SERIKO animation ID completes
        case resetPrecise
        case clickWait(noclear: Bool)
        case end
        case toggleQuickMode
        case setQuickMode(Bool)
        case voiceCommand([String])
        case moveAway
        case moveClose
        case bootGhost
        case bootAllGhosts
        case executeSNTPApply
        case executeSNTP
        case playSound(String)
        case deferredCommand(() -> Void) // Deferred command to execute after script completes
        case embeddedEvent(event: String, references: [String])
    }
    var playbackQueue: [PlaybackUnit] = []
    var isPlaying: Bool = false
    /// 非同期待機コールバックが古いスクリプトのキューを再開しないための世代番号。
    private var playbackGeneration: UInt64 = 0
    private var quickMode: Bool = false
    private var preciseBase: Date = Date()
    private let defaultTypingInterval: TimeInterval = 0.1
    private var typingInterval: TimeInterval = 0.1
    /// `\![set,serikotalk,...]` は永続設定ではなく現在スクリプトだけの上書き。
    var serikoTalkEnabledForScript: Bool?
    private var syncEnabled: Bool = false
    private var syncScopes: Set<Int> = []
    var pendingClick: Bool? = nil
    /// `\_a[ID,...]` 開始から `\_a` 閉じまでの範囲アンカー構築中の状態。
    /// textStart は開始時点のバルーン本文の UTF-16 文字数（閉じタグ時点との差分がアンカー範囲になる）。
    private var pendingAnchorOpen: (id: String, references: [String], pluginOrigin: Bool, textStart: Int)? = nil
    
    // Append mode flag - when true, balloon text is not cleared on script start
    private var appendModeEnabled: Bool = false
    
    // Sound playback tracking
    var currentSounds: [SoundPlayer] = []
    var namedSounds: [String: [SoundPlayer]] = [:]
    var preloadedSounds: [String: [SoundPlayer]] = [:]
    var videoPlayers: [String: VideoPlayerWindow] = [:]
    var preloadedVideos: [String: [VideoPreloadPlayer]] = [:]
    var importedSurfaceTimers: [String: Timer] = [:]
    var importedSurfaceTokensByOwner: [String: String] = [:]

    // Sakura Script \__v 音声合成制御。自動読み上げは既定で無効にし、明示指定時だけ使う。
    // `voiceAlternateText` は次のテキストトークン1つにだけ適用し、\__v 終了タグで解除する。
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var voiceSynthesisEnabled = false
    private var voiceAlternateText: String?
    private var voiceAlternateConsumed = false
    
    // Animation engine
    var animationEngine: AnimationEngine = AnimationEngine()
    var surfaceAliases: [Int: Int] = [:]
    var surfaceNameAliases: [String: Int] = [:]   // \s[alias] 用: 文字列別名 → サーフェスID
    var parsedSurfaceDefs: [Int: SerikoSurfaceDefinition] = [:]  // element 合成・アニメ定義のキャッシュ
    var surfaceTable: SurfaceTable? = nil  // surfacetable.txt のメタデータ（サーフィステスト用グループ定義）
    var waitingForAnimation: Int? = nil  // Animation ID we're waiting for

    // Window management (used by Window extension)
    var stickyWindowRelationships: [Int: Set<Int>] = [:] // Master scope -> follower scopes
    var stickyWindowOffsets: [Int: [Int: CGPoint]] = [:] // Master scope -> follower scope -> initial relative origin
    var windowZOrderScopes: [Int]? = nil // Persisted z-order group for windows created later
    var pendingWindowStateReasons: [Int: String] = [:] // Scope -> reason for the next minimize/restore notification
    var serikoScaleFactorsByScope: [Int: [Int: CGPoint]] = [:] // scope -> animationID -> x/y multiplier
    /// PROPERTY の animation.num 用。実行開始時の scope とIDを保持する。
    var activeAnimationIDsByScope: [Int: Set<Int>] = [:]
    /// 画面引き継ぎイベントの直前モニター状態（scopeごと）。
    /// displayIDをwire値と分離して保持し、同一形状のモニター間でも移動を検出する。
    var displayHandoverStates: [Int: DisplaySnapshot] = [:]
    /// 起動時のOnDisplayHandover(init)を同一scopeへ二重送信しないための集合。
    var sentInitialDisplayHandoverScopes: Set<Int> = []

    // Choice dialog state (used by System extension)
    var pendingChoices: [(title: String, action: ChoiceAction, pluginOrigin: Bool)] = []
    var choiceHasCancelOption: Bool = false
    var choiceTimeout: TimeInterval? = nil
    /// \* 指定（このスクリプトの選択肢をタイムアウトさせない）
    var choiceTimeoutDisabled: Bool = false
    var localEventTimers: [String: Timer] = [:]
    /// 実ポインタが入っているアンカー（scopeごとの一意キー）。
    var hoveredAnchorKeysByScope: [Int: String] = [:]
    var remoteEventTimers: [String: Timer] = [:]
    var pluginEventTimers: [String: Timer] = [:]
    /// オンラインマーカーのスコープ別アニメーションタイマー。
    var onlineMarkerTimers: [Int: Timer] = [:]
    /// `set,scaling` / `set,alpha` の時間変化をスコープ単位で管理する。
    /// 新しい指定が来たときは、古い補間を中断して最新の目標値へ切り替える。
    var visualEffectAnimationTimers: [String: Timer] = [:]
    /// \![execute,websocket,URL] で開いた WebSocket 接続（URL 文字列でキー）
    var webSocketTasks: [String: URLSessionWebSocketTask] = [:]
    /// \![execute,http-stream*,URL] で開始した HTTP ストリーミング要求（URL 文字列でキー）。\![cancel,http,URL] で中断する。
    var httpStreamingTasks: [String: URLSessionDataTask] = [:]
    /// URLSession delegate を保持するための HTTP ストリーミング実行器。
    var httpStreamingRunners: [String: HTTPDataTaskRunner] = [:]
    /// ストリーミングで `--sync` を指定した場合の待機ID。
    var httpStreamingWaitIDs: [String: UUID] = [:]
    /// チャンク境界で分割された UTF-8/Shift_JIS 文字を次のチャンクへ持ち越す。
    var httpStreamingPendingData: [String: Data] = [:]
    /// 通常の HTTP 要求も progress 通知中は delegate の寿命を保持する。
    var httpRequestRunners: [UUID: HTTPDataTaskRunner] = [:]
    /// `--sync` HTTP/RSS 要求が完了するまで SakuraScript を停止するための待機集合。
    var pendingHTTPWaits: Set<UUID> = []
    var selectModeActive: Bool = false
    var selectModeScope: Int = 0
    var selectModeName: String = "rect"
    var quickSessionEnabled: Bool = false
    var collisionModeActive: Bool = false
    var passiveModeActive: Bool = false
    var inductionModeActive: Bool = false
    var noUserBreakModeActive: Bool = false
    /// \t タイムクリティカルセクション中（スクリプトブレークまたは \e まで、マウス系イベント通知を抑止）
    var timeCriticalActive: Bool = false
    /// 他ゴーストのサーフェス変更を OnOtherSurfaceChange で受け取るか。
    /// `\![set,othersurfacechange,...]` の有効期間はゴーストのセッション中のみ。
    var observesOtherSurfaceChange: Bool = false

    struct PluginTalkNotificationContext {
        let script: String
        let reasons: Set<String>
        let eventID: String
        let references: [String]
    }
    var pendingPluginTalkAfter: PluginTalkNotificationContext?
    var isEmittingPluginTalk = false
    var currentScriptIsPluginOrigin = false

    // 終了シーケンス管理（OnClose 応答再生 → \- → 終了確定）
    var isShuttingDown: Bool = false
    var awaitingTerminateReply: Bool = false
    var didFinalizeTermination: Bool = false
    var terminateAfterPlayback: Bool = false
    /// OnCloseAll を複数ゴーストへ送るアプリ終了シーケンスの完了通知。
    /// `\-` を含む応答でも NSApplication を先に終了させず、AppDelegate が全ゴーストの
    /// 応答再生完了を集約してから終了を確定する。
    var closeSequenceCompletion: (() -> Void)?
    /// OnDestroy の Reference0（UKADOC: リロード時のみ "reload"、通常終了は Reference なし）
    private var pendingDestroyReason: String?

    // OnOffscreen / OnOverlap の遷移検出用の直前状態（UKADOC Reference1 に渡す）。
    // nil = 未サンプル（初回 tick でベースラインを確立し、イベントは発火しない）
    var lastOffscreenRef0: String?
    var lastOverlapRef0: String?

    // Dressup configuration
    var dressupConfigurations: [DressupConfig] = []
    var dressupBindGroupsByScope: [Int: [Int: DressupBindGroupMeta]] = [:]
    var dressupMenuItemsByScope: [Int: [Int: Int]] = [:] // scope -> menuIndex -> bindgroupID

    enum ChoiceAction {
        case event(id: String, references: [String])
        case script(String)
    }

    // Dressup configuration types
    struct DressupConfig {
        let category: String
        let parts: [DressupPartBinding]
    }

    struct DressupPartBinding {
        let partName: String
        let surfaceID: Int
        let x: Int
        let y: Int
        let overlay: Bool
    }

    struct DressupBindGroupMeta: Equatable {
        let scope: Int
        let bindGroupID: Int
        let category: String
        let part: String
        let thumbnail: String?
        let isDefault: Bool
    }

    // MARK: - Initialization

    init(ghostURL: URL) {
        self.ghostURL = ghostURL
        super.init()
        self.sakuraEngine.delegate = self
        // `\![set,property,...]` は sakuraEngine.propertyManager 経由で書き込まれる。
        // デフォルトの SakuraScriptEngine() は独立した PropertyManager インスタンスを持つため、
        // ここで PropertyManager.shared に差し替えないと、SSTPDispatcher/ResourceBridge 等
        // 他の全読み取り経路（.shared 参照）から SET した値が一切見えなくなる。
        self.sakuraEngine.propertyManager = PropertyManager.shared
        PropertyManager.shared.bindCurrentGhostRuntime(self)

        // Load saved username into environment expander
        if let username = resourceManager.username {
            sakuraEngine.envExpander.username = username
        }
        
        // Load persistent character names
        loadPersistentCharacterNames()
        
        // Setup animation engine callbacks
        setupAnimationCallbacks()

        // Load dressup configuration
        loadDressupConfiguration()

        // Setup screen change observer for desktop alignment
        setupScreenChangeObserver()
    }

    deinit {
        // Swift Testing/Task の所有権解放はバックグラウンドスレッドで起こり得る。
        // deinit から AppKit の停止処理を呼ぶと、stopAllVideos() などがメインキューへ
        // self の weak capture を登録する途中で objc_initWeak が abort するため、
        // UI を含む終了処理は明示的な shutdown() に限定する。
        // メインスレッドでの解放時だけは、従来どおり最後の保険として実行する。
        if Thread.isMainThread {
            shutdown()
        }
    }

    /// `currentghost.scope(ID).scaling` が返す実効倍率を、SET/SERIKO 後の ViewModel から組み立てる。
    /// 単一倍率時は百分率を返し、非等方倍率時は横・縦をカンマ区切りで保持する。
    func propertyScopeScaling(for scope: Int) -> String? {
        guard let viewModel = characterViewModels[scope] else { return nil }
        return Self.propertyScalingValue(x: viewModel.scaleX, y: viewModel.scaleY)
    }

    /// `currentghost.scope(ID).*` のうち、実行中状態を持つプロパティを返す。
    /// 静的な PropertyProvider のスナップショットでは、サーフェス切替やアニメーション開始後の
    /// 値を返せないため、ここから CharacterViewModel / 実行中アニメーションを直接参照する。
    func propertyScopeValue(for scope: Int, property: String) -> String? {
        switch property {
        case "surface.num":
            guard let viewModel = characterViewModels[scope] else { return nil }
            return String(viewModel.currentSurfaceID)
        case "animation.num":
            var activeIDs = activeAnimationIDsByScope[scope] ?? []
            // 自動発火や旧AnimationEngineの完了通知前でも、現在の実状態を反映する。
            if scope == currentScope {
                activeIDs.formUnion(serikoExecutor.activeAnimations.keys)
                activeIDs.formUnion(animationEngine.activeAnimationIDs)
            }
            return activeIDs.sorted().map(String.init).joined(separator: ",")
        case "scaling":
            return propertyScopeScaling(for: scope)
        default:
            return nil
        }
    }

    /// `currentghost.scope(ID).surface.num` / `animation.num` のSETを実ランタイムへ反映する。
    @discardableResult
    func setPropertyScopeValue(for scope: Int, property: String, value: String) -> Bool {
        applyScopePropertySideEffect(
            key: "currentghost.scope(\(scope)).\(property)",
            value: value
        )
    }

    /// `currentghost.balloon.scope(ID).scaling` が返す実効倍率を、表示中バルーンから読む。
    func propertyBalloonScopeScaling(for scope: Int) -> String? {
        guard let viewModel = balloonViewModels[scope] else { return nil }
        return Self.propertyScalingValue(x: viewModel.scaleX, y: viewModel.scaleY)
    }

    private static func propertyScalingValue(x: Double, y: Double) -> String? {
        guard x.isFinite, y.isFinite else { return nil }
        let xPercent = x * 100.0
        let yPercent = y * 100.0
        if x == y {
            return String(xPercent)
        }
        return "\(xPercent),\(yPercent)"
    }
    
    // MARK: - Character Name Persistence
    
    func loadPersistentCharacterNames() {
        let defaults = UserDefaults.standard
        
        if let savedSakuraName = defaults.string(forKey: "OurinSakuraName") {
            sakuraEngine.envExpander.selfname = savedSakuraName
            Log.debug("[GhostManager] Loaded sakura name: \(savedSakuraName)")
        }
        
        if let savedKeroName = defaults.string(forKey: "OurinKeroName") {
            sakuraEngine.envExpander.keroname = savedKeroName
            Log.debug("[GhostManager] Loaded kero name: \(savedKeroName)")
        }
    }
    
    func loadDressupConfiguration() {
        dressupConfigurations.removeAll()
        dressupBindGroupsByScope.removeAll()
        dressupMenuItemsByScope.removeAll()
        // Load dressup configuration from shell descript.txt
        guard let shellPath = loadShellPath() else { return }
        let descriptPath = shellPath.appendingPathComponent("descript.txt")

        var content: String?
        if let utf8Content = try? String(contentsOf: descriptPath, encoding: .utf8) {
            content = utf8Content
        } else if let shiftJISContent = try? String(contentsOf: descriptPath, encoding: .shiftJIS) {
            content = shiftJISContent
        }

        guard let fileContent = content else {
            Log.debug("[GhostManager] Failed to load shell descript.txt")
            return
        }

        let parsed = Self.parseDressupMetadata(content: fileContent)
        let partsByCategory = parsed.partsByCategory

        if partsByCategory.isEmpty {
            Log.debug("[GhostManager] No dressup configuration found in descript.txt")
        } else {
            let configs = partsByCategory
                .map { DressupConfig(category: $0.key, parts: $0.value) }
                .sorted { $0.category < $1.category }
            dressupConfigurations.append(contentsOf: configs)
            let totalParts = configs.reduce(0) { $0 + $1.parts.count }
            Log.debug("[GhostManager] Dressup configuration loaded: categories=\(configs.count), parts=\(totalParts)")
        }

        for (scope, groups) in parsed.bindGroupNameByScope {
            for (id, groupValue) in groups {
                let meta = DressupBindGroupMeta(
                    scope: scope,
                    bindGroupID: id,
                    category: groupValue.category,
                    part: groupValue.part,
                    thumbnail: groupValue.thumbnail,
                    isDefault: parsed.bindGroupDefaultByScope[scope]?[id] ?? false
                )
                dressupBindGroupsByScope[scope, default: [:]][id] = meta
            }
        }
        dressupMenuItemsByScope = parsed.menuItemsByScope
    }

    static func parseDressupMetadata(content: String) -> (
        partsByCategory: [String: [DressupPartBinding]],
        bindGroupNameByScope: [Int: [Int: (category: String, part: String, thumbnail: String?)]],
        bindGroupDefaultByScope: [Int: [Int: Bool]],
        menuItemsByScope: [Int: [Int: Int]]
    ) {
        var partsByCategory: [String: [DressupPartBinding]] = [:]
        var bindGroupNameByScope: [Int: [Int: (category: String, part: String, thumbnail: String?)]] = [:]
        var bindGroupDefaultByScope: [Int: [Int: Bool]] = [:]
        var menuItemsByScope: [Int: [Int: Int]] = [:]

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("//") else { continue }

            if trimmedLine.lowercased().hasPrefix("dressup,") {
                let components = trimmedLine.split(separator: ",", maxSplits: 5)
                if components.count >= 4 {
                    let category = String(components[1]).trimmingCharacters(in: .whitespaces)
                    let partName = String(components[2]).trimmingCharacters(in: .whitespaces)
                    let surfaceID = Int(components[3]) ?? 0
                    let x = components.count >= 5 ? Int(components[4]) ?? 0 : 0
                    let y = components.count >= 6 ? Int(components[5]) ?? 0 : 0

                    let binding = DressupPartBinding(
                        partName: partName,
                        surfaceID: surfaceID,
                        x: x,
                        y: y,
                        overlay: true
                    )
                    partsByCategory[category, default: []].append(binding)
                }
                continue
            }

            let segments = trimmedLine.split(separator: ",", maxSplits: 1).map(String.init)
            guard !segments.isEmpty else { continue }
            let key = segments[0].trimmingCharacters(in: .whitespaces)
            let value = segments.count > 1 ? segments[1].trimmingCharacters(in: .whitespaces) : ""

            if let parsed = parseBindGroupNameKey(key) {
                let fields = value.split(separator: ",", maxSplits: 2).map { String($0).trimmingCharacters(in: .whitespaces) }
                if fields.count >= 2 {
                    let thumbnail = fields.count >= 3 && !fields[2].isEmpty ? fields[2] : nil
                    bindGroupNameByScope[parsed.scope, default: [:]][parsed.bindGroupID] = (
                        category: fields[0],
                        part: fields[1],
                        thumbnail: thumbnail
                    )
                }
                continue
            }

            if let parsed = parseBindGroupDefaultKey(key) {
                let flag = value == "1" || value.lowercased() == "true"
                bindGroupDefaultByScope[parsed.scope, default: [:]][parsed.bindGroupID] = flag
                continue
            }

            if let parsed = parseMenuItemKey(key), let bindID = Int(value) {
                menuItemsByScope[parsed.scope, default: [:]][parsed.menuIndex] = bindID
            }
        }

        return (partsByCategory, bindGroupNameByScope, bindGroupDefaultByScope, menuItemsByScope)
    }

    private static func parseBindGroupNameKey(_ key: String) -> (scope: Int, bindGroupID: Int)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(sakura|kero|char\d+)\.bindgroup(\d+)\.name$"#, options: [.caseInsensitive]) else {
            return nil
        }
        let nsKey = key as NSString
        guard let match = regex.firstMatch(in: key, range: NSRange(location: 0, length: nsKey.length)),
              let scopeRange = Range(match.range(at: 1), in: key),
              let idRange = Range(match.range(at: 2), in: key),
              let bindGroupID = Int(key[idRange]) else {
            return nil
        }
        return (scopeTokenToID(String(key[scopeRange])), bindGroupID)
    }

    private static func parseBindGroupDefaultKey(_ key: String) -> (scope: Int, bindGroupID: Int)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(sakura|kero|char\d+)\.bindgroup(\d+)\.default$"#, options: [.caseInsensitive]) else {
            return nil
        }
        let nsKey = key as NSString
        guard let match = regex.firstMatch(in: key, range: NSRange(location: 0, length: nsKey.length)),
              let scopeRange = Range(match.range(at: 1), in: key),
              let idRange = Range(match.range(at: 2), in: key),
              let bindGroupID = Int(key[idRange]) else {
            return nil
        }
        return (scopeTokenToID(String(key[scopeRange])), bindGroupID)
    }

    private static func parseMenuItemKey(_ key: String) -> (scope: Int, menuIndex: Int)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(sakura|kero|char\d+)\.menuitem(\d+)$"#, options: [.caseInsensitive]) else {
            return nil
        }
        let nsKey = key as NSString
        guard let match = regex.firstMatch(in: key, range: NSRange(location: 0, length: nsKey.length)),
              let scopeRange = Range(match.range(at: 1), in: key),
              let indexRange = Range(match.range(at: 2), in: key),
              let menuIndex = Int(key[indexRange]) else {
            return nil
        }
        return (scopeTokenToID(String(key[scopeRange])), menuIndex)
    }

    private static func scopeTokenToID(_ token: String) -> Int {
        let lowered = token.lowercased()
        if lowered == "sakura" { return 0 }
        if lowered == "kero" { return 1 }
        if lowered.hasPrefix("char"), let value = Int(lowered.dropFirst(4)) {
            return value
        }
        return 0
    }
    
    func saveCharacterNames(sakuraName: String, keroName: String?) {
        let defaults = UserDefaults.standard
        defaults.set(sakuraName, forKey: "OurinSakuraName")
        if let kero = keroName {
            defaults.set(kero, forKey: "OurinKeroName")
        }
        sakuraEngine.envExpander.selfname = sakuraName
        if let kero = keroName {
            sakuraEngine.envExpander.keroname = kero
        }
        Log.debug("[GhostManager] Saved character names - Sakura: \(sakuraName), Kero: \(keroName ?? "none")")
    }

    // MARK: - Public API

    /// descript.txtのSHIORI指定から、実装言語に依存しないロード入力を作る。
    /// YAYAの場合だけyaya.txtを解釈し、他ランタイムへYAYA辞書規則を持ち込まない。
    func makeShioriLoadContext(moduleName: String, ghostRoot: URL) -> ShioriRuntimeLoadContext {
        let communication = ShioriCommunicationOptions(
            version: ghostConfig?.shioriVersion,
            encoding: ghostConfig?.shioriEncoding,
            forceEncoding: ghostConfig?.shioriForceEncoding,
            escapeUnknown: ghostConfig?.shioriEscapeUnknown ?? false,
            cache: ghostConfig?.shioriCache ?? false
        )
        guard ShioriRuntimeFactory.kind(for: moduleName) == .yaya else {
            return ShioriRuntimeLoadContext(
                ghostURL: ghostURL,
                ghostRoot: ghostRoot,
                moduleName: moduleName,
                communication: communication
            )
        }

        let fm = FileManager.default
        var collector = DicCollector()
        let yayaTxtPath = ghostRoot.appendingPathComponent("yaya.txt")
        if let yayaContent = (try? String(contentsOf: yayaTxtPath, encoding: .utf8)) ??
                             (try? String(contentsOf: yayaTxtPath, encoding: .shiftJIS)) {
            Log.debug("[GhostManager] Found yaya.txt, parsing dictionary list with includes...")
            collectDicEntries(
                content: yayaContent,
                baseURL: ghostRoot,
                sourceName: "yaya.txt",
                collector: &collector,
                visited: []
            )
        } else {
            let contents = (try? fm.contentsOfDirectory(at: ghostRoot, includingPropertiesForKeys: nil)) ?? []
            collector.entries = contents
                .filter { $0.pathExtension.lowercased() == "dic" }
                .map { DicEntry(path: $0.lastPathComponent, encoding: nil, sourceConfig: "(fallback)", sourceLine: 0) }
            Log.debug("[GhostManager] yaya.txt not found, loading all \(collector.entries.count) .dic files")
        }

        return ShioriRuntimeLoadContext(
            ghostURL: ghostURL,
            ghostRoot: ghostRoot,
            moduleName: moduleName,
            dictionaryEntries: collector.entries,
            dictionaryEncoding: collector.globalCharset ?? "auto",
            communication: communication
        )
    }

    /// 共通Factoryとload(context:)を通じてSHIORIを生成・ロードする。
    func createLoadedShioriRuntime(moduleName: String, ghostRoot: URL) -> GhostShioriRuntime? {
        guard let runtime = ShioriRuntimeFactory.makeRuntime(for: moduleName) else {
            Log.info("[GhostManager] Failed to create SHIORI runtime for \(moduleName)")
            return nil
        }
        runtime.resourceManager = resourceManager
        let context = makeShioriLoadContext(moduleName: moduleName, ghostRoot: ghostRoot)
        guard runtime.load(context: context) else {
            Log.info("[GhostManager] Failed to load SHIORI runtime: \(moduleName)")
            runtime.unload()
            return nil
        }
        return runtime
    }

    func start(
        bootRequest: GhostBootRequest? = nil,
        completion: ((GhostManager, GhostBootResult) -> Void)? = nil
    ) {
        Log.info("[GhostManager] start() called for ghost at: \(ghostURL.path)")
        bootCompletion = completion
        pendingBootResult = nil
        setupWindows()
        setupRightClickMenu()
        Log.debug("[GhostManager] Windows setup complete")

        // Load the initial real surface immediately when the shell asset is available.
        DispatchQueue.main.async {
            self.updateSurface(id: 0)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let ghostRoot = self.ghostURL.appendingPathComponent("ghost/master", isDirectory: true)
            Log.debug("[GhostManager] Ghost root: \(ghostRoot.path)")
            // Load ghost configuration from descript.txt
            if let config = GhostConfiguration.load(from: ghostRoot) {
                self.ghostConfig = config
                self.activeShellName = config.defaultShellDirectory.isEmpty ? "master" : config.defaultShellDirectory
                RateOfUseStore.shared.beginSession(
                    identifier: self.ghostURL.standardizedFileURL.path,
                    name: config.name,
                    sakuraname: config.sakuraName,
                    keroname: config.keroName ?? ""
                )
                self.usageSessionStarted = true
                self.reloadMakotoTranslators()
                self.loadDressupConfiguration()
                Log.info("[GhostManager] Loaded ghost configuration: \(config.name)")
                Log.debug("[GhostManager]   - Sakura: \(config.sakuraName), Kero: \(config.keroName ?? "none")")
                Log.debug("[GhostManager]   - SHIORI: \(config.shiori)")
                Log.debug("[GhostManager]   - Default shell: \(config.defaultShellDirectory)")

                // Apply configuration settings to environment
                self.applyGhostConfiguration(config, ghostRoot: ghostRoot)
                DispatchQueue.main.async {
                    self.applyDefaultDressupBindings(for: self.currentScope)
                }
                
                // Initialization notifies (hwnd, capability, OnNotifySelfInfo etc.)
                // are sent later after EventBridge registration and window creation.
            } else {
                Log.info("[GhostManager] Failed to load ghost configuration from descript.txt")
            }

            // Load balloon configuration from ghost/balloon/descript.txt
            // Try to find balloon directory in ghost root first
            let balloonPath = self.ghostURL.appendingPathComponent("balloon", isDirectory: true).path
            let balloonDescriptPath = (balloonPath as NSString).appendingPathComponent("descript.txt")
            if let config = BalloonConfig.load(from: balloonDescriptPath) {
                self.balloonConfig = config
                self.balloonImageLoader = BalloonImageLoader(balloonPath: balloonPath)
                Log.info("[GhostManager] Loaded balloon configuration: \(config.name)")
            } else {
                Log.info("[GhostManager] Failed to load balloon configuration from \(balloonDescriptPath)")
            }

            let moduleName = ShioriRuntimeFactory.moduleName(for: self.ghostConfig)
            Log.info("[GhostManager] Loading configured SHIORI: \(moduleName)")
            let loadStart = Date()
            let context = self.makeShioriLoadContext(moduleName: moduleName, ghostRoot: ghostRoot)
            let appDelegate: AppDelegate? = Thread.isMainThread
                ? NSApp.delegate as? AppDelegate
                : DispatchQueue.main.sync { NSApp.delegate as? AppDelegate }
            let cachedRuntime = appDelegate?.shioriRuntimeCache.take(context: context)
            let runtime: GhostShioriRuntime
            if let cachedRuntime {
                runtime = cachedRuntime
                runtime.resourceManager = self.resourceManager
                _ = runtime.request(
                    method: "NOTIFY",
                    id: "OnCacheRestore",
                    headers: ["Charset": "UTF-8", "SecurityLevel": "local", "Sender": "Ourin"],
                    refs: [],
                    timeout: 1.0
                )
                Log.info("[GhostManager] Restored cached SHIORI runtime: \(moduleName)")
            } else {
                guard let loaded = self.createLoadedShioriRuntime(moduleName: moduleName, ghostRoot: ghostRoot) else {
                    DispatchQueue.main.async {
                        self.finishBootIfNeeded(with: GhostBootResult(
                            eventID: bootRequest?.eventID.rawValue ?? "",
                            script: "",
                            shellName: self.activeShellName,
                            succeeded: false
                        ))
                    }
                    return
                }
                runtime = loaded
            }
            let loadTime = Date().timeIntervalSince(loadStart)
            Log.debug("[GhostManager] SHIORI load complete (kind=\(runtime.kind.rawValue)) in \(String(format: "%.2f", loadTime))s")

            // load成功後にだけ保持・イベント登録する。失敗したruntimeを配送先に残さない。
            DispatchQueue.main.sync {
                self.shioriRuntime = runtime
                self.yayaAdapter = runtime as? YayaAdapter
                self.eventToken = EventBridge.shared.register(runtime: runtime, ghostManager: self)
                self.emitInitialDisplayHandoverEvents()
            }

            let defaults = UserDefaults.standard
            let bootCount = defaults.integer(forKey: "OurinBootCount")

            // Per UKADOC, OnFirstBoot/OnBoot are GET events (not NOTIFY).
            // Only emit an internal OnInitialize notify; GET is handled below via obtainBootScript().
            DispatchQueue.main.async {
                EventBridge.shared.notify(.OnInitialize)
                defaults.set(bootCount + 1, forKey: "OurinBootCount")
            }

            // Start EventBridge immediately after OnBoot load (dictionary loading completed).
            // 実ゴーストのロード完了をシステムイベント有効化の唯一の集約点とし、標準の自動イベント
            // （タイマー/入力/スリープ/ディスプレイ等）をここで有効にする。以前は既定 false のため、
            // 名前入力ダイアログ経路（GhostManager+Display）を通らないと自動イベントが queue のみに
            // 留まる経路があった。テスト時のみ副作用を避けるため明示的に無効化する。
            let enableAutoEvents = !GhostManager.isRunningUnderTests
            Log.info("[GhostManager] Starting EventBridge after OnBoot load (autoEvents=\(enableAutoEvents))")
            DispatchQueue.main.async {
                self.startEventBridgeIfNeeded(enableAutoEvents: enableAutoEvents)
            }

            // Request the boot script with a timeout; keep the already loaded surface visible meanwhile.
            Log.info("[GhostManager] Requesting boot script (initial lifecycle event/OnFirstBoot/OnBoot)...")
            let sem = DispatchSemaphore(value: 0)

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.obtainBootScript(
                    using: runtime,
                    bootCount: bootCount,
                    initialRequest: bootRequest
                )
                if let result {
                    let trimmed = result.script.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        Log.debug("[GhostManager] Boot script resolved (len=\(trimmed.count))")
                        // Print a safe preview via NSLog so it always appears in logs
                        let preview = trimmed.replacingOccurrences(of: "\n", with: "\\n").prefix(160)
                        NSLog("[GhostManager] Boot script preview: \(preview)")
                        DispatchQueue.main.async {
                            self.pendingBootResult = GhostBootResult(
                                eventID: result.eventID,
                                script: trimmed,
                                shellName: result.shellName,
                                succeeded: true
                            )
                            self.runScript(trimmed, translationContext: .init(eventID: result.eventID))
                        }
                    } else {
                        NSLog("[GhostManager] Boot script is whitespace-only after trim; skipping display")
                        DispatchQueue.main.async {
                            self.finishBootIfNeeded(with: result)
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.finishBootIfNeeded(with: GhostBootResult(
                            eventID: bootRequest?.eventID.rawValue ?? "",
                            script: "",
                            shellName: self.activeShellName,
                            succeeded: true
                        ))
                    }
                }
                sem.signal()
            }

            // If OnBoot takes too long, just wait - EventBridge is already started
            let timeout: DispatchTime = .now() + .seconds(5)
            if sem.wait(timeout: timeout) == .timedOut {
                Log.info("[GhostManager] OnBoot timed out (5s). EventBridge already running; keeping the current surface.")
            }

            // Send initialization NOTIFYs after boot (windows and EventBridge exist)
            if let config = self.ghostConfig {
                DispatchQueue.main.async {
                    self.sendInitializationNotifies(config: config)
                    NotificationCenter.default.post(name: .fmoNeedsRefresh, object: nil)
                }
            }
        }
    }

    /// 起動済みゴーストへ、呼出し／切替の初期ライフサイクル GET を送る。
    ///
    /// 追加起動と同じ `OnGhostCalled` / `OnGhostChanged` → `OnBoot` のフォールバックを
    /// 使うが、既存ゴーストは「新規起動」として扱わない。返答スクリプトの再生完了後に
    /// completion を呼ぶため、`OnGhostCallComplete` 等の後続イベントを順序保証できる。
    func requestLifecycleEvent(
        _ request: GhostBootRequest,
        completion: @escaping (GhostManager, GhostBootResult) -> Void
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.requestLifecycleEvent(request, completion: completion)
            }
            return
        }

        bootCompletion = completion
        pendingBootResult = nil
        guard let runtime = shioriRuntime else {
            finishBootIfNeeded(with: GhostBootResult(
                eventID: request.eventID.rawValue,
                script: "",
                shellName: activeShellName,
                succeeded: false,
                isNewBoot: false
            ))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.obtainBootScript(
                using: runtime,
                bootCount: 1,
                initialRequest: request
            )
            DispatchQueue.main.async {
                let existingResult = GhostBootResult(
                    eventID: result?.eventID ?? request.eventID.rawValue,
                    script: result?.script ?? "",
                    shellName: result?.shellName ?? self.activeShellName,
                    succeeded: true,
                    isNewBoot: false
                )
                let trimmed = existingResult.script.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    self.finishBootIfNeeded(with: existingResult)
                    return
                }
                self.pendingBootResult = existingResult
                self.runScript(trimmed, translationContext: .init(eventID: existingResult.eventID))
            }
        }
    }

    @discardableResult
    func shutdown(preserveRuntimeForCache: Bool = false) -> CachedRuntime? {
        guard !didShutdown else { return nil }
        didShutdown = true
        if usageSessionStarted {
            RateOfUseStore.shared.endSession(identifier: ghostURL.standardizedFileURL.path)
            usageSessionStarted = false
        }
        NotificationCenter.default.post(name: .fmoNeedsRefresh, object: nil)
        NotificationCenter.default.removeObserver(self)
        if let config = ghostConfig,
           let dispatcher = (NSApp.delegate as? AppDelegate)?.pluginDispatcher {
            dispatcher.onGhostExit(
                windows: characterWindows.sorted(by: { $0.key < $1.key }).map { $0.value },
                ghostName: config.name,
                shellName: activeShellName,
                ghostID: config.id ?? ghostURL.lastPathComponent,
                path: ghostURL.path
            )
        }
        for timer in localEventTimers.values {
            timer.invalidate()
        }
        localEventTimers.removeAll()
        hoveredAnchorKeysByScope.removeAll()
        for timer in remoteEventTimers.values {
            timer.invalidate()
        }
        remoteEventTimers.removeAll()
        for timer in pluginEventTimers.values {
            timer.invalidate()
        }
        pluginEventTimers.removeAll()
        for timer in onlineMarkerTimers.values {
            timer.invalidate()
        }
        onlineMarkerTimers.removeAll()
        for timer in visualEffectAnimationTimers.values {
            timer.invalidate()
        }
        visualEffectAnimationTimers.removeAll()
        taskTrayAnimationTimer?.invalidate()
        taskTrayAnimationTimer = nil
        if let taskTrayStatusItem {
            NSStatusBar.system.removeStatusItem(taskTrayStatusItem)
            self.taskTrayStatusItem = nil
        }
        for viewModel in balloonViewModels.values {
            viewModel.onlineModeActive = false
            viewModel.onlineMarkerIndex = 0
        }
        shutdownSerikoLoop()
        stopAllImportedSurfaceAnimations()
        for w in characterWindows.values { w.orderOut(nil) }
        for w in balloonWindows.values { w.orderOut(nil) }
        surfaceTestWindow?.orderOut(nil)
        surfaceTestWindow = nil
        teachBoxProgrammaticClose = true
        for w in utilityWindows.values {
            w.orderOut(nil)
            w.close()
        }
        utilityWindows.removeAll()
        teachBoxTextField = nil
        teachBoxProgrammaticClose = false
        characterWindows.removeAll()
        balloonWindows.removeAll()
        stopAllVideos()
        stopSpeechSynthesis()
        // OnDestroy（NOTIFY、UKADOC）: SHIORI unload の直前に対象ゴーストへのみ直接送信する。
        // EventBridge.notify は autoEventsEnabled=false 時にキュー滞留し、全セッションへ
        // ブロードキャストされるためここでは使わない（OnClose と同じ直接送信の流儀）。
        let runtimeToCache = preserveRuntimeForCache && ghostConfig?.shioriCache == true ? shioriRuntime : nil
        let cached: CachedRuntime?
        if let runtime = runtimeToCache {
            _ = runtime.request(
                method: "NOTIFY",
                id: "OnCacheSuspend",
                headers: ["Charset": "UTF-8", "SecurityLevel": "local", "Sender": "Ourin"],
                refs: [],
                timeout: 1.0
            )
            let ghostRoot = ghostURL.appendingPathComponent("ghost/master", isDirectory: true)
            let moduleName = ShioriRuntimeFactory.moduleName(for: ghostConfig)
            cached = CachedRuntime(
                runtime: runtime,
                context: makeShioriLoadContext(moduleName: moduleName, ghostRoot: ghostRoot)
            )
            runtime.resourceManager = nil
        } else {
            let destroyRefs = pendingDestroyReason.map { [$0] } ?? []
            if let runtime = shioriRuntime {
                let hdrs: [String: String] = ["Charset": "UTF-8", "SecurityLevel": "local", "Sender": "Ourin"]
                _ = runtime.request(method: "NOTIFY", id: "OnDestroy", headers: hdrs, refs: destroyRefs, timeout: 1.0)
            } else {
                _ = BridgeToSHIORI.handle(event: "OnDestroy", references: destroyRefs)
            }
            cached = nil
        }
        pendingDestroyReason = nil
        unloadMakotoTranslators()
        if runtimeToCache == nil {
            shioriRuntime?.unload()
        }
        shioriRuntime = nil
        yayaAdapter = nil
        if let token = eventToken { EventBridge.shared.unregister(token); eventToken = nil }
        return cached
    }

    // MARK: - Scripting

    /// 今すぐトークを再生してよい状態かどうか（OnSecondChange 等の Reference3 / GET・NOTIFY 切替に使用）。
    /// 再生中・タイムクリティカルセクション中・受動/誘導モード中は false。
    func canPlayTalkNow() -> Bool {
        return !isPlaying && !timeCriticalActive && !passiveModeActive && !inductionModeActive
    }

    // MARK: - Termination sequence

    /// 終了シーケンスを開始する。指定した終了イベントを GET で送り、応答スクリプト
    /// （お別れトーク、通常は末尾 \-）を再生してから終了する（UKADOC）。
    /// - Parameters:
    ///   - eventID: 終了イベント（通常は OnClose、アプリ全体終了時は OnCloseAll）
    ///   - reason: 終了イベントの Reference0（user / system 等）
    ///   - replyToTermination: applicationShouldTerminate から呼ばれた場合 true（reply で完了を通知する）
    ///   - completion: OnCloseAll 等でアプリ側が全ゴーストの完了を集約する場合のコールバック
    /// - Returns: シーケンスを開始した場合 true（既に終了処理中なら false）
    @discardableResult
    func beginCloseSequence(
        eventID: String = EventID.OnClose.rawValue,
        reason: String = "user",
        replyToTermination: Bool = false,
        completion: (() -> Void)? = nil
    ) -> Bool {
        guard !isShuttingDown else { return false }
        isShuttingDown = true
        awaitingTerminateReply = replyToTermination
        closeSequenceCompletion = completion
        Log.info("[GhostManager] Close sequence started (reason: \(reason))")

        DispatchQueue.global(qos: .userInitiated).async {
            var script = ""
            if let runtime = self.shioriRuntime {
                let hdrs: [String: String] = ["Charset": "UTF-8", "SecurityLevel": "local", "Sender": "Ourin"]
                if let r = runtime.request(method: "GET", id: eventID, headers: hdrs, refs: [reason], timeout: 4.0),
                   r.ok, let v = r.value {
                    script = v.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                script = BridgeToSHIORI.handle(event: eventID, references: [reason])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            DispatchQueue.main.async {
                if script.isEmpty {
                    self.finishCloseSequence()
                } else {
                    // OnClose は \- が含まれていなくても再生完了後に終了する。
                    // OnCloseAll は AppDelegate の完了集約を使うため、同フラグを立てない。
                    self.terminateAfterPlayback = replyToTermination && completion == nil
                    self.runScript(
                        script,
                        translationContext: .init(eventID: eventID, references: [reason])
                    )
                }
            }
        }
        return true
    }

    /// 終了イベントの応答が空、または再生完了した時点の共通出口。
    func finishCloseSequence() {
        if let completion = closeSequenceCompletion {
            closeSequenceCompletion = nil
            completion()
            return
        }
        finalizeTermination()
    }

    /// ゴースト終了を確定する（\- ハンドラ／OnClose 応答再生完了から呼ばれる）。
    func finalizeTermination() {
        guard !didFinalizeTermination else { return }
        didFinalizeTermination = true
        isShuttingDown = true
        Log.info("[GhostManager] Finalizing ghost termination")
        DispatchQueue.main.async {
            if self.awaitingTerminateReply {
                self.awaitingTerminateReply = false
                NSApp.reply(toApplicationShouldTerminate: true)
            } else {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Entity reference / Jump

    /// \&[ID] の実体参照を解決する。数値文字参照（#NNN / #xHHHH）と主要な名前付き実体に対応。
    static func resolveEntityReference(_ id: String) -> String? {
        // 数値文字参照: #123 / #x30A2 / 0x30A2
        if id.hasPrefix("#") || id.lowercased().hasPrefix("0x") {
            var body = id.hasPrefix("#") ? String(id.dropFirst()) : String(id.dropFirst(2))
            var radix = 10
            if body.lowercased().hasPrefix("x") {
                body = String(body.dropFirst())
                radix = 16
            } else if id.lowercased().hasPrefix("0x") {
                radix = 16
            }
            guard let value = UInt32(body, radix: radix), let scalar = UnicodeScalar(value) else { return nil }
            return String(scalar)
        }
        // 名前付き実体（HTML互換の主要なもの）
        let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
            "copy": "©", "reg": "®", "trade": "™", "hellip": "…", "mdash": "—", "ndash": "–"
        ]
        return named[id.lowercased()]
    }

    /// \j[ID] - ジャンプタグ。スクリプト内ラベルは SakuraScriptEngine 側で解決済み。
    /// URL/ファイルはオープン、それ以外は指定 ID の SHIORI GET として扱う。
    private func resolveJumpFileURL(_ target: String) -> URL? {
        guard let url = URL(string: target), url.isFileURL else { return nil }

        // UKADOC の `file:///name` は ghost/master からの相対指定としても使われる。
        // まず実在する絶対パスを尊重し、存在しない単一スラッシュのパスだけを
        // ghost/master 相対へ解決する。これにより file:///Users/... の絶対指定も失わない。
        let absoluteURL = URL(fileURLWithPath: url.path).standardizedFileURL
        if FileManager.default.fileExists(atPath: absoluteURL.path) {
            return absoluteURL
        }

        let relativePath = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("../"),
              relativePath != ".." else { return absoluteURL }
        return ghostURL
            .appendingPathComponent("ghost/master", isDirectory: true)
            .appendingPathComponent(relativePath)
    }

    func handleJumpCommand(args: [String]) {
        guard let target = args.first?.trimmingCharacters(in: .whitespaces), !target.isEmpty else {
            Log.info("[GhostManager] \\j with no target (ignored)")
            return
        }
        let lowered = target.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            // URLジャンプ: 既定ブラウザで開く
            playbackQueue.append(.deferredCommand {
                if let url = URL(string: target) {
                    Log.info("[GhostManager] \\j opening URL: \(target)")
                    NSWorkspace.shared.open(url)
                }
            })
        } else if lowered.hasPrefix("file://") {
            playbackQueue.append(.deferredCommand {
                if let url = self.resolveJumpFileURL(target) {
                    Log.info("[GhostManager] \\j opening file: \(target)")
                    NSWorkspace.shared.open(url)
                }
            })
        } else {
            // IDジャンプ: On* に限定せず、指定された任意の SHIORI ID へ GET する。
            // 旧実装は On* 以外を無視しており、ゴースト固有イベントを壊していた。
            let references = Array(args.dropFirst())
            playbackQueue.append(.deferredCommand { [weak self] in
                guard let self else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let runtime = self.shioriRuntime,
                          let r = runtime.request(method: "GET", id: target, headers: ["Charset": "UTF-8"], refs: references, timeout: 3.0),
                          r.ok, let v = r.value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else {
                        Log.info("[GhostManager] \\j[\(target)] event jump returned no script")
                        return
                    }
                    DispatchQueue.main.async {
                        self.runScript(
                            v,
                            translationContext: .init(eventID: target, references: references)
                        )
                    }
                }
            })
        }
    }

    func reloadMakotoTranslators() {
        unloadMakotoTranslators()
        let ghostRoot = ghostURL.appendingPathComponent("ghost/master", isDirectory: true)
        let ghostModuleName = ghostConfig?.makoto?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "makoto.dll"
        if !ghostModuleName.isEmpty {
            let moduleName = ghostModuleName
            ghostMakotoTranslator = MakotoTranslator(moduleName: moduleName, base: ghostRoot)
            if ghostMakotoTranslator == nil, ghostConfig?.makoto != nil {
                Log.info("[GhostManager] MAKOTO module could not be loaded: \(moduleName)")
            }
        }
        if let shellRoot = loadShellPath() {
            let descriptor = YayaBackend.parseDescript(url: shellRoot.appendingPathComponent("descript.txt"))
            let shellModuleName = descriptor["makoto"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "makoto.dll"
            if !shellModuleName.isEmpty {
                let moduleName = shellModuleName
                shellMakotoTranslator = MakotoTranslator(moduleName: moduleName, base: shellRoot)
                if shellMakotoTranslator == nil, descriptor["makoto"] != nil {
                    Log.info("[GhostManager] Shell MAKOTO module could not be loaded: \(moduleName)")
                }
            }
        }
        NotificationCenter.default.post(name: .fmoNeedsRefresh, object: nil)
    }

    func unloadMakotoTranslators() {
        ghostMakotoTranslator?.unload()
        shellMakotoTranslator?.unload()
        ghostMakotoTranslator = nil
        shellMakotoTranslator = nil
    }

    /// UKADOC順序: 環境変数展開 → OnTranslate → ghost MAKOTO → shell MAKOTO。
    func translateForDisplay(_ script: String, context: ScriptTranslationContext) -> String {
        var translated = sakuraEngine.expandEnvironment(in: script)
        let bypassRequested = context.reasons.contains("notranslate")
        let forcedForSSTP = context.isSSTP && ghostConfig?.sstpAlwaysTranslate == true
        guard !bypassRequested || forcedForSSTP else { return translated }

        if let runtime = shioriRuntime {
            var headers = [
                "Charset": "UTF-8",
                "SecurityLevel": context.securityLevel,
                "Sender": context.sender
            ]
            if let origin = context.securityOrigin, !origin.isEmpty {
                headers["SecurityOrigin"] = origin
            }
            if let reasons = context.reasonHeader {
                headers["Reference1"] = reasons
            }
            if let eventID = context.eventID, !eventID.isEmpty {
                headers["Reference2"] = eventID
            }
            if let references = context.sourceReferencesHeader {
                headers["Reference3"] = references
            }
            if let response = runtime.request(
                method: "GET",
                id: "OnTranslate",
                headers: headers,
                refs: [translated],
                timeout: 2.0
            ), response.ok, response.status == 200, let value = response.value {
                if Self.shouldAcceptTranslationResponse(original: translated, candidate: value) {
                    translated = value
                } else {
                    Log.info("[GhostManager] Ignoring numeric OnTranslate response for non-numeric script")
                }
            }
        }
        if let value = ghostMakotoTranslator?.translate(translated) {
            translated = value
        }
        if let value = shellMakotoTranslator?.translate(translated) {
            translated = value
        }
        return translated
    }

    func runScript(_ script: String, translationContext: ScriptTranslationContext = .baseware) {
        let preview = script.prefix(200)
        Log.debug("[GhostManager] runScript called with: \(preview)")
        guard !Self.shouldIgnoreNumericEventResponse(script, eventID: translationContext.eventID) else {
            Log.info("[GhostManager] Ignoring numeric SHIORI event response: event=\(translationContext.eventID ?? "unknown") value=\(script.trimmingCharacters(in: .whitespacesAndNewlines))")
            return
        }
        let translated = translateForDisplay(script, context: translationContext)
        runTranslatedScript(translated)
    }

    /// SHIORIのイベント応答はSakura Scriptであり、裸の数値は会話本文ではなく
    /// YAYA等が返す制御値として扱う。通常の本文「0」は保持しつつ、On*イベントの
    /// 数値応答だけを再生境界で止める。
    static func shouldIgnoreNumericEventResponse(_ value: String, eventID: String?) -> Bool {
        guard let eventID,
              eventID.lowercased().hasPrefix("on") else { return false }
        return isNumericOnlyScript(value)
    }

    /// OnTranslate の異常な裸数値で、元の Sakura Script 全体を置換しない。
    /// 元の本文自体が数値だけの場合は、正当な翻訳結果として受け入れる。
    static func shouldAcceptTranslationResponse(original: String, candidate: String) -> Bool {
        !isNumericOnlyScript(candidate) || isNumericOnlyScript(original)
    }

    private static func isNumericOnlyScript(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, Double(trimmed) != nil else { return false }
        return trimmed.contains(where: \.isNumber)
    }

    /// 既にOnTranslate/MAKOTOを通過したスクリプトを再生する。
    /// SSTP応答と実再生で同じ翻訳結果を共有し、二重翻訳を避けるための内部境界。
    func runTranslatedScript(_ script: String) {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recordBacklog(from: trimmed)
        beginPluginTalkNotification(script: trimmed, reasons: ["owned"])

        // `\C` は本文の再生前に判定しないと、通常のスクリプト開始処理で
        // 直前のバルーンを消してしまう。仕様上は先頭指定でスコープ0へ追記する。
        let startsInAppendMode: Bool = {
            guard let first = sakuraEngine.parse(script: trimmed, expandEnvironment: false).first else { return false }
            if case .appendMode = first { return true }
            return false
        }()

        // Reset playback state and balloon text for new script
        playbackGeneration &+= 1
        playbackQueue.removeAll()
        isPlaying = false
        quickMode = false
        preciseBase = Date()
        resetVoiceSynthesisState()
        // 新しいスクリプト開始 = スクリプトブレーク扱い: タイムクリティカル区間と \* 指定を解除
        timeCriticalActive = false
        choiceTimeoutDisabled = false
        pendingAnchorOpen = nil
        if startsInAppendMode {
            appendModeEnabled = true
            currentScope = 0
        } else {
            for vm in balloonViewModels.values {
                vm.resetBalloonContent()
            }
        }
        resetScriptScopedBalloonSettings()
        let previousPluginOrigin = currentScriptIsPluginOrigin
        currentScriptIsPluginOrigin = false
        sakuraEngine.runPreprocessed(script: trimmed)
        currentScriptIsPluginOrigin = previousPluginOrigin
        startPlaybackIfNeeded()
    }

    /// Run a script originating from NOTIFY. If the script contains no visible text
    /// tokens, keep the current balloon text and apply only commands (surface/scope/etc.).
    func runNotifyScript(_ script: String, translationContext: ScriptTranslationContext = .baseware) {
        guard !Self.shouldIgnoreNumericEventResponse(script, eventID: translationContext.eventID) else {
            Log.info("[GhostManager] Ignoring numeric SHIORI notify response: event=\(translationContext.eventID ?? "unknown") value=\(script.trimmingCharacters(in: .whitespacesAndNewlines))")
            return
        }
        let translated = translateForDisplay(script, context: translationContext)
        runTranslatedNotifyScript(translated)
    }

    /// 既に翻訳済みのNOTIFY由来スクリプトを、再翻訳せず適用する。
    func runTranslatedNotifyScript(_ script: String) {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let hasText = sakuraEngine.containsTextInPreprocessedScript(trimmed)
        if hasText {
            recordBacklog(from: trimmed)
            beginPluginTalkNotification(script: trimmed, reasons: ["owned"])
            // New visible text: cancel pending playback and clear balloon
            playbackGeneration &+= 1
            playbackQueue.removeAll()
            isPlaying = false
            quickMode = false
            preciseBase = Date()
            timeCriticalActive = false
            choiceTimeoutDisabled = false
            pendingAnchorOpen = nil
            for vm in balloonViewModels.values {
                vm.resetBalloonContent()
            }
            resetScriptScopedBalloonSettings()
            resetVoiceSynthesisState()
        } else {
            // NOTIFY に本文がない場合も、設定コマンドだけをこのスクリプトの
            // 有効範囲として扱い、前のスクリプトの一時設定を持ち越さない。
            resetScriptScopedBalloonSettings()
        }
        let previousPluginOrigin = currentScriptIsPluginOrigin
        currentScriptIsPluginOrigin = false
        sakuraEngine.runPreprocessed(script: trimmed)
        currentScriptIsPluginOrigin = previousPluginOrigin
        startPlaybackIfNeeded()
    }

    func runPluginScript(_ script: String, options: Set<String>) {
        var reasons = options.intersection(["plugin-script", "plugin-event", "notranslate"])
        if reasons.isEmpty {
            reasons.insert("plugin-script")
        }
        let trimmed = translateForDisplay(script, context: .init(reasons: reasons))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recordBacklog(from: trimmed)
        if options.contains("nobreak") {
            beginPluginTalkNotification(script: trimmed, reasons: reasons)
            let previousPluginOrigin = currentScriptIsPluginOrigin
            currentScriptIsPluginOrigin = true
            sakuraEngine.runPreprocessed(script: trimmed)
            currentScriptIsPluginOrigin = previousPluginOrigin
            startPlaybackIfNeeded()
        } else {
            beginPluginTalkNotification(script: trimmed, reasons: reasons)
            playbackGeneration &+= 1
            playbackQueue.removeAll()
            isPlaying = false
            quickMode = false
            preciseBase = Date()
            timeCriticalActive = false
            choiceTimeoutDisabled = false
            pendingAnchorOpen = nil
            for vm in balloonViewModels.values {
                vm.resetBalloonContent()
            }
            resetScriptScopedBalloonSettings()
            resetVoiceSynthesisState()
            let previousPluginOrigin = currentScriptIsPluginOrigin
            currentScriptIsPluginOrigin = true
            sakuraEngine.runPreprocessed(script: trimmed)
            currentScriptIsPluginOrigin = previousPluginOrigin
            startPlaybackIfNeeded()
        }
    }

    func matchesPluginTarget(_ token: String) -> Bool {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        var candidates = [
            ghostURL.path,
            ghostURL.standardizedFileURL.path,
            ghostURL.lastPathComponent,
            ghostConfig?.name,
            ghostConfig?.id,
            ghostConfig?.title,
            ghostConfig?.sakuraName,
            ghostConfig?.keroName
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        candidates.append(contentsOf: characterWindows.values.map { String($0.windowNumber).lowercased() })
        return candidates.contains(normalized)
    }

    private func beginPluginTalkNotification(script: String, reasons: Set<String>, eventID: String = "", references: [String] = []) {
        guard sakuraEngine.containsText(in: script) else { return }
        let context = PluginTalkNotificationContext(script: script, reasons: reasons, eventID: eventID, references: references)
        pendingPluginTalkAfter = context
        emitPluginTalkNotification(context, phase: .before)
    }

    private func emitPluginTalkAfterIfNeeded() {
        guard let context = pendingPluginTalkAfter else { return }
        pendingPluginTalkAfter = nil
        emitPluginTalkNotification(context, phase: .after)
    }

    private func emitPluginTalkNotification(_ context: PluginTalkNotificationContext, phase: PluginOtherGhostTalkTiming) {
        guard !isEmittingPluginTalk,
              let dispatcher = (NSApp.delegate as? AppDelegate)?.pluginDispatcher else { return }
        isEmittingPluginTalk = true
        defer { isEmittingPluginTalk = false }
        let ghostName = ghostConfig?.name ?? ghostURL.lastPathComponent
        let baseName = ghostConfig?.sakuraName ?? ghostName
        dispatcher.onOtherGhostTalk(
            ghostName: ghostName,
            baseName: baseName,
            reasons: context.reasons.sorted().joined(separator: ","),
            eventID: context.eventID,
            script: context.script,
            refs: context.references,
            phase: phase
        )
    }

    // MARK: - SakuraScriptEngineDelegate

    func sakuraEngine(_ engine: SakuraScriptEngine, didEmit token: SakuraScriptEngine.Token) {
        // Enqueue tokens for playback with per-character typing delay for text
        NSLog("[GhostManager] sakuraEngine didEmit token: \(token)")
        switch token {
        case .scope(let id):
            playbackQueue.append(.scope(id))
        case .surface(let id):
            playbackQueue.append(.surface(id))
        case .surfaceNamed(let name):
            // \s[alias]: 文字列別名を surfaceNameAliases で解決して数値サーフェスへ
            if let id = surfaceNameAliases[name.lowercased()] {
                playbackQueue.append(.surface(id))
            } else {
                NSLog("[GhostManager] Unknown surface alias \(name) in \\s[...]")
            }
        case .text(let text):
            // Display text character by character with typing effect
            playbackQueue.append(.textToken(text))
            enqueueSpeech(for: text)
        case .newline:
            playbackQueue.append(.newline)
        case .newlineVariation(let type):
            // 可変改行も通常の改行と同じ再生キューに積む。
            // runPreprocessed はトークン列を同期的に列挙するため、ここで直接 ViewModel を
            // 更新すると、先行する文字より先に改行を適用したり、VM 未生成時に改行を落としたりする。
            playbackQueue.append(.newlineVariation(type))
        case .balloon(let id):
            // \bN or \b[ID] - change balloon ID
            Log.debug("[GhostManager] Switching to balloon ID: \(id)")
            playbackQueue.append(.deferredCommand { [weak self] in
                guard let self else { return }
                self.switchBalloon(to: id, scope: self.currentScope)
            })
        case .balloonWithFallback(let primary, let fallbacks):
            // \b[ID1,--fallback=ID2,...] - use the first installed balloon surface.
            let candidates = [primary] + fallbacks
            Log.debug("[GhostManager] Switching to balloon ID with fallbacks: \(candidates)")
            playbackQueue.append(.deferredCommand { [weak self] in
                guard let self else { return }
                self.switchBalloon(to: candidates, scope: self.currentScope)
            })
            
        case .appendMode:
            // \C - append to previous balloon
            Log.debug("[GhostManager] Append mode enabled - will not clear balloon text")
            appendModeEnabled = true
            // Append mode keeps the current balloon open and adds new text
            // The balloon view will continue displaying the previous content
         case .end:
            playbackQueue.append(.end)
        case .animation(let id, let wait):
            // \i[ID] or \i[ID,wait] - play surface animation
            // アニメーション開始自体も本文と同じ再生順序に置く。
            playbackQueue.append(.startAnimation(id: id, wait: wait))
        // New token types - added for comprehensive Sakura Script support
        case .wait:
            // \t - タイムクリティカルセクション（UKADOC）。
            // スクリプトブレークまたは \e までマウス系イベント通知を抑止する（ポーズではない）。
            playbackQueue.append(.deferredCommand { [weak self] in
                self?.timeCriticalActive = true
            })

        case .endConversation(let clearBalloon):
            // \x or \x[noclear] - End conversation
            playbackQueue.append(.clickWait(noclear: !clearBalloon))

        case .choiceCancel:
            // \z - Choice cancellation
            Log.debug("[GhostManager] Choice cancel marker")
            choiceHasCancelOption = true

        case .choiceMarker:
            // \* - このスクリプトの選択肢をタイムアウトさせない（UKADOC）
            Log.debug("[GhostManager] \\* - disabling choice timeout for this script")
            choiceTimeout = nil
            choiceTimeoutDisabled = true

        case .anchor:
            // \a - 旧仕様: OnAITalk（ランダムトーク）を発生させる（UKADOC）。
            // GET で送り、返値スクリプトがあれば再生する。
            Log.debug("[GhostManager] \\a - raising OnAITalk (legacy)")
            playbackQueue.append(.deferredCommand { [weak self] in
                guard let self else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let runtime = self.shioriRuntime,
                          let r = runtime.request(method: "GET", id: "OnAITalk", timeout: 3.0), r.ok,
                          let v = r.value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return }
                    DispatchQueue.main.async {
                        self.runScript(
                            v,
                            translationContext: .init(eventID: "OnAITalk")
                        )
                    }
                }
            })

        case .choiceLineBr:
            // \- - 当該ゴーストの終了（UKADOC）。先行テキストの表示後に終了処理を行う。
            Log.info("[GhostManager] \\- - ghost termination requested by script")
            playbackQueue.append(.deferredCommand { [weak self] in
                guard let self else { return }
                if self.closeSequenceCompletion != nil {
                    self.finishCloseSequence()
                } else {
                    self.finalizeTermination()
                }
            })

        case .choiceLegacy(let title, let id, let numbered):
            // 旧式 q[ID][title] / q*[ID][title]。* は表示上の通し番号。
            let displayTitle = numbered ? "\(pendingChoices.count + 1). \(title)" : title
            pendingChoices.append((
                title: displayTitle,
                action: .event(id: id, references: []),
                pluginOrigin: currentScriptIsPluginOrigin
            ))

        case .moveAway:
            // \4 - 相方キャラクターから離れる方向へ移動（UKADOC）
            playbackQueue.append(.moveAway)

        case .moveClose:
            // \5 - 相方キャラクターと接触する距離まで移動（UKADOC）
            playbackQueue.append(.moveClose)
        
        case .bootGhost:
            // \+ - Boot/call other ghost via SSTP
            // The ghost name should be specified in a following command or in context
            Log.debug("[GhostManager] Boot ghost command - attempting to boot ghost via SSTP")
            playbackQueue.append(.bootGhost)
        
        case .bootAllGhosts:
            // \_+ - sequential ghost switch (UKADOC). This is separate from
            // bootAllGhosts(), which remains an internal broadcast helper.
            Log.debug("[GhostManager] Sequential ghost switch command")
            playbackQueue.append(.bootAllGhosts)
        
        case .openPreferences:
            // \v - このスクリプト以降、最前面表示（stay-on-top）にする（UKADOC）。
            // 旧実装の「設定ウィンドウを開く」は誤り。
            playbackQueue.append(.deferredCommand { [weak self] in
                self?.setWindowState(state: "stayontop")
            })
        
        case .openURL:
            // \6 - execute SNTP correction action (ukadoc semantics)
            playbackQueue.append(.executeSNTPApply)
        
        case .openEmail:
            // \7 - begin SNTP sequence (same family as \![executesntp])
            playbackQueue.append(.executeSNTP)
        
        case .playSound(let filename):
            // \8[filename] - Play sound file
            playbackQueue.append(.playSound(filename))
        
        case .choiceQueue(let title, let id, let references):
            // \__q メタタグ（選択肢キュー）。title は範囲ベース構文の表示テキスト。
            // ID の取扱いは \q と同じ（script: プレフィックス / On* イベント）。
            if id.hasPrefix("script:") {
                let script = String(id.dropFirst(7))
                pendingChoices.append((title: title, action: .script(script), pluginOrigin: currentScriptIsPluginOrigin))
            } else {
                pendingChoices.append((title: title, action: .event(id: id, references: references), pluginOrigin: currentScriptIsPluginOrigin))
            }
        
        case .command(let name, let args):
            // SakuraScript タグは大文字小文字を区別する（\_V=再生完了待ち と \_v=再生 は別タグ）。
            // 下の switch は小文字化して照合するため、大文字を含むタグはここで先に分岐する。
            if name == "_V" {
                // \_V - 現在の音声・効果音・動画が完了するまで待つ。
                playbackQueue.append(.waitForAudio)
                break
            }
            switch name.lowercased() {
            case "w":
                if let first = args.first, let n = Int(first) {
                    if n >= 0 {
                        // Sakura Script の \w[N] は N×50ms。多桁値の末尾を本文へ
                        // 流すと、\w10 が「待機後に 0 を発話」するため禁止する。
                        playbackQueue.append(.wait(Double(n) * 0.05))
                    }
                } else {
                    // No arg: default pause
                    playbackQueue.append(.wait(defaultTypingInterval))
                }
            case "_w":
                if let first = args.first, let ms = Double(first) {
                    playbackQueue.append(.wait(ms/1000.0))
                }
            case "__w":
                if let first = args.first?.lowercased() {
                    if first == "clear" {
                        playbackQueue.append(.resetPrecise)
                    } else if first == "animation" {
                        // \__w[animation,ID] – wait until SERIKO animation with ID completes
                        if args.count >= 2, let animID = Int(args[1]) {
                            playbackQueue.append(.waitAnimation(animID))
                        }
                    } else if let ms = Double(first) {
                        playbackQueue.append(.waitUntil(ms/1000.0))
                    }
                }
            case "x":
                let noclear = (args.first?.lowercased() == "noclear")
                playbackQueue.append(.clickWait(noclear: noclear))
            case "_q":
                playbackQueue.append(.toggleQuickMode)
            case "__t":
                // \__t メタタグ: 教えてダイアログを開く（\![open,teachbox] と同等）
                playbackQueue.append(.deferredCommand {
                    DispatchQueue.main.async { self.showTeachBoxDialog() }
                })
            case "__c":
                // \__c メタタグ: CommunicateBox を開く（\![open,communicatebox] と同等）
                playbackQueue.append(.deferredCommand {
                    DispatchQueue.main.async { self.showCommunicateBoxDialog(timeoutMs: nil, initialText: "") }
                })
            case "_n":
                // \_n: 次の \_n まで自動折り返しを抑止する。
                // パース時ではなく再生キュー上で反映し、範囲内の本文だけに適用する。
                playbackQueue.append(.deferredCommand { [weak self] in
                    guard let self else { return }
                    let vm = self.getBalloonVM(for: self.currentScope)
                    vm.wordWrapEnabled.toggle()
                    Log.debug("[GhostManager] \\_n word wrap: \(vm.wordWrapEnabled)")
                })
            case "__v":
                // \__v[disable]...\__v / \__v[alternate,よみ]...\__v
                // パースだけで捨てず、後続テキストの音声合成状態へ反映する。
                playbackQueue.append(.voiceCommand(args))
            case "!":
                NSLog("[GhostManager] ! command with args: \(args)")
                if let first = args.first?.lowercased() {
                    NSLog("[GhostManager] ! command first arg: \(first)")
                    if first == "raise" {
                        // \![raise,イベント名,Reference0,Reference1,...]
                        // raise は GET の返答スクリプトを現在のゴーストへ反映する。
                        if args.count >= 2 {
                            let eventName = args[1]
                            let refs = Array(args.dropFirst(2))
                            playbackQueue.append(.deferredCommand { [weak self] in
                                self?.dispatchLocalEvent(
                                    event: eventName,
                                    references: refs,
                                    notifyOnly: false,
                                    preserveFollowingPlayback: true
                                )
                            })
                        }
                    } else if first == "notify", args.count >= 2 {
                        // \![notify,event,ref0,ref1,...]
                        let eventName = args[1]
                        let refs = Array(args.dropFirst(2))
                        playbackQueue.append(.deferredCommand { [weak self] in
                            self?.dispatchLocalEvent(event: eventName, references: refs, notifyOnly: true)
                        })
                    } else if first == "raiseother", args.count >= 3 {
                        // \![raiseother,ghost,event,ref0,ref1,...]
                        let ghostSpec = args[1]
                        let eventName = args[2]
                        let refs = Array(args.dropFirst(3))
                        playbackQueue.append(.deferredCommand { [weak self] in
                            self?.raiseOtherGhostEvent(ghostSpec: ghostSpec, event: eventName, references: refs, notifyOnly: false)
                        })
                    } else if first == "embed", args.count >= 2 {
                        // \![embed,event,ref0,ref1,...]
                        let eventName = args[1]
                        let refs = Array(args.dropFirst(2))
                        playbackQueue.append(.embeddedEvent(event: eventName, references: refs))
                    } else if first == "timerraise", args.count >= 4 {
                        // \![timerraise,ms,repeat,event,ref0,ref1,...]
                        let intervalMs = Int(args[1]) ?? 0
                        let repeatSpec = args[2]
                        let eventName = args[3]
                        let refs = Array(args.dropFirst(4))
                        playbackQueue.append(.deferredCommand { [weak self] in
                            self?.scheduleLocalEventTimer(intervalMs: intervalMs, repeatSpec: repeatSpec, event: eventName, references: refs, notifyOnly: false)
                        })
                    } else if first == "timernotify", args.count >= 4 {
                        // \![timernotify,ms,repeat,event,ref0,ref1,...]
                        let intervalMs = Int(args[1]) ?? 0
                        let repeatSpec = args[2]
                        let eventName = args[3]
                        let refs = Array(args.dropFirst(4))
                        playbackQueue.append(.deferredCommand { [weak self] in
                            self?.scheduleLocalEventTimer(intervalMs: intervalMs, repeatSpec: repeatSpec, event: eventName, references: refs, notifyOnly: true)
                        })
                    } else if first == "timerraiseother", args.count >= 5 {
                        // \![timerraiseother,ms,repeat,ghost,event,ref0,ref1,...]
                        let intervalMs = Int(args[1]) ?? 0
                        let repeatSpec = args[2]
                        let ghostSpec = args[3]
                        let eventName = args[4]
                        let refs = Array(args.dropFirst(5))
                        playbackQueue.append(.deferredCommand { [weak self] in
                            self?.scheduleTimerRaiseOther(intervalMs: intervalMs, repeatSpec: repeatSpec, ghostSpec: ghostSpec, event: eventName, references: refs, notifyOnly: false)
                        })
                    } else if first == "raiseplugin", args.count >= 3 {
                        // \![raiseplugin,plugin,event,ref0,ref1,...]
                        let pluginSpec = args[1]
                        let eventName = args[2]
                        let refs = Array(args.dropFirst(3))
                        playbackQueue.append(.deferredCommand { [weak self] in
                            self?.dispatchPluginEvent(pluginSpec: pluginSpec, event: eventName, references: refs, notifyOnly: false)
                        })
                    } else if first == "timerraiseplugin", args.count >= 5 {
                        // \![timerraiseplugin,ms,repeat,plugin,event,ref0,ref1,...]
                        let intervalMs = Int(args[1]) ?? 0
                        let repeatSpec = args[2]
                        let pluginSpec = args[3]
                        let eventName = args[4]
                        let refs = Array(args.dropFirst(5))
                        playbackQueue.append(.deferredCommand { [weak self] in
                            self?.scheduleTimerPluginEvent(intervalMs: intervalMs, repeatSpec: repeatSpec, pluginSpec: pluginSpec, event: eventName, references: refs, notifyOnly: false)
                        })
                    } else if first == "notifyother", args.count >= 3 {
                        // \![notifyother,ghost,event,ref0,ref1,...]
                        let ghostSpec = args[1]
                        let eventName = args[2]
                        let refs = Array(args.dropFirst(3))
                        playbackQueue.append(.deferredCommand { [weak self] in
                            self?.raiseOtherGhostEvent(ghostSpec: ghostSpec, event: eventName, references: refs, notifyOnly: true)
                        })
                    } else if first == "timernotifyother", args.count >= 5 {
                        // \![timernotifyother,ms,repeat,ghost,event,ref0,ref1,...]
                        let intervalMs = Int(args[1]) ?? 0
                        let repeatSpec = args[2]
                        let ghostSpec = args[3]
                        let eventName = args[4]
                        let refs = Array(args.dropFirst(5))
                        playbackQueue.append(.deferredCommand { [weak self] in
                            self?.scheduleTimerRaiseOther(intervalMs: intervalMs, repeatSpec: repeatSpec, ghostSpec: ghostSpec, event: eventName, references: refs, notifyOnly: true)
                        })
                    } else if first == "notifyplugin", args.count >= 3 {
                        // \![notifyplugin,plugin,event,ref0,ref1,...]
                        let pluginSpec = args[1]
                        let eventName = args[2]
                        let refs = Array(args.dropFirst(3))
                        playbackQueue.append(.deferredCommand { [weak self] in
                            self?.dispatchPluginEvent(pluginSpec: pluginSpec, event: eventName, references: refs, notifyOnly: true)
                        })
                    } else if first == "timernotifyplugin", args.count >= 5 {
                        // \![timernotifyplugin,ms,repeat,plugin,event,ref0,ref1,...]
                        let intervalMs = Int(args[1]) ?? 0
                        let repeatSpec = args[2]
                        let pluginSpec = args[3]
                        let eventName = args[4]
                        let refs = Array(args.dropFirst(5))
                        playbackQueue.append(.deferredCommand { [weak self] in
                            self?.scheduleTimerPluginEvent(intervalMs: intervalMs, repeatSpec: repeatSpec, pluginSpec: pluginSpec, event: eventName, references: refs, notifyOnly: true)
                        })
                    } else if first == "change", args.count >= 3 {
                        // \![change,ghost|shell|balloon,target]
                        let target = args[1].lowercased()
                        let value = args[2]
                        let options = Array(args.dropFirst(3))
                        playbackQueue.append(.deferredCommand { [weak self] in
                            guard let self else { return }
                            switch target {
                            case "ghost":
                                self.switchGhost(named: value, options: options)
                            case "shell":
                                _ = self.switchShell(named: value, raiseEvent: options.contains("--option=raise-event"))
                            case "balloon":
                                _ = self.switchBalloon(named: value, scope: self.currentScope, raiseEvent: options.contains("--option=raise-event"))
                            default:
                                Log.info("[GhostManager] Unsupported change target: \(target)")
                            }
                        })
                    } else if first == "call", args.count >= 3 {
                        // \![call,ghost,target(,--option=raise-event)]
                        let target = args[1].lowercased()
                        let value = args[2]
                        let options = Array(args.dropFirst(3))
                        playbackQueue.append(.deferredCommand { [weak self] in
                            guard let self, target == "ghost" else { return }
                            self.callGhost(named: value, options: options)
                        })
                    } else if first == "get", args.count >= 2 {
                        let getType = args[1].lowercased()
                        if getType == "property", args.count >= 4 {
                            // \![get,property,イベント名,プロパティ名,...]
                            // UKADOC: 指定イベントをGETで発生させ、各プロパティ値を
                            // Reference0以降へ1つずつ渡す。
                            let eventName = args[2]
                            let propertyKeys = Array(args.dropFirst(3))
                            playbackQueue.append(.deferredCommand { [weak self] in
                                guard let self else { return }
                                let references = propertyKeys.map { self.sakuraEngine.propertyManager.get($0) ?? "" }
                                Log.debug("[GhostManager] Property get: \(propertyKeys.count) values, raising GET event: \(eventName)")
                                _ = self.requestDialogEvent(eventID: eventName, references: references)
                            })
                        } else {
                            let eventByGetType: [String: String] = [
                                "word": "OnGetWord",
                                "string": "OnGetString",
                                "integer": "OnGetInteger",
                                "wordcount": "OnGetWordCount",
                                "wordposition": "OnGetWordPosition"
                            ]
                            if let eventID = eventByGetType[getType] {
                                let references = Array(args.dropFirst(2))
                                playbackQueue.append(.deferredCommand { [weak self] in
                                    guard let self else { return }
                                    Log.debug("[GhostManager] Dispatching SHIORI GET event: \(eventID), refs=\(references.count)")
                                    _ = self.requestDialogEvent(eventID: eventID, references: references)
                                })
                            }
                        }
                    } else if first == "set", args.count >= 3, args[1].lowercased() == "property" {
                        // \![set,property,プロパティ名,値]
                        // Set property value
                        let propertyKey = args[2]
                        let propertyValue = args.count >= 4 ? args[3] : ""
                        playbackQueue.append(.deferredCommand { [weak self] in
                            guard let self else { return }
                            let success = self.sakuraEngine.propertyManager.set(propertyKey, value: propertyValue)
                            Log.debug("[GhostManager] Property set: \(propertyKey) = \(propertyValue), success: \(success)")
                        })
                    } else if first == "save", args.count >= 2, args[1].lowercased() == "wallpaper" {
                        // \![save,wallpaper] - save the current desktop wallpaper URLs
                        playbackQueue.append(.deferredCommand { [weak self] in
                            self?.saveWallpaper()
                        })
                    } else if first == "restore", args.count >= 2, args[1].lowercased() == "wallpaper" {
                        // \![restore,wallpaper] - restore the saved desktop wallpaper URLs
                        playbackQueue.append(.deferredCommand { [weak self] in
                            self?.restoreWallpaper()
                        })
                    } else if first == "quicksection", args.count >= 2 {
                        let v = args[1].lowercased()
                        playbackQueue.append(.setQuickMode(v == "1" || v == "true"))
                    } else if first == "wait", args.count >= 2, args[1].lowercased() == "syncobject" {
                        let name = args.count >= 3 ? args[2] : ""
                        let timeout = args.count >= 4 ? (Double(args[3]) ?? 0) : 0
                        let delay = timeout <= 0 ? TimeInterval.infinity : timeout/1000.0
                        playbackQueue.append(.waitForSyncObject(
                            name: name,
                            timeout: delay,
                            generation: playbackGeneration
                        ))
                    } else if first == "wait", args.count >= 2, args[1].lowercased() == "timer" {
                        // \![wait,timer,ms]
                        if args.count >= 3, let ms = Double(args[2]) {
                            playbackQueue.append(.wait(max(0, ms / 1000.0)))
                        }
                    } else if first == "signal", args.count >= 2, args[1].lowercased() == "syncobject" {
                        let name = args.count >= 3 ? args[2] : ""
                        playbackQueue.append(.deferredCommand {
                            SyncCenter.shared.signal(name: name)
                        })
                    } else if first == "input", args.count >= 2 {
                        // Compatibility aliases: \![input,*]
                        let inputType = args[1].lowercased()
                        let rawInputArguments = Array(args.dropFirst(2))
                        let parsed = parseCommandArguments(rawInputArguments)
                        let inputOptions = inputDialogOptions(from: rawInputArguments)
                        let id = parsed.positionals.first ?? parsed.options["id"] ?? "input"
                        let timeoutMs = parsed.options["timeout"].flatMap(Int.init)
                            ?? (parsed.positionals.count >= 2 ? Int(parsed.positionals[1]) : nil)

                        if inputType == "textbox" || inputType == "text" {
                            let initialText = parsed.options["text"]
                                ?? (parsed.positionals.count >= 3 ? parsed.positionals[2] : "")
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showInputBoxDialog(id: id, timeoutMs: timeoutMs, initialText: initialText, options: inputOptions)
                                }
                            })
                        } else if inputType == "pass" || inputType == "password" {
                            let initialText = parsed.options["text"]
                                ?? (parsed.positionals.count >= 3 ? parsed.positionals[2] : "")
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showPasswordInputDialog(id: id, timeoutMs: timeoutMs, initialText: initialText, options: inputOptions)
                                }
                            })
                        } else if inputType == "date" {
                            let csv = parsed.options["text"]?.split(separator: ",").map(String.init) ?? []
                            let year = csv.count >= 1 ? Int(csv[0]) : (parsed.positionals.count >= 3 ? Int(parsed.positionals[2]) : nil)
                            let month = csv.count >= 2 ? Int(csv[1]) : (parsed.positionals.count >= 4 ? Int(parsed.positionals[3]) : nil)
                            let day = csv.count >= 3 ? Int(csv[2]) : (parsed.positionals.count >= 5 ? Int(parsed.positionals[4]) : nil)
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showDateInputDialog(id: id, timeoutMs: timeoutMs, year: year, month: month, day: day, options: inputOptions)
                                }
                            })
                        } else if inputType == "choice" {
                            let choices = parsed.positionals.count >= 3
                                ? Array(parsed.positionals.dropFirst(2))
                                : parsed.options["choices"]?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } ?? []
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showChoiceInputDialog(id: id, timeoutMs: timeoutMs, choices: choices, options: inputOptions)
                                }
                            })
                        } else if inputType == "capture" {
                            // Minimal compatibility: route to text input and raise OnUserInput.
                            let initialText = parsed.options["text"]
                                ?? (parsed.positionals.count >= 3 ? parsed.positionals[2] : "")
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showInputBoxDialog(id: id, timeoutMs: timeoutMs, initialText: initialText, options: inputOptions)
                                }
                            })
                        }
                    } else if first == "file", args.count >= 2 {
                        let fileAction = args[1].lowercased()
                        if fileAction == "open" {
                            let eventID = args.count >= 3 ? args[2] : ""
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showSystemDialog(type: "open", parameters: ["--id=\(eventID)"])
                                }
                            })
                        } else if fileAction == "save" {
                            let eventID = args.count >= 3 ? args[2] : ""
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showSystemDialog(type: "save", parameters: ["--id=\(eventID)"])
                                }
                            })
                        }
                    } else if first == "hide" {
                        setCurrentWindowHidden(true)
                    } else if first == "show" {
                        setCurrentWindowHidden(false)
                    } else if first == "focus" {
                        focusCurrentWindow()
                    } else if first == "b" {
                        // \![b] compatibility: bring/focus current window.
                        focusCurrentWindow()
                    } else if first == "minimize" {
                        setWindowState(state: "minimize")
                    } else if first == "maximize" {
                        maximizeCurrentWindow()
                    } else if ["*", "#", "x", "<", ">"].contains(first) {
                        // \![*] は choice marker ではなく、バルーンに設定された
                        // SSTP/通信マーカーを表示するコマンド（%* も同じ経路）。
                        let marker: String
                        switch first {
                        case "*": marker = "*"
                        case "#": marker = "#"
                        case "x": marker = "X"
                        case "<": marker = "<"
                        case ">": marker = ">"
                        default: marker = first
                        }
                        setBalloonMarker(marker)
                    } else if first == "open", args.count >= 2 {
                        let openType = args[1].lowercased()
                        switch openType {
                        case "configurationdialog", "config":
                            // \![open,configurationdialog,setup] / \![open,config,setup]
                            if args.count >= 3, args[2].lowercased() == "setup" {
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async { self.showNameInputDialog() }
                                })
                            } else {
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async { self.showSettings() }
                                })
                            }
                        case "inputbox":
                            let rawInputArguments = Array(args.dropFirst(2))
                            let parsed = parseCommandArguments(rawInputArguments)
                            let inputOptions = inputDialogOptions(from: rawInputArguments)
                            let id = parsed.positionals.first ?? parsed.options["id"] ?? "inputbox"
                            let timeoutMs = parsed.options["timeout"].flatMap(Int.init)
                                ?? (parsed.positionals.count >= 2 ? Int(parsed.positionals[1]) : nil)
                            let initialText = parsed.options["text"]
                                ?? (parsed.positionals.count >= 3 ? parsed.positionals[2] : "")
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showInputBoxDialog(id: id, timeoutMs: timeoutMs, initialText: initialText, options: inputOptions)
                                }
                            })
                        case "passwordinput":
                            let rawInputArguments = Array(args.dropFirst(2))
                            let parsed = parseCommandArguments(rawInputArguments)
                            let inputOptions = inputDialogOptions(from: rawInputArguments)
                            let id = parsed.positionals.first ?? parsed.options["id"] ?? "passwordinput"
                            let timeoutMs = parsed.options["timeout"].flatMap(Int.init)
                                ?? (parsed.positionals.count >= 2 ? Int(parsed.positionals[1]) : nil)
                            let initialText = parsed.options["text"]
                                ?? (parsed.positionals.count >= 3 ? parsed.positionals[2] : "")
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showPasswordInputDialog(id: id, timeoutMs: timeoutMs, initialText: initialText, options: inputOptions)
                                }
                            })
                        case "dateinput":
                            let rawInputArguments = Array(args.dropFirst(2))
                            let parsed = parseCommandArguments(rawInputArguments)
                            let inputOptions = inputDialogOptions(from: rawInputArguments)
                            let id = parsed.positionals.first ?? parsed.options["id"] ?? "dateinput"
                            let timeoutMs = parsed.options["timeout"].flatMap(Int.init)
                                ?? (parsed.positionals.count >= 2 ? Int(parsed.positionals[1]) : nil)
                            let csv = parsed.options["text"]?.split(separator: ",").map(String.init) ?? []
                            let year = csv.count >= 1 ? Int(csv[0]) : (parsed.positionals.count >= 3 ? Int(parsed.positionals[2]) : nil)
                            let month = csv.count >= 2 ? Int(csv[1]) : (parsed.positionals.count >= 4 ? Int(parsed.positionals[3]) : nil)
                            let day = csv.count >= 3 ? Int(csv[2]) : (parsed.positionals.count >= 5 ? Int(parsed.positionals[4]) : nil)
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showDateInputDialog(id: id, timeoutMs: timeoutMs, year: year, month: month, day: day, options: inputOptions)
                                }
                            })
                        case "sliderinput":
                            let rawInputArguments = Array(args.dropFirst(2))
                            let parsed = parseCommandArguments(rawInputArguments)
                            let inputOptions = inputDialogOptions(from: rawInputArguments)
                            let id = parsed.positionals.first ?? parsed.options["id"] ?? "sliderinput"
                            let timeoutMs = parsed.options["timeout"].flatMap(Int.init)
                                ?? (parsed.positionals.count >= 2 ? Int(parsed.positionals[1]) : nil)
                            let csv = parsed.options["text"]?.split(separator: ",").map(String.init) ?? []
                            let initial = csv.count >= 1 ? Double(csv[0]) : (parsed.positionals.count >= 3 ? Double(parsed.positionals[2]) : nil)
                            let min = csv.count >= 2 ? Double(csv[1]) : (parsed.positionals.count >= 4 ? Double(parsed.positionals[3]) : nil)
                            let max = csv.count >= 3 ? Double(csv[2]) : (parsed.positionals.count >= 5 ? Double(parsed.positionals[4]) : nil)
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showSliderInputDialog(id: id, timeoutMs: timeoutMs, initial: initial, min: min, max: max, options: inputOptions)
                                }
                            })
                        case "timeinput":
                            let rawInputArguments = Array(args.dropFirst(2))
                            let parsed = parseCommandArguments(rawInputArguments)
                            let inputOptions = inputDialogOptions(from: rawInputArguments)
                            let id = parsed.positionals.first ?? parsed.options["id"] ?? "timeinput"
                            let timeoutMs = parsed.options["timeout"].flatMap(Int.init)
                                ?? (parsed.positionals.count >= 2 ? Int(parsed.positionals[1]) : nil)
                            let csv = parsed.options["text"]?.split(separator: ",").map(String.init) ?? []
                            let hour = csv.count >= 1 ? Int(csv[0]) : (parsed.positionals.count >= 3 ? Int(parsed.positionals[2]) : nil)
                            let minute = csv.count >= 2 ? Int(csv[1]) : (parsed.positionals.count >= 4 ? Int(parsed.positionals[3]) : nil)
                            let second = csv.count >= 3 ? Int(csv[2]) : (parsed.positionals.count >= 5 ? Int(parsed.positionals[4]) : nil)
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showTimeInputDialog(id: id, timeoutMs: timeoutMs, hour: hour, minute: minute, second: second, options: inputOptions)
                                }
                            })
                        case "ipinput":
                            let rawInputArguments = Array(args.dropFirst(2))
                            let parsed = parseCommandArguments(rawInputArguments)
                            let inputOptions = inputDialogOptions(from: rawInputArguments)
                            let id = parsed.positionals.first ?? parsed.options["id"] ?? "ipinput"
                            let timeoutMs = parsed.options["timeout"].flatMap(Int.init)
                                ?? (parsed.positionals.count >= 2 ? Int(parsed.positionals[1]) : nil)
                            let initialText: String = {
                                if let text = parsed.options["text"] {
                                    return text
                                }
                                if parsed.positionals.count >= 6 {
                                    return parsed.positionals[2...5].joined(separator: ",")
                                }
                                return parsed.positionals.count >= 3 ? parsed.positionals[2] : ""
                            }()
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showIPInputDialog(id: id, timeoutMs: timeoutMs, initialText: initialText, options: inputOptions)
                                }
                            })
                        case "dialog":
                            if args.count >= 3 {
                                let dialogType = args[2].lowercased()
                                let params = Array(args.dropFirst(3))
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async {
                                        self.showSystemDialog(type: dialogType, parameters: params)
                                    }
                                })
                            }
                        case "teachbox":
                            // \![open,teachbox]
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showTeachBoxDialog()
                                }
                            })
                        case "communicatebox":
                            let rawCommunicateArguments = Array(args.dropFirst(2))
                            let parsed = parseCommandArguments(rawCommunicateArguments)
                            let initialText = parsed.options["text"] ?? parsed.positionals.first ?? ""
                            let timeoutMs = parsed.options["timeout"].flatMap(Int.init)
                                ?? (parsed.positionals.count >= 2 ? Int(parsed.positionals[1]) : nil)
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showCommunicateBoxDialog(timeoutMs: timeoutMs, initialText: initialText)
                                }
                            })
                        case "addressbar":
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openAddressBar() }
                            })
                        case "errorlog":
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openErrorLogViewer() }
                            })
                        case "pictureviewer":
                            let path = args.count >= 3 ? args[2] : nil
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openPictureViewer(path: path) }
                            })
                        case "archiveviewer":
                            let path = args.count >= 3 ? args[2] : nil
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openArchiveViewer(path: path) }
                            })
                        case "backlogviewer":
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openBacklogViewer() }
                            })
                        case "browser":
                            if args.count >= 3 {
                                let target = args[2]
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async { self.openURL(target) }
                                })
                            }
                        case "http":
                            if args.count >= 3 {
                                let params = Array(args.dropFirst(2))
                                executeHTTP(subcommand: "http-get", params: params)
                            }
                        case "send":
                            if args.count >= 3 {
                                let target = args[2]
                                let body = args.count >= 4 ? args[3] : ""
                                executeHTTP(subcommand: "http-post", params: [target, body])
                            }
                        case "mailer":
                            if args.count >= 3 {
                                let target = args[2]
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async { self.openEmail(target) }
                                })
                            }
                        case "editor", "file":
                            let parsed = parseCommandArguments(Array(args.dropFirst(2)))
                            let path = parsed.positionals.first ?? parsed.options["path"] ?? ""
                            if !path.isEmpty {
                                let line = parsed.options["line"].flatMap(Int.init)
                                    ?? (parsed.positionals.count >= 2 ? Int(parsed.positionals[1]) : nil)
                                let app = parsed.options["app"]
                                let allowExternal = parsed.flags.contains("allow-external")
                                    || (parsed.options["allow-external"]?.lowercased() == "1")
                                    || (parsed.options["allow-external"]?.lowercased() == "true")
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async {
                                        self.openFilePath(path: path, line: line, appName: app, allowExternal: allowExternal)
                                    }
                                })
                            }
                        case "explorer":
                            if args.count >= 4 {
                                let kind = args[2].lowercased()
                                let name = args[3]
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async { self.openInstalledTypeDirectory(type: kind, name: name) }
                                })
                            } else if args.count >= 3 {
                                let path = args[2]
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async { self.revealInExplorer(path) }
                                })
                            }
                        case "ghostexplorer":
                            let name = args.count >= 3 ? args[2] : nil
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openInstalledTypeDirectory(type: "ghost", name: name) }
                            })
                        case "shellexplorer":
                            let name = args.count >= 3 ? args[2] : nil
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openInstalledTypeDirectory(type: "shell", name: name) }
                            })
                        case "balloonexplorer":
                            let name = args.count >= 3 ? args[2] : nil
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openInstalledTypeDirectory(type: "balloon", name: name) }
                            })
                        case "headlinesensorexplorer":
                            let name = args.count >= 3 ? args[2] : nil
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openInstalledTypeDirectory(type: "headline", name: name) }
                            })
                        case "pluginexplorer":
                            let name = args.count >= 3 ? args[2] : nil
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openInstalledTypeDirectory(type: "plugin", name: name) }
                            })
                        case "calendar":
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openInstalledTypeDirectory(type: "calendar") }
                            })
                        case "rateofusegraph", "rateofusegraphballoon", "rateofusegraphtotal":
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openRateOfUseGraph(kind: openType) }
                            })
                        case "messenger":
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.showCommunicateBox() }
                            })
                        case "readme":
                            let readmeType = args.count >= 3 ? args[2] : nil
                            let readmeName = args.count >= 4 ? args[3] : nil
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.openGhostReadme(type: readmeType, name: readmeName)
                                }
                            })
                        case "terms":
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.handleGhostTermsConsent() }
                            })
                        case "help":
                            let helpID = args.count >= 3 ? args[2] : nil
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openHelp(dialogID: helpID) }
                            })
                        case "developer", "shiorirequest", "dressupexplorer":
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openDeveloperTool(openType) }
                            })
                        case "surfacetest":
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openSurfaceTestWindow() }
                            })
                        case "aigraph":
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openAIGraph() }
                            })
                        default:
                            // \![open,URL] は未知のサブコマンドとして捨てず、URLとして委譲する。
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openURL(args[1]) }
                            })
                        }
                    } else if first == "close", args.count >= 2 {
                        let closeType = args[1].lowercased()
                        switch closeType {
                        case "inputbox":
                            let id = args.count >= 3 ? args[2] : "inputbox"
                            _ = closeInputDialog(id: id)
                        case "communicatebox":
                            closeCommunicateBoxDialog()
                        case "dialog":
                            let id = args.count >= 3 ? args[2] : ""
                            emitSystemDialogCancel(type: "dialog", eventID: id)
                        case "teachbox":
                            // スクリプトから閉じた場合は OnTeachInputCancel を発生させない。
                            closeTeachBoxDialog()
                        case "websocket":
                            closeWebSocket(params: Array(args.dropFirst(2)))
                        default:
                            break
                        }
                    } else if first == "send", args.count >= 2 {
                        // \![send,websocket,URL,data] / \![send,websocket-binary,URL,base64]
                        let sendType = args[1].lowercased()
                        if sendType == "websocket" {
                            sendWebSocket(params: Array(args.dropFirst(2)), binary: false)
                        } else if sendType == "websocket-binary" {
                            sendWebSocket(params: Array(args.dropFirst(2)), binary: true)
                        }
                    } else if first == "cancel", args.count >= 2 {
                        // \![cancel,websocket,URL] / \![cancel,http,URL]
                        let cancelType = args[1].lowercased()
                        if cancelType == "websocket" {
                            cancelWebSocket(params: Array(args.dropFirst(2)))
                        } else if cancelType == "http" {
                            cancelHTTPStreaming(params: Array(args.dropFirst(2)))
                        }
                    } else if first == "enter", args.count >= 2 {
                        let enterType = args[1].lowercased()
                        switch enterType {
                        case "selectmode":
                            let params = Array(args.dropFirst(2))
                            enterSelectMode(params: params)
                        case "selectrect":
                            let params = Array(args.dropFirst(2))
                            enterSelectMode(params: ["rect"] + params)
                        case "collisionmode":
                            enterCollisionMode()
                        case "passivemode":
                            enterPassiveMode()
                        case "inductionmode":
                            let params = Array(args.dropFirst(2))
                            enterInductionMode(params: params)
                        case "nouserbreakmode":
                            enterNoUserBreakMode()
                        case "onlinemode":
                            enterOnlineMode(scope: currentScope)
                        default:
                            break
                        }
                    } else if first == "leave", args.count >= 2 {
                        let leaveType = args[1].lowercased()
                        switch leaveType {
                        case "selectmode":
                            let params = Array(args.dropFirst(2))
                            leaveSelectMode(params: params)
                        case "collisionmode":
                            leaveCollisionMode()
                        case "passivemode":
                            leavePassiveMode()
                        case "inductionmode":
                            leaveInductionMode()
                        case "nouserbreakmode":
                            leaveNoUserBreakMode()
                        case "onlinemode":
                            leaveOnlineMode(scope: currentScope)
                        default:
                            break
                        }
                    } else if first == "sound", args.count >= 2 {
                        // \![sound,*]
                        let subcmd = args[1].lowercased()
                        switch subcmd {
                        case "play":
                            if args.count >= 3 {
                                let filename = args[2]
                                let options = Array(args.dropFirst(3))
                                if GhostManager.isVideoFile(filename) {
                                    playVideo(filename: filename, loop: false, options: options)
                                } else {
                                    playSound(filename: filename, loop: false, options: options)
                                }
                            }
                        case "load":
                            if args.count >= 3 {
                                let filename = args[2]
                                let options = Array(args.dropFirst(3))
                                if GhostManager.isVideoFile(filename) {
                                    loadVideo(filename: filename, options: options)
                                } else {
                                    loadSound(filename: filename, options: options)
                                }
                            }
                        case "loop":
                            if args.count >= 3 {
                                let filename = args[2]
                                let options = Array(args.dropFirst(3))
                                if GhostManager.isVideoFile(filename) {
                                    playVideo(filename: filename, loop: true, options: options)
                                } else {
                                    playSound(filename: filename, loop: true, options: options)
                                }
                            }
                        case "wait":
                            // UKADOC: sound,wait is equivalent to _V.  It must be
                            // evaluated during playback, after preceding play/load
                            // commands have taken effect, not while the whole script
                            // is still being tokenized.
                            playbackQueue.append(.waitForAudio)
                        case "cdplay":
                            let track = args.count >= 3 ? args[2] : ""
                            let filename = track.isEmpty ? "audio-cd" : "audio-cd-track-\(track)"
                            Log.info("[GhostManager] sound,cdplay is unavailable on macOS: track=\(track)")
                            notifySoundError(command: "cdplay", filename: filename, code: -2, message: "audio_cd_unsupported")
                        case "pause":
                            let filename = args.count >= 3 ? args[2] : nil
                            if let filename, GhostManager.isVideoFile(filename) {
                                pauseVideo(filename: filename)
                            } else {
                                pauseSound(filename: filename)
                                if filename == nil {
                                    pauseVideo(filename: nil)
                                }
                            }
                        case "resume":
                            let filename = args.count >= 3 ? args[2] : nil
                            if let filename, GhostManager.isVideoFile(filename) {
                                resumeVideo(filename: filename)
                            } else {
                                resumeSound(filename: filename)
                                if filename == nil {
                                    resumeVideo(filename: nil)
                                }
                            }
                        case "stop":
                            if args.count >= 3 {
                                let filename = args[2]
                                if GhostManager.isVideoFile(filename) {
                                    stopVideo(filename: filename)
                                } else {
                                    stopSound(filename: filename)
                                }
                            } else {
                                stopAllSounds()
                            }
                        case "option":
                            if args.count >= 3 {
                                let filename = args[2]
                                let options = Array(args.dropFirst(3))
                                applySoundOptions(filename: filename, options: options)
                            }
                        default:
                            break
                        }
                    } else if first == "set", args.count >= 2 {
                        // Handle \![set,*] commands
                        let subcmd = args[1].lowercased()
                        switch subcmd {
                        case "scaling":
                            executeSetScalingCommand(args: args)
                        case "syncobject":
                            if args.count >= 3 {
                                SyncCenter.shared.set(name: args[2])
                            }
                        case "alpha":
                            executeSetAlphaCommand(args: args)
                        case "alignmentondesktop", "alignmenttodesktop":
                            // \![set,alignmenttodesktop,direction]
                            if args.count >= 3 {
                                let direction = args[2].lowercased()
                                DispatchQueue.main.async {
                                    guard let vm = self.characterViewModels[self.currentScope],
                                          self.characterWindows[self.currentScope] != nil else { return }

                                    switch direction {
                                    case "top": vm.alignment = .top
                                    case "bottom": vm.alignment = .bottom
                                    case "left": vm.alignment = .left
                                    case "right": vm.alignment = .right
                                    case "free": vm.alignment = .free
                                    case "default": vm.alignment = .free
                                    default: break
                                    }
                                    
                                    // Apply desktop alignment constraint
                                    self.enforceDesktopAlignment(for: self.currentScope)
                                }
                            }
                        case "position":
                            // \![set,position,x,y,scopeID]
                            if args.count >= 5, let x = Int(args[2]), let y = Int(args[3]), let scopeID = Int(args[4]) {
                                setWindowPosition(x: x, y: y, scopeID: scopeID)
                            }
                        case "zorder":
                            executeSetZOrderCommand(args: args)
                        case "sticky-window":
                            executeSetStickyWindowCommand(args: args)
                        case "timerinterval":
                            if args.count >= 3, let ms = Double(args[2]) {
                                typingInterval = max(0, ms / 1000.0)
                            }
                        case "balloonoffset":
                            // \![set,balloonoffset,x,y]
                            if args.count >= 4 {
                                let xValue = args[2]
                                let yValue = args[3]
                                let isRelative = xValue.hasPrefix("@") || yValue.hasPrefix("@")
                                handleBalloonOffset(x: xValue, y: yValue, isRelative: isRelative)
                            }
                        case "balloonalign":
                            // \![set,balloonalign,direction]
                            if args.count >= 3 {
                                let direction = args[2].lowercased()
                                handleBalloonAlignment(direction: direction)
                            }
                        case "autoscroll":
                            // \![set,autoscroll,0/1/true/false]
                            if args.count >= 3 {
                                let value = args[2].lowercased()
                                DispatchQueue.main.async {
                                    guard let vm = self.balloonViewModels[self.currentScope] else { return }
                                    vm.autoscrollEnabled = !["0", "false", "disable", "disabled", "off"].contains(value)
                                    Log.debug("[GhostManager] Autoscroll set to: \(vm.autoscrollEnabled)")
                                }
                            }
                        case "balloontimeout":
                            // \![set,balloontimeout,time]。省略時は既定値へ戻す。
                            let value = args.count >= 3 ? args[2] : nil
                            playbackQueue.append(.deferredCommand { [weak self] in
                                self?.applyBalloonTimeout(value)
                            })
                        case "choicetimeout":
                            // \![set,choicetimeout,time]
                            if args.count >= 3, let timeoutMs = Double(args[2]) {
                                // \* で「このスクリプトの選択肢をタイムアウトさせない」指定中は上書きしない
                                if !choiceTimeoutDisabled {
                                    choiceTimeout = timeoutMs > 0 ? timeoutMs / 1000.0 : nil
                                }
                                Log.debug("[GhostManager] Choice timeout set to: \(choiceTimeout ?? -1)s")
                            }
                        case "balloonwait":
                            // \![set,balloonwait,倍率]。数値/%/msを文字送りへ反映する。
                            let value = args.count >= 3 ? args[2] : nil
                            playbackQueue.append(.deferredCommand { [weak self] in
                                self?.applyBalloonWait(value)
                            })
                        case "balloonmarker":
                            if args.count >= 3 {
                                setBalloonMarker(args[2])
                            }
                        case "balloonnum":
                            // \![set,balloonnum,file,current,max]。各引数は省略可。
                            setBalloonNumber(
                                fileName: args.count >= 3 ? args[2] : "",
                                current: args.count >= 4 ? args[3] : "",
                                maximum: args.count >= 5 ? args[4] : ""
                            )
                        case "wallpaper":
                            // \![set,wallpaper,filename,options]
                            let filename = args.count >= 3 ? args[2] : ""
                            let options = args.count >= 4 ? Array(args.dropFirst(3)) : []
                            setWallpaper(filename: filename, options: options)
                        case "tasktrayicon", "trayicon":
                            // \![set,tasktrayicon,filename,text,--duration=ms,--runcount=n]
                            if args.count >= 3 {
                                let filename = args[2]
                                let text = args.count >= 4 ? args[3] : ""
                                setTaskTrayIcon(filename: filename, text: text, options: Array(args.dropFirst(4)))
                            }
                        case "trayballoon":
                            // \![set,trayballoon,options...]
                            let options = Array(args.dropFirst(2))
                            setTrayBalloon(options: options)
                        case "otherghosttalk":
                            // \![set,otherghosttalk,true/false/before/after]
                            if args.count >= 3 {
                                setOtherGhostTalk(mode: args[2])
                            }
                        case "othersurfacechange":
                            // \![set,othersurfacechange,true/false]
                            if args.count >= 3 {
                                let value = args[2].lowercased()
                                setOtherSurfaceChange(enabled: value == "true" || value == "1" || value == "on")
                            }
                        case "windowstate":
                            // \![set,windowstate,stayontop/!stayontop/minimize]
                            if args.count >= 3 {
                                setWindowState(state: args[2])
                            }
                        case "shioridebugmode":
                            if args.count >= 3 {
                                let enabled = args[2].lowercased() == "1" || args[2].lowercased() == "true" || args[2].lowercased() == "on"
                                UserDefaults.standard.set(enabled, forKey: "OurinShioriDebugMode")
                                EventBridge.shared.notifyCustom("OnShioriDebugModeChanged", refs: ["enabled": enabled ? "1" : "0"])
                            }
                        case "serikotalk":
                            if args.count >= 3 {
                                let mode = args[2]
                                playbackQueue.append(.deferredCommand { [weak self] in
                                    self?.setSerikoTalk(mode: mode)
                                })
                            }
                        default:
                            break
                        }
                    } else if first == "reset" {
                        // \![reset,*] と \![reset]（z-order/sticky の両方を解除）
                        if args.count >= 2 {
                            let subcmd = args[1].lowercased()
                            switch subcmd {
                            case "syncobject":
                                if args.count >= 3 {
                                    SyncCenter.shared.reset(name: args[2])
                                }
                            case "position":
                                // \![reset,position] - unlock position
                                resetWindowPosition()
                            case "zorder":
                                // \![reset,zorder] - reset to default z-order
                                resetWindowZOrder()
                            case "sticky-window":
                                // \![reset,sticky-window] - unlink windows
                                resetStickyWindow()
                            default:
                                break
                            }
                        } else {
                            resetWindowZOrder()
                            resetStickyWindow()
                        }
                    } else if first == "bind" || first == "bind-noevent", args.count >= 2 {
                        executeBindCommand(args: args)
                    } else if first == "reload", args.count >= 2 {
                        let target = args[1].lowercased()
                        if target == "surfaces.txt" {
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.reloadSurfacesDefinition()
                                }
                            })
                        }
                    } else if first == "lock", args.count >= 2 {
                        // Handle \![lock,*] commands
                        let subcmd = args[1].lowercased()
                        if subcmd == "repaint" {
                            let manual = args.count >= 3 && args[2].lowercased() == "manual"
                            DispatchQueue.main.async {
                                guard let vm = self.characterViewModels[self.currentScope] else { return }
                                vm.repaintLocked = true
                                vm.manualRepaintLock = manual
                            }
                        } else if subcmd == "balloonrepaint" {
                            let manual = args.count >= 3 && args[2].lowercased() == "manual"
                            DispatchQueue.main.async {
                                guard let vm = self.balloonViewModels[self.currentScope] else { return }
                                vm.repaintLocked = true
                                vm.manualRepaintLock = manual
                                Log.debug("[GhostManager] Balloon repaint locked: \(manual)")
                            }
                        } else if subcmd == "balloonmove" {
                            DispatchQueue.main.async {
                                guard let vm = self.balloonViewModels[self.currentScope] else { return }
                                vm.balloonMoveLocked = true
                                Log.debug("[GhostManager] Balloon move locked")
                            }
                        }
                    } else if first == "unlock", args.count >= 2 {
                        // Handle \![unlock,*] commands
                        let subcmd = args[1].lowercased()
                        if subcmd == "repaint" {
                            DispatchQueue.main.async {
                                guard let vm = self.characterViewModels[self.currentScope] else { return }
                                vm.repaintLocked = false
                                vm.manualRepaintLock = false
                            }
                        } else if subcmd == "balloonrepaint" {
                            DispatchQueue.main.async {
                                guard let vm = self.balloonViewModels[self.currentScope] else { return }
                                vm.repaintLocked = false
                                vm.manualRepaintLock = false
                                Log.debug("[GhostManager] Balloon repaint unlocked")
                            }
                        } else if subcmd == "balloonmove" {
                            DispatchQueue.main.async {
                                guard let vm = self.balloonViewModels[self.currentScope] else { return }
                                vm.balloonMoveLocked = false
                                Log.debug("[GhostManager] Balloon move unlocked")
                            }
                        }
                    } else if first == "execute", args.count >= 2 {
                        // Handle \![execute,*] commands
                        let subcmd = args[1].lowercased()
                        if subcmd == "resetwindowpos" {
                            // \![execute,resetwindowpos] - reset all windows to initial positions
                            executeResetWindowPos()
                        } else if subcmd == "resetballoonpos" {
                            // \![execute,resetballoonpos] - reset all balloon positions
                            resetBalloonPositions()
                        } else if subcmd == "headline" {
                            // \![execute,headline,headlineName]
                            let headlineName = args.count >= 3 ? args[2] : ""
                            executeHeadline(name: headlineName)
                        } else if subcmd.hasPrefix("http-stream-") || subcmd == "http-stream" {
                            // \![execute,http-stream-get,URL,...] / \![execute,http-stream,URL,...]
                            let params = Array(args.dropFirst(2))
                            executeHTTPStreaming(subcommand: subcmd, params: params)
                        } else if subcmd.hasPrefix("http-") {
                            let params = Array(args.dropFirst(2))
                            executeHTTP(subcommand: subcmd, params: params)
                        } else if subcmd.hasPrefix("rss-") {
                            let params = Array(args.dropFirst(2))
                            executeRSS(subcommand: subcmd, params: params)
                        } else if subcmd == "extractarchive" {
                            executeExtractArchive(params: Array(args.dropFirst(2)))
                        } else if subcmd == "compressarchive" {
                            executeCompressArchive(params: Array(args.dropFirst(2)))
                        } else if subcmd == "dumpsurface" {
                            executeDumpSurface(params: Array(args.dropFirst(2)))
                        } else if subcmd == "install" {
                            executeInstall(params: Array(args.dropFirst(2)))
                        } else if subcmd == "createnar" {
                            executeCreateNar()
                        } else if subcmd == "createupdatedata" {
                            executeCreateUpdateData()
                        } else if subcmd == "emptyrecyclebin" {
                            executeEmptyRecycleBin()
                        } else if subcmd == "ping" {
                            executePing(params: Array(args.dropFirst(2)))
                        } else if subcmd == "nslookup" {
                            executeNslookup(params: Array(args.dropFirst(2)))
                        } else if subcmd == "websocket" {
                            executeWebSocket(params: Array(args.dropFirst(2)))
                        }
                    } else if first == "create", args.count >= 2 {
                        let createType = args[1].lowercased()
                        if createType == "shortcut" {
                            executeCreateShortcut(params: Array(args.dropFirst(2)))
                        }
                    } else if first == "clipboard", args.count >= 2 {
                        let subcmd = args[1].lowercased()
                        if subcmd == "set" || subcmd == "copy" {
                            let text = args.count >= 3 ? args[2] : ""
                            setClipboardText(text)
                        } else if subcmd == "get" || subcmd == "paste" {
                            let text = getClipboardText()
                            if args.count >= 3 {
                                let eventID = args[2]
                                _ = requestDialogEvent(eventID: eventID, references: [text])
                            } else {
                                EventBridge.shared.notifyCustom("OnClipboardRead", refs: ["text": text])
                            }
                        } else if subcmd == "clear" {
                            clearClipboard()
                        }
                    } else if first == "systemmessage" || (first == "system" && args.count >= 2 && args[1].lowercased() == "message") {
                        let offset = first == "systemmessage" ? 1 : 2
                        let title = args.count > offset ? args[offset] : ""
                        let body = args.count > offset + 1 ? args[offset + 1] : ""
                        let level = args.count > offset + 2 ? args[offset + 2] : "info"
                        postSystemMessage(title: title, body: body, level: level)
                    } else if first == "quicksession" {
                        // \![quicksession,true/false] - enable/disable quick session mode
                        let enabled = args.count >= 2 && args[1].lowercased() == "true"
                        quickSessionEnabled = enabled
                        Log.debug("[GhostManager] Quick session mode: \(enabled)")
                    } else if first == "executesntp" {
                        // \![executesntp] - execute SNTP time synchronization
                        executeSNTP()
                    } else if first == "biff" {
                        // \![biff(,account)] - check for new mail
                        executeBiff(account: args.count >= 2 ? args[1] : nil)
                    } else if first == "updatebymyself" {
                        // \![updatebymyself(,options...)] - options must not be discarded.
                        executeUpdate(target: "self", options: Array(args.dropFirst()))
                    } else if first == "update" {
                        // \![update,http,url] or \![update,target,options...]
                        if args.count >= 3, args[1].lowercased() == "http" {
                            let params = Array(args.dropFirst(2))
                            executeHTTP(subcommand: "http-get", params: params)
                        } else {
                            let target = args.count >= 2 ? args[1] : "platform"
                            let options = Array(args.dropFirst(2))
                            executeUpdate(target: target, options: options)
                        }
                    } else if first == "updateother" {
                        // \![updateother,target/options...] - preserve check/test/reason options.
                        executeUpdate(target: "other", options: Array(args.dropFirst()))
                    } else if first == "vanishbymyself" {
                        // \![vanishbymyself[,ghostName]][,--option=query]
                        let rawOptions = Array(args.dropFirst())
                        let parsed = parseCommandArguments(rawOptions)
                        let query = parsed.flags.contains("query") ||
                            parsed.options["option"]?.lowercased() == "query"
                        executeVanish(
                            uninstall: true,
                            nextGhostName: parsed.positionals.first,
                            query: query
                        )
                    } else if first == "reloadsurface" {
                        executeReloadSurface()
                    } else if first == "reload", args.count >= 2 {
                        executeReload(target: args[1], params: Array(args.dropFirst(2)))
                    } else if first == "unload", args.count >= 2 {
                        executeUnload(target: args[1])
                    } else if first == "load", args.count >= 2 {
                        executeLoad(target: args[1])
                    } else if first == "anim", args.count >= 2 {
                        // Handle \![anim,*] commands - animation control
                        let subcmd = args[1].lowercased()
                        switch subcmd {
                        case "clear":
                            // \![anim,clear,ID] - clear specific animation/overlay
                            if args.count >= 3, let animID = Int(args[2]) {
                                handleAnimClear(id: animID)
                            }
                        case "pause":
                            // \![anim,pause,ID] - pause animation
                            if args.count >= 3, let animID = Int(args[2]) {
                                handleAnimPause(id: animID)
                            }
                        case "resume":
                            // \![anim,resume,ID] - resume animation
                            if args.count >= 3, let animID = Int(args[2]) {
                                handleAnimResume(id: animID)
                            }
                        case "stop":
                            // \![anim,stop] / \![anim,stop,ID]
                            if args.count >= 3, let animID = Int(args[2]) {
                                handleAnimClear(id: animID)
                            } else {
                                handleAnimStop()
                            }
                        case "offset":
                            // \![anim,offset,ID,x,y] - offset an animation/overlay
                            if args.count >= 5,
                               let overlayID = Int(args[2]),
                               let x = Int(args[3]),
                               let y = Int(args[4]) {
                                handleAnimOffset(id: overlayID, x: x, y: y)
                            }
                        case "add":
                            // \![anim,add,overlay,ID] or \![anim,add,base,ID] or \![anim,add,text,...]
                            if args.count >= 4 {
                                let addType = args[2].lowercased()
                                if addType == "overlay" {
                                    if let surfaceID = Int(args[3]) {
                                        handleAnimAddOverlay(id: surfaceID)
                                    }
                                } else if addType == "overlayfast" {
                                    if let surfaceID = Int(args[3]) {
                                        handleAnimAddOverlayFast(id: surfaceID)
                                    }
                                } else if addType == "base" {
                                    if let surfaceID = Int(args[3]) {
                                        handleAnimAddBase(id: surfaceID)
                                    }
                                } else if addType == "move" {
                                    if args.count >= 5,
                                       let moveX = Int(args[3]),
                                       let moveY = Int(args[4]) {
                                        handleAnimAddMove(x: moveX, y: moveY)
                                    }
                                } else if addType == "bind" {
                                    if let surfaceID = Int(args[3]) {
                                        handleSurfaceOverlay(surfaceID: surfaceID, type: .bind)
                                    }
                                } else if addType == "text" {
                                    // \![anim,add,text,x,y,width,height,text,time,r,g,b,size,font]
                                    if args.count >= 13 {
                                        let x = Int(args[3]) ?? 0
                                        let y = Int(args[4]) ?? 0
                                        let width = Int(args[5]) ?? 100
                                        let height = Int(args[6]) ?? 20
                                        let text = args[7]
                                        let time = Int(args[8]) ?? 1000
                                        let r = Int(args[9]) ?? 0
                                        let g = Int(args[10]) ?? 0
                                        let b = Int(args[11]) ?? 0
                                        let size = Int(args[12]) ?? 12
                                        let font = args.count >= 14 ? args[13] : "sans-serif"
                                        addTextAnimation(x: x, y: y, width: width, height: height, text: text, 
                                                       time: time, r: r, g: g, b: b, size: size, font: font)
                                    }
                                }
                            }
                        default:
                            // 旧仕様の \![anim,pauseID] / \![anim,stopID]。
                            if subcmd.hasPrefix("pause"),
                               let animID = Int(subcmd.dropFirst("pause".count)) {
                                handleAnimPause(id: animID)
                            } else if subcmd.hasPrefix("stop"),
                                      let animID = Int(subcmd.dropFirst("stop".count)) {
                                handleAnimClear(id: animID)
                            }
                        }
                    } else if first == "bind" || first == "bind-noevent", args.count >= 2 {
                        executeBindCommand(args: args)
                    } else if first == "effect", args.count >= 2 {
                        // \![effect,plugin,speed,params] - apply effect plugin
                        let plugin = args[1]
                        let speed = args.count >= 3 ? Double(args[2]) ?? 1.0 : 1.0
                        let params = Array(args.dropFirst(3))
                        applyEffect(plugin: plugin, speed: speed, params: params, surfaceID: nil)
                    } else if first == "effect2", args.count >= 3 {
                        // \![effect2,surfaceID,plugin,speed,params] - apply effect to specific surface
                        if let surfaceID = Int(args[1]) {
                            let plugin = args[2]
                            let speed = args.count >= 4 ? Double(args[3]) ?? 1.0 : 1.0
                            let params = Array(args.dropFirst(4))
                            applyEffect(plugin: plugin, speed: speed, params: params, surfaceID: surfaceID)
                        }
                    } else if first == "filter" {
                        if args.count >= 2 {
                            // \![filter,plugin,time,params] - apply filter plugin
                            let plugin = args[1]
                            let time = args.count >= 3 ? Double(args[2]) ?? 0 : 0
                            let params = Array(args.dropFirst(3))
                            applyFilter(plugin: plugin, time: time, params: params)
                        } else {
                            // \![filter] - clear all filters
                            clearFilters()
                        }
                    } else if first == "move" {
                        let params = Array(args.dropFirst())
                        if params.first?.lowercased() == "window" {
                            executeMoveCommand(args: Array(params.dropFirst()), async: false)
                        } else {
                            executeMoveCommand(args: params, async: false)
                        }
                    } else if first == "moveasync" {
                        let params = Array(args.dropFirst())
                        if params.first?.lowercased() == "cancel" {
                            let scopeID = params.count >= 2 ? Int(params[1]) : nil
                            cancelMoveWindowAsync(scope: scopeID)
                        } else if params.first?.lowercased() == "window" {
                            executeMoveCommand(args: Array(params.dropFirst()), async: true)
                        } else {
                            executeMoveCommand(args: params, async: true)
                        }
                    } else if first == "resize" {
                        let params = Array(args.dropFirst())
                        if params.first?.lowercased() == "window" {
                            executeResizeCommand(args: Array(params.dropFirst()))
                        } else {
                            executeResizeCommand(args: params)
                        }
                    } else if first == "open", args.count >= 2 {
                        // Handle \![open,browser,URL] and \![open,mailer,email]
                        let target = args[1].lowercased()
                        if target == "browser" && args.count >= 3 {
                            let url = args[2]
                            openURL(url)
                        } else if target == "mailer" && args.count >= 3 {
                            let email = args[2]
                            openEmail(email)
                        } else if target == "addressbar" {
                            openAddressBar()
                        } else if target == "errorlog" {
                            openErrorLogViewer()
                        } else if target == "pictureviewer" {
                            openPictureViewer(path: args.count >= 3 ? args[2] : nil)
                        } else if target == "archiveviewer" {
                            openArchiveViewer(path: args.count >= 3 ? args[2] : nil)
                        } else if target == "backlogviewer" {
                            openBacklogViewer()
                        } else {
                            // UKADOC: \![open,URL] は指定URLを既定アプリへ委譲する。
                            openURL(args[1])
                        }
                    } else if ["*", "#", "x", "<", ">"].contains(first) {
                        // Choice marker shorthand: \![*], \![#], \![X], \![<], \![>]
                        let marker: String
                        switch first {
                        case "*": marker = "*"
                        case "#": marker = "#"
                        case "x": marker = "X"
                        case "<": marker = "<"
                        case ">": marker = ">"
                        default: marker = first
                        }
                        setBalloonMarker(marker)
                    }
                }
            case "b":
                // フォールバック付き \b はパーサーが保持した候補を選択する。
                let candidates = args.compactMap { value -> Int? in
                    if let id = Int(value) { return id }
                    let prefix = "--fallback="
                    guard value.lowercased().hasPrefix(prefix) else { return nil }
                    return Int(value.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces))
                }
                if !candidates.isEmpty {
                    switchBalloon(to: candidates, scope: currentScope)
                    Log.debug("[GhostManager] Switching to balloon ID with command candidates: \(candidates)")
                } else {
                    Log.info("[GhostManager] Invalid balloon fallback command: \(args)")
                }
            case "_s":
                if args.isEmpty {
                    syncEnabled.toggle()
                    if syncEnabled && syncScopes.isEmpty { syncScopes = [0,1] }
                    if !syncEnabled { syncScopes = [] }
                } else {
                    syncEnabled = true
                    syncScopes = Set(args.compactMap { Int($0) })
                }
            
            case "q":
                // \q[title,ID] or various choice formats
                handleChoiceCommand(args: args)
            
            case "_a":
                // \_a[ID,...] 開始 / \_a 閉じ。\_a[ID,r0,r1,...]...\_a の範囲をアンカーとして
                // 構築し、各範囲のテキスト・文字範囲・クリック時のアクションを保持する。
                // 範囲テキストの表示位置と整合させるため、再生キュー上のここで開始/確定する。
                if args.isEmpty {
                    playbackQueue.append(.deferredCommand { [weak self] in
                        self?.closeAnchorRange()
                    })
                } else {
                    let eventID = args[0]
                    let references = Array(args.dropFirst())
                    Log.debug("[GhostManager] Anchor open: \(eventID) with refs: \(references)")
                    let pluginOrigin = currentScriptIsPluginOrigin
                    playbackQueue.append(.deferredCommand { [weak self] in
                        self?.openAnchorRange(id: eventID, references: references, pluginOrigin: pluginOrigin)
                    })
                }
            
            case "_b":
                // \_b[filepath,...] - balloon image display
                // スコープ切り替えや本文送りと同じ順序で実行する。解析時に直接
                // handleBalloonImage を呼ぶと、\1\_b[...] が常に旧スコープへ登録される。
                playbackQueue.append(.balloonImage(args))

            case "_l":
                // \_l[x,y] - move cursor position
                if args.count >= 2 {
                    handleCursorMove(x: args[0], y: args[1])
                }
            
            case "_v":
                // \_v[filename] - play voice file
                if let filename = args.first {
                    playSound(filename: filename)
                }

            case "_u":
                // \_u[0xXXXX] - append Unicode scalar text
                if let scalar = decodeScalarLiteral(args.first) {
                    let text = String(scalar)
                    playbackQueue.append(.textChunk(text))
                    enqueueSpeech(for: text)
                }

            case "_m":
                // \_m[0xNN] - append an ASCII byte. Values outside ASCII are invalid.
                if let value = Self.parseScalarLiteral(args.first), value <= 0x7f,
                   let scalar = UnicodeScalar(value) {
                    let text = String(scalar)
                    playbackQueue.append(.textChunk(text))
                    enqueueSpeech(for: text)
                } else {
                    Log.info("[GhostManager] Ignoring non-ASCII \\_m value: \(args.first ?? "")")
                }

            case "&":
                // \&[ID] - 識別子による実体参照（UKADOC）。アンカーイベントではない。
                if let entityID = args.first, !entityID.isEmpty {
                    if let text = Self.resolveEntityReference(entityID) {
                        playbackQueue.append(.textChunk(text))
                        enqueueSpeech(for: text)
                    } else {
                        Log.info("[GhostManager] \\&[\(entityID)] - unknown entity reference (ignored)")
                    }
                }

            case "j":
                // \j[ID] - ジャンプ（UKADOC）。URL はブラウザで開く。イベントIDは raise 相当。
                handleJumpCommand(args: args)

            case "m":
                // \m[umsg,wparam,lparam] - message dispatch
                if let umsg = args.first, !umsg.isEmpty {
                    var refs = [umsg]
                    refs.append(contentsOf: Array(args.dropFirst()))
                    _ = requestDialogEvent(eventID: "OnMessage", references: refs)
                }
            
            case "c":
                // \c[char,line,...] - clear text
                // 本文より先に即時実行すると、まだ再生されていない本文を消せない。
                // deferredCommand で同じ再生キュー上の先行文字の後に実行する。
                playbackQueue.append(.deferredCommand { [weak self] in
                    self?.handleTextClear(args: args)
                })
            
            case "f":
                // \f[align,...], \f[name,...], \f[height,...], \f[color,...], \f[shadowcolor,...], \f[shadowstyle,...], \f[bold,...], \f[italic,...], \f[strike,...], \f[underline,...], \f[sub,...], \f[sup,...], \f[default], \f[disable], \f[anchor.font.color,...]
                if args.isEmpty {
                    break
                }
                let subcmd = args[0].lowercased()
                DispatchQueue.main.async {
                    guard let vm = self.balloonViewModels[self.currentScope] else { return }
                    
                    switch subcmd {
                    case "align":
                        // \f[align,left/center/right]
                        if args.count >= 2 {
                            let align = args[1].lowercased()
                            switch align {
                            case "left":
                                vm.textAlign = .left
                            case "center":
                                vm.textAlign = .center
                            case "right":
                                vm.textAlign = .right
                            default:
                                Log.info("[GhostManager] Unknown text align: \(align)")
                            }
                            Log.debug("[GhostManager] Text align set to: \(align)")
                        }
                    case "valign":
                        // \f[valign,top/center/bottom]
                        if args.count >= 2 {
                            let valign = args[1].lowercased()
                            switch valign {
                            case "top":
                                vm.textVAlign = .top
                            case "center", "middle":
                                vm.textVAlign = .center
                            case "bottom":
                                vm.textVAlign = .bottom
                            default:
                                Log.info("[GhostManager] Unknown text valign: \(valign)")
                            }
                            Log.debug("[GhostManager] Text valign set to: \(valign)")
                        }
                    case "name":
                        // \f[name,fontname,...]
                        if args.count >= 2 {
                            let fontNames = Array(args.dropFirst()).joined(separator: ",")
                            vm.fontName = fontNames
                            Log.debug("[GhostManager] Font name set to: \(fontNames)")
                        }
                    case "height":
                        // \f[height,size]
                        if args.count >= 2 {
                            let sizeStr = args[1]
                            let size = self.parseFontHeight(sizeStr, baseFontSize: CGFloat(self.balloonConfig?.fontHeight ?? 12))
                            vm.fontSize = size
                            Log.debug("[GhostManager] Font height set to: \(size)")
                        }
                    case "color":
                        // \f[color,r,g,b] or \f[color,#RRGGBB] or \f[color,name]
                        if args.count >= 2 {
                            let color = self.parseColor(from: Array(args.dropFirst()), defaultValue: vm.fontColor)
                            vm.fontColor = color
                            Log.debug("[GhostManager] Font color set to: \(color)")
                        }
                    case "shadowcolor":
                        // \f[shadowcolor,r,g,b] or \f[shadowcolor,#RRGGBB] or \f[shadowcolor,name]
                        if args.count >= 2 {
                            let color = self.parseColor(from: Array(args.dropFirst()), defaultValue: vm.shadowColor)
                            vm.shadowColor = color
                            Log.debug("[GhostManager] Shadow color set to: \(color)")
                        }
                    case "shadowstyle":
                        // \f[shadowstyle,offset/outline]
                        if args.count >= 2 {
                            let style = args[1].lowercased()
                            switch style {
                            case "offset":
                                vm.shadowStyle = .offset
                            case "outline":
                                vm.shadowStyle = .outline
                            case "none":
                                vm.shadowStyle = .none
                            default:
                                Log.info("[GhostManager] Unknown shadow style: \(style)")
                            }
                            Log.debug("[GhostManager] Shadow style set to: \(style)")
                        }
                    case "bold":
                        // \f[bold,0/1/true/false/default/disable]
                        if args.count >= 2 {
                            let value = args[1].lowercased()
                            let isBold = self.parseTriState(value, currentValue: vm.fontWeight == .bold ? "1" : "0")
                            vm.fontWeight = isBold ? .bold : .regular
                            Log.debug("[GhostManager] Font bold set to: \(isBold)")
                        }
                    case "italic":
                        // \f[italic,0/1/true/false/default/disable]
                        if args.count >= 2 {
                            let value = args[1].lowercased()
                            vm.fontItalic = self.parseTriState(value, currentValue: vm.fontItalic ? "1" : "0")
                            Log.debug("[GhostManager] Font italic set to: \(vm.fontItalic)")
                        }
                    case "strike":
                        // \f[strike,0/1/true/false/default/disable]
                        if args.count >= 2 {
                            let value = args[1].lowercased()
                            vm.fontStrike = self.parseTriState(value, currentValue: vm.fontStrike ? "1" : "0")
                            Log.debug("[GhostManager] Font strike set to: \(vm.fontStrike)")
                        }
                    case "underline":
                        // \f[underline,0/1/true/false/default/disable]
                        if args.count >= 2 {
                            let value = args[1].lowercased()
                            vm.fontUnderline = self.parseTriState(value, currentValue: vm.fontUnderline ? "1" : "0")
                            Log.debug("[GhostManager] Font underline set to: \(vm.fontUnderline)")
                        }
                    case "sub":
                        // \f[sub,0/1/true/false/default/disable]
                        if args.count >= 2 {
                            let value = args[1].lowercased()
                            vm.fontSubscript = self.parseTriState(value, currentValue: vm.fontSubscript ? "1" : "0")
                            if vm.fontSubscript { vm.fontSuperscript = false }
                            Log.debug("[GhostManager] Font subscript set to: \(vm.fontSubscript)")
                        }
                    case "sup":
                        // \f[sup,0/1/true/false/default/disable]
                        if args.count >= 2 {
                            let value = args[1].lowercased()
                            vm.fontSuperscript = self.parseTriState(value, currentValue: vm.fontSuperscript ? "1" : "0")
                            if vm.fontSuperscript { vm.fontSubscript = false }
                            Log.debug("[GhostManager] Font superscript set to: \(vm.fontSuperscript)")
                        }
                    case "default":
                        // \f[default] - reset to default
                        self.resetFontDefaults(vm: vm)
                    case "disable":
                        // \f[disable] - set all to disabled style
                        self.setFontDisabled(vm: vm)
                    case "anchor.font.color", "anchorfontcolor":
                        // \f[anchorfontcolor,...]（選択時文字色）/ \f[anchornotselectfontcolor,...]（非選択時文字色）
                        // 色指定は r,g,b / #RRGGBB / 色名。
                        if args.count >= 2 {
                            vm.anchorFontColor = self.parseColor(from: Array(args.dropFirst()), defaultValue: vm.anchorFontColor)
                            Log.debug("[GhostManager] Anchor font color set via \(subcmd)")
                        }
                    case "anchornotselectfontcolor":
                        if args.count >= 2 {
                            vm.anchorNotSelectFontColor = self.parseColor(from: Array(args.dropFirst()), defaultValue: vm.anchorNotSelectFontColor)
                            Log.debug("[GhostManager] Anchornotselect font color set via \(subcmd)")
                        }
                    case "anchorvisitedfontcolor":
                        if args.count >= 2 {
                            vm.anchorVisitedFontColor = self.parseColor(from: Array(args.dropFirst()), defaultValue: vm.anchorVisitedFontColor)
                            Log.debug("[GhostManager] Anchorvisited font color set via \(subcmd)")
                        }
                    case "anchorstyle":
                        // \f[anchorstyle,形状] - 選択中（ホバー中）アンカーの形状。
                        if args.count >= 2 {
                            if let style = AnchorDecorationStyle(shape: args[1]) {
                                vm.anchorStyle = style
                            } else if args[1].lowercased() == "default" {
                                vm.anchorStyle = .underline
                            }
                            Log.debug("[GhostManager] anchorstyle set via \(subcmd)")
                        }
                    case "anchorbrushcolor", "anchorcolor":
                        // \f[anchorbrushcolor,色] もしくは \f[anchorcolor,色] - 選択中アンカーの矩形内の色。
                        if args.count >= 2 {
                            vm.anchorBrushColor = self.parseColor(from: Array(args.dropFirst()), defaultValue: vm.anchorBrushColor)
                            Log.debug("[GhostManager] Anchor brush color set via \(subcmd)")
                        }
                    case "anchorpencolor":
                        // \f[anchorpencolor,色] - 選択中アンカーの矩形枠および下線の色。
                        if args.count >= 2 {
                            vm.anchorPenColor = self.parseColor(from: Array(args.dropFirst()), defaultValue: vm.anchorPenColor)
                            Log.debug("[GhostManager] Anchor pen color set via \(subcmd)")
                        }
                    case "anchornotselectstyle":
                        // \f[anchornotselectstyle,形状] - 非選択中アンカーの形状。
                        if args.count >= 2 {
                            if let style = AnchorDecorationStyle(shape: args[1]) {
                                vm.anchornotselectStyle = style
                            } else if args[1].lowercased() == "default" {
                                vm.anchornotselectStyle = .underline
                            }
                            Log.debug("[GhostManager] anchornotselectstyle set via \(subcmd)")
                        }
                    case "anchornotselectbrushcolor", "anchornotselectcolor":
                        // \f[anchornotselectbrushcolor,色] もしくは \f[anchornotselectcolor,色] - 非選択中アンカーの矩形内の色。
                        if args.count >= 2 {
                            vm.anchornotselectBrushColor = self.parseColor(from: Array(args.dropFirst()), defaultValue: vm.anchornotselectBrushColor)
                            Log.debug("[GhostManager] Anchornotselect brush color set via \(subcmd)")
                        }
                    case "anchornotselectpencolor":
                        // \f[anchornotselectpencolor,色] - 非選択中アンカーの矩形枠および下線の色。
                        if args.count >= 2 {
                            vm.anchornotselectPenColor = self.parseColor(from: Array(args.dropFirst()), defaultValue: vm.anchornotselectPenColor)
                            Log.debug("[GhostManager] Anchornotselect pen color set via \(subcmd)")
                        }
                    case "anchorvisitedstyle":
                        // \f[anchorvisitedstyle,形状] - 訪問済みアンカーの形状。
                        if args.count >= 2 {
                            if let style = AnchorDecorationStyle(shape: args[1]) {
                                vm.anchorvisitedStyle = style
                            } else if args[1].lowercased() == "default" {
                                vm.anchorvisitedStyle = .underline
                            }
                            Log.debug("[GhostManager] anchorvisitedstyle set via \(subcmd)")
                        }
                    case "anchorvisitedbrushcolor", "anchorvisitedcolor":
                        // \f[anchorvisitedbrushcolor,色] もしくは \f[anchorvisitedcolor,色] - 訪問済みアンカーの矩形内の色。
                        if args.count >= 2 {
                            vm.anchorvisitedBrushColor = self.parseColor(from: Array(args.dropFirst()), defaultValue: vm.anchorvisitedBrushColor)
                            Log.debug("[GhostManager] Anchorvisited brush color set via \(subcmd)")
                        }
                    case "anchorvisitedpencolor":
                        // \f[anchorvisitedpencolor,色] - 訪問済みアンカーの矩形枠および下線の色。
                        if args.count >= 2 {
                            vm.anchorvisitedPenColor = self.parseColor(from: Array(args.dropFirst()), defaultValue: vm.anchorvisitedPenColor)
                            Log.debug("[GhostManager] Anchorvisited pen color set via \(subcmd)")
                        }
                    case "anchormethod", "anchornotselectmethod", "anchorvisitedmethod":
                        // \f[anchor*method,描画方法]。`default` は descript.txt の値へ戻す。
                        guard args.count >= 2 else {
                            Log.info("[GhostManager] Missing raster operation for \\(subcmd)")
                            break
                        }
                        let requested = args[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        let operation: AnchorRasterOperation?
                        switch subcmd {
                        case "anchormethod":
                            if requested == "default" {
                                operation = vm.defaultAnchorMethod
                            } else {
                                operation = AnchorRasterOperation(name: requested)
                            }
                        case "anchornotselectmethod":
                            if requested == "default" {
                                operation = vm.defaultAnchornotselectMethod
                            } else {
                                operation = AnchorRasterOperation(name: requested)
                            }
                        default:
                            if requested == "default" {
                                operation = vm.defaultAnchorvisitedMethod
                            } else {
                                operation = AnchorRasterOperation(name: requested)
                            }
                        }
                        guard let operation else {
                            Log.info("[GhostManager] Unknown anchor raster operation for \(subcmd): \(args[1])")
                            break
                        }
                        switch subcmd {
                        case "anchormethod": vm.anchorMethod = operation
                        case "anchornotselectmethod": vm.anchornotselectMethod = operation
                        default: vm.anchorvisitedMethod = operation
                        }
                        Log.debug("[GhostManager] Anchor raster operation '\(requested)' applied to \(subcmd)")
                    case "cursorstyle", "cursornotselectstyle":
                        guard args.count >= 2 else { break }
                        let requested = args[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        let style: AnchorDecorationStyle?
                        if requested == "default" {
                            if subcmd == "cursorstyle", let configured = self.balloonConfig?.cursorStyle {
                                style = AnchorDecorationStyle(shape: configured) ?? .square
                            } else {
                                style = AnchorDecorationStyle.none
                            }
                        } else {
                            style = AnchorDecorationStyle(shape: requested)
                        }
                        guard let style else {
                            Log.info("[GhostManager] Unknown cursor style: \(args[1])")
                            break
                        }
                        if subcmd == "cursorstyle" {
                            vm.cursorStyle = style
                        } else {
                            vm.cursorNotSelectStyle = style
                        }
                    case "cursorbrushcolor", "cursorcolor", "cursornotselectbrushcolor", "cursornotselectcolor":
                        guard args.count >= 2 else { break }
                        let isNotSelected = subcmd.hasPrefix("cursornotselect")
                        let fallback = isNotSelected ? vm.cursorNotSelectBrushColor : vm.cursorBrushColor
                        let color = self.parseColor(from: Array(args.dropFirst()), defaultValue: fallback)
                        if isNotSelected {
                            vm.cursorNotSelectBrushColor = color
                        } else {
                            vm.cursorBrushColor = color
                        }
                    case "cursorpencolor", "cursornotselectpencolor":
                        guard args.count >= 2 else { break }
                        let isNotSelected = subcmd.hasPrefix("cursornotselect")
                        let fallback = isNotSelected ? vm.cursorNotSelectPenColor : vm.cursorPenColor
                        let color = self.parseColor(from: Array(args.dropFirst()), defaultValue: fallback)
                        if isNotSelected {
                            vm.cursorNotSelectPenColor = color
                        } else {
                            vm.cursorPenColor = color
                        }
                    case "cursorfontcolor", "cursornotselectfontcolor":
                        guard args.count >= 2 else { break }
                        let isNotSelected = subcmd.hasPrefix("cursornotselect")
                        let fallback = isNotSelected ? vm.cursorNotSelectFontColor : vm.cursorFontColor
                        let color = self.parseColor(from: Array(args.dropFirst()), defaultValue: fallback)
                        if isNotSelected {
                            vm.cursorNotSelectFontColor = color
                        } else {
                            vm.cursorFontColor = color
                        }
                    case "cursormethod", "cursornotselectmethod":
                        guard args.count >= 2 else {
                            Log.info("[GhostManager] Missing raster operation for \\(subcmd)")
                            break
                        }
                        let requested = args[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        let isNotSelected = subcmd.hasPrefix("cursornotselect")
                        let operation: AnchorRasterOperation?
                        if requested == "default" {
                            operation = isNotSelected ? AnchorRasterOperation.none :
                                (AnchorRasterOperation(name: self.balloonConfig?.cursorBlendMethod ?? "none") ?? AnchorRasterOperation.none)
                        } else {
                            operation = AnchorRasterOperation(name: requested)
                        }
                        guard let operation else {
                            Log.info("[GhostManager] Unknown cursor raster operation: \(args[1])")
                            break
                        }
                        if isNotSelected {
                            vm.cursorNotSelectMethod = operation
                        } else {
                            vm.cursorMethod = operation
                        }
                        Log.debug("[GhostManager] Cursor raster operation '\(requested)' applied to \(subcmd)")
                    case "outline":
                        // \f[outline,width]
                        if args.count >= 2 {
                            let value = args[1].lowercased()
                            if value == "default" || value == "disable" || value == "0" || value == "false" {
                                vm.outlineWidth = 0
                                if vm.shadowStyle == .outline {
                                    vm.shadowStyle = .none
                                }
                            } else if let width = Double(value) {
                                vm.outlineWidth = max(0, CGFloat(width))
                                vm.shadowStyle = vm.outlineWidth > 0 ? .outline : vm.shadowStyle
                            } else {
                                vm.outlineWidth = 1
                                vm.shadowStyle = .outline
                            }
                            Log.debug("[GhostManager] Font outline width set to: \(vm.outlineWidth)")
                        }
                    default:
                        Log.info("[GhostManager] Unknown font command: \(subcmd)")
                    }
                }
            
            default:
                break
             }
        }
    }

    // MARK: - Helper Methods

    /// \__v の状態をスクリプト単位の初期値へ戻す。
    /// 前のスクリプトの無効化指定や読み替えを次の会話へ漏らさない。
    /// スクリプト中だけ有効なバルーン設定を初期値へ戻す。
    /// `balloonmarker` / `balloonnum` / `onlinemode` のようにゴースト寿命へ
    /// またがる状態はここでは変更しない。
    private func resetScriptScopedBalloonSettings() {
        typingInterval = defaultTypingInterval
        serikoTalkEnabledForScript = nil
        appendModeEnabled = false
        for vm in balloonViewModels.values {
            vm.balloonTimeout = BalloonViewModel.defaultBalloonTimeout
            vm.balloonWaitEnabled = true
            vm.balloonWaitMultiplier = 1.0
            vm.wordWrapEnabled = true
            if !vm.manualRepaintLock {
                vm.repaintLocked = false
            }
        }
        for vm in characterViewModels.values where !vm.manualRepaintLock {
            vm.repaintLocked = false
        }
    }

    /// `\![set,balloonwait,...]` の仕様値を文字送り間隔へ変換する。
    private func balloonWaitSettings(_ rawValue: String?) -> (interval: TimeInterval, multiplier: Double) {
        guard let rawValue else { return (defaultTypingInterval, 1.0) }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty || value == "default" || value == "true" {
            return (defaultTypingInterval, 1.0)
        }
        if value == "false" { return (0, 0) }

        if value.hasSuffix("ms") {
            let number = Double(value.dropLast(2)) ?? 100
            let milliseconds = min(max(number, 0), 10_000)
            let interval = milliseconds / 1000.0
            return (interval, interval / defaultTypingInterval)
        }
        if value.hasSuffix("%") {
            let number = Double(value.dropLast()) ?? 100
            let percent = min(max(number, 0), 10_000)
            let multiplier = percent / 100.0
            return (defaultTypingInterval * multiplier, multiplier)
        }

        let multiplier = min(max(Double(value) ?? 1.0, 0), 100)
        return (defaultTypingInterval * multiplier, multiplier)
    }

    private func applyBalloonWait(_ rawValue: String?) {
        let settings = balloonWaitSettings(rawValue)
        typingInterval = settings.interval
        let vm = getBalloonVM(for: currentScope)
        vm.balloonWaitEnabled = settings.interval > 0
        vm.balloonWaitMultiplier = settings.multiplier
        Log.debug("[GhostManager] Balloon wait interval set to: \(settings.interval)s")
    }

    private func applyBalloonTimeout(_ rawValue: String?) {
        let timeout: TimeInterval
        if let rawValue,
           let milliseconds = Double(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            timeout = milliseconds / 1000.0
        } else {
            timeout = BalloonViewModel.defaultBalloonTimeout
        }
        let vm = getBalloonVM(for: currentScope)
        vm.balloonTimeout = timeout
        Log.debug("[GhostManager] Balloon timeout set to: \(timeout)s")
    }

    private func resetVoiceSynthesisState() {
        stopSpeechSynthesis()
        voiceSynthesisEnabled = false
        voiceAlternateText = nil
        voiceAlternateConsumed = false
    }

    /// \__v タグを実行時状態へ反映する。
    private func applyVoiceSynthesisCommand(_ args: [String]) {
        guard let option = args.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !option.isEmpty else {
            // 引数なしは範囲終了タグ。既定の自動読み上げ無効へ戻す。
            voiceSynthesisEnabled = false
            voiceAlternateText = nil
            voiceAlternateConsumed = false
            return
        }

        switch option {
        case "disable":
            voiceSynthesisEnabled = false
            voiceAlternateText = nil
            voiceAlternateConsumed = false
        case "enable":
            voiceSynthesisEnabled = true
            voiceAlternateText = nil
            voiceAlternateConsumed = false
        case "alternate":
            voiceSynthesisEnabled = true
            let alternate = args.dropFirst().joined(separator: ",")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            voiceAlternateText = alternate.isEmpty ? nil : alternate
            voiceAlternateConsumed = false
        default:
            Log.info("[GhostManager] Unknown \\__v option: \(option)")
        }
    }

    /// 表示テキストに対応する音声単位をキューへ追加する。
    /// `alternate` は指定範囲内の最初のテキストトークンへ一度だけ適用する。
    private func enqueueSpeech(for text: String) {
        guard !text.isEmpty else { return }
        // 音声状態は解析時ではなく、この本文トークンが再生される時点で判定する。
        // そうしないと `\__v[disable]text\__v` の終了タグが先に解析され、範囲全体が
        // 無音になってしまう。
        playbackQueue.append(.speakTextToken(text))
    }

    private func speakTextToken(_ text: String) {
        guard voiceSynthesisEnabled, !text.isEmpty else { return }
        if let alternate = voiceAlternateText, !voiceAlternateConsumed {
            voiceAlternateConsumed = true
            speakText(alternate)
        } else {
            speakText(text)
        }
    }

    private func speakText(_ text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: normalized)
        // 日本語ゴーストを優先しつつ、システムに音声が無ければ既定音声へフォールバックする。
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        speechSynthesizer.speak(utterance)
    }

    private func stopSpeechSynthesis() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func startPlaybackIfNeeded() {
        if !isPlaying {
            isPlaying = true
            DispatchQueue.main.async { self.processNextUnit() }
        }
    }

    // MARK: - \_a 範囲アンカー構築

    /// `\_a[ID,...]` 開始: 現在位置を開始文字位置としてアンカー構築を開始する。
    func openAnchorRange(id: String, references: [String], pluginOrigin: Bool? = nil) {
        let vm = getBalloonVM(for: currentScope)
        pendingAnchorOpen = (
            id: id,
            references: references,
            pluginOrigin: pluginOrigin ?? currentScriptIsPluginOrigin,
            textStart: (vm.text as NSString).length
        )
        vm.anchorActive = true
    }

    /// `\_a` 閉じ: 開始タグからの範囲を1つのアンカーとして確定する。
    func closeAnchorRange() {
        finalizePendingAnchorIfNeeded()
    }

    /// 未閉じのアンカー範囲があれば現在位置で確定する（`\_a` 閉じタグ／スクリプト終端時）。
    func finalizePendingAnchorIfNeeded() {
        guard let open = pendingAnchorOpen else { return }
        pendingAnchorOpen = nil
        guard let vm = balloonViewModels[currentScope] else { return }
        vm.anchors.append(BalloonAnchorRange(
            id: open.id,
            references: open.references,
            text: vm.anchorText(in: open.textStart),
            range: vm.anchorRange(from: open.textStart),
            pluginOrigin: open.pluginOrigin
        ))
        vm.anchorActive = !vm.anchors.isEmpty
    }

    func processNextUnit() {
        // Process immediate units (scope/surface/end) without delay; delay only text/newline
        while true {
            guard !playbackQueue.isEmpty else {
                isPlaying = false
                resetScriptScopedBalloonSettings()
                // \e を含まないスクリプトの終端でもアンカー範囲を確定する。
                finalizePendingAnchorIfNeeded()
                emitPluginTalkAfterIfNeeded()
                finishBootIfNeeded()
                // OnClose 応答スクリプトの再生完了後に終了する（スクリプトが \- を含まない場合の保険）
                if terminateAfterPlayback {
                    finalizeTermination()
                } else if closeSequenceCompletion != nil {
                    finishCloseSequence()
                } else if !pendingChoices.isEmpty {
                    // \q / \__q で蓄積された選択肢を再生完了後に提示する。
                    // 選択時に OnChoiceSelect(Ex) が発火し、プラグインへも横流しされる（showChoiceDialog 内）。
                    showChoiceDialog()
                }
                return
            }
            let unit = playbackQueue.removeFirst()
            switch unit {
            case .textToken(let text):
                guard !text.isEmpty else { continue }
                if quickMode {
                    // クイックセクションでも、後続のウェイトや制御タグは通常どおり
                    // キュー上で実行する。本文トークンだけを即時追加する。
                    appendText(text)
                    continue
                }
                let characters = Array(text)
                appendText(String(characters[0]))
                if characters.count > 1 {
                    playbackQueue.insert(contentsOf: characters.dropFirst().map { .text($0) }, at: 0)
                }
                scheduleNext(after: typingInterval)
                return
            case .startAnimation(let id, let wait):
                playAnimation(id: id, wait: false)
                if wait {
                    playbackQueue.insert(.waitAnimation(id), at: 0)
                }
                continue
            case .scope(let id):
                // SSP は複数スコープ（\0=sakura / \1=kero / \p[n]）のバルーンを同時表示できる。
                // スコープ切替では他スコープも切替先スコープ自身のバルーンも消さず、各スコープの
                // 表示寿命を独立させる。クリアはスクリプト開始時の一括クリア（runScript）と
                // 明示コマンド（\c / \e[clear] / \x 等）のみが行う。
                // （旧実装は切替のたびに他スコープを全消去し、同一スコープ再訪時も本文を消していたため
                //  複数キャラ同時発話や同一スコープへの追記が SSP と食い違っていた。）
                currentScope = id
                Log.debug("[GhostManager] Switched to scope \(id)")

                // Show the character window for this scope (遅延生成: 未作成スコープはここで生成)
                if let window = ensureCharacterWindow(for: id) {
                    window.orderFront(nil)
                    Log.debug("[GhostManager] Ordered scope \(id) window to front")
                }

                positionBalloonWindow()
                continue
            case .surface(let id):
                Log.debug("[GhostManager] Updating surface to id: \(id)")
                // Don't clear balloon - keep displaying until next script
                updateSurface(id: id)
                // Add a small delay after surface change to respect script timing
                scheduleNext(after: 0.05)
                return
            case .balloonImage(let args):
                handleBalloonImage(args: args)
                continue
            case .end:
                Log.debug("[GhostManager] Script end.")
                quickMode = false
                syncEnabled = false
                appendModeEnabled = false
                resetScriptScopedBalloonSettings()
                // 未閉じのアンカー範囲（\_a 閉じタグなし）は現在位置で確定する。
                finalizePendingAnchorIfNeeded()
                // \e でタイムクリティカルセクション終了（UKADOC: \t はスクリプトブレークか \e まで）
                timeCriticalActive = false
                continue
            case .toggleQuickMode:
                quickMode.toggle()
                continue
            case .setQuickMode(let enabled):
                quickMode = enabled
                continue
            case .voiceCommand(let args):
                applyVoiceSynthesisCommand(args)
                continue
            case .moveAway:
                moveAwayFromPartner(scope: currentScope)
                continue
            case .moveClose:
                moveTowardPartner(scope: currentScope)
                continue
            case .bootGhost:
                bootOtherGhost()
                continue
            case .bootAllGhosts:
                switchGhost(named: "sequential", options: [])
                continue
            case .executeSNTPApply:
                executeSNTPApply()
                continue
            case .executeSNTP:
                executeSNTP()
                continue
            case .playSound(let filename):
                playSound(filename: filename)
                continue
            case .resetPrecise:
                preciseBase = Date()
                continue
            case .waitUntil(let sec):
                let target = preciseBase.addingTimeInterval(sec)
                let now = Date()
                let delay = max(0.0, target.timeIntervalSince(now))
                scheduleNext(after: delay)
                return
            case .waitForAudio:
                let hasSound = estimatedSoundWaitDuration() > 0
                let hasSpeech = speechSynthesizer.isSpeaking
                let hasVideo = estimatedVideoWaitDuration() > 0
                if hasSound || hasSpeech || hasVideo {
                    scheduleNext(after: 0.05)
                    return
                }
                continue
            case .waitForHTTP(let taskID):
                if pendingHTTPWaits.contains(taskID) {
                    scheduleNext(after: 0.05)
                    return
                }
                continue
            case .waitForVisualEffect(let key):
                // 時間付き set,scaling / set,alpha は固定秒数ではなく、
                // 実際のフレームタイマーが完了したことを待つ。
                if visualEffectAnimationTimers[key] != nil {
                    scheduleNext(after: 1.0 / 60.0)
                    return
                }
                continue
            case .waitForSyncObject(let name, let timeout, let generation):
                guard generation == playbackGeneration else { continue }
                // syncobject の待機はスクリプト解析・UI処理を止めない。
                // シグナルまたはタイムアウト後に、同じスクリプト世代だけを再開する。
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    _ = SyncCenter.shared.wait(name: name, timeout: timeout)
                    DispatchQueue.main.async {
                        guard let self,
                              self.isPlaying,
                              self.playbackGeneration == generation else { return }
                        self.processNextUnit()
                    }
                }
                return
            case .wait(let sec):
                scheduleNext(after: max(0.0, sec))
                return
            case .waitAnimation(let animID):
                // If the animation is currently active, set wait flag and pause processing.
                // When the animation finishes, onAnimationFinished will resume playback.
                if serikoExecutor.activeAnimations[animID] != nil {
                    waitingForAnimation = animID
                    return
                } else {
                    // Animation not active; continue immediately.
                    continue
                }
            case .clickWait(let noclear):
                pendingClick = noclear
                return
            case .text(let ch):
                // Character-by-character mode with typing effect
                appendText(String(ch))
                scheduleNext(after: typingInterval)
                return
            case .textChunk(let s):
                // Chunk mode (for quickMode) - display immediately
                appendText(s)
                continue
            case .speak(let s):
                speakText(s)
                continue
            case .speakTextToken(let text):
                speakTextToken(text)
                continue
            case .newline:
                // Display newline with delay
                appendNewline(advance: 1.0)
                scheduleNext(after: typingInterval)
                return
            case .newlineVariation(let type):
                appendNewline(advance: BalloonViewModel.newlineAdvance(for: type))
                scheduleNext(after: typingInterval)
                return
            case .deferredCommand(let command):
                // Execute deferred command immediately (it's already at the right time in the queue)
                NSLog("[GhostManager] Executing deferred command")
                command()
                continue
            case .embeddedEvent(let event, let references):
                // `\![embed]` の結果は、タグの後ろに既に積まれている本文より先に
                // 再生する。応答側のトークンを一時キューへ収集して先頭へ戻す。
                let followingPlayback = playbackQueue
                playbackQueue.removeAll()
                executeEmbeddedEvent(event: event, references: references)
                let embeddedPlayback = playbackQueue
                playbackQueue = embeddedPlayback + followingPlayback
                continue
            }
        }
    }

    private func scheduleNext(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.processNextUnit()
        }
    }

    /// 起動時イベントの応答スクリプト再生が完了したことを、呼出し元へ一度だけ通知する。
    private func finishBootIfNeeded(with result: GhostBootResult? = nil) {
        if let result {
            pendingBootResult = result
        }
        guard let completion = bootCompletion,
              let result = pendingBootResult else {
            return
        }
        bootCompletion = nil
        pendingBootResult = nil
        completion(self, result)
    }

    /// Try to obtain a boot script in order:
    /// 1) 呼出し/切替で指定された GET（OnGhostCalled / OnGhostChanged）
    /// 2) 初回起動のみ GET OnFirstBoot（Reference0 = vanish回数）
    /// 3) GET OnBoot（Reference0 = シェル名。2回目以降の起動もすべて OnBoot）
    /// 4) BridgeToSHIORI for OnBoot
    /// 5) SHIORI が応答しない場合は空応答（合成文は生成しない）
    private func obtainBootScript(
        using runtime: GhostShioriRuntime,
        bootCount: Int,
        initialRequest: GhostBootRequest?
    ) -> GhostBootResult? {
        let hdrs: [String: String] = ["Charset": "UTF-8", "SecurityLevel": "local", "Sender": "Ourin"]
        let shellName = activeShellName

        if let initialRequest {
            var refs = initialRequest.references
            while refs.count < 8 { refs.append("") }
            // OnGhostCalled / OnGhostChanged の Reference7 は、切替先・呼出先のシェル名。
            refs[7] = shellName
            if let r = runtime.request(
                method: "GET",
                id: initialRequest.eventID.rawValue,
                headers: hdrs,
                refs: refs,
                timeout: 4.0
            ), r.ok {
                let v = r.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let pv = v.replacingOccurrences(of: "\n", with: "\\n").prefix(160)
                NSLog("[GhostManager] \(initialRequest.eventID.rawValue) response: ok=true, len=\(v.count), preview=\(pv)")
                if !v.isEmpty {
                    return GhostBootResult(
                        eventID: initialRequest.eventID.rawValue,
                        script: v,
                        shellName: shellName,
                        succeeded: true
                    )
                }
            } else {
                NSLog("[GhostManager] \(initialRequest.eventID.rawValue) request failed or no response")
            }
        }

        if bootCount == 0 {
            // UKADOC: OnFirstBoot Reference0 = vanish された回数（通常 0）
            let vanishCount = UserDefaults.standard.integer(forKey: "OurinVanishCount")
            if let r = runtime.request(method: "GET", id: "OnFirstBoot", headers: hdrs, refs: [String(vanishCount)], timeout: 4.0), r.ok {
                let v = r.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let pv = v.replacingOccurrences(of: "\n", with: "\\n").prefix(160)
                NSLog("[GhostManager] OnFirstBoot response: ok=true, len=\(v.count), preview=\(pv)")
                if !v.isEmpty {
                    return GhostBootResult(
                        eventID: "OnFirstBoot",
                        script: v,
                        shellName: shellName,
                        succeeded: true
                    )
                }
            } else {
                NSLog("[GhostManager] OnFirstBoot request failed or no response")
            }
        }

        // 2) OnBoot（UKADOC: Reference0 = 起動したシェル名）
        if let r = runtime.request(method: "GET", id: "OnBoot", headers: hdrs, refs: [shellName], timeout: 4.0), r.ok {
            let v = r.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let pv = v.replacingOccurrences(of: "\n", with: "\\n").prefix(160)
            NSLog("[GhostManager] OnBoot response: ok=true, len=\(v.count), preview=\(pv)")
            if !v.isEmpty {
                return GhostBootResult(
                    eventID: "OnBoot",
                    script: v,
                    shellName: shellName,
                    succeeded: true
                )
            }
        } else {
            NSLog("[GhostManager] OnBoot request failed or no response")
        }

        // 3) Bridge fallback
        let bridge = BridgeToSHIORI.handle(event: "OnBoot", references: [shellName])
        let bv = bridge.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bv.isEmpty {
            NSLog("[GhostManager] BridgeToSHIORI fallback used (len=\(bv.count))")
            return GhostBootResult(
                eventID: "OnBoot",
                script: bridge,
                shellName: shellName,
                succeeded: true
            )
        }

        // 4) No synthetic greeting: an unavailable SHIORI must remain observable as
        // an empty boot response instead of masking a broken ghost with mock content.
        NSLog("[GhostManager] No SHIORI boot script was returned")
        return nil
    }

    /// 単体テスト実行中かどうか。テスト時は自動システムイベント（タイマー/入力監視等）を抑止する。
    static var isRunningUnderTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
    }

    func startEventBridgeIfNeeded(enableAutoEvents: Bool = false) {
        // Start the event bridge only after the initial UI is ready
        guard (NSApplication.shared.delegate as? AppDelegate)?.eventBridge == nil else {
            // If bridge is already started and we need auto events, restart with auto events enabled
            if enableAutoEvents {
                let bridge = EventBridge.shared
                bridge.stop()
                bridge.start(enableAutoEvents: true)
                Log.debug("[GhostManager] EventBridge restarted with auto events enabled")
            }
            return
        }
        let bridge = EventBridge.shared
        bridge.start(enableAutoEvents: enableAutoEvents)
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.eventBridge = bridge
        }
        Log.debug("[GhostManager] EventBridge started with enableAutoEvents=\(enableAutoEvents)")
    }

    // MARK: - SHIORI Initialization NOTIFYs

    func sendInitializationNotifies(config: GhostConfiguration) {
        let bridge = EventBridge.shared

        // hwnd: Reference0 = comma-separated character window handles
        let hwndValues = characterWindows.sorted(by: { $0.key < $1.key })
            .map { String($0.value.windowNumber) }
        let hwndRef0 = hwndValues.joined(separator: ",")
        let balloonHwnds = balloonWindows.sorted(by: { $0.key < $1.key })
            .map { String($0.value.windowNumber) }
        let hwndRef1 = balloonHwnds.joined(separator: ",")
        bridge.notifyCustom("hwnd", params: [
            "Reference0": hwndRef0,
            "Reference1": hwndRef1
        ], ignoreResponseScript: true)

        // uniqueid: Owned SSTPの照合に使用するため、推測可能なフォルダ名ではなく
        // 起動セッション固有のIDを通知する。
        bridge.notifyCustom("uniqueid", params: [
            "Reference0": sstpUniqueID
        ], ignoreResponseScript: true)

        // basewareversion
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        bridge.notifyCustom("basewareversion", params: [
            "Reference0": "Ourin/\(version)"
        ], ignoreResponseScript: true)

        // capability
        bridge.notifyCustom("capability", params: [
            "Reference0": "response",
            "Reference1": "nobreak",
            "Reference2": "communicate",
            "Reference3": "lock",
            "Reference4": "notify"
        ], ignoreResponseScript: true)

        // OnNotifySelfInfo: ref0=ghostName, ref1=sakuraName, ref2=keroName,
        //   ref3=shellName, ref4=shellPath, ref5=balloonName, ref6=balloonPath
        let shellPath = loadShellPath()?.path ?? ""
        let shellName = activeShellName
        let balloonName = balloonConfig?.name ?? ""
        let balloonPath = self.ghostURL.appendingPathComponent("balloon").path
        bridge.notify(.OnNotifySelfInfo, params: [
            "Reference0": config.sakuraName,
            "Reference1": config.sakuraName,
            "Reference2": config.keroName ?? "",
            "Reference3": shellName,
            "Reference4": shellPath,
            "Reference5": balloonName,
            "Reference6": balloonPath
        ])

        // OnNotifyShellInfo: ref0=shellName, ref1=shellPath
        bridge.notify(.OnNotifyShellInfo, params: [
            "Reference0": shellName,
            "Reference1": shellPath
        ])

        // OnNotifyDressupInfo は起動時だけ NOTIFY で完全な着せ替え定義を送る。
        // デフォルト着せ替えの反映は loadGhost() 内で先に完了させ、ここで状態を確定する。
        notifyDressupInfo(scope: currentScope, requestResponse: false)

        // OnNotifyBalloonInfo: ref0=balloonName, ref1=balloonPath
        bridge.notify(.OnNotifyBalloonInfo, params: [
            "Reference0": balloonName,
            "Reference1": balloonPath
        ])
        if let dispatcher = (NSApp.delegate as? AppDelegate)?.pluginDispatcher {
            let windows = characterWindows.sorted(by: { $0.key < $1.key }).map { $0.value }
            dispatcher.onGhostBoot(
                windows: windows,
                ghostName: config.name,
                shellName: shellName,
                ghostID: config.id ?? ghostURL.lastPathComponent,
                path: ghostURL.path
            )
            dispatcher.onGhostInfoUpdate(
                windows: windows,
                ghostName: config.name,
                shellName: shellName,
                ghostID: config.id ?? ghostURL.lastPathComponent,
                path: ghostURL.path
            )
        }

        sendUserInfoNotify()

        // OnNotifyOSInfo: macOS/CPU/memory/uptime を実環境から通知する。
        bridge.notify(.OnNotifyOSInfo, params: SystemNotificationData.currentOSInfo().parameters)

        // OnNotifyFontInfo: Reference* にインストール済みフォントを1件ずつ並べる。
        bridge.notify(.OnNotifyFontInfo,
                      params: SystemNotificationData.fontParameters(SystemNotificationData.currentFontNames()))

        // OnNotifyInternationalInfo: タイムゾーン・DST・国・言語を通知する。
        bridge.notify(.OnNotifyInternationalInfo,
                      params: SystemNotificationData.currentInternationalInfo().parameters)

        // ownerghostname: list of all running ghosts
        let ghostName = config.sakuraName
        bridge.notifyCustom("ownerghostname", params: [
            "Reference0": ghostName
        ], ignoreResponseScript: true)

        Log.info("[GhostManager] Sent initialization NOTIFY events (hwnd, uniqueid, capability, OnNotifySelfInfo, etc.)")
    }

    /// OnNotifyUserInfo を現在のユーザー設定で送信する。
    /// 起動時だけでなく、設定ダイアログで呼び方が変更された時にも使用する。
    func sendUserInfoNotify() {
        let info = SystemNotificationData.currentUserInfo(addressName: resourceManager.username)
        EventBridge.shared.notify(.OnNotifyUserInfo, params: info.parameters)
    }
}

// MARK: - Owner Draw Menu Actions
extension GhostManager {
    /// メニューアクションを処理
    func handleMenuAction(_ action: String) {
        if action.hasPrefix(PluginMenuEntry.actionPrefix) {
            executePluginMenuAction(action)
            return
        }
        switch action {
        case "menu_ghost_info":
            showGhostInfo()
        case let action where action.hasPrefix("switch_ghost:"):
            let ghostID = String(action.dropFirst("switch_ghost:".count))
            switchGhost(to: ghostID)
        case let action where action.hasPrefix("switch_shell:"):
            let shellID = String(action.dropFirst("switch_shell:".count))
            switchShell(to: shellID)
        case let action where action.hasPrefix("switch_balloon:"):
            let balloonID = String(action.dropFirst("switch_balloon:".count))
            switchBalloon(to: balloonID)
        case let action where action.hasPrefix("dressup_bindgroup:"):
            let raw = String(action.dropFirst("dressup_bindgroup:".count))
            let parts = raw.split(separator: ":").map(String.init)
            if parts.count == 2, let scope = Int(parts[0]), let bindID = Int(parts[1]) {
                toggleDressupBindGroup(scope: scope, bindGroupID: bindID)
            } else if let bindID = Int(raw) {
                toggleDressupBindGroup(scope: currentScope, bindGroupID: bindID)
            }
        case "menu_communicate":
            showCommunicateBox()
        case "menu_reload":
            reloadGhost()
        case "menu_vanish":
            vanishCurrentGhost()
        case "menu_update":
            checkNetworkUpdate()
        case "menu_settings":
            showSettings()
        case "menu_quit":
            NSApplication.shared.terminate(nil)
        default:
            Log.info("[GhostManager] Unknown menu action: \(action)")
        }
    }

    private func executePluginMenuAction(_ action: String) {
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let registry = appDelegate.pluginRegistry,
              let entry = registry.pluginMenuEntry(forActionIdentifier: action) else {
            Log.info("[GhostManager] Unknown plugin menu action: \(action)")
            return
        }

        guard entry.canDispatchRequests else {
            Log.info("[GhostManager] Plugin menu item is metadata-only: \(entry.pluginName) / \(entry.itemID)")
            return
        }

        guard let config = ghostConfig,
              let dispatcher = appDelegate.pluginDispatcher else {
            Log.info("[GhostManager] Plugin dispatcher unavailable for menu action: \(entry.pluginID)")
            return
        }

        dispatcher.onMenuExec(
            menuItemID: entry.itemID,
            targetPluginID: entry.pluginID,
            windows: characterWindows.sorted(by: { $0.key < $1.key }).map { $0.value },
            ghostName: config.name,
            shellName: activeShellName,
            ghostID: config.id ?? ghostURL.lastPathComponent,
            path: ghostURL.path,
            callerGhost: self
        )
    }
    
    /// ゴースト情報を表示
    private func showGhostInfo() {
        let alert = NSAlert()
        alert.messageText = ghostConfig?.name ?? NSLocalizedString("Ghost Info", comment: "ghost info dialog title")
        var lines: [String] = []
        lines.append("Path: \(ghostURL.path)")
        lines.append("Shell: \(activeShellName)")
        if let sakura = ghostConfig?.sakuraName, !sakura.isEmpty {
            lines.append("Sakura: \(sakura)")
        }
        if let kero = ghostConfig?.keroName, !kero.isEmpty {
            lines.append("Kero: \(kero)")
        }
        if let home = ghostConfig?.homeurl, !home.isEmpty {
            lines.append("Home URL: \(home)")
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "ok button"))
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    /// 設定を表示
    private func showSettings() {
        DispatchQueue.main.async {
            if #available(macOS 13, *) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } else {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
            let settingsID = NSUserInterfaceItemIdentifier("SettingsWindow")
            for window in NSApplication.shared.windows {
                if window.identifier == settingsID || window.title == NSLocalizedString("Settings", comment: "Settings window title") {
                    window.makeKeyAndOrderFront(nil)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    return
                }
            }
            let controller = NSHostingController(rootView: ContentView())
            let window = NSWindow(contentViewController: controller)
            window.identifier = settingsID
            window.title = NSLocalizedString("Settings", comment: "Settings window title")
            window.setContentSize(NSSize(width: 900, height: 600))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    
    /// 話しかけるダイアログを表示
    private func showCommunicateBox() {
        DispatchQueue.main.async {
            self.showCommunicateBoxDialog(timeoutMs: nil, initialText: "")
        }
    }

    /// ゴーストを再読み込み
    private func reloadGhost() {
        let name = ghostConfig?.name ?? ""
        Log.info("[GhostManager] Reloading ghost: \(name)")
        pendingDestroyReason = "reload" // shutdown() 時の OnDestroy Reference0 に反映
        EventBridge.shared.notify(.OnClose, refs: ["closeReason": "reload"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.runGhost(at: self.ghostURL)
            }
        }
    }

    /// ゴーストを消滅させる
    private func vanishCurrentGhost() {
        executeVanish(uninstall: true, query: true)
    }

    /// ネットワーク更新を確認
    private func checkNetworkUpdate() {
        // メニュー操作でも更新検査本体を通し、候補検出・適用・失敗理由まで同じイベント列を発火する。
        checkGhostUpdate(options: ["--reason=manual"])
    }

    /// ゴーストを切り替え
    private func switchGhost(to ghostID: String) {
        let target = ghostID.trimmingCharacters(in: .whitespacesAndNewlines).removingPercentEncoding ?? ghostID
        guard !target.isEmpty else {
            Log.info("[GhostManager] switch_ghost ignored: empty target")
            return
        }
        switchGhost(named: target, options: ["--option=raise-event"])
    }
    
    /// シェルを切り替え
    private func switchShell(to shellID: String) {
        let rawTarget = shellID.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = rawTarget.removingPercentEncoding ?? rawTarget
        guard !target.isEmpty else {
            Log.info("[GhostManager] switch_shell ignored: empty target")
            return
        }

        if switchShell(named: target, raiseEvent: true) {
            return
        }

        // Fallback for menu actions that pass index-like values (e.g. "0" / "shell1")
        let shellRoot = ghostURL.appendingPathComponent("shell")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: shellRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            Log.info("[GhostManager] switch_shell failed: shell directory is unavailable")
            return
        }
        let shellNames = entries
            .filter { $0.hasDirectoryPath }
            .map(\.lastPathComponent)
            .sorted()

        let normalized = target.lowercased()
        var resolvedIndex: Int?
        if let n = Int(normalized) {
            resolvedIndex = n
        } else if normalized.hasPrefix("shell"), let n = Int(normalized.dropFirst("shell".count)) {
            resolvedIndex = n
        }

        guard let index = resolvedIndex, shellNames.indices.contains(index) else {
            Log.info("[GhostManager] switch_shell failed: unknown target \(target)")
            return
        }

        let resolvedName = shellNames[index]
        if !switchShell(named: resolvedName, raiseEvent: true) {
            Log.info("[GhostManager] switch_shell failed: resolved shell not available \(resolvedName)")
        }
    }
    
    /// バルーンを切り替え
    private func switchBalloon(to balloonID: String) {
        if let id = Int(balloonID) {
            switchBalloon(to: id, scope: currentScope)
        } else {
            Log.info("[GhostManager] Invalid balloon ID: \(balloonID)")
        }
    }
}
