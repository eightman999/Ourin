import SwiftUI

/// A view that displays the character's shell image.
struct CharacterView: View {
    /// The ViewModel that provides the character image.
    @StateObject var viewModel: CharacterViewModel

    var body: some View {
        if let image = viewModel.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            // The view is transparent and shows nothing if there is no image.
            EmptyView()
        }
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
