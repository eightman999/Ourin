import AVFoundation
import Foundation
import ImageIO

/// ファイルそのものを対象にする処理（UKADOC 2.9.25 internal_file）。いまは MediaInfo だけ。
///
/// 音声・動画は AVFoundation、画像は ImageIO で、再生の準備をせずにヘッダとタグだけを読む。
/// どの形式のどの項目が取れるかは OS 次第で、取れない値は空文字（エラーにしない）。
struct InternalFileModule: InternalSaoriModule {
    let name = "internal_file"

    static let keys = ["title", "artist", "albumartist", "album", "genre", "comment", "year", "track", "duration", "width", "height"]

    var functions: [InternalSaoriFunction] {
        // Argument1 がパス、Argument2 以降が欲しい値のキー（1〜11 個）。
        [InternalSaoriFunction("MediaInfo", required: 2, total: 1 + 1 + Self.keys.count, options: []) { call, context in
            let requested = call.positionals.dropFirst().map { $0.lowercased() }
            guard requested.count <= Self.keys.count else { throw InternalSaoriError.invalidParameter }
            let url = try Self.resolve(call.positionals[0], context: context)
            let info = Self.read(url)
            let values = requested.map { info.values[$0] ?? "" }
            return InternalSaoriResult(info.kind, values: values)
        }]
    }

    // MARK: - パス

    static func resolve(_ path: String, context: InternalSaoriContext) throws -> URL {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        if normalized.contains("://") { throw InternalSaoriError.badRequest("file not found") }
        let url: URL
        if normalized.hasPrefix("/") {
            url = URL(fileURLWithPath: normalized)
        } else if let root = context.ghostRoot {
            url = root.appendingPathComponent(normalized)
        } else {
            throw InternalSaoriError.ghostRequired
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw InternalSaoriError.badRequest("file not found")
        }
        return url
    }

    // MARK: - 読み取り

    struct Info {
        var kind = ""
        var values: [String: String] = [:]
    }

    static func read(_ url: URL) -> Info {
        if let info = readImage(url) { return info }
        return readAV(url)
    }

    private static func readImage(_ url: URL) -> Info? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { return nil }
        return Info(kind: "image", values: ["width": String(width), "height": String(height)])
    }

    private static func readAV(_ url: URL) -> Info {
        let asset = AVURLAsset(url: url)
        guard asset.isReadable else { return Info() }
        var info = Info()
        let videoTracks = asset.tracks(withMediaType: .video).filter { $0.naturalSize.width > 0 && $0.naturalSize.height > 0 }
        let audioTracks = asset.tracks(withMediaType: .audio)
        if let video = videoTracks.first {
            info.kind = "video"
            let size = video.naturalSize.applying(video.preferredTransform)
            info.values["width"] = String(Int(abs(size.width).rounded()))
            info.values["height"] = String(Int(abs(size.height).rounded()))
        } else if !audioTracks.isEmpty {
            info.kind = "audio"
        }
        let seconds = asset.duration.seconds
        if !info.kind.isEmpty, seconds.isFinite, seconds > 0 { info.values["duration"] = String(Int((seconds * 1000).rounded())) }

        let items = asset.metadata + asset.availableMetadataFormats.flatMap { asset.metadata(forFormat: $0) }
        for key in ["title", "artist", "albumartist", "album", "genre", "comment"] {
            if let text = joined(items, matching: identifiers[key] ?? []) { info.values[key] = text }
        }
        if let text = joined(items, matching: identifiers["year"] ?? []), text.count >= 4 {
            let year = String(text.prefix(4))
            if year.allSatisfy(\.isASCIINumber) { info.values["year"] = year }
        }
        if let text = joined(items, matching: identifiers["track"] ?? [], limit: 1) {
            // 3/12 → 3。iTunes 形式のバイナリは別に読む。
            let number = text.split(separator: "/").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            if let value = Int(number), value > 0 { info.values["track"] = String(value) }
        }
        return info
    }

    private static let identifiers: [String: [AVMetadataIdentifier]] = [
        "title": [.commonIdentifierTitle, .id3MetadataTitleDescription, .iTunesMetadataSongName, .quickTimeMetadataTitle],
        "artist": [.commonIdentifierArtist, .id3MetadataLeadPerformer, .iTunesMetadataArtist, .quickTimeMetadataArtist],
        "albumartist": [.iTunesMetadataAlbumArtist, .id3MetadataBand],
        "album": [.commonIdentifierAlbumName, .id3MetadataAlbumTitle, .iTunesMetadataAlbum, .quickTimeMetadataAlbum],
        "genre": [.id3MetadataContentType, .iTunesMetadataUserGenre, .quickTimeMetadataGenre],
        "comment": [.id3MetadataComments, .iTunesMetadataUserComment, .quickTimeMetadataComment],
        "year": [.id3MetadataYear, .id3MetadataRecordingTime, .iTunesMetadataReleaseDate, .commonIdentifierCreationDate, .quickTimeMetadataCreationDate],
        "track": [.id3MetadataTrackNumber, .iTunesMetadataTrackNumber]
    ]

    /// 一致する項目の文字列を `; ` でつなぐ（同じ値は 1 つに）。改行は 0x01、NUL は除く。
    private static func joined(_ items: [AVMetadataItem], matching identifiers: [AVMetadataIdentifier], limit: Int = .max) -> String? {
        var seen: [String] = []
        for item in items {
            guard let id = item.identifier, identifiers.contains(id), let text = text(of: item), !text.isEmpty, !seen.contains(text) else { continue }
            seen.append(text)
            if seen.count >= limit { break }
        }
        guard !seen.isEmpty else { return nil }
        return seen.map(clean).joined(separator: "; ")
    }

    private static func text(of item: AVMetadataItem) -> String? {
        if let string = item.stringValue { return string }
        if let date = item.dateValue { return String(Calendar(identifier: .gregorian).component(.year, from: date)) }
        if let data = item.dataValue, data.count >= 4, item.identifier == .iTunesMetadataTrackNumber {
            // trkn: 2 バイトの予約、2 バイトの曲番号、2 バイトの総数。
            return String(Int(data[data.startIndex + 2]) << 8 | Int(data[data.startIndex + 3]))
        }
        if let number = item.numberValue { return number.stringValue }
        return nil
    }

    private static func clean(_ text: String) -> String {
        var output = String.UnicodeScalarView()
        var previousWasCR = false
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\r": output.append("\u{01}"); previousWasCR = true; continue
            case "\n": if !previousWasCR { output.append("\u{01}") }
            case "\0": break
            default: output.append(scalar)
            }
            previousWasCR = false
        }
        return String(output)
    }
}

private extension Character {
    var isASCIINumber: Bool { isASCII && isNumber }
}
