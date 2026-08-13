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

    /// \_b の --clipping を SwiftUI の表示矩形へ変換した結果。
    struct BalloonImageLayout: Equatable {
        let displaySize: CGSize
        let imageOffset: CGSize
    }

    /// 画像の切り抜き範囲を画像境界内へ制限し、表示後のサイズと元画像のオフセットを求める。
    /// UKADOC の clipping は画像側の左・上・右・下座標であり、切り抜いた部分は
    /// \_b の x/y 位置を左上として表示する。
    static func balloonImageLayout(for imageSize: CGSize, clipping: CGRect?) -> BalloonImageLayout {
        guard let clipped = normalizedBalloonImageClipping(for: imageSize, clipping: clipping) else {
            return BalloonImageLayout(displaySize: imageSize, imageOffset: .zero)
        }
        return BalloonImageLayout(
            displaySize: clipped.size,
            imageOffset: CGSize(width: -clipped.minX, height: -clipped.minY)
        )
    }

    /// clipping の座標を画像境界内へ正規化する。不正値は nil（画像全体表示）とする。
    static func normalizedBalloonImageClipping(for imageSize: CGSize, clipping: CGRect?) -> CGRect? {
        guard let clipping,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return nil
        }
        let clipped = clipping.standardized.intersection(CGRect(origin: .zero, size: imageSize))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        return clipped
    }

    /// inline 画像用に、clipping 範囲だけを持つ NSImage を生成する。
    /// NSImage のCG座標（左下原点）へ変換してから切り抜く。
    static func clippedBalloonImage(_ image: NSImage, clipping: CGRect?) -> NSImage? {
        guard let clipping,
              let clipped = normalizedBalloonImageClipping(for: image.size, clipping: clipping),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        let cropRect = CGRect(
            x: clipped.minX * scaleX,
            y: (image.size.height - clipped.maxY) * scaleY,
            width: clipped.width * scaleX,
            height: clipped.height * scaleY
        ).intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard cropRect.width > 0, cropRect.height > 0,
              let cropped = cgImage.cropping(to: cropRect.integral) else {
            return image
        }
        return NSImage(cgImage: cropped, size: clipped.size)
    }

    /// バルーン枠サイズ = サーフェス画像の実寸（無ければ descript の maxwidth/maxheight、最後に既定値）。
    private func balloonSize(for image: NSImage?) -> CGSize {
        if let img = image, img.size.width > 1, img.size.height > 1 {
            return img.size
        }
        if let c = config {
            let width = c.maxWidth > 0 ? CGFloat(c.maxWidth) : fallbackBalloonSize.width
            let height = c.maxHeight > 0 ? CGFloat(c.maxHeight) : fallbackBalloonSize.height
            if width > 1, height > 1 {
                return CGSize(width: width, height: height)
            }
        }
        return fallbackBalloonSize
    }

    /// descript.txt の座標指定を、バルーン画像左上原点の矩形へ解決する。
    /// UKADOC では *1 付き座標の負値を画像の右端／下端からの相対値として扱う。
    private static func relativeCoordinate(_ value: Int, extent: CGFloat) -> CGFloat {
        let coordinate = CGFloat(value)
        return coordinate < 0 ? extent + coordinate : coordinate
    }

    /// 描画範囲の右端／下端。`0` は既定値として画像端を意味する。
    private static func boundaryCoordinate(_ value: Int, extent: CGFloat) -> CGFloat {
        value == 0 ? extent : relativeCoordinate(value, extent: extent)
    }

    /// descript.txt の origin / validrect / wordwrappoint / margin を合成した文字領域。
    /// `wordwrappointright` は右寄せ時の折返し位置として使用する SSP 拡張値。
    static func textLayoutRect(
        for config: BalloonConfig?,
        size: CGSize,
        alignment: BalloonViewModel.BalloonTextAlign = .left
    ) -> CGRect {
        guard let config else {
            // 設定が無い Preview / フォールバック表示は従来の既定レイアウトを維持する。
            let originX: CGFloat = 20
            let originY: CGFloat = 10
            return CGRect(
                x: originX,
                y: originY,
                width: max(0, size.width - originX * 2),
                height: max(0, size.height - originY)
            )
        }

        let width = max(0, size.width)
        let height = max(0, size.height)
        let validLeft = min(
            width,
            max(0, relativeCoordinate(config.validRectLeft, extent: width))
        )
        let validTop = min(
            height,
            max(0, relativeCoordinate(config.validRectTop, extent: height))
        )
        let validRight = min(
            width,
            max(validLeft, boundaryCoordinate(config.validRectRight, extent: width))
        )
        let validBottom = min(
            height,
            max(validTop, boundaryCoordinate(config.validRectBottom, extent: height))
        )

        let originX = min(
            validRight,
            max(validLeft, relativeCoordinate(config.originX, extent: width))
        )
        let originY = min(
            validBottom,
            max(validTop, relativeCoordinate(config.originY, extent: height))
        )

        let configuredWrapPoint: Int
        switch alignment {
        case .right where config.wordwrapPointRight != 0:
            configuredWrapPoint = config.wordwrapPointRight
        default:
            configuredWrapPoint = config.wordwrapPointX
        }
        let wrapX = configuredWrapPoint == 0
            ? validRight
            : min(
                validRight,
                max(validLeft, relativeCoordinate(configuredWrapPoint, extent: width))
            )

        let marginX = CGFloat(config.marginX)
        let marginY = CGFloat(config.marginY)
        let left = min(validRight, max(validLeft, originX + marginX))
        let top = min(validBottom, max(validTop, originY + marginY))
        let right = max(left, min(validRight, wrapX - marginX))
        let bottom = max(top, min(validBottom, validBottom - marginY))

        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
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
        let hasBalloonImages = !viewModel.balloonImages.isEmpty
        if !viewModel.text.isEmpty || hasAuxiliaryText || onlineMarkerImage != nil || hasBalloonImages {
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

                // 背景画像は文字の下に描画する（既定値および --option=background）。
                // --option=fixed が指定されていない画像は、テキスト送り（\_l によるカーソル移動）に追従してスクロールする。
                // fixed指定時は背景として固定位置に留まる（UKADOC \_b 仕様）。
                ForEach(viewModel.balloonImages.filter { !$0.isInline && !$0.isForeground }) { balloonImage in
                    balloonImageView(balloonImage)
                }

                if !viewModel.text.isEmpty {
                    let textLayout = Self.textLayoutRect(
                        for: config,
                        size: size,
                        alignment: viewModel.textAlign
                    )
                    // Text overlay with proper positioning. `\_n` uses a fixed horizontal
                    // size and clips at the text region instead of wrapping to a new line.
                    if viewModel.wordWrapEnabled {
                        decoratedText(for: viewModel, surfaceImage: bImage, surfaceSize: size)
                            .lineLimit(nil)
                            .frame(
                                width: textLayout.width,
                                height: textLayout.height,
                                alignment: .topLeading
                            )
                            .padding(
                                EdgeInsets(
                                    top: textLayout.minY + viewModel.cursorY + viewModel.balloonOffsetY,
                                    leading: textLayout.minX + viewModel.cursorX + viewModel.balloonOffsetX,
                                    bottom: 0,
                                    trailing: 0
                                )
                            )
                    } else {
                        decoratedText(for: viewModel, surfaceImage: bImage, surfaceSize: size)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(
                                width: textLayout.width,
                                height: textLayout.height,
                                alignment: .topLeading
                            )
                            .clipped()
                            .padding(
                                EdgeInsets(
                                    top: textLayout.minY + viewModel.cursorY + viewModel.balloonOffsetY,
                                    leading: textLayout.minX + viewModel.cursorX + viewModel.balloonOffsetX,
                                    bottom: 0,
                                    trailing: 0
                                )
                            )
                    }
                }

                // 前景画像は本文とバルーン背景より前面に描画する。
                ForEach(viewModel.balloonImages.filter { !$0.isInline && $0.isForeground }) { balloonImage in
                    balloonImageView(balloonImage)
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
            // 画像単独の \_b も有効な表示内容なので、画像がある場合は表示する。
            EmptyView()
        }
    }

    /// \_b 画像を、必要なら clipping 用のビューポートに入れて表示する。
    @ViewBuilder
    private func balloonImageView(_ balloonImage: BalloonViewModel.BalloonImage) -> some View {
        if let nsImage = balloonImage.image {
            let scrollX = balloonImage.isFixed ? 0 : viewModel.cursorX
            let scrollY = balloonImage.isFixed ? 0 : viewModel.cursorY
            let layout = Self.balloonImageLayout(for: nsImage.size, clipping: balloonImage.clipping)

            ZStack(alignment: .topLeading) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: nsImage.size.width, height: nsImage.size.height)
                    .offset(x: layout.imageOffset.width, y: layout.imageOffset.height)
            }
            .frame(width: layout.displaySize.width, height: layout.displaySize.height, alignment: .topLeading)
            .clipped()
            .offset(x: balloonImage.x + scrollX, y: balloonImage.y + scrollY)
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

    /// Convert BalloonTextAlign to a line container alignment.
    private func lineFrameAlignment(
        for align: BalloonViewModel.BalloonTextAlign,
        valign: BalloonViewModel.BalloonTextVAlign
    ) -> Alignment {
        let horizontal: HorizontalAlignment
        switch align {
        case .left:
            horizontal = .leading
        case .center:
            horizontal = .center
        case .right:
            horizontal = .trailing
        }
        let vertical: VerticalAlignment
        switch valign {
        case .top:
            vertical = .top
        case .center:
            vertical = .center
        case .bottom:
            vertical = .bottom
        }
        return Alignment(horizontal: horizontal, vertical: vertical)
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
    private func segmentText(_ segment: String, for vm: BalloonViewModel, textRange: NSRange, isAnchor: Bool, anchorIndex: Int?, surfaceImage: NSImage?, surfaceSize: CGSize) -> some View {
        if isAnchor {
            let decoration = vm.decoration(forAnchorAt: anchorIndex)
            decoratedAnchorText(segment, for: vm, textRange: textRange, decoration: decoration, surfaceImage: surfaceImage, surfaceSize: surfaceSize)
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
            styledTextWithInlineImages(segment, for: vm, textRange: textRange)
                .foregroundColor(Color(vm.fontColor))
        }
    }

    /// アンカー1セグメントに UKADOC の装飾（none / underline / square / square+underline）を適用する。
    /// - underline: ペン色の下線
    /// - square: ブラシ色の背景＋ペン色の矩形枠
    @ViewBuilder
    private func decoratedAnchorText(_ segment: String, for vm: BalloonViewModel, textRange: NSRange, decoration: AnchorDecoration, surfaceImage: NSImage?, surfaceSize: CGSize) -> some View {
        let base = styledTextWithInlineImages(segment, for: vm, textRange: textRange)
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
        let lineStarts = lineStartOffsets(for: vm.text)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { lineIndex, line in
                let spacing = lineTopOffset(for: vm, lineIndex: lineIndex)
                HStack(alignment: .top, spacing: 0) {
                    if line.isEmpty {
                        // 空行（末尾改行など）でも行高を確保する。
                        Text(" ").font(font(for: vm))
                    } else {
                        let segments = vm.anchorSegments(lineIndex: lineIndex)
                        ForEach(Array(segments.enumerated()), id: \.offset) { segmentIndex, seg in
                            let segmentStart = lineStarts[lineIndex] + segments.prefix(segmentIndex).reduce(0) {
                                $0 + ($1.text as NSString).length
                            }
                            let textRange = NSRange(
                                location: segmentStart,
                                length: (seg.text as NSString).length
                            )
                            segmentText(
                                seg.text,
                                for: vm,
                                textRange: textRange,
                                isAnchor: seg.isAnchor,
                                anchorIndex: seg.anchorIndex,
                                surfaceImage: surfaceImage,
                                surfaceSize: surfaceSize
                            )
                        }
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: lineHeight(for: vm),
                    alignment: lineFrameAlignment(
                        for: vm.lineAlignment(forLineIndex: lineIndex),
                        valign: vm.lineVAlignment(forLineIndex: lineIndex)
                    )
                )
                .padding(.top, spacing.topPadding)
                .offset(y: spacing.yOffset)
            }
        }
    }

    private func lineStartOffsets(for text: String) -> [Int] {
        var offset = 0
        return text.components(separatedBy: "\n").map { line in
            defer { offset += (line as NSString).length + 1 }
            return offset
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

    /// 本文セグメント中の inline 画像を Text の連結要素として組み立てる。
    /// プレースホルダー自体は描画せず、画像は仕様上の1文字幅として本文位置を占有する。
    private func styledTextWithInlineImages(_ text: String, for vm: BalloonViewModel, textRange: NSRange) -> Text {
        let textLength = (text as NSString).length
        let images = vm.balloonImages
            .filter { image in
                guard image.isInline,
                      let offset = image.inlineTextOffset,
                      image.image != nil else { return false }
                return offset >= textRange.location && offset < textRange.location + textRange.length
            }
            .sorted { ($0.inlineTextOffset ?? 0) < ($1.inlineTextOffset ?? 0) }

        guard !images.isEmpty else {
            return styledTextPart(
                text.replacingOccurrences(of: BalloonViewModel.inlineImagePlaceholder, with: ""),
                for: vm
            )
        }

        var result = Text(verbatim: "")
        var cursor = 0
        for balloonImage in images {
            guard let offset = balloonImage.inlineTextOffset,
                  let originalImage = balloonImage.image else { continue }
            let nsImage = Self.clippedBalloonImage(originalImage, clipping: balloonImage.clipping) ?? originalImage
            let localOffset = max(0, min(textLength, offset - textRange.location))
            if localOffset > cursor {
                let prefix = (text as NSString).substring(with: NSRange(
                    location: cursor,
                    length: localOffset - cursor
                ))
                result = result + styledTextPart(prefix, for: vm)
            }

            var imageText = Text(Image(nsImage: nsImage)).font(font(for: vm))
            if #available(macOS 13.0, *) {
                imageText = imageText.baselineOffset(baselineOffset(for: vm))
            }
            result = result + imageText
            // U+FFFC はUTF-16で1単位なので、次の文字から再開する。
            cursor = min(textLength, localOffset + 1)
        }

        if cursor < textLength {
            let suffix = (text as NSString).substring(with: NSRange(
                location: cursor,
                length: textLength - cursor
            ))
            result = result + styledTextPart(
                suffix.replacingOccurrences(of: BalloonViewModel.inlineImagePlaceholder, with: ""),
                for: vm
            )
        }
        return result
    }

    private func styledTextPart(_ text: String, for vm: BalloonViewModel) -> Text {
        var result = Text(verbatim: text).font(font(for: vm))
        if #available(macOS 13.0, *) {
            result = result
                .italic(vm.fontItalic)
                .underline(vm.fontUnderline)
                .strikethrough(vm.fontStrike)
                .baselineOffset(baselineOffset(for: vm))
        }
        return result
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
