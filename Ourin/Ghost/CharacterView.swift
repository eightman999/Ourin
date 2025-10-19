import SwiftUI
import AppKit

/// A view that displays the character's shell image.
struct CharacterView: View {
    /// The ViewModel that provides the character image.
    @ObservedObject var viewModel: CharacterViewModel
    /// Optional callback for handling drag and drop events
    var onDragDropEvent: ((ShioriEvent) -> Void)?

    var body: some View {
        ZStack {
            if let image = viewModel.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .contentShape(Rectangle()) // Make entire image area tappable
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                handleTap(at: value.location)
                            }
                    )
            } else {
                // The view is transparent and shows nothing if there is no image.
                EmptyView()
            }

            // Overlay for drag and drop functionality
            if let onEvent = onDragDropEvent {
                DragDropView(onEvent: onEvent)
            }
        }
    }

    /// Handle tap/click on the character
    private func handleTap(at location: CGPoint) {
        NSLog("[CharacterView] Ghost tapped at location: (\(location.x), \(location.y))")
        // The InputMonitor will dispatch this to SHIORI as OnMouseClick event
        // with the proper coordinates and parameters
    }
}

#if DEBUG
struct CharacterView_Previews: PreviewProvider {
    static var previews: some View {
        let vm = CharacterViewModel()
        // To preview, you would need to load a sample image.
        // For example, from the app's asset catalog or a file path.
        // vm.image = NSImage(named: "someSampleImage")

        return CharacterView(viewModel: vm)
            .frame(width: 200, height: 300)
            .background(Color.gray.opacity(0.3))
    }
}
#endif
