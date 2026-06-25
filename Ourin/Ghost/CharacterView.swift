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
                .frame(width: overlay.image.size.width, height: overlay.image.size.height)
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
                    .frame(width: baseImage.size.width, height: baseImage.size.height)
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

// MARK: - Pixel Hit Testing

/// NSHostingView that only accepts mouse hits on visible character pixels.
///
/// The ghost window itself is rectangular, but surface images are not. Filtering hitTest
/// here keeps transparent surface areas from behaving like clickable/drag targets.
final class CharacterHitTestingHostingView: NSHostingView<CharacterView> {
    private weak var characterViewModel: CharacterViewModel?
    private let alphaThreshold = 0.01

    @MainActor @preconcurrency required init(rootView: CharacterView) {
        self.characterViewModel = rootView.viewModel
        super.init(rootView: rootView)
    }

    convenience init(rootView: CharacterView, viewModel: CharacterViewModel) {
        self.init(rootView: rootView)
        self.characterViewModel = viewModel
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hitView = super.hitTest(point) else { return nil }
        guard let viewModel = characterViewModel else { return hitView }
        guard !viewModel.repaintLocked, viewModel.alpha > alphaThreshold else { return nil }

        let localPoint = characterPoint(from: point, viewModel: viewModel)
        guard isVisibleCharacterPixel(at: localPoint, viewModel: viewModel) else { return nil }
        return hitView
    }

    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown else {
            super.mouseDown(with: event)
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard event.type == .leftMouseDragged else {
            super.mouseDragged(with: event)
            return
        }
        window?.performDrag(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        showRightClickMenu(for: event)
        super.rightMouseUp(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        showRightClickMenu(for: event)
        return nil
    }

    private func characterPoint(from point: NSPoint, viewModel: CharacterViewModel) -> CGPoint {
        let topLeftPoint = CGPoint(
            x: point.x,
            y: isFlipped ? point.y : bounds.height - point.y
        )

        let scaleX = CGFloat(viewModel.scaleX)
        let scaleY = CGFloat(viewModel.scaleY)
        guard abs(scaleX) > .ulpOfOne, abs(scaleY) > .ulpOfOne else {
            return topLeftPoint
        }

        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        return CGPoint(
            x: ((topLeftPoint.x - center.x) / scaleX) + center.x,
            y: ((topLeftPoint.y - center.y) / scaleY) + center.y
        )
    }

    private func isVisibleCharacterPixel(at point: CGPoint, viewModel: CharacterViewModel) -> Bool {
        let canvas = CGSize(width: bounds.width, height: bounds.height)
        guard canvas.width > 0, canvas.height > 0 else { return false }

        if let baseImage = viewModel.image {
            let destination = CGRect(origin: .zero, size: baseImage.size)
            if image(baseImage, isVisibleAt: point, destination: destination, alpha: 1.0) {
                return true
            }
        }

        for overlay in SurfaceOverlay.sortedForDisplay(viewModel.overlays).reversed() {
            let destination = CGRect(origin: overlay.offset, size: overlay.image.size)
            if image(overlay.image, isVisibleAt: point, destination: destination, alpha: overlay.alpha) {
                return true
            }
        }

        for part in viewModel.dressupParts.sorted(by: { $0.zOrder > $1.zOrder }) where part.isEnabled {
            if image(part.image, isVisibleAt: point, destination: part.frame, alpha: 1.0) {
                return true
            }
        }

        for textAnimation in viewModel.textAnimations {
            let textFrame = CGRect(
                x: CGFloat(textAnimation.x) - CGFloat(textAnimation.width) / 2,
                y: CGFloat(textAnimation.y) - CGFloat(textAnimation.height) / 2,
                width: CGFloat(textAnimation.width),
                height: CGFloat(textAnimation.height)
            )
            if textFrame.contains(point) {
                return true
            }
        }

        return false
    }

    private func showRightClickMenu(for event: NSEvent) {
        let locationInWindow = event.locationInWindow
        let screenPoint = window?.convertPoint(toScreen: locationInWindow) ?? NSEvent.mouseLocation
        InputMonitor.shared.rightClickMenuHandler?(screenPoint)
    }

    private func image(_ image: NSImage, isVisibleAt point: CGPoint, destination: CGRect, alpha: Double) -> Bool {
        guard image.isValid, alpha > alphaThreshold, destination.width > 0, destination.height > 0 else {
            return false
        }
        guard destination.contains(point) else { return false }

        let testRect = NSRect(x: point.x, y: point.y, width: 1, height: 1)
        return image.hitTest(
            testRect,
            withDestinationRect: destination,
            context: nil,
            hints: nil,
            flipped: true
        )
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
