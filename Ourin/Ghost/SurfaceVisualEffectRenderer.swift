import AppKit
import CoreImage

/// `\![effect]` / `\![filter]` のうち、ホストが単独で再現できる画像変換。
///
/// SSP の effect/filter は本来プラグイン拡張であり、任意のプラグイン名を
/// ホスト側の別の効果へ置き換えてはいけない。そのため、この型は Core Image
/// の組み込み変換だけを明示的に扱い、未知の名前は入力画像を変更しない。
enum SurfaceVisualEffectRenderer {
    private static let context = CIContext(options: nil)

    static let supportedPluginNames: Set<String> = [
        "blur", "gaussianblur", "motionblur", "zoomblur",
        "colorcontrols", "saturation", "brightness", "contrast",
        "grayscale", "greyscale", "sepia", "invert", "negative",
        "hue", "vibrance", "pixellate", "pixelate", "crystallize",
        "edges", "edge", "posterize", "opacity", "alpha"
    ]

    static func isSupported(plugin: String) -> Bool {
        supportedPluginNames.contains(normalizedName(plugin))
    }

    /// 1つの組み込み変換を画像へ適用する。未知のプラグインは入力画像を返す。
    static func applying(image: NSImage, plugin: String, params: [String]) -> NSImage? {
        let name = normalizedName(plugin)
        guard supportedPluginNames.contains(name) else { return image }
        guard let input = ciImage(from: image) else { return nil }

        let output: CIImage?
        switch name {
        case "blur", "gaussianblur":
            output = applyFilter(
                "CIGaussianBlur",
                to: input,
                values: ["inputRadius": parameter(params, keys: ["radius", "blur"], index: 0, default: 2.0)]
            )
        case "motionblur":
            output = applyFilter(
                "CIMotionBlur",
                to: input,
                values: [
                    "inputRadius": parameter(params, keys: ["radius"], index: 0, default: 10.0),
                    "inputAngle": parameter(params, keys: ["angle"], index: 1, default: 0.0)
                ]
            )
        case "zoomblur":
            output = applyFilter(
                "CIZoomBlur",
                to: input,
                values: ["inputAmount": parameter(params, keys: ["amount", "radius"], index: 0, default: 20.0)]
            )
        case "colorcontrols":
            output = applyFilter(
                "CIColorControls",
                to: input,
                values: [
                    "inputSaturation": parameter(params, keys: ["saturation"], index: 0, default: 1.0),
                    "inputBrightness": parameter(params, keys: ["brightness"], index: 1, default: 0.0),
                    "inputContrast": parameter(params, keys: ["contrast"], index: 2, default: 1.0)
                ]
            )
        case "saturation":
            output = applyFilter(
                "CIColorControls",
                to: input,
                values: ["inputSaturation": parameter(params, keys: ["saturation"], index: 0, default: 1.0)]
            )
        case "brightness":
            output = applyFilter(
                "CIColorControls",
                to: input,
                values: ["inputBrightness": parameter(params, keys: ["brightness"], index: 0, default: 0.0)]
            )
        case "contrast":
            output = applyFilter(
                "CIColorControls",
                to: input,
                values: ["inputContrast": parameter(params, keys: ["contrast"], index: 0, default: 1.0)]
            )
        case "grayscale", "greyscale":
            output = applyFilter("CIColorControls", to: input, values: ["inputSaturation": 0.0])
        case "sepia":
            output = applyFilter(
                "CISepiaTone",
                to: input,
                values: ["inputIntensity": parameter(params, keys: ["intensity"], index: 0, default: 1.0)]
            )
        case "invert", "negative":
            output = applyFilter("CIColorInvert", to: input, values: [:])
        case "hue":
            output = applyFilter(
                "CIHueAdjust",
                to: input,
                values: ["inputAngle": parameter(params, keys: ["angle", "radians"], index: 0, default: 0.0)]
            )
        case "vibrance":
            output = applyFilter(
                "CIVibrance",
                to: input,
                values: ["inputAmount": parameter(params, keys: ["amount"], index: 0, default: 0.0)]
            )
        case "pixellate", "pixelate":
            output = applyFilter(
                "CIPixellate",
                to: input,
                values: ["inputScale": parameter(params, keys: ["scale", "size"], index: 0, default: 8.0)]
            )
        case "crystallize":
            output = applyFilter(
                "CICrystallize",
                to: input,
                values: ["inputRadius": parameter(params, keys: ["radius"], index: 0, default: 20.0)]
            )
        case "edges", "edge":
            output = applyFilter(
                "CIEdges",
                to: input,
                values: ["inputIntensity": parameter(params, keys: ["intensity"], index: 0, default: 1.0)]
            )
        case "posterize":
            output = applyFilter(
                "CIColorPosterize",
                to: input,
                values: ["inputLevels": parameter(params, keys: ["levels"], index: 0, default: 6.0)]
            )
        case "opacity", "alpha":
            let amount = max(0.0, min(1.0, parameter(params, keys: ["opacity", "alpha"], index: 0, default: 1.0)))
            output = applyFilter(
                "CIColorMatrix",
                to: input,
                values: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: amount)]
            )
        default:
            output = input
        }

        guard let output,
              let cgImage = context.createCGImage(output.cropped(to: input.extent), from: input.extent) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: image.size)
    }

    static func applying(
        image: NSImage,
        effects: [EffectConfig],
        filters: [FilterConfig]
    ) -> NSImage? {
        var result = image
        for effect in effects {
            guard let transformed = applying(image: result, plugin: effect.plugin, params: effect.params) else { return nil }
            result = transformed
        }
        for filter in filters {
            guard let transformed = applying(image: result, plugin: filter.plugin, params: filter.params) else { return nil }
            result = transformed
        }
        return result
    }

    private static func normalizedName(_ plugin: String) -> String {
        let compact = plugin
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        return compact.hasPrefix("ci") ? String(compact.dropFirst(2)) : compact
    }

    private static func ciImage(from image: NSImage) -> CIImage? {
        var proposed = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        return CIImage(cgImage: cgImage)
    }

    private static func applyFilter(_ name: String, to input: CIImage, values: [String: Any]) -> CIImage? {
        guard let filter = CIFilter(name: name) else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        for (key, value) in values {
            filter.setValue(value, forKey: key)
        }
        return filter.outputImage
    }

    private static func parameter(_ params: [String], keys: [String], index: Int, default defaultValue: Double) -> Double {
        for item in params {
            let pieces = item.split(separator: "=", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            let key = normalizedName(pieces[0])
            if keys.contains(where: { normalizedName($0) == key }), let value = Double(pieces[1]) {
                return value
            }
        }
        guard params.indices.contains(index) else { return defaultValue }
        let raw = params[index].trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasSuffix("%"), let percentage = Double(raw.dropLast()) {
            return percentage / 100.0
        }
        return Double(raw) ?? defaultValue
    }
}
