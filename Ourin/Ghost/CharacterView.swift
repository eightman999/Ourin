import SwiftUI
import AppKit

// MARK: - Overlay View

/// View for rendering a single surface overlay
struct OverlayView: View {
    let overlay: SurfaceOverlay

    var body: some View {
        if overlay.image.isValid {
            Image(nsImage: overlay.image)
                .resizable()
                .opacity(overlay.alpha)
        } else {
            EmptyView()
        }
    }
}

// MARK: - Dressup Part View

/// View for rendering a dressup part
struct DressupPartView: View {
    let part: DressupPart

    var body: some View {
        if part.isEnabled {
            Image(nsImage: part.image)
                .resizable()
                .frame(width: part.frame.width, height: part.frame.height)
                .position(x: part.frame.midX, y: part.frame.midY)
        } else {
            EmptyView()
        }
    }
}

// MARK: - Character View

/// A view that displays the character's shell image.
struct CharacterView: View {
    /// The ViewModel that provides the character image.
    @ObservedObject var viewModel: CharacterViewModel
    /// Optional callback for handling drag and drop events
    var onDragDropEvent: ((ShioriEvent) -> Void)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Base surface
            if let baseImage = viewModel.image {
                Image(nsImage: baseImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }

            // Overlay layers sorted by z-order then insertion for deterministic stacking.
            ForEach(SurfaceOverlay.sortedForDisplay(viewModel.overlays)) { overlay in
                OverlayView(overlay: overlay)
                    .offset(x: overlay.offset.x, y: overlay.offset.y)
            }

            // Dressup parts (sorted by Z-order)
            ForEach(viewModel.dressupParts.sorted { $0.zOrder < $1.zOrder }) { part in
                DressupPartView(part: part)
            }

            // Text animations from \![anim,add,text,...]
            ForEach(Array(viewModel.textAnimations.enumerated()), id: \.offset) { _, anim in
                Text(anim.text)
                    .font(.custom(anim.fontName, size: CGFloat(anim.fontSize)))
                    .foregroundColor(Color(
                        red: Double(anim.r) / 255.0,
                        green: Double(anim.g) / 255.0,
                        blue: Double(anim.b) / 255.0
                    ))
                    .frame(width: CGFloat(anim.width), height: CGFloat(anim.height), alignment: .leading)
                    .position(x: CGFloat(anim.x), y: CGFloat(anim.y))
            }

            // Drag and drop overlay
            if let onEvent = onDragDropEvent {
                DragDropView(onEvent: onEvent)
            }
        }
        .scaleEffect(x: viewModel.scaleX, y: viewModel.scaleY)
        .blur(radius: filterBlurRadius())
        .brightness(effectBrightness())
        .opacity(viewModel.alpha)
        .allowsHitTesting(!viewModel.repaintLocked)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    handleTap(at: value.location)
                }
        )
    }

    /// Handle tap/click on the character
    private func handleTap(at location: CGPoint) {
        NSLog("[CharacterView] Ghost tapped at location: (\(location.x), \(location.y))")
        // The InputMonitor will dispatch this to SHIORI as OnMouseClick event
        // with the proper coordinates and parameters
    }

    private func filterBlurRadius() -> CGFloat {
        guard let filter = viewModel.activeFilters.last else { return 0 }
        if let first = filter.params.first, let v = Double(first) {
            return max(0, min(20, CGFloat(v)))
        }
        return 2
    }

    private func effectBrightness() -> Double {
        guard !viewModel.activeEffects.isEmpty else { return 0 }
        return min(0.3, Double(viewModel.activeEffects.count) * 0.05)
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
