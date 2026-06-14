import SwiftUI

/// A view that displays a ghost's dialogue in a balloon.
struct BalloonView: View {
    /// The ViewModel that provides balloon text.
    @ObservedObject var viewModel: BalloonViewModel
    var onClick: (() -> Void)? = nil

    // Balloon configuration and image loader
    var config: BalloonConfig?
    var imageLoader: BalloonImageLoader?

    // Fixed balloon size based on emily4/balloon typical size
    private let balloonWidth: CGFloat = 400
    private let balloonHeight: CGFloat = 150

    var body: some View {
        if !viewModel.text.isEmpty {
            ZStack(alignment: .topLeading) {
                // Background balloon image - use current balloon ID
                if let imageLoader = imageLoader,
                   let balloonImage = imageLoader.loadSurface(index: viewModel.balloonID, type: "s") {
                    Image(nsImage: balloonImage)
                        .resizable()
                        .frame(width: balloonWidth, height: balloonHeight)
                } else {
                    // Fallback to simple background
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.textBackgroundColor))
                        .frame(width: balloonWidth, height: balloonHeight)
                        .shadow(radius:3)
                }

                // Balloon images (both positioned and inline)
                ForEach(viewModel.balloonImages) { balloonImage in
                    if let nsImage = balloonImage.image {
                        Image(nsImage: nsImage)
                            .resizable()
                            .frame(width: CGFloat(nsImage.size.width), height: CGFloat(nsImage.size.height))
                            .offset(x: balloonImage.x, y: balloonImage.y)
                    }
                }

                // Text overlay with proper positioning
                decoratedText(for: viewModel)
                    .lineLimit(nil)
                    .multilineTextAlignment(textAlignment(for: viewModel.textAlign))
                    .frame(
                        width: balloonWidth - CGFloat((config?.originX ?? 20) * 2),
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
            .frame(width: balloonWidth, height: balloonHeight)
            .contentShape(Rectangle())
            .onTapGesture { onClick?() }
        } else {
            // If there is no text,  view should not be visible.
            EmptyView()
        }
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

    @ViewBuilder
    private func styledText(for vm: BalloonViewModel) -> some View {
        let text = Text(vm.text).font(font(for: vm))
        if #available(macOS 13.0, *) {
            text
                .italic(vm.fontItalic)
                .underline(vm.fontUnderline)
                .strikethrough(vm.fontStrike)
                .baselineOffset(baselineOffset(for: vm))
        } else {
            text
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
    private func decoratedText(for vm: BalloonViewModel) -> some View {
        let base = styledText(for: vm)
            .foregroundColor(Color(vm.anchorActive ? vm.anchorFontColor : vm.fontColor))
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
