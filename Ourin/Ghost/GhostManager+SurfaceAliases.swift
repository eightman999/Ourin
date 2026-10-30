import Foundation

extension GhostManager {
    func cacheSurfaceAliases(_ content: String) {
        guard surfaceAliasDefinitionContent != content else { return }
        let parsed = SerikoParser.parseScopedSurfaceAliases(content)
        // Preserve explicit legacy test/API overrides when the first shell has no aliases.
        if surfaceAliasDefinitionContent != nil || !parsed.isEmpty {
            let primary = parsed[0] ?? [:]
            surfaceNameAliases = primary.compactMapValues { $0.first }
            surfaceAliases = Dictionary(uniqueKeysWithValues: primary.compactMap { key, candidates in
                guard let id = Int(key), let first = candidates.first else { return nil }
                return (id, first)
            })
        }
        surfaceAliasCandidatesByScope = parsed
        surfaceAliasDefinitionContent = content
    }

    private func ensureSurfaceAliasesLoaded() {
        guard let shell = loadShellPath() else { return }
        if surfaceAliasDefinitionPath == nil, surfaceAliasDefinitionContent != nil {
            surfaceAliasDefinitionPath = shell.path
            return
        }
        guard surfaceAliasDefinitionPath != shell.path || surfaceAliasDefinitionContent == nil else { return }
        if surfaceAliasDefinitionPath != nil, surfaceAliasDefinitionPath != shell.path {
            surfaceAliases.removeAll(); surfaceNameAliases.removeAll()
            surfaceAliasCandidatesByScope.removeAll()
        }
        surfaceAliasDefinitionPath = shell.path
        surfaceAliasDefinitionContent = nil
        cacheSurfaceAliases(SurfaceDefinitionLoader.load(from: shell)?.content ?? "")
    }

    func resolveNumericSurfaceAlias(_ id: Int, scope: Int) -> Int {
        ensureSurfaceAliasesLoaded()
        if !surfaceAliasCandidatesByScope.isEmpty {
            return surfaceAliasCandidatesByScope[scope]?[String(id)]?.randomElement() ?? id
        }
        return surfaceAliases[id] ?? id
    }

    func resolveNamedSurfaceAlias(_ name: String, scope: Int) -> Int? {
        ensureSurfaceAliasesLoaded()
        if !surfaceAliasCandidatesByScope.isEmpty {
            return surfaceAliasCandidatesByScope[scope]?[name.lowercased()]?.randomElement()
        }
        return surfaceNameAliases[name.lowercased()]
    }
}
