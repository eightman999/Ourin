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
                Text(viewModel.text)
                    .lineLimit(nil)
                    .multilineTextAlignment(textAlignment(for: viewModel.textAlign))
                    .font(font(for: viewModel))
                    .foregroundColor(Color(viewModel.anchorActive ? viewModel.anchorFontColor : viewModel.fontColor))
                    .shadow(color: Color(viewModel.shadowColor), radius: viewModel.shadowStyle == .none ? 0 : 1)
                    .frame(
                        width: balloonWidth - CGFloat((config?.originX ?? 20) * 2),
                        height: nil
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
        if !vm.fontName.isEmpty {
            return Font.custom(vm.fontName, size: vm.fontSize)
        } else {
            return Font.system(size: vm.fontSize, weight: vm.fontWeight)
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
