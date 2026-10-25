import Foundation

/// Minimal copy of production `AnchorDecorationStyle` for headless balloon_probe compilation.
enum AnchorDecorationStyle: Equatable, Sendable {
    case none
    case underline
    case square
    case squareUnderline

    init?(shape: String) {
        switch shape.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "none": self = .none
        case "underline": self = .underline
        case "square": self = .square
        case "square+underline": self = .squareUnderline
        default: return nil
        }
    }
}
