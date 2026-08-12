import Foundation

/// Win32 SetROP2-compatible raster operations used by balloon anchors.
///
/// The names intentionally omit the `R2_` prefix because that is the spelling
/// used by SSP/UKADOC. `none` means that no raster operation is applied.
enum AnchorRasterOperation: String, CaseIterable, Equatable, Sendable {
    case none
    case black
    case notMergePen = "notmergepen"
    case maskNotPen = "masknotpen"
    case notCopyPen = "notcopypen"
    case maskPenNot = "maskpennot"
    case not
    case xorPen = "xorpen"
    case notMaskPen = "notmaskpen"
    case maskPen = "maskpen"
    case notXorPen = "notxorpen"
    case nop
    case mergeNotPen = "mergenotpen"
    case copyPen = "copypen"
    case mergePenNot = "mergepennot"
    case mergePen = "mergepen"
    case white

    /// Parse the SSP spelling. `default` is handled by the caller because it
    /// means "restore the balloon's configured value", not a raster operator.
    init?(name: String) {
        let normalized = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("r2_")
            ? String(name.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(3)).lowercased()
            : name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.init(rawValue: normalized)
    }

    /// Apply one ROP2 operation to an 8-bit source/pen and destination pixel.
    /// This is the exact per-channel Boolean operation defined by SetROP2.
    func apply(source: UInt8, destination: UInt8) -> UInt8 {
        switch self {
        case .none, .nop:
            return destination
        case .black:
            return 0
        case .notMergePen:
            return ~(source | destination)
        case .maskNotPen:
            return (~source) & destination
        case .notCopyPen:
            return ~source
        case .maskPenNot:
            return source & (~destination)
        case .not:
            return ~destination
        case .xorPen:
            return source ^ destination
        case .notMaskPen:
            return ~(source & destination)
        case .maskPen:
            return source & destination
        case .notXorPen:
            return ~(source ^ destination)
        case .mergeNotPen:
            return (~source) | destination
        case .copyPen:
            return source
        case .mergePenNot:
            return source | (~destination)
        case .mergePen:
            return source | destination
        case .white:
            return 255
        }
    }

    /// Apply the operation to an RGB triplet without changing alpha.
    func apply(source: (red: UInt8, green: UInt8, blue: UInt8),
               destination: (red: UInt8, green: UInt8, blue: UInt8))
        -> (red: UInt8, green: UInt8, blue: UInt8) {
        (
            red: apply(source: source.red, destination: destination.red),
            green: apply(source: source.green, destination: destination.green),
            blue: apply(source: source.blue, destination: destination.blue)
        )
    }
}
