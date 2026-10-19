import AppKit
import ImageIO

/// A decoded frame of a SERIKO `import` animation.
struct AnimatedSurfaceFrame {
    let image: NSImage
    let duration: TimeInterval
}

/// Decodes animated GIF/APNG/WebP files through ImageIO without depending on
/// a third-party image library. The source repeat count is intentionally not
/// exposed; SERIKO import replays the decoded frame sequence once.
enum AnimatedSurfaceLoader {
    static func load(from url: URL) -> [AnimatedSurfaceFrame] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return [] }

        return (0..<count).compactMap { index in
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
            let image = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as NSDictionary?
            let duration = frameDuration(properties: properties)
            return AnimatedSurfaceFrame(image: image, duration: duration)
        }
    }

    private static func frameDuration(properties: NSDictionary?) -> TimeInterval {
        guard let properties,
              let delay = findDelay(in: properties), delay.isFinite, delay > 0 else {
            return 0.1
        }
        // Avoid a zero-delay busy loop while preserving normal GIF/APNG timing.
        return max(0.01, delay)
    }

    private static func findDelay(in value: Any) -> Double? {
        if let number = value as? NSNumber {
            let candidate = number.doubleValue
            return candidate > 0 ? candidate : nil
        }
        guard let dictionary = value as? NSDictionary else { return nil }

        for (key, nested) in dictionary {
            let name = String(describing: key).lowercased()
            if name.contains("delaytime"), let number = nested as? NSNumber {
                let candidate = number.doubleValue
                if candidate > 0 { return candidate }
            }
        }
        for (_, nested) in dictionary {
            if let delay = findDelay(in: nested) { return delay }
        }
        return nil
    }
}
