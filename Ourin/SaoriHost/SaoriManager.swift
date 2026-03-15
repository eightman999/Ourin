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
        try registry.loadModule(named: name)
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

        default:
            return ["ok": false, "error": "unsupported operation: \(operation)"]
        }
    }
}
