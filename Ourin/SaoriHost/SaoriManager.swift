import Foundation

public final class SaoriManager {
    private let registry: SaoriRegistry

    public init(registry: SaoriRegistry = SaoriRegistry()) {
        self.registry = registry
    }

    public func addSearchPath(_ path: URL) {
        registry.addSearchPath(path)
    }

    public func discover(under base: URL) {
        registry.discoverSaoriDirectory(under: base)
    }

    @discardableResult
    public func loadModule(named name: String) throws -> SaoriLoader {
        let loader = try registry.loadModule(named: name)
        try ensureVersionHandshake(loader: loader)
        return loader
    }

    public func unloadModule(named name: String) {
        registry.unloadModule(named: name)
    }

    public func unloadAll() {
        registry.unloadAll()
    }

    public func request(moduleName: String, requestText: String, charset: String = "UTF-8") throws -> String {
        let loader = try registry.loadModule(named: moduleName)
        return try loader.send(requestText, charset: charset)
    }

    public func execute(
        moduleName: String,
        arguments: [String],
        charset: String = "UTF-8",
        securityLevel: String? = nil,
        securityOrigin: String? = nil
    ) throws -> SaoriResponse {
        var headers: [String: String] = ["Charset": charset, "Sender": "Ourin"]
        for (idx, value) in arguments.enumerated() {
            headers["Argument\(idx)"] = value
        }
        if let securityLevel, !securityLevel.isEmpty {
            headers["SecurityLevel"] = securityLevel
        }
        if let securityOrigin, !securityOrigin.isEmpty {
            headers["SecurityOrigin"] = securityOrigin
        }
        let request = SaoriRequest(method: "EXECUTE", target: nil, version: "SAORI/1.0", headers: headers, body: nil)
        let wire = SaoriProtocol.buildRequest(request)
        let responseText = try self.request(moduleName: moduleName, requestText: wire, charset: charset)
        return try SaoriProtocol.parseResponse(responseText)
    }

    /// Bridge target for yaya_core pluginOperation.
    public func handlePluginOperation(_ operation: String, params: [String: Any]) -> [String: Any] {
        switch operation {
        case "saori_load":
            guard let module = params["module"] as? String else {
                return ["ok": false, "error": "module parameter required"]
            }
            do {
                _ = try loadModule(named: module)
                return ["ok": true]
            } catch {
                return ["ok": false, "error": "\(error)"]
            }

        case "saori_unload":
            guard let module = params["module"] as? String else {
                return ["ok": false, "error": "module parameter required"]
            }
            unloadModule(named: module)
            return ["ok": true]

        case "saori_request":
            guard let module = params["module"] as? String else {
                return ["ok": false, "error": "module parameter required"]
            }
            let charset = (params["charset"] as? String) ?? "UTF-8"
            let text = (params["request"] as? String) ?? ""
            do {
                let response = try request(moduleName: module, requestText: text, charset: charset)
                return ["ok": true, "response": response]
            } catch {
                return ["ok": false, "error": "\(error)"]
            }

        case "saori_execute":
            guard let module = params["module"] as? String else {
                return ["ok": false, "error": "module parameter required"]
            }
            let charset = (params["charset"] as? String) ?? "UTF-8"
            let securityLevel = params["securityLevel"] as? String
            let securityOrigin = params["securityOrigin"] as? String
            let arguments = (params["arguments"] as? [String]) ?? []
            do {
                let response = try execute(
                    moduleName: module,
                    arguments: arguments,
                    charset: charset,
                    securityLevel: securityLevel,
                    securityOrigin: securityOrigin
                )
                return ["ok": true, "status": response.statusCode, "response": SaoriProtocol.buildResponse(response)]
            } catch {
                return ["ok": false, "error": "\(error)"]
            }

        default:
            return ["ok": false, "error": "unsupported operation: \(operation)"]
        }
    }

    private func ensureVersionHandshake(loader: SaoriLoader) throws {
        let request = SaoriRequest(
            method: "GET",
            target: "Version",
            version: "SAORI/1.0",
            headers: ["Charset": "UTF-8", "Sender": "Ourin"],
            body: nil
        )
        let wire = SaoriProtocol.buildRequest(request)
        let responseText = try loader.send(wire, charset: "UTF-8")
        let response = try SaoriProtocol.parseResponse(responseText)
        guard response.statusCode == 200 || response.statusCode == 204 else {
            throw NSError(
                domain: "SaoriManager",
                code: response.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "SAORI GET Version failed: \(response.statusCode) \(response.statusMessage)"]
            )
        }
    }
}
