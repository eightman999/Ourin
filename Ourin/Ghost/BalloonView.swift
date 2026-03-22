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
                styledText(for: viewModel)
                    .lineLimit(nil)
                    .multilineTextAlignment(textAlignment(for: viewModel.textAlign))
                    .foregroundColor(Color(viewModel.anchorActive ? viewModel.anchorFontColor : viewModel.fontColor))
                    .shadow(
                        color: Color(viewModel.shadowColor),
                        radius: shadowRadius(for: viewModel),
                        x: viewModel.shadowStyle == .offset ? 1 : 0,
                        y: viewModel.shadowStyle == .offset ? -1 : 0
                    )
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

    private func shadowRadius(for vm: BalloonViewModel) -> CGFloat {
        switch vm.shadowStyle {
        case .none:
            return 0
        case .offset:
            return 1
        case .outline:
            return max(1, vm.outlineWidth)
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
