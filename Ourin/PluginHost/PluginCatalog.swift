import Foundation

/// Ourin サイトで再配布対象として管理している対応版パッケージ。
struct PluginCatalogItem: Decodable, Identifiable {
    let id: String
    let name: String
    let file: String
    let limitations: String
    let upstream: String?
    let source_url: String?
    let author: String?
    let sha256: String
    let bytes: Int

    var pageURL: URL? { (source_url ?? upstream).flatMap(PluginCatalog.webURL) }
    var downloadURL: URL? {
        // 配布元 JSON のパスを同一サイトの単一ファイル名に限定する。
        guard !file.isEmpty, file.hasSuffix(".zip"),
              file.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*\\.zip$", options: .regularExpression) != nil else { return nil }
        return PluginCatalog.downloadBaseURL.appendingPathComponent(file)
    }
    func matches(_ query: String) -> Bool {
        PluginCatalog.matches(query, fields: [name, id, limitations, author ?? ""])
    }
}

enum PluginCatalog {
    static let sourceURL = URL(string: "https://furinlab.com/ourin/docs/library/compatibility-plugin-ports/ja/")!
    static let downloadBaseURL = URL(string: "https://furinlab.com/ourin/downloads/plugins/")!
    static let feedURL = downloadBaseURL.appendingPathComponent("packages.json")

    static func webURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func matches(_ query: String, fields: [String]) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        return terms.allSatisfy { term in
            fields.contains { $0.localizedStandardContains(String(term)) }
        }
    }

    static func decode(_ data: Data) throws -> [PluginCatalogItem] {
        struct Feed: Decodable {
            let schema: Int
            let packages: [PluginCatalogItem]
            let withheld: [String]?
        }
        let feed = try JSONDecoder().decode(Feed.self, from: data)
        guard feed.schema == 1 else { throw URLError(.cannotParseResponse) }
        let withheld = Set(feed.withheld ?? [])
        var seen: Set<String> = []
        return feed.packages.filter {
            !$0.id.isEmpty && !$0.name.isEmpty && !withheld.contains($0.id)
                && $0.downloadURL != nil && $0.bytes > 0
                && $0.sha256.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil
                && seen.insert($0.id).inserted
        }
    }

    static func fetch() async throws -> [PluginCatalogItem] {
        let request = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, let response { continuation.resume(returning: (data, response)) }
                else { continuation.resume(throwing: URLError(.badServerResponse)) }
            }.resume()
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 2_000_000 else {
            throw URLError(.badServerResponse)
        }
        return try decode(data)
    }
}

struct InstalledPluginItem: Identifiable {
    let id: String // package path: 同じ plugin ID の別パッケージも区別する
    let pluginID: String
    let name: String
    let author: String
    let status: String
    let path: String
}

extension PluginCatalog {
    /// Registry 未再読込の新規インストールも表示する。探索で DLL の変換・ロードは行わない。
    static func installedItems(registered: [PluginCompatibilityEntry], paths: [URL]) -> [InstalledPluginItem] {
        var items = registered.map { entry in
            let path = entry.packagePath ?? entry.compatibilityPath
            return InstalledPluginItem(id: path, pluginID: entry.id, name: entry.name,
                                       author: entry.craftman ?? "不明",
                                       status: entry.canDispatchRequests ? "読み込み可能" : "情報のみ（実行未対応）", path: path)
        }
        var seen = Set(items.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path })
        for root in paths {
            let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
            for child in children {
                guard let dict = LegacyDescriptor.readDictionary(from: child.appendingPathComponent("descript.txt")),
                      seen.insert(child.standardizedFileURL.path).inserted else { continue }
                // legacy registry の path は DLL を指すので、親フォルダでも照合する。
                if registered.contains(where: {
                    URL(fileURLWithPath: $0.compatibilityPath).deletingLastPathComponent().standardizedFileURL == child.standardizedFileURL
                }) { continue }
                items.append(InstalledPluginItem(id: child.path, pluginID: dict["id"] ?? "",
                                                 name: dict["name"] ?? child.lastPathComponent,
                                                 author: dict["craftman"] ?? "不明",
                                                 status: "未読込（再起動後に確認）", path: child.path))
            }
        }
        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
