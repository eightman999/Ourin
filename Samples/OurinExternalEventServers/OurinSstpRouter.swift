// OurinSstpRouter.swift
import Foundation

public struct SstpMessage {
    public let method: String      // NOTIFY/SEND
    public let version: String     // SSTP/1.x
    public let headers: [String:String] // Event, Sender, Charset, ReferenceN...
}

public enum SstpParser {
    public static func parse(_ raw: String) -> SstpMessage? {
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { return nil }
        let comps = first.split(separator: " ")
        guard comps.count >= 2 else { return nil }
        let method = String(comps[0])
        let version = String(comps[1])
        var headers: [String:String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let idx = line.firstIndex(of: ":") {
                let key = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = val
            }
        }
        return SstpMessage(method: method, version: version, headers: headers)
    }
}

public final class OurinSstpRouter {
    public init() {}
    public func handle(raw: String) -> String {
        guard let msg = SstpParser.parse(raw) else {
            return "SSTP/1.1 400 Bad Request\r\n\r\n"
        }
        // Example policy: NOTIFY -> 204, SEND -> 200
        let isNotify = msg.method.uppercased() == "NOTIFY"
        if isNotify {
            // TODO: dispatch to SHIORI as NOTIFY (returned script ignored by spec)
            return "SSTP/1.1 204 No Content\r\n\r\n"
        } else {
            // TODO: dispatch to SHIORI as GET and return script if any
            return "SSTP/1.1 200 OK\r\nCharset: UTF-8\r\nSender: Ourin\r\nScript: \\0\\s[0]OK\\e\r\n\r\n"
        }
    }
}
