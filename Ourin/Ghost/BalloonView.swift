import SwiftUI

/// A view that displays the ghost's dialogue in a balloon.
struct BalloonView: View {
    /// The ViewModel that provides the balloon text.
    @StateObject var viewModel: BalloonViewModel

    var body: some View {
        if !viewModel.text.isEmpty {
            Text(viewModel.text)
                .padding()
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(10)
                .shadow(radius: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                )
                .padding() // Padding to ensure shadow is not clipped
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
