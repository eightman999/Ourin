import AppKit
import CoreGraphics

/// Renders the square part of an anchor decoration against the balloon surface.
///
/// SwiftUI's blend modes do not expose the complete Win32 SetROP2 truth table.
/// This small bitmap compositor therefore applies the operation to the actual
/// balloon surface pixels before the generated patch is placed behind the text.
enum AnchorRasterImageRenderer {
    /// Create a patch whose coordinate system is the same top-left coordinate
    /// system used by `BalloonView`.
    static func renderPatch(
        background: NSImage?,
        fallbackColor: NSColor,
        surfaceSize: CGSize,
        rect: CGRect,
        operation: AnchorRasterOperation,
        brushColor: NSColor,
        cornerRadius: CGFloat = 2
    ) -> NSImage? {
        let surfaceWidth = Int(surfaceSize.width.rounded(.up))
        let surfaceHeight = Int(surfaceSize.height.rounded(.up))
        let patchWidth = Int(rect.width.rounded(.up))
        let patchHeight = Int(rect.height.rounded(.up))
        guard surfaceWidth > 0, surfaceHeight > 0, patchWidth > 0, patchHeight > 0 else {
            return nil
        }

        var surfacePixels = [UInt8](repeating: 0, count: surfaceWidth * surfaceHeight * 4)
        guard let surfaceContext = CGContext(
            data: &surfacePixels,
            width: surfaceWidth,
            height: surfaceHeight,
            bitsPerComponent: 8,
            bytesPerRow: surfaceWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }

        if let background {
            var proposedRect = CGRect(origin: .zero, size: background.size)
            if let image = background.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
                surfaceContext.draw(image, in: CGRect(x: 0, y: 0, width: surfaceSize.width, height: surfaceSize.height))
            } else {
                surfaceContext.setFillColor(fallbackColor.usingColorSpace(.deviceRGB)?.cgColor ?? NSColor.textBackgroundColor.cgColor)
                surfaceContext.fill(CGRect(x: 0, y: 0, width: surfaceSize.width, height: surfaceSize.height))
            }
        } else {
            surfaceContext.setFillColor(fallbackColor.usingColorSpace(.deviceRGB)?.cgColor ?? NSColor.textBackgroundColor.cgColor)
            surfaceContext.fill(CGRect(x: 0, y: 0, width: surfaceSize.width, height: surfaceSize.height))
        }

        return renderPatch(
            surfacePixels: surfacePixels,
            surfaceSize: surfaceSize,
            rect: rect,
            operation: operation,
            brushColor: brushColor,
            cornerRadius: cornerRadius
        )
    }

    /// Apply an operation to an already-normalized RGBA surface. This overload
    /// keeps the pixel operation independently testable without color-profile
    /// conversion performed by `NSImage`.
    static func renderPatch(
        surfacePixels: [UInt8],
        surfaceSize: CGSize,
        rect: CGRect,
        operation: AnchorRasterOperation,
        brushColor: NSColor,
        cornerRadius: CGFloat = 2
    ) -> NSImage? {
        let surfaceWidth = Int(surfaceSize.width.rounded(.up))
        let surfaceHeight = Int(surfaceSize.height.rounded(.up))
        let patchWidth = Int(rect.width.rounded(.up))
        let patchHeight = Int(rect.height.rounded(.up))
        guard surfaceWidth > 0, surfaceHeight > 0, patchWidth > 0, patchHeight > 0,
              surfacePixels.count >= surfaceWidth * surfaceHeight * 4 else {
            return nil
        }

        let source = RGBColor(color: brushColor)
        let sourceAlpha = UInt8((source.alpha * 255).rounded().clamped(to: 0...255))
        let minX = max(0, Int(floor(rect.minX)))
        let minY = max(0, Int(floor(rect.minY)))
        let maxX = min(surfaceWidth, Int(ceil(rect.maxX)))
        let maxY = min(surfaceHeight, Int(ceil(rect.maxY)))
        let radius = min(max(0, cornerRadius), min(rect.width, rect.height) / 2)

        var patchPixels = [UInt8](repeating: 0, count: patchWidth * patchHeight * 4)
        for localY in 0..<patchHeight {
            for localX in 0..<patchWidth {
                let x = rect.minX + CGFloat(localX) + 0.5
                let y = rect.minY + CGFloat(localY) + 0.5
                guard x >= CGFloat(minX), x < CGFloat(maxX), y >= CGFloat(minY), y < CGFloat(maxY),
                      isInsideRoundedRect(x: x - rect.minX, y: y - rect.minY,
                                          width: rect.width, height: rect.height, radius: radius) else {
                    continue
                }

                let surfaceX = min(surfaceWidth - 1, max(0, Int(floor(x))))
                let surfaceTopY = min(surfaceHeight - 1, max(0, Int(floor(y))))
                // CGContext's bitmap rows are bottom-up from the view's
                // top-left perspective.
                let surfaceY = surfaceHeight - 1 - surfaceTopY
                let destinationIndex = (surfaceY * surfaceWidth + surfaceX) * 4
                let destination = RGBColor(
                    red: unpremultiply(surfacePixels[destinationIndex], alpha: surfacePixels[destinationIndex + 3]),
                    green: unpremultiply(surfacePixels[destinationIndex + 1], alpha: surfacePixels[destinationIndex + 3]),
                    blue: unpremultiply(surfacePixels[destinationIndex + 2], alpha: surfacePixels[destinationIndex + 3]),
                    alpha: Double(surfacePixels[destinationIndex + 3]) / 255
                )
                let result: RGBColor
                if operation == .none {
                    // `none` means that SetROP2 is not selected; preserve the
                    // ordinary opaque brush fill used by SwiftUI.
                    result = source
                } else {
                    let rgb = operation.apply(
                        source: (source.red, source.green, source.blue),
                        destination: (destination.red, destination.green, destination.blue)
                    )
                    result = RGBColor(
                        red: rgb.red,
                        green: rgb.green,
                        blue: rgb.blue,
                        // ROP2 defines RGB only. Keep the surface visible for
                        // opaque brush colors and preserve a transparent base.
                        alpha: sourceAlpha == 255 ? max(destination.alpha, 1) : max(destination.alpha, source.alpha)
                    )
                }

                let patchIndex = (localY * patchWidth + localX) * 4
                patchPixels[patchIndex] = result.red
                patchPixels[patchIndex + 1] = result.green
                patchPixels[patchIndex + 2] = result.blue
                patchPixels[patchIndex + 3] = UInt8((result.alpha * 255).rounded().clamped(to: 0...255))
            }
        }

        let provider = CGDataProvider(data: Data(patchPixels) as CFData)
        guard let provider,
              let patchImage = CGImage(
                  width: patchWidth,
                  height: patchHeight,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: patchWidth * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            return nil
        }
        return NSImage(cgImage: patchImage, size: CGSize(width: patchWidth, height: patchHeight))
    }

    private static func isInsideRoundedRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat) -> Bool {
        guard radius > 0 else { return x >= 0 && y >= 0 && x < width && y < height }
        let nearestX = min(max(x, radius), width - radius)
        let nearestY = min(max(y, radius), height - radius)
        let dx = x - nearestX
        let dy = y - nearestY
        return dx * dx + dy * dy <= radius * radius
    }

    private static func unpremultiply(_ component: UInt8, alpha: UInt8) -> UInt8 {
        guard alpha > 0 else { return 0 }
        return UInt8(min(255, (Int(component) * 255 + Int(alpha) / 2) / Int(alpha)))
    }

    private struct RGBColor {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: Double

        init(red: UInt8, green: UInt8, blue: UInt8, alpha: Double = 1) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        init(color: NSColor) {
            let rgb = color.usingColorSpace(.deviceRGB) ?? NSColor.clear
            self.init(
                red: UInt8((rgb.redComponent * 255).rounded().clamped(to: 0...255)),
                green: UInt8((rgb.greenComponent * 255).rounded().clamped(to: 0...255)),
                blue: UInt8((rgb.blueComponent * 255).rounded().clamped(to: 0...255)),
                alpha: rgb.alphaComponent
            )
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
