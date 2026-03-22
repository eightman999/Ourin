// Ourin/NarInstall/InstallTxtParser.swift
import Foundation

struct InstallManifest {
    var type: String = ""
    var directory: String = ""
    var accept: String?
    var extras: [String: String] = [:] // balloon.directory, *.source.directory etc.
}

enum TextEncodingDetector {
    static func decode(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        // Try Shift_JIS (CP932)
        let enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)))
        if let s = String(data: data, encoding: enc) { return s }
        return nil
    }
}

struct InstallTxtParser {
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
            case "type": manifest.type = value
            case "directory": manifest.directory = value
            case "accept": manifest.accept = value
            default:
                manifest.extras[key] = value
            }
        }
        guard !manifest.type.isEmpty else { throw NarInstaller.Error.installTxtMissingKey("type") }
        guard !manifest.directory.isEmpty else { throw NarInstaller.Error.installTxtMissingKey("directory") }
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
