import Foundation

/// MAKOTO/2.0 translator wire codec.
/// SATORI/ninixの挙動参照に留め、実装は公開ABI（String header）だけに依存する。
enum MakotoWireCodec {
    static func makeRequest(_ script: String, charset: String = "UTF-8") -> String {
        let safeScript = script
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        return [
            "TRANSLATE Sentence MAKOTO/2.0",
            "Charset: \(charset)",
            "Sender: Ourin",
            "String: \(safeScript)",
            "",
            ""
        ].joined(separator: "\r\n")
    }

    static func parseResponse(_ response: String) -> String? {
        let lines = response.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        guard let first = lines.first else { return nil }
        let status = first.split(whereSeparator: { $0.isWhitespace })
        guard status.count >= 2,
              status[0].uppercased().hasPrefix("MAKOTO/"),
              status[1] == "200" else { return nil }
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            if key.caseInsensitiveCompare("String") == .orderedSame {
                var value = line[line.index(after: colon)...]
                if value.first == " " { value = value.dropFirst() }
                return String(value)
            }
        }
        return nil
    }
}

/// ゴースト／シェルのMAKOTOモジュールをSHIORIとは独立して保持する。
/// native moduleはShioriLoaderのraw XPC backendを使い、本体プロセスへdlopenしない。
final class MakotoTranslator {
    private let loader: ShioriRequesting

    init(loader: ShioriRequesting) {
        self.loader = loader
    }

    convenience init?(moduleName: String, base: URL) {
        let searchPaths = [base, base.appendingPathComponent("modules", isDirectory: true)]
        guard let moduleURL = ShioriLoader.find(name: moduleName, in: searchPaths),
              let loader = ShioriLoader(
                moduleURL: moduleURL,
                communication: .init(version: "MAKOTO/2.0"),
                shiori2Compatibility: false
              ) else { return nil }
        self.init(loader: loader)
    }

    func translate(_ script: String) -> String? {
        guard let response = loader.request(MakotoWireCodec.makeRequest(script)) else { return nil }
        return MakotoWireCodec.parseResponse(response)
    }

    func unload() {
        loader.unload()
    }

}

struct ScriptTranslationContext: Equatable {
    var reasons: Set<String>
    var eventID: String?
    var references: [String]
    var isSSTP: Bool
    var sender: String
    var securityLevel: String
    var securityOrigin: String?

    init(
        reasons: Set<String> = [],
        eventID: String? = nil,
        references: [String] = [],
        isSSTP: Bool = false,
        sender: String = "Ourin",
        securityLevel: String = "local",
        securityOrigin: String? = nil
    ) {
        self.reasons = reasons
        self.eventID = eventID
        self.references = references
        self.isSSTP = isSSTP
        self.sender = sender
        self.securityLevel = securityLevel
        self.securityOrigin = securityOrigin
    }

    static let baseware = ScriptTranslationContext()

    var reasonHeader: String? {
        reasons.isEmpty ? nil : reasons.sorted().joined(separator: ",")
    }

    var sourceReferencesHeader: String? {
        references.isEmpty ? nil : references.joined(separator: String(UnicodeScalar(1)))
    }
}
