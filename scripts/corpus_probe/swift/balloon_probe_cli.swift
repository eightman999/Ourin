import Foundation
import ImageIO
import AppKit

struct ProbeOutput: Codable {
    struct DescriptSummary: Codable {
        var parsed: Bool
        var nameLength: Int
        var originX: Int
        var originY: Int
        var fontColorRGB: [Int]
        var charsetLength: Int
    }

    struct PNGSummary: Codable {
        var decodedCount: Int
        var invalidCount: Int
        var surfaces: [[String: Int]]
    }

    var descript: DescriptSummary
    var png: PNGSummary
}

let maxImageBytes = 16 * 1024 * 1024
let maxImagePixels = 4096 * 4096
let maxBalloonImages = 8

func rgbComponents(_ color: NSColor) -> [Int] {
    let rgb = color.usingColorSpace(.deviceRGB) ?? .black
    return [
        Int((rgb.redComponent * 255).rounded()),
        Int((rgb.greenComponent * 255).rounded()),
        Int((rgb.blueComponent * 255).rounded()),
    ]
}

func decodePNG(at url: URL) -> [String: Int]? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
          let fileSize = attrs[.size] as? NSNumber,
          fileSize.intValue > 0,
          fileSize.intValue <= maxImageBytes else { return nil }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0,
          height > 0,
          width <= 4096,
          height <= 4096,
          width * height <= maxImagePixels else { return nil }
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    return ["width": image.width, "height": image.height]
}

func balloonCandidates(root: String, index: Int) -> [String] {
    [
        "balloons\(index).png",
        "balloon\(index).png",
        "balloonk\(index).png",
        index == 0 ? "normalPNG.png" : "normalPNG\(index).png",
    ]
}

@main
enum BalloonProbeCLI {
static func main() {
    guard CommandLine.arguments.count >= 3 else {
        fputs("{\"error\":\"usage\"}\n", stderr)
        exit(2)
    }
    let descriptPath = CommandLine.arguments[1]
    let balloonRoot = CommandLine.arguments[2]

    guard let config = BalloonConfig.load(from: descriptPath) else {
        let empty = ProbeOutput(
            descript: .init(parsed: false, nameLength: 0, originX: 0, originY: 0, fontColorRGB: [], charsetLength: 0),
            png: .init(decodedCount: 0, invalidCount: 0, surfaces: [])
        )
        print(String(data: try! JSONEncoder().encode(empty), encoding: .utf8)!)
        exit(1)
    }

    var surfaces: [[String: Int]] = []
    var invalid = 0
    for index in 0..<maxBalloonImages {
        var decoded: [String: Int]? = nil
        for filename in balloonCandidates(root: balloonRoot, index: index) {
            let path = (balloonRoot as NSString).appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: path) {
                if let size = decodePNG(at: URL(fileURLWithPath: path)) {
                    decoded = size
                } else {
                    invalid += 1
                }
                break
            }
        }
        if let size = decoded {
            surfaces.append(["index": index, "width": size["width"]!, "height": size["height"]!])
        }
    }

    let summary = ProbeOutput(
        descript: .init(
            parsed: true,
            nameLength: config.name.count,
            originX: config.originX,
            originY: config.originY,
            fontColorRGB: rgbComponents(config.fontColor),
            charsetLength: config.charset.count
        ),
        png: .init(decodedCount: surfaces.count, invalidCount: invalid, surfaces: surfaces)
    )
    print(String(data: try! JSONEncoder().encode(summary), encoding: .utf8)!)
}
}
