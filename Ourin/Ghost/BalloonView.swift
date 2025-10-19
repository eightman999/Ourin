import SwiftUI

/// A view that displays the ghost's dialogue in a balloon.
struct BalloonView: View {
    /// The ViewModel that provides the balloon text.
    @ObservedObject var viewModel: BalloonViewModel
    var onClick: (() -> Void)? = nil

    var body: some View {
        if !viewModel.text.isEmpty {
            Text(viewModel.text)
                .lineLimit(nil) // Allow unlimited lines
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true) // Allow vertical growth, constrain horizontal
                .frame(maxWidth: 230) // Max width to fit in balloon window (250 - padding)
                .padding()
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(10)
                .shadow(radius: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                )
                .padding() // Padding to ensure shadow is not clipped
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
