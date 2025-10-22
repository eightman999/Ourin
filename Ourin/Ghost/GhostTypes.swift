import Foundation

// Shared configuration types for effects, filters, and text animations

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

