import Foundation

/// 登録されたプロバイダを用いてプロパティを解決する管理クラス。
public final class PropertyManager {
    /// プレフィックス（例: `system`）毎のプロバイダ一覧。
    private var providers: [String: PropertyProvider] = [:]

    /// 既定のプロバイダを登録して初期化する。
    public init() {
        register("system", provider: SystemPropertyProvider())
        register("baseware", provider: BasewarePropertyProvider())
        // Sample ghost data used for property responses.
        let sampleGhosts = [
            Ghost(name: "Sample", path: "/Applications/Sample.ghost", icon: "/Applications/Sample/icon.png")
        ]
        let active = [0]
        register("ghostlist", provider: GhostPropertyProvider(mode: .ghostlist, ghosts: sampleGhosts, activeIndices: active))
        register("activeghostlist", provider: GhostPropertyProvider(mode: .activeghostlist, ghosts: sampleGhosts, activeIndices: active))
        register("currentghost", provider: GhostPropertyProvider(mode: .currentghost, ghosts: sampleGhosts, activeIndices: active))
    }

    /// `prefix.*` を処理するプロバイダを登録する。
    public func register(_ prefix: String, provider: PropertyProvider) {
        providers[prefix.lowercased()] = provider
    }

    /// 例: `system.year` のような完全キーから値を取得する。
    public func get(_ key: String) -> String? {
        let lower = key.lowercased()
        guard let dot = lower.firstIndex(of: ".") else { return nil }
        let prefix = String(lower[..<dot])
        let rest = String(lower[lower.index(after: dot)...])
        guard let provider = providers[prefix] else { return nil }
        return provider.get(key: rest)
    }

    /// 書き込み可能な場合に値を設定する。
    @discardableResult
    public func set(_ key: String, value: String) -> Bool {
        let lower = key.lowercased()
        guard let dot = lower.firstIndex(of: ".") else { return false }
        let prefix = String(lower[..<dot])
        let rest = String(lower[lower.index(after: dot)...])
        guard let provider = providers[prefix] else { return false }
        return provider.set(key: rest, value: value)
    }
}

/// 文字列中の `%property[...]` を展開するユーティリティ。
public extension PropertyManager {
    func expand(text: String) -> String {
        var result = text
        // `%property[...]` を単純に検索する正規表現
        let pattern = "%property\\[([^\\]]+)\\]"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let matches = regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        for m in matches.reversed() {
            if let r = Range(m.range(at: 1), in: text) {
                let key = String(text[r])
                let value = get(key) ?? ""
                if let full = Range(m.range(at: 0), in: result) {
                    result.replaceSubrange(full, with: value)
                }
            }
        }
        return result
    }
}
