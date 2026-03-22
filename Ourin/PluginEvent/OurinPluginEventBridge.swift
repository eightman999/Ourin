import Foundation

struct PluginTransportAction {
    let target: String?
    let script: String?
    let eventName: String?
    let references: [String: String]
}

final class OurinPluginEventBridge {
    private let registry: PluginRegistry
    private let runScript: (String) -> Void
    private let emitEvent: (String, [String: String]) -> Void

    init(
        registry: PluginRegistry,
        runScript: @escaping (String) -> Void,
        emitEvent: @escaping (String, [String: String]) -> Void
    ) {
        self.registry = registry
        self.runScript = runScript
        self.emitEvent = emitEvent
    }

    func resolveTargets(spec: String) -> [Plugin] {
        let token = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return [] }
        if token.caseInsensitiveCompare("random") == .orderedSame {
            guard let random = registry.plugins.randomElement() else { return [] }
            return [random]
        }
        if token.caseInsensitiveCompare("lastinstalled") == .orderedSame {
            guard let last = registry.plugins.last else { return [] }
            return [last]
        }
        return registry.plugins.filter { plugin in
            if let meta = registry.metas[plugin] {
                return meta.id.caseInsensitiveCompare(token) == .orderedSame
                    || meta.name.caseInsensitiveCompare(token) == .orderedSame
                    || meta.filename.caseInsensitiveCompare(token) == .orderedSame
            }
            return plugin.bundle.bundleURL.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(token) == .orderedSame
        }
    }

    func dispatch(pluginSpec: String, event: String, references: [String], notifyOnly: Bool) {
        let targets = resolveTargets(spec: pluginSpec)
        guard !targets.isEmpty else {
            Log.info("[PluginEventBridge] No plugin target matched: \(pluginSpec)")
            return
        }
        let refMap = Dictionary(uniqueKeysWithValues: references.enumerated().map { ("Reference\($0.offset)", $0.element) })
        for plugin in targets {
            do {
                if notifyOnly {
                    _ = try plugin.notify(id: event, references: refMap)
                    continue
                }
                let response = try plugin.get(id: event, references: refMap)
                guard let action = Self.transportAction(from: response, notifyOnly: false) else {
                    continue
                }
                guard Self.shouldHandleTarget(action.target) else {
                    Log.debug("[PluginEventBridge] ignored target: \(action.target ?? "nil")")
                    continue
                }
                if let script = action.script {
                    runScript(script)
                }
                if let eventName = action.eventName {
                    emitEvent(eventName, action.references)
                }
            } catch {
                Log.info("[PluginEventBridge] dispatch failed (\(event)): \(error)")
            }
        }
    }

    static func shouldHandleTarget(_ target: String?) -> Bool {
        guard let target else { return true }
        let normalized = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty { return true }
        return ["self", "ghost", "baseware", "ourin"].contains(normalized)
    }

    static func transportAction(from response: PluginResponse, notifyOnly: Bool) -> PluginTransportAction? {
        if notifyOnly { return nil }
        let scriptSource = response.script ?? response.value ?? ""
        let script = scriptSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let refs = references(from: response.otherHeaders)
        let eventName = response.otherHeaders.first(where: { $0.key.caseInsensitiveCompare("Event") == .orderedSame })?.value
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if script.isEmpty && (eventName == nil || eventName?.isEmpty == true) {
            return nil
        }
        return PluginTransportAction(
            target: response.target,
            script: script.isEmpty ? nil : script,
            eventName: eventName?.isEmpty == true ? nil : eventName,
            references: refs
        )
    }

    static func references(from headers: [String: String]) -> [String: String] {
        headers.reduce(into: [String: String]()) { acc, pair in
            guard pair.key.lowercased().starts(with: "reference") else { return }
            acc[pair.key] = pair.value
        }
    }
}
