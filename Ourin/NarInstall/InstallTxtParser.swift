// Ourin/NarInstall/InstallTxtParser.swift
import Foundation

struct InstallManifest {
    var type: String = ""
    var directory: String = ""
    var accept: String?
    /// install.txt の charset 宣言値（宣言されていた場合のみ）
    var charset: String?
    /// refresh,1 でインストール前に既存インストール先を削除する（更新インストール）
    var refresh: Bool = false
    /// refresh 時に残すパスを表す正規表現の集合（UKADOC: コロン区切り。互換のためカンマも許容）
    var refreshUndeleteMask: [String] = []
    /// type=ghost に同梱されたバルーンのインストール先ディレクトリ名
    var balloonDirectory: String?
    /// 同梱バルーンの NAR 内ソースディレクトリ名（既定は balloonDirectory）
    var balloonSourceDirectory: String?
    var extras: [String: String] = [:] // shell.directory, *.source.directory etc.
}

enum TextEncodingDetector {
    /// Windows 互換 Shift_JIS (CP932)
    static let shiftJIS = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)))

    static func decode(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        // Try Shift_JIS (CP932)
        if let s = String(data: data, encoding: shiftJIS) { return s }
        return nil
    }

    /// `charset,<value>` / `charset:<value>` の宣言値（小文字）を String.Encoding へ写像する。
    /// 未対応・不明な値は nil を返す。
    static func encoding(forCharset declared: String) -> String.Encoding? {
        let v = declared.lowercased().trimmingCharacters(in: .whitespaces)
        switch v {
        case "utf-8", "utf8":
            return .utf8
        case "shift_jis", "shift-jis", "shiftjis", "sjis", "cp932", "windows-31j", "ms932":
            return shiftJIS
        default:
            return nil
        }
    }

    /// install.txt 等の生バイト列の先頭行を走査し、`charset` 宣言を探す。
    /// 宣言があれば対応するエンコーディング、なければ nil を返す。
    static func declaredCharset(in data: Data) -> String.Encoding? {
        // 先頭部分だけを ASCII 互換として安全に走査する（最大 4KB）。
        let probeCount = min(data.count, 4096)
        let probe = data.prefix(probeCount)
        guard let ascii = String(data: probe, encoding: .isoLatin1) else { return nil }
        let lines = ascii.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            // `charset,<value>` または `charset:<value>` の両表記を許容する。
            let lower = line.lowercased()
            guard lower.hasPrefix("charset") else { continue }
            let afterKey = line.dropFirst("charset".count)
            guard let sep = afterKey.first, sep == "," || sep == ":" else { continue }
            let value = afterKey.dropFirst().trimmingCharacters(in: .whitespaces)
            if let enc = encoding(forCharset: value) { return enc }
        }
        return nil
    }
}

struct InstallTxtParser {
    /// install.txt の生バイト列を解析する。
    /// 先頭行に `charset` 宣言があればそのエンコーディングで優先的にデコードし、
    /// 宣言が無い／デコード失敗時は従来の推定（UTF-8 → Shift_JIS）へフォールバックする。
    static func parse(data: Data) throws -> InstallManifest {
        var text: String?
        if let declared = TextEncodingDetector.declaredCharset(in: data) {
            text = String(data: data, encoding: declared)
        }
        if text == nil {
            text = TextEncodingDetector.decode(data)
        }
        guard let str = text else { throw NarInstaller.Error.installTxtDecodeFailed }
        return try parse(str)
    }

    static func parse(_ text: String) throws -> InstallManifest {
        var manifest = InstallManifest()
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            let parts = line.split(separator: ",", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts[1]
            switch key {
            case "charset": manifest.charset = value
            case "type": manifest.type = value
            case "directory": manifest.directory = value
            case "accept": manifest.accept = value
            case "refresh":
                manifest.refresh = (value == "1" || value.lowercased() == "true")
            case "refreshundeletemask":
                // UKADOC では `refreshundeletemask,ファイル名1:ファイル名2...` のコロン区切り。
                // 既存データ互換のためカンマ区切りも寛容に受ける。
                manifest.refreshUndeleteMask = value
                    .split(whereSeparator: { $0 == ":" || $0 == "," })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            case "balloon.directory":
                manifest.balloonDirectory = value
                manifest.extras[key] = value
            case "balloon.source.directory":
                manifest.balloonSourceDirectory = value
                manifest.extras[key] = value
            default:
                manifest.extras[key] = value
            }
        }
        guard !manifest.type.isEmpty else { throw NarInstaller.Error.installTxtMissingKey("type") }
        // UKADOC: directory は supplement / package では任意、それ以外では必須。
        let typeLower = manifest.type.lowercased()
        let directoryOptional = (typeLower == "supplement" || typeLower == "package")
        if !directoryOptional {
            guard !manifest.directory.isEmpty else { throw NarInstaller.Error.installTxtMissingKey("directory") }
        }
        return manifest
    }
}

struct UpdateDescriptorParser {
    static func parse(_ text: String, baseURL: URL) -> [URL] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var results: [URL] = []

        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix(";"), !line.hasPrefix("#"), !line.hasPrefix("//") else { continue }

            let components = line
                .replacingOccurrences(of: "\u{0001}", with: ",")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            guard let rawTarget = components.first(where: { !$0.isEmpty }) else { continue }
            let candidate = rawTarget.replacingOccurrences(of: "\\", with: "/")

            if let absolute = URL(string: candidate), let scheme = absolute.scheme?.lowercased(),
               scheme == "https" || scheme == "http" {
                results.append(absolute)
                continue
            }
            if let relative = URL(string: candidate, relativeTo: baseURL)?.absoluteURL {
                results.append(relative)
            }
        }

        return Array(Set(results)).sorted { $0.absoluteString < $1.absoluteString }
    }
}
