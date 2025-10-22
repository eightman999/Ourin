import Foundation
import AppKit

/// Configuration for balloon display loaded from descript.txt
struct BalloonConfig {
    // Basic info
    let name: String
    let charset: String
    let craftman: String
    let craftmanUrl: String

    // Origin point for text
    let originX: Int
    let originY: Int

    // Word wrap point
    let wordwrapPointX: Int
    let wordwrapPointY: Int

    // Font settings
    let fontHeight: Int
    let fontColor: NSColor

    // Anchor (link) font settings
    let anchorFontColor: NSColor
    let anchorPenColor: NSColor

    // Cursor settings
    let cursorBlendMethod: String
    let cursorStyle: String
    let cursorBrushColor: NSColor
    let cursorPenColor: NSColor
    let cursorFontColor: NSColor

    // Number settings (for choice dialogs)
    let numberFontHeight: Int
    let numberFontColor: NSColor
    let numberXR: Int
    let numberY: Int

    // Online marker position
    let onlineMarkerX: Int
    let onlineMarkerY: Int

    // SSTP marker position
    let sstpMarkerX: Int
    let sstpMarkerY: Int

    // SSTP message settings
    let sstpMessageX: Int
    let sstpMessageY: Int
    let sstpMessageFontHeight: Int
    let sstpMessageFontColor: NSColor

    // Arrow positions
    let arrow0X: Int
    let arrow0Y: Int
    let arrow1X: Int
    let arrow1Y: Int

    // Valid rect (text area)
    let validRectLeft: Int
    let validRectTop: Int
    let validRectRight: Int
    let validRectBottom: Int

    // Communication box (input area)
    let communicateBoxX: Int
    let communicateBoxY: Int
    let communicateBoxWidth: Int
    let communicateBoxHeight: Int

    static func load(from path: String) -> BalloonConfig? {
        // Try multiple encodings
        var content: String?

        // Try Shift_JIS first
        if let shiftJISContent = try? String(contentsOfFile: path, encoding: .shiftJIS) {
            content = shiftJISContent
        }
        // Fallback to UTF-8
        else if let utf8Content = try? String(contentsOfFile: path, encoding: .utf8) {
            content = utf8Content
        }
        // Last resort: let system detect encoding
        else if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                let detectedContent = String(data: data, encoding: .shiftJIS) ?? String(data: data, encoding: .utf8) {
            content = detectedContent
        }

        guard let content = content else {
            NSLog("[BalloonConfig] Failed to read file at path: \(path)")
            return nil
        }

        var config: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") {
                continue
            }

            let parts = trimmed.components(separatedBy: ",")
            if parts.count >= 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1...].joined(separator: ",").trimmingCharacters(in: .whitespaces)
                config[key] = value
            }
        }

        // Helper functions
        func getInt(_ key: String, default defaultValue: Int = 0) -> Int {
            return Int(config[key] ?? "") ?? defaultValue
        }

        func getString(_ key: String, default defaultValue: String = "") -> String {
            return config[key] ?? defaultValue
        }

        func getColor(r: String, g: String, b: String) -> NSColor {
            let red = CGFloat(getInt(r)) / 255.0
            let green = CGFloat(getInt(g)) / 255.0
            let blue = CGFloat(getInt(b)) / 255.0
            return NSColor(red: red, green: green, blue: blue, alpha: 1.0)
        }

        return BalloonConfig(
            name: getString("name"),
            charset: getString("charset", default: "Shift_JIS"),
            craftman: getString("craftman"),
            craftmanUrl: getString("craftmanurl"),
            originX: getInt("origin.x", default: 20),
            originY: getInt("origin.y", default: 10),
            wordwrapPointX: getInt("wordwrappoint.x", default: -34),
            wordwrapPointY: getInt("wordwrappoint.y", default: 0),
            fontHeight: getInt("font.height", default: 12),
            fontColor: getColor(r: "font.color.r", g: "font.color.g", b: "font.color.b"),
            anchorFontColor: getColor(r: "anchor.font.color.r", g: "anchor.font.color.g", b: "anchor.font.color.b"),
            anchorPenColor: getColor(r: "anchor.pen.color.r", g: "anchor.pen.color.g", b: "anchor.pen.color.b"),
            cursorBlendMethod: getString("cursor.blendmethod", default: "none"),
            cursorStyle: getString("cursor.style", default: "square"),
            cursorBrushColor: getColor(r: "cursor.brush.color.r", g: "cursor.brush.color.g", b: "cursor.brush.color.b"),
            cursorPenColor: getColor(r: "cursor.pen.color.r", g: "cursor.pen.color.g", b: "cursor.pen.color.b"),
            cursorFontColor: getColor(r: "cursor.font.color.r", g: "cursor.font.color.g", b: "cursor.font.color.b"),
            numberFontHeight: getInt("number.font.height", default: 10),
            numberFontColor: getColor(r: "number.font.color.r", g: "number.font.color.g", b: "number.font.color.b"),
            numberXR: getInt("number.xr", default: -29),
            numberY: getInt("number.y", default: -18),
            onlineMarkerX: getInt("onlinemarker.x", default: 16),
            onlineMarkerY: getInt("onlinemarker.y", default: 6),
            sstpMarkerX: getInt("sstpmarker.x", default: 17),
            sstpMarkerY: getInt("sstpmarker.y", default: -17),
            sstpMessageX: getInt("sstpmessage.x", default: 30),
            sstpMessageY: getInt("sstpmessage.y", default: -18),
            sstpMessageFontHeight: getInt("sstpmessage.font.height", default: 10),
            sstpMessageFontColor: getColor(r: "sstpmessage.font.color.r", g: "sstpmessage.font.color.g", b: "sstpmessage.font.color.b"),
            arrow0X: getInt("arrow0.x", default: 306),
            arrow0Y: getInt("arrow0.y", default: 7),
            arrow1X: getInt("arrow1.x", default: 307),
            arrow1Y: getInt("arrow1.y", default: -20),
            validRectLeft: getInt("validrect.left", default: 0),
            validRectTop: getInt("validrect.top", default: 0),
            validRectRight: getInt("validrect.right", default: 0),
            validRectBottom: getInt("validrect.bottom", default: -10),
            communicateBoxX: getInt("communicatebox.x", default: 25),
            communicateBoxY: getInt("communicatebox.y", default: 25),
            communicateBoxWidth: getInt("communicatebox.width", default: 360),
            communicateBoxHeight: getInt("communicatebox.height", default: 25)
        )
    }
}

/// Loads balloon images from a balloon directory
class BalloonImageLoader {
    let balloonPath: String
    private var imageCache: [String: NSImage] = [:]

    init(balloonPath: String) {
        self.balloonPath = balloonPath
    }

    /// Load a balloon surface image with PNA transparency support
    /// - Parameter index: Surface index (0, 1, 2, 3 for balloons*, balloonk*, balloonc*)
    /// - Parameter type: Type of balloon ("s" for speech, "k" for kero/another character, "c" for communication)
    /// - Returns: The loaded image with transparency applied, or nil if not found
    func loadSurface(index: Int, type: String = "s") -> NSImage? {
        let filename = "balloon\(type)\(index).png"

        if let cached = imageCache[filename] {
            return cached
        }

        let imagePath = (balloonPath as NSString).appendingPathComponent(filename)
        let imageURL = URL(fileURLWithPath: imagePath)

        guard FileManager.default.fileExists(atPath: imagePath) else {
            return nil
        }

        // Check for PNA mask file
        let pnaPath = (balloonPath as NSString).appendingPathComponent("balloon\(type)\(index).pna")
        let pnaURL = URL(fileURLWithPath: pnaPath)

        var image: NSImage?

        if FileManager.default.fileExists(atPath: pnaPath),
           let maskedImage = applyPNAMask(baseURL: imageURL, maskURL: pnaURL) {
            image = maskedImage
            NSLog("[BalloonImageLoader] Loaded \(filename) with PNA transparency")
        } else {
            image = NSImage(contentsOfFile: imagePath)
        }

        if let image = image {
            imageCache[filename] = image
        }

        return image
    }

    /// Apply PNA mask to create transparent image
    private func applyPNAMask(baseURL: URL, maskURL: URL) -> NSImage? {
        guard let baseCI = CIImage(contentsOf: baseURL),
              let maskCI = CIImage(contentsOf: maskURL) else { return nil }

        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: baseCI.extent)

        guard let output = CIFilter(name: "CIBlendWithMask",
                                    parameters: [kCIInputImageKey: baseCI,
                                                 kCIInputBackgroundImageKey: clear,
                                                 kCIInputMaskImageKey: maskCI])?.outputImage else { return nil }

        let ctx = CIContext(options: nil)
        guard let cg = ctx.createCGImage(output, from: baseCI.extent) else { return nil }

        let size = NSSize(width: cg.width, height: cg.height)
        let nsimg = NSImage(size: size)
        nsimg.lockFocus()
        NSGraphicsContext.current?.cgContext.draw(cg, in: CGRect(origin: .zero, size: size))
        nsimg.unlockFocus()

        return nsimg
    }

    /// Load arrow image
    func loadArrow(index: Int) -> NSImage? {
        let filename = "arrow\(index).png"

        if let cached = imageCache[filename] {
            return cached
        }

        let imagePath = (balloonPath as NSString).appendingPathComponent(filename)
        guard let image = NSImage(contentsOfFile: imagePath) else {
            return nil
        }

        imageCache[filename] = image
        return image
    }

    /// Load marker image
    func loadMarker() -> NSImage? {
        let filename = "marker.png"

        if let cached = imageCache[filename] {
            return cached
        }

        let imagePath = (balloonPath as NSString).appendingPathComponent(filename)
        guard let image = NSImage(contentsOfFile: imagePath) else {
            return nil
        }

        imageCache[filename] = image
        return image
    }

    /// Load online marker image
    func loadOnlineMarker(index: Int) -> NSImage? {
        let filename = "online\(index).png"

        if let cached = imageCache[filename] {
            return cached
        }

        let imagePath = (balloonPath as NSString).appendingPathComponent(filename)
        guard let image = NSImage(contentsOfFile: imagePath) else {
            return nil
        }

        imageCache[filename] = image
        return image
    }

    /// Load SSTP marker images
    func loadSstpMarker(new: Bool = false) -> NSImage? {
        let filename = new ? "sstp_new.png" : "sstp.png"

        if let cached = imageCache[filename] {
            return cached
        }

        let imagePath = (balloonPath as NSString).appendingPathComponent(filename)
        guard let image = NSImage(contentsOfFile: imagePath) else {
            return nil
        }

        imageCache[filename] = image
        return image
    }
}
