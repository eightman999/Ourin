import Foundation
import AppKit

// MARK: - Effects and Filters

struct EffectConfig {
    let plugin: String
    let speed: Double
    let params: [String]
    let surfaceID: Int?
}

struct FilterConfig {
    let plugin: String
    let time: Double
    let params: [String]
}

struct TextAnimationConfig {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let text: String
    let duration: Int // milliseconds
    let r: Int
    let g: Int
    let b: Int
    let fontSize: Int
    let fontName: String
}

// MARK: - Surface Overlay

/// Surface overlay data for character rendering
struct SurfaceOverlay: Identifiable {
    let id: String
    let image: NSImage
    var offset: CGPoint = .zero
    var alpha: Double = 1.0
    var zOrder: Int = 0
    var insertionOrder: Int = 0

    static func sortedForDisplay(_ overlays: [SurfaceOverlay]) -> [SurfaceOverlay] {
        overlays.sorted {
            if $0.zOrder == $1.zOrder {
                return $0.insertionOrder < $1.insertionOrder
            }
            return $0.zOrder < $1.zOrder
        }
    }
}

/// Desktop alignment options
enum DesktopAlignment {
    case free
    case top
    case bottom
    case left
    case right
}

// MARK: - Dressup Part

/// Dressup part data for character rendering
struct DressupPart: Identifiable {
    let id = UUID()
    let category: String
    let partName: String
    let image: NSImage
    let frame: CGRect
    var zOrder: Int = 0
    var isEnabled: Bool = true
}

// MARK: - Extensions

extension NSImage {
    var isValid: Bool {
        return size.width > 0 && size.height > 0
    }
}
