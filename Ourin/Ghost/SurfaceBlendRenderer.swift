import AppKit
import CoreGraphics

/// SERIKO image-compositing methods that depend on the destination alpha.
enum SurfaceBlendMode: Equatable {
    case normal
    case overlayFast
    case interpolate
    case asis
    case replace
    case reduce
    case blend(SerikoBlendMode, destinationAlphaAware: Bool)
}

/// CPU compositor for SERIKO methods whose result cannot be represented by a
/// simple SwiftUI opacity modifier. The input/output buffers use an
/// unpremultiplied RGBA layout with rows ordered from the top of the image.
enum SurfaceBlendRenderer {
    static func composite(base: NSImage?, overlays: [SurfaceOverlay]) -> NSImage? {
        // Treat the base as an ordinary layer so `background` animations can
        // be placed before it. A synthetic insertion order keeps the base
        // before ordinary zOrder=0 overlays while preserving all existing
        // overlay ordering rules.
        var layers = overlays
        if let base {
            layers.append(SurfaceOverlay(
                id: "__base_surface__",
                image: base,
                zOrder: 0,
                insertionOrder: Int.min,
                blendMode: .normal
            ))
        }
        let ordered = SurfaceOverlay.sortedForDisplay(layers)
        let canvasSize = canvasSize(base: nil, overlays: ordered)
        let width = Int(canvasSize.width.rounded(.up))
        let height = Int(canvasSize.height.rounded(.up))
        guard width > 0, height > 0 else { return nil }

        var destination = imagePixels(nil, size: CGSize(width: width, height: height))
        for overlay in ordered where overlay.image.isValid {
            let sourceSize = CGSize(
                width: max(1, overlay.image.size.width.rounded(.up)),
                height: max(1, overlay.image.size.height.rounded(.up))
            )
            let source = imagePixels(overlay.image, size: sourceSize)
            destination = composite(
                destinationPixels: destination,
                destinationSize: CGSize(width: width, height: height),
                sourcePixels: source,
                sourceSize: sourceSize,
                offset: overlay.offset,
                mode: overlay.blendMode,
                opacity: overlay.alpha
            )
        }
        return image(pixels: destination, size: CGSize(width: width, height: height))
    }

    /// Testable pixel-level composition entry point.
    static func composite(
        destinationPixels: [UInt8],
        destinationSize: CGSize,
        sourcePixels: [UInt8],
        sourceSize: CGSize,
        offset: CGPoint = .zero,
        mode: SurfaceBlendMode,
        opacity: Double = 1
    ) -> [UInt8] {
        let destinationWidth = Int(destinationSize.width.rounded(.up))
        let destinationHeight = Int(destinationSize.height.rounded(.up))
        let sourceWidth = Int(sourceSize.width.rounded(.up))
        let sourceHeight = Int(sourceSize.height.rounded(.up))
        guard destinationWidth > 0, destinationHeight > 0,
              sourceWidth > 0, sourceHeight > 0,
              destinationPixels.count >= destinationWidth * destinationHeight * 4,
              sourcePixels.count >= sourceWidth * sourceHeight * 4 else {
            return destinationPixels
        }

        var result = Array(destinationPixels.prefix(destinationWidth * destinationHeight * 4))
        let offsetX = Int(offset.x.rounded(.down))
        let offsetY = Int(offset.y.rounded(.down))
        let clampedOpacity = max(0, min(1, opacity))

        for sourceY in 0..<sourceHeight {
            let destinationY = sourceY + offsetY
            guard destinationY >= 0, destinationY < destinationHeight else { continue }
            for sourceX in 0..<sourceWidth {
                let destinationX = sourceX + offsetX
                guard destinationX >= 0, destinationX < destinationWidth else { continue }

                let sourceIndex = (sourceY * sourceWidth + sourceX) * 4
                let destinationIndex = (destinationY * destinationWidth + destinationX) * 4
                let sourceAlpha = Double(sourcePixels[sourceIndex + 3]) / 255 * clampedOpacity
                let destinationAlpha = Double(result[destinationIndex + 3]) / 255
                let effectiveAlpha: Double
                switch mode {
                case .normal:
                    effectiveAlpha = sourceAlpha
                case .overlayFast:
                    // UKADOC: the less transparent the base layer is, the
                    // more strongly the new layer is composited.
                    effectiveAlpha = sourceAlpha * destinationAlpha
                case .interpolate:
                    // UKADOC: the more transparent the base layer is, the
                    // more strongly the new layer is composited.
                    effectiveAlpha = sourceAlpha * (1 - destinationAlpha)
                case .asis:
                    // asis ignores the source transparency/key colour. The
                    // RGB values have already passed through surface loading.
                    effectiveAlpha = clampedOpacity
                case .replace:
                    effectiveAlpha = sourceAlpha
                case .reduce:
                    effectiveAlpha = 0
                case .blend(_, let destinationAlphaAware):
                    effectiveAlpha = sourceAlpha * (destinationAlphaAware ? destinationAlpha : 1)
                }

                let outputAlpha = effectiveAlpha + destinationAlpha * (1 - effectiveAlpha)
                let sourceRed = Double(sourcePixels[sourceIndex]) / 255
                let sourceGreen = Double(sourcePixels[sourceIndex + 1]) / 255
                let sourceBlue = Double(sourcePixels[sourceIndex + 2]) / 255
                let destinationRed = Double(result[destinationIndex]) / 255
                let destinationGreen = Double(result[destinationIndex + 1]) / 255
                let destinationBlue = Double(result[destinationIndex + 2]) / 255
                if case .replace = mode {
                    // replace is scoped to the source image rectangle. A fully
                    // transparent source pixel therefore clears the destination
                    // instead of falling back to source-over.
                    result[destinationIndex] = byte(sourceRed)
                    result[destinationIndex + 1] = byte(sourceGreen)
                    result[destinationIndex + 2] = byte(sourceBlue)
                    result[destinationIndex + 3] = byte(sourceAlpha)
                    continue
                }
                if case .reduce = mode {
                    // reduce keeps the destination colour and multiplies its
                    // alpha by the source alpha. Source RGB is intentionally
                    // ignored by the SERIKO specification.
                    result[destinationIndex] = byte(destinationRed)
                    result[destinationIndex + 1] = byte(destinationGreen)
                    result[destinationIndex + 2] = byte(destinationBlue)
                    result[destinationIndex + 3] = byte(destinationAlpha * sourceAlpha)
                    continue
                }
                let blended = blendComponents(
                    mode: mode,
                    source: (sourceRed, sourceGreen, sourceBlue),
                    destination: (destinationRed, destinationGreen, destinationBlue),
                    x: sourceX,
                    y: sourceY
                )
                let red = compositedComponent(
                    source: blended.0,
                    destination: destinationRed,
                    sourceAlpha: effectiveAlpha,
                    destinationAlpha: destinationAlpha,
                    outputAlpha: outputAlpha
                )
                let green = compositedComponent(
                    source: blended.1,
                    destination: destinationGreen,
                    sourceAlpha: effectiveAlpha,
                    destinationAlpha: destinationAlpha,
                    outputAlpha: outputAlpha
                )
                let blue = compositedComponent(
                    source: blended.2,
                    destination: destinationBlue,
                    sourceAlpha: effectiveAlpha,
                    destinationAlpha: destinationAlpha,
                    outputAlpha: outputAlpha
                )

                result[destinationIndex] = byte(red)
                result[destinationIndex + 1] = byte(green)
                result[destinationIndex + 2] = byte(blue)
                result[destinationIndex + 3] = byte(outputAlpha)
            }
        }
        return result
    }

    private static func blendComponents(
        mode: SurfaceBlendMode,
        source: (Double, Double, Double),
        destination: (Double, Double, Double),
        x: Int,
        y: Int
    ) -> (Double, Double, Double) {
        guard case .blend(let blend, _) = mode else { return source }

        switch blend {
        case .multiply:
            return componentWise(source, destination) { $0 * $1 }
        case .screen:
            return componentWise(source, destination) { $0 + $1 - $0 * $1 }
        case .overlay:
            return componentWise(source, destination) { s, d in
                d <= 0.5 ? 2 * s * d : 1 - 2 * (1 - s) * (1 - d)
            }
        case .add, .addGlow:
            return componentWise(source, destination) { min(1, $0 + $1) }
        case .softLight:
            return componentWise(source, destination) { s, d in
                if s <= 0.5 {
                    return d - (1 - 2 * s) * d * (1 - d)
                }
                let g = d <= 0.25 ? ((16 * d - 12) * d + 4) * d : sqrt(d)
                return d + (2 * s - 1) * (g - d)
            }
        case .hardLight:
            return componentWise(source, destination) { s, d in
                s <= 0.5 ? 2 * s * d : 1 - 2 * (1 - s) * (1 - d)
            }
        case .colorDodge, .colorDodgeGlow:
            return componentWise(source, destination) { s, d in
                s >= 1 ? 1 : min(1, d / max(1e-9, 1 - s))
            }
        case .colorBurn:
            return componentWise(source, destination) { s, d in
                s <= 0 ? 0 : 1 - min(1, (1 - d) / s)
            }
        case .linearBurn:
            return componentWise(source, destination) { max(0, $0 + $1 - 1) }
        case .difference:
            return componentWise(source, destination) { abs($0 - $1) }
        case .exclusion:
            return componentWise(source, destination) { $0 + $1 - 2 * $0 * $1 }
        case .subtract:
            return componentWise(source, destination) { max(0, $1 - $0) }
        case .divide:
            return componentWise(source, destination) { s, d in
                s <= 1e-9 ? 1 : min(1, d / s)
            }
        case .darken:
            return componentWise(source, destination, function: min)
        case .lighten:
            return componentWise(source, destination, function: max)
        case .darkerColor:
            return luminance(destination) <= luminance(source) ? destination : source
        case .lighterColor:
            return luminance(destination) >= luminance(source) ? destination : source
        case .vividLight:
            return componentWise(source, destination) { s, d in
                s < 0.5
                    ? colorBurnComponent(base: d, blend: min(1, 2 * s))
                    : colorDodgeComponent(base: d, blend: min(1, 2 * (s - 0.5)))
            }
        case .linearLight:
            return componentWise(source, destination) { s, d in max(0, min(1, d + 2 * s - 1)) }
        case .pinLight:
            return componentWise(source, destination) { s, d in
                s < 0.5 ? min(d, 2 * s) : max(d, 2 * s - 1)
            }
        case .hardMix:
            let vivid = blendComponents(mode: .blend(.vividLight, destinationAlphaAware: false), source: source, destination: destination, x: x, y: y)
            return (
                vivid.0 >= 0.5 ? 1 : 0,
                vivid.1 >= 0.5 ? 1 : 0,
                vivid.2 >= 0.5 ? 1 : 0
            )
        case .hue:
            return hslComposite(source: source, destination: destination, preserve: .hue)
        case .saturation:
            return hslComposite(source: source, destination: destination, preserve: .saturation)
        case .color:
            return hslComposite(source: source, destination: destination, preserve: .color)
        case .luminosity:
            return hslComposite(source: source, destination: destination, preserve: .luminosity)
        case .dither:
            // SSP の dither は実装依存の乱数ではなく、隣接画素へ分散する
            // 二値化合成として安定させる。フレームごとのちらつきを避けるため
            // 座標ベースの 2x2 Bayer 閾値を使う。
            let threshold = [0.0, 0.5, 0.75, 0.25][((y & 1) * 2) + (x & 1)]
            return (
                source.0 >= threshold ? source.0 : destination.0,
                source.1 >= threshold ? source.1 : destination.1,
                source.2 >= threshold ? source.2 : destination.2
            )
        }
    }

    private enum HSLComponent {
        case hue, saturation, color, luminosity
    }

    private struct HSL {
        let h: Double
        let s: Double
        let l: Double
    }

    private static func hslComposite(
        source: (Double, Double, Double),
        destination: (Double, Double, Double),
        preserve component: HSLComponent
    ) -> (Double, Double, Double) {
        let s = hsl(source)
        let d = hsl(destination)
        switch component {
        case .hue:
            return rgb(h: s.h, s: d.s, l: d.l)
        case .saturation:
            return rgb(h: d.h, s: s.s, l: d.l)
        case .color:
            return rgb(h: s.h, s: s.s, l: d.l)
        case .luminosity:
            return rgb(h: d.h, s: d.s, l: s.l)
        }
    }

    private static func hsl(_ color: (Double, Double, Double)) -> HSL {
        let maxValue = max(color.0, max(color.1, color.2))
        let minValue = min(color.0, min(color.1, color.2))
        let lightness = (maxValue + minValue) / 2
        let delta = maxValue - minValue
        guard delta > 1e-9 else { return HSL(h: 0, s: 0, l: lightness) }

        let saturation = lightness > 0.5
            ? delta / max(1e-9, 2 - maxValue - minValue)
            : delta / max(1e-9, maxValue + minValue)
        let hueBase: Double
        if maxValue == color.0 {
            hueBase = (color.1 - color.2) / delta + (color.1 < color.2 ? 6 : 0)
        } else if maxValue == color.1 {
            hueBase = (color.2 - color.0) / delta + 2
        } else {
            hueBase = (color.0 - color.1) / delta + 4
        }
        return HSL(h: hueBase / 6, s: saturation, l: lightness)
    }

    private static func rgb(h: Double, s: Double, l: Double) -> (Double, Double, Double) {
        guard s > 1e-9 else { return (l, l, l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return (
            hueToRGB(p: p, q: q, t: h + 1 / 3),
            hueToRGB(p: p, q: q, t: h),
            hueToRGB(p: p, q: q, t: h - 1 / 3)
        )
    }

    private static func hueToRGB(p: Double, q: Double, t value: Double) -> Double {
        var t = value
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1 / 6 { return p + (q - p) * 6 * t }
        if t < 1 / 2 { return q }
        if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
        return p
    }

    private static func componentWise(
        _ source: (Double, Double, Double),
        _ destination: (Double, Double, Double),
        function: (Double, Double) -> Double
    ) -> (Double, Double, Double) {
        (
            max(0, min(1, function(source.0, destination.0))),
            max(0, min(1, function(source.1, destination.1))),
            max(0, min(1, function(source.2, destination.2)))
        )
    }

    private static func luminance(_ color: (Double, Double, Double)) -> Double {
        0.2126 * color.0 + 0.7152 * color.1 + 0.0722 * color.2
    }

    private static func colorBurnComponent(base: Double, blend: Double) -> Double {
        blend <= 0 ? 0 : 1 - min(1, (1 - base) / blend)
    }

    private static func colorDodgeComponent(base: Double, blend: Double) -> Double {
        blend >= 1 ? 1 : min(1, base / max(1e-9, 1 - blend))
    }

    private static func canvasSize(base: NSImage?, overlays: [SurfaceOverlay]) -> CGSize {
        var width = base?.size.width ?? 0
        var height = base?.size.height ?? 0
        for overlay in overlays where overlay.image.isValid {
            width = max(width, overlay.offset.x + overlay.image.size.width)
            height = max(height, overlay.offset.y + overlay.image.size.height)
        }
        return CGSize(width: max(0, width), height: max(0, height))
    }

    private static func imagePixels(_ image: NSImage?, size: CGSize) -> [UInt8] {
        let width = Int(size.width.rounded(.up))
        let height = Int(size.height.rounded(.up))
        var pixels = [UInt8](repeating: 0, count: max(0, width * height * 4))
        guard let image, width > 0, height > 0 else { return pixels }
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return pixels }
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return pixels
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[index + 3]
            pixels[index] = unpremultiply(pixels[index], alpha: alpha)
            pixels[index + 1] = unpremultiply(pixels[index + 1], alpha: alpha)
            pixels[index + 2] = unpremultiply(pixels[index + 2], alpha: alpha)
        }
        return pixels
    }

    private static func image(pixels: [UInt8], size: CGSize) -> NSImage? {
        let width = Int(size.width.rounded(.up))
        let height = Int(size.height.rounded(.up))
        guard width > 0, height > 0, pixels.count >= width * height * 4 else { return nil }
        // `pixels` is kept in the compositor's top-left coordinate order so
        // SERIKO offsets can be applied with positive Y meaning downward.
        // A CGImage data provider, however, is consumed by AppKit from the
        // bottom row first. Reverse the rows at this boundary only; doing the
        // flip inside the compositor would invert every element/overlay offset.
        let bytesPerRow = width * 4
        var displayPixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            let sourceStart = row * bytesPerRow
            let displayStart = (height - 1 - row) * bytesPerRow
            displayPixels[displayStart..<(displayStart + bytesPerRow)] =
                pixels[sourceStart..<(sourceStart + bytesPerRow)]
        }
        guard let provider = CGDataProvider(data: Data(displayPixels) as CFData),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
    }

    private static func compositedComponent(
        source: Double,
        destination: Double,
        sourceAlpha: Double,
        destinationAlpha: Double,
        outputAlpha: Double
    ) -> Double {
        guard outputAlpha > 0 else { return 0 }
        return (source * sourceAlpha + destination * destinationAlpha * (1 - sourceAlpha)) / outputAlpha
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8((max(0, min(1, value)) * 255).rounded())
    }

    private static func unpremultiply(_ component: UInt8, alpha: UInt8) -> UInt8 {
        guard alpha > 0 else { return 0 }
        return UInt8(min(255, (Int(component) * 255 + Int(alpha) / 2) / Int(alpha)))
    }
}
