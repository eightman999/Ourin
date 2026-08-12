import SwiftUI
import AppKit

/// A view that displays a ghost's dialogue in a balloon.
struct BalloonView: View {
    /// The ViewModel that provides balloon text.
    @ObservedObject var viewModel: BalloonViewModel
    var onClick: (() -> Void)? = nil
    /// `\_a` 範囲アンカーがクリックされたときに、クリックされたアンカーを通知する。
    var onAnchorClick: ((BalloonAnchorRange) -> Void)? = nil
    /// `\_a` 範囲アンカーの実ポインタ入退場を通知する（true=入場、false=退場）。
    var onAnchorHover: ((BalloonAnchorRange, Bool) -> Void)? = nil

    // Balloon configuration and image loader
    var config: BalloonConfig?
    var imageLoader: BalloonImageLoader?

    // バルーンの既定サイズ（画像も maxwidth/maxheight も無い場合のフォールバック）
    private let fallbackBalloonSize = CGSize(width: 400, height: 150)

    /// 変換後の実表示サイズ。負の倍率は反転表示なので、レイアウト領域は絶対値で求める。
    static func scaledSize(for baseSize: CGSize, scaleX: Double, scaleY: Double) -> CGSize {
        let x = scaleX.isFinite ? abs(CGFloat(scaleX)) : 1
        let y = scaleY.isFinite ? abs(CGFloat(scaleY)) : 1
        return CGSize(width: baseSize.width * x, height: baseSize.height * y)
    }

    /// バルーン枠サイズ = サーフェス画像の実寸（無ければ descript の maxwidth/maxheight、最後に既定値）。
    private func balloonSize(for image: NSImage?) -> CGSize {
        if let img = image, img.size.width > 1, img.size.height > 1 {
            return img.size
        }
        if let c = config, c.maxWidth > 0, c.maxHeight > 0 {
            return CGSize(width: CGFloat(c.maxWidth), height: CGFloat(c.maxHeight))
        }
        return fallbackBalloonSize
    }

    /// テキスト領域幅 = validrect（負値は右端からのオフセット）から算出。無ければ origin マージンを控除。
    private func textWidth(for size: CGSize) -> CGFloat {
        if let c = config, c.validRectRight != 0 || c.validRectLeft != 0 {
            let rightEdge = c.validRectRight > 0 ? c.validRectRight : Int(size.width) + c.validRectRight
            let w = rightEdge - c.validRectLeft
            if w > 0 { return CGFloat(w) }
        }
        return size.width - CGFloat((config?.originX ?? 20) * 2)
    }

    var body: some View {
        let hasBalloonNumber = viewModel.balloonNumberVisible
            && (!viewModel.balloonNumberFileName.isEmpty
                || !viewModel.balloonNumberCurrent.isEmpty
                || !viewModel.balloonNumberMaximum.isEmpty)
        let onlineMarkerImage = viewModel.onlineModeActive
            ? imageLoader?.loadOnlineMarker(
                index: viewModel.onlineMarkerIndex,
                filenamePrefix: config?.onlineMarkerFilename ?? "online"
            )
            : nil
        let hasAuxiliaryText = !viewModel.balloonMarkerText.isEmpty || hasBalloonNumber
        if !viewModel.text.isEmpty || hasAuxiliaryText || onlineMarkerImage != nil {
            let bImage = imageLoader?.loadSurface(index: viewModel.balloonID, type: "s")
            let size = balloonSize(for: bImage)
            let scaledSize = Self.scaledSize(
                for: size,
                scaleX: viewModel.scaleX,
                scaleY: viewModel.scaleY
            )
            ZStack(alignment: .topLeading) {
                // Background balloon image - use current balloon ID
                if let bImage = bImage {
                    Image(nsImage: bImage)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                } else {
                    // Fallback to simple background
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.textBackgroundColor))
                        .frame(width: size.width, height: size.height)
                        .shadow(radius:3)
                }

                if let onlineMarkerImage {
                    let markerSize = onlineMarkerImage.size
                    Image(nsImage: onlineMarkerImage)
                        .resizable()
                        .frame(width: markerSize.width, height: markerSize.height)
                        .offset(
                            x: markerOffset(
                                coordinate: config?.onlineMarkerX ?? 16,
                                markerLength: markerSize.width,
                                containerLength: size.width
                            ),
                            y: markerOffset(
                                coordinate: config?.onlineMarkerY ?? 6,
                                markerLength: markerSize.height,
                                containerLength: size.height
                            )
                        )
                }

                // Balloon images (both positioned and inline)
                // --option=fixed が指定されていない画像は、テキスト送り（\_l によるカーソル移動）に追従してスクロールする。
                // fixed指定時は背景として固定位置に留まる（UKADOC \_b 仕様）。
                ForEach(viewModel.balloonImages) { balloonImage in
                    if let nsImage = balloonImage.image {
                        let scrollX = balloonImage.isFixed ? 0 : viewModel.cursorX
                        let scrollY = balloonImage.isFixed ? 0 : viewModel.cursorY
                        Image(nsImage: nsImage)
                            .resizable()
                            .frame(width: CGFloat(nsImage.size.width), height: CGFloat(nsImage.size.height))
                            .offset(x: balloonImage.x + scrollX, y: balloonImage.y + scrollY)
                    }
                }

                if !viewModel.text.isEmpty {
                    // Text overlay with proper positioning
                    decoratedText(for: viewModel, surfaceImage: bImage, surfaceSize: size)
                        .lineLimit(nil)
                        .multilineTextAlignment(textAlignment(for: viewModel.textAlign))
                        .frame(
                            width: textWidth(for: size),
                            height: nil,
                            alignment: textFrameAlignment(for: viewModel.textVAlign)
                        )
                        .padding(
                            EdgeInsets(
                                top: CGFloat(config?.originY ?? 10) + viewModel.cursorY + viewModel.balloonOffsetY,
                                leading: CGFloat(config?.originX ?? 20) + viewModel.cursorX + viewModel.balloonOffsetX,
                                bottom: 0,
                                trailing: 0
                            )
                        )
                }

                VStack(alignment: .trailing, spacing: 2) {
                    Spacer(minLength: 0)
                    if !viewModel.balloonMarkerText.isEmpty {
                        Text(viewModel.balloonMarkerText)
                            .font(.caption)
                            .foregroundColor(Color(viewModel.fontColor))
                    }
                    if hasBalloonNumber {
                        Text(balloonNumberText)
                            .font(.caption)
                            .foregroundColor(Color(viewModel.fontColor))
                    }
                }
                .frame(width: size.width - 12, height: size.height - 12, alignment: .bottomTrailing)
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(
                x: viewModel.scaleX.isFinite ? viewModel.scaleX : 1,
                y: viewModel.scaleY.isFinite ? viewModel.scaleY : 1,
                anchor: .center
            )
            .frame(width: scaledSize.width, height: scaledSize.height, alignment: .center)
            .coordinateSpace(name: "balloon")
            .contentShape(Rectangle())
            .onTapGesture { onClick?() }
        } else {
            // If there is no text,  view should not be visible.
            EmptyView()
        }
    }

    /// Balloon coordinates may be negative, in which case they are measured
    /// from the right/bottom edge of the balloon image (UKADOC descript.txt).
    private func markerOffset(coordinate: Int, markerLength: CGFloat, containerLength: CGFloat) -> CGFloat {
        let value = CGFloat(coordinate)
        return value < 0 ? containerLength + value - markerLength : value
    }

    private var balloonNumberText: String {
        let file = viewModel.balloonNumberFileName
        let current = viewModel.balloonNumberCurrent
        let maximum = viewModel.balloonNumberMaximum
        var body = ""
        if !current.isEmpty || !maximum.isEmpty {
            body = current
            if !maximum.isEmpty { body += "/\(maximum)" }
        }
        if !file.isEmpty && !body.isEmpty { return "\(file)  \(body)" }
        return file.isEmpty ? body : file
    }

    /// Convert BalloonTextAlign to TextAlignment
    private func textAlignment(for align: BalloonViewModel.BalloonTextAlign) -> TextAlignment {
        switch align {
        case .left:
            return .leading
        case .center:
            return .center
        case .right:
            return .trailing
        }
    }

    /// Create Font from BalloonViewModel properties
    private func font(for vm: BalloonViewModel) -> Font {
        let baseSize = vm.fontSize
        let effectiveSize = (vm.fontSubscript || vm.fontSuperscript) ? baseSize * 0.85 : baseSize
        if !vm.fontName.isEmpty {
            return Font.custom(vm.fontName, size: effectiveSize)
        } else {
            return Font.system(size: effectiveSize, weight: vm.fontWeight)
        }
    }

    /// 行送り（行高）の計測値。`\n[half]` / `\n[パーセント]` の送り倍率を実際のピクセルへ換算する。
    private func lineHeight(for vm: BalloonViewModel) -> CGFloat {
        let baseSize = vm.fontSize
        let effectiveSize = (vm.fontSubscript || vm.fontSuperscript) ? baseSize * 0.85 : baseSize
        let nsFont: NSFont
        if !vm.fontName.isEmpty, let custom = NSFont(name: vm.fontName, size: effectiveSize) {
            nsFont = custom
        } else {
            nsFont = NSFont.systemFont(ofSize: effectiveSize)
        }
        return nsFont.ascender + abs(nsFont.descender) + nsFont.leading
    }

    /// 1行分のテキストを、アンカー範囲 / 非アンカーセグメントに分けて描画する。
    /// アンカーセグメントはアンカー色で描画し、クリック時に所属アンカーを通知する。
    /// 装飾は `anchorstyle`（選択中）→ `anchorvisited*`（訪問済み）→ `anchornotselect*`（非選択）の順で決まる。
    @ViewBuilder
    private func segmentText(_ segment: String, for vm: BalloonViewModel, isAnchor: Bool, anchorIndex: Int?, surfaceImage: NSImage?, surfaceSize: CGSize) -> some View {
        if isAnchor {
            let decoration = vm.decoration(forAnchorAt: anchorIndex)
            decoratedAnchorText(segment, for: vm, decoration: decoration, surfaceImage: surfaceImage, surfaceSize: surfaceSize)
                .contentShape(Rectangle())
                .onHover { hovering in
                    guard let anchorIndex = anchorIndex else { return }
                    if hovering {
                        vm.activeAnchorIndex = anchorIndex
                    } else if vm.activeAnchorIndex == anchorIndex {
                        vm.activeAnchorIndex = nil
                    }
                    if vm.anchors.indices.contains(anchorIndex) {
                        onAnchorHover?(vm.anchors[anchorIndex], hovering)
                    }
                }
                .onTapGesture {
                    if let anchorIndex = anchorIndex, vm.anchors.indices.contains(anchorIndex) {
                        onAnchorClick?(vm.anchors[anchorIndex])
                    }
                }
        } else {
            styledText(segment, for: vm)
                .foregroundColor(Color(vm.fontColor))
        }
    }

    /// アンカー1セグメントに UKADOC の装飾（none / underline / square / square+underline）を適用する。
    /// - underline: ペン色の下線
    /// - square: ブラシ色の背景＋ペン色の矩形枠
    @ViewBuilder
    private func decoratedAnchorText(_ segment: String, for vm: BalloonViewModel, decoration: AnchorDecoration, surfaceImage: NSImage?, surfaceSize: CGSize) -> some View {
        let base = styledText(segment, for: vm)
            .foregroundColor(Color(decoration.fontColor))
        switch decoration.style {
        case .none:
            base
        case .underline:
            underlineView(base, penColor: decoration.penColor)
        case .square:
            squareView(base, decoration: decoration, surfaceImage: surfaceImage, surfaceSize: surfaceSize)
        case .squareUnderline:
            underlineView(squareView(base, decoration: decoration, surfaceImage: surfaceImage, surfaceSize: surfaceSize), penColor: decoration.penColor)
        }
    }

    /// 下線付きテキストビュー（pen = 下線色）。`underline(color:)` は macOS 13.0+ のため、それ以前は装飾なしにフォールバックする。
    @ViewBuilder
    private func underlineView(_ content: some View, penColor: NSColor) -> some View {
        if #available(macOS 13.0, *) {
            content.underline(true, color: Color(penColor))
        } else {
            content
        }
    }

    /// 矩形枠（square）付きテキストビュー。brush = 背景色、pen = 枠線色。
    @ViewBuilder
    private func squareView(_ content: some View, decoration: AnchorDecoration, surfaceImage: NSImage?, surfaceSize: CGSize) -> some View {
        content
            .padding(.horizontal, 2)
            .background(GeometryReader { proxy in
                if decoration.rasterOperation == .none {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(decoration.brushColor))
                } else if let patch = AnchorRasterImageRenderer.renderPatch(
                    background: surfaceImage,
                    fallbackColor: NSColor.textBackgroundColor,
                    surfaceSize: surfaceSize,
                    rect: proxy.frame(in: .named("balloon")),
                    operation: decoration.rasterOperation,
                    brushColor: decoration.brushColor
                ) {
                    Image(nsImage: patch)
                        .resizable()
                        .interpolation(.none)
                } else {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(decoration.brushColor))
                }
            })
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color(decoration.penColor), lineWidth: 1)
            )
    }

    /// 行 index の上端に適用する垂直送り（正の拡大はパディング、負の縮小はオフセットで表現）。
    private func lineTopOffset(for vm: BalloonViewModel, lineIndex: Int) -> (topPadding: CGFloat, yOffset: CGFloat) {
        let advance = vm.leadingAdvance(forLineIndex: lineIndex)
        let delta = (advance - 1) * lineHeight(for: vm)
        return (max(0, delta), min(0, delta))
    }

    /// バルーン本文全体を、行ごとのテキスト＋可変改行送り＋アンカー範囲を反映して構成する。
    @ViewBuilder
    private func balloonTextContent(for vm: BalloonViewModel, surfaceImage: NSImage?, surfaceSize: CGSize) -> some View {
        let lines = vm.text.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { lineIndex, line in
                let spacing = lineTopOffset(for: vm, lineIndex: lineIndex)
                HStack(alignment: .top, spacing: 0) {
                    if line.isEmpty {
                        // 空行（末尾改行など）でも行高を確保する。
                        Text(" ").font(font(for: vm))
                    } else {
                        ForEach(Array(vm.anchorSegments(lineIndex: lineIndex).enumerated()), id: \.offset) { _, seg in
                            segmentText(seg.text, for: vm, isAnchor: seg.isAnchor, anchorIndex: seg.anchorIndex, surfaceImage: surfaceImage, surfaceSize: surfaceSize)
                        }
                    }
                }
                .padding(.top, spacing.topPadding)
                .offset(y: spacing.yOffset)
            }
        }
    }

    @ViewBuilder
    private func styledText(_ text: String, for vm: BalloonViewModel) -> some View {
        let result = Text(text).font(font(for: vm))
        if #available(macOS 13.0, *) {
            result
                .italic(vm.fontItalic)
                .underline(vm.fontUnderline)
                .strikethrough(vm.fontStrike)
                .baselineOffset(baselineOffset(for: vm))
        } else {
            result
        }
    }

    private func textFrameAlignment(for valign: BalloonViewModel.BalloonTextVAlign) -> Alignment {
        switch valign {
        case .top:
            return .topLeading
        case .center:
            return .leading
        case .bottom:
            return .bottomLeading
        }
    }

    private func baselineOffset(for vm: BalloonViewModel) -> CGFloat {
        if vm.fontSubscript {
            return -vm.fontSize * 0.2
        }
        if vm.fontSuperscript {
            return vm.fontSize * 0.2
        }
        return 0
    }

    /// 文字色＋装飾（影／縁取り）を適用したテキストビューを返す。
    /// - `.offset`: ドロップシャドウ（右下 1px）
    /// - `.outline`: 8方向のオフセット影による縁取り（単純なブラーではなく実際のアウトライン）
    @ViewBuilder
    private func decoratedText(for vm: BalloonViewModel, surfaceImage: NSImage?, surfaceSize: CGSize) -> some View {
        let base = balloonTextContent(for: vm, surfaceImage: surfaceImage, surfaceSize: surfaceSize)
        switch vm.shadowStyle {
        case .none:
            base
        case .offset:
            base.shadow(color: Color(vm.shadowColor), radius: 1, x: 1, y: -1)
        case .outline:
            let w = max(1, vm.outlineWidth)
            let c = Color(vm.shadowColor)
            // 上下左右＋斜め4方向に縁取り色の影を重ね、文字の輪郭を描く
            base
                .shadow(color: c, radius: 0, x:  w, y: 0)
                .shadow(color: c, radius: 0, x: -w, y: 0)
                .shadow(color: c, radius: 0, x: 0, y:  w)
                .shadow(color: c, radius: 0, x: 0, y: -w)
                .shadow(color: c, radius: 0, x:  w, y:  w)
                .shadow(color: c, radius: 0, x: -w, y: -w)
                .shadow(color: c, radius: 0, x:  w, y: -w)
                .shadow(color: c, radius: 0, x: -w, y:  w)
        }
    }
}

#if DEBUG
struct BalloonView_Previews: PreviewProvider {
    static var previews: some View {
        let vmWithText = BalloonViewModel()
        vmWithText.text = "こんにちは、世界！\nThis is a sample balloon message."

        let vmEmpty = BalloonViewModel()

        return VStack {
            BalloonView(viewModel: vmWithText)
                .frame(width: 300)
            BalloonView(viewModel: vmEmpty)
        }
        .padding()
    }
}
#endif
