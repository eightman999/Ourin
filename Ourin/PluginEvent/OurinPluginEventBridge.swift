import Foundation

struct PluginTransportAction {
    let target: String?
    let script: String?
    let scriptOptions: Set<String>
    let eventName: String?
    let eventOptions: Set<String>
    let references: [String: String]

    var sendsEventAsNotify: Bool {
        eventOptions.contains("notify")
    }
}

final class OurinPluginEventBridge {
    private let registry: PluginRegistry
    private let runScript: (PluginTransportAction) -> Void
    private let emitEvent: (PluginTransportAction) -> Bool

    init(
        registry: PluginRegistry,
        runScript: @escaping (PluginTransportAction) -> Void,
        emitEvent: @escaping (PluginTransportAction) -> Bool
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
                guard EventBridge.shared.canResolvePluginTarget(action.target) else {
                    Log.debug("[PluginEventBridge] ignored target: \(action.target ?? "nil")")
                    continue
                }
                Self.deliver(action, runScript: runScript, emitEvent: emitEvent)
            } catch {
                Log.info("[PluginEventBridge] dispatch failed (\(event)): \(error)")
            }
        }
    }

    /// notifyplugin 経路のディスパッチ（常に [NOTIFY] を強制）。
    /// 仕様 PLUGIN_EVENT/2.0M §4.17: notifyplugin は [NOTIFY] 固定。
    /// 呼び出し元のフラグに依らず NOTIFY として送信する専用エントリポイント。
    func dispatchNotify(pluginSpec: String, event: String, references: [String]) {
        let targets = resolveTargets(spec: pluginSpec)
        guard !targets.isEmpty else {
            Log.info("[PluginEventBridge] No plugin target matched (notifyplugin): \(pluginSpec)")
            return
        }
        let refMap = Dictionary(uniqueKeysWithValues: references.enumerated().map { ("Reference\($0.offset)", $0.element) })
        for plugin in targets {
            do {
                _ = try plugin.notify(id: event, references: refMap)
            } catch {
                Log.info("[PluginEventBridge] dispatchNotify failed (\(event)): \(error)")
            }
        }
    }

    static func shouldHandleTarget(_ target: String?) -> Bool {
        guard let target else { return true }
        let normalized = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty { return true }
        return [
            "self",
            "ghost",
            "baseware",
            "ourin",
            "__system_all_ghost__",
            "system_all_ghost",
            "systemany",
            "any",
            "all"
        ].contains(normalized)
    }

    static func transportAction(from response: PluginResponse, notifyOnly: Bool) -> PluginTransportAction? {
        if notifyOnly { return nil }
        let scriptSource = response.script ?? response.value ?? ""
        let script = scriptSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let refs = references(from: response.otherHeaders)
        let eventName = headerValue("Event", in: response.otherHeaders)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if script.isEmpty && (eventName == nil || eventName?.isEmpty == true) {
            return nil
        }
        return PluginTransportAction(
            target: response.target,
            script: script.isEmpty ? nil : script,
            scriptOptions: optionSet(response.scriptOption),
            eventName: eventName?.isEmpty == true ? nil : eventName,
            eventOptions: optionSet(response.eventOption),
            references: refs
        )
    }

    static func references(from headers: [String: String]) -> [String: String] {
        headers.reduce(into: [String: String]()) { acc, pair in
            guard let index = referenceIndex(of: pair.key) else { return }
            acc["Reference\(index)"] = pair.value
        }
    }

    @discardableResult
    static func deliver(
        _ action: PluginTransportAction,
        runScript: (PluginTransportAction) -> Void,
        emitEvent: (PluginTransportAction) -> Bool
    ) -> Bool {
        var eventProducedScript = false
        if action.eventName != nil {
            eventProducedScript = emitEvent(action)
        }
        if let script = action.script, !script.isEmpty, !eventProducedScript, !action.sendsEventAsNotify {
            runScript(action)
            return true
        }
        return eventProducedScript || action.eventName != nil
    }

    private static func headerValue(_ name: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private static func referenceIndex(of key: String) -> Int? {
        let lower = key.lowercased()
        guard lower.starts(with: "reference") else { return nil }
        return Int(lower.dropFirst("reference".count))
    }

    private static func optionSet(_ value: String?) -> Set<String> {
        guard let value else { return [] }
        let separators = CharacterSet(charactersIn: ", \t\r\n")
        return Set(
            value.components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }
}
