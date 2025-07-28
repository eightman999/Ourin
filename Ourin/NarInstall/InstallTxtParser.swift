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
