import SwiftUI

/// A view that displays the ghost's dialogue in a balloon.
struct BalloonView: View {
    /// The ViewModel that provides the balloon text.
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
                // Background balloon image
                if let imageLoader = imageLoader,
                   let balloonImage = imageLoader.loadSurface(index: 0, type: "s") {
                    Image(nsImage: balloonImage)
                        .resizable()
                        .frame(width: balloonWidth, height: balloonHeight)
                } else {
                    // Fallback to simple background
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.textBackgroundColor))
                        .frame(width: balloonWidth, height: balloonHeight)
                        .shadow(radius: 3)
                }

                // Text overlay with proper positioning
                Text(viewModel.text)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .font(.system(size: CGFloat(config?.fontHeight ?? 12)))
                    .foregroundColor(config != nil ? Color(config!.fontColor) : Color.primary)
                    .frame(
                        width: balloonWidth - CGFloat((config?.originX ?? 20) * 2),
                        alignment: .topLeading
                    )
                    .padding(
                        EdgeInsets(
                            top: CGFloat(config?.originY ?? 10),
                            leading: CGFloat(config?.originX ?? 20),
                            bottom: 0,
                            trailing: 0
                        )
                    )
            }
            .frame(width: balloonWidth, height: balloonHeight)
            .contentShape(Rectangle())
            .onTapGesture { onClick?() }
        } else {
            // If there is no text, the view should not be visible.
            EmptyView()
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
