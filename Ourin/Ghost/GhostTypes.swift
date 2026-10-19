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

/// Parsed arguments for CROW's `\\![anim,add,text,...]` command.
///
/// The fields through `text` are required by the SakuraScript specification;
/// display time, RGB color, font size, and font name are optional. Keeping the
/// optional-argument handling in a value type prevents the playback dispatcher
/// from indexing past the end of a valid short command.
struct AnimAddTextParameters: Equatable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let text: String
    let time: Int
    let red: Int
    let green: Int
    let blue: Int
    let size: Int
    let font: String

    static func parse(_ args: [String]) -> Self? {
        guard args.count >= 8,
              args[0].caseInsensitiveCompare("anim") == .orderedSame,
              args[1].caseInsensitiveCompare("add") == .orderedSame,
              args[2].caseInsensitiveCompare("text") == .orderedSame else {
            return nil
        }

        func integer(at index: Int, fallback: Int) -> Int {
            guard args.indices.contains(index) else { return fallback }
            return Int(args[index]) ?? fallback
        }

        return Self(
            x: integer(at: 3, fallback: 0),
            y: integer(at: 4, fallback: 0),
            width: integer(at: 5, fallback: 100),
            height: integer(at: 6, fallback: 20),
            text: args[7],
            time: integer(at: 8, fallback: 1000),
            red: integer(at: 9, fallback: 0),
            green: integer(at: 10, fallback: 0),
            blue: integer(at: 11, fallback: 0),
            size: integer(at: 12, fallback: 12),
            font: args.indices.contains(13) ? args[13] : "sans-serif"
        )
    }
}

// MARK: - Surface Overlay

/// Surface overlay data for character rendering
struct SurfaceOverlay: Identifiable {
    let id: String
    var image: NSImage
    var offset: CGPoint = .zero
    var alpha: Double = 1.0
    var zOrder: Int = 0
    var insertionOrder: Int = 0
    /// SERIKO の合成モード。通常の overlay 以外は CharacterView で
    /// 宛先アルファを含むビットマップ合成へ回す。
    var blendMode: SurfaceBlendMode = .normal
    /// このオーバーレイを作成したサーフェス ID（`effect2` の対象解決用）。
    var surfaceID: Int? = nil
    /// SERIKO アニメーションが所有する一時オーバーレイの場合のみ設定する。
    /// surface ID はフレームごとに変わるため、ID文字列の接頭辞ではなく所有アニメーションで追跡する。
    var animationID: Int? = nil

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
