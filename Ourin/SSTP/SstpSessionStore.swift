import Foundation

final class SstpSessionStore {
    static let shared = SstpSessionStore()

    private let lock = NSLock()
    private var entries: [String: String] = [:]
    private var cookiesBySender: [String: [String: String]] = [:]
    private var quietModeEnabled = false

    private init() {}

    func mergeEntries(_ incoming: [String: String]) {
        guard !incoming.isEmpty else { return }
        lock.lock()
        for (id, script) in incoming {
            entries[id] = script
        }
        lock.unlock()
    }

    func allEntriesHeaderValue() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !entries.isEmpty else { return nil }
        let serialized = entries.keys.sorted().compactMap { key -> String? in
            guard let value = entries[key] else { return nil }
            return "\(key)=\(value)"
        }.joined(separator: ";")
        return serialized.isEmpty ? nil : serialized
    }

    func setCookie(sender: String, name: String, value: String) {
        guard !sender.isEmpty, !name.isEmpty else { return }
        lock.lock()
        var cookies = cookiesBySender[sender] ?? [:]
        cookies[name] = value
        cookiesBySender[sender] = cookies
        lock.unlock()
        if persistenceEnabled {
            persistIfNeeded()
        }
    }

    func getCookie(sender: String, name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cookiesBySender[sender]?[name]
    }

    func allCookies(sender: String) -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return cookiesBySender[sender] ?? [:]
    }

    func setQuietMode(_ enabled: Bool) {
        lock.lock()
        quietModeEnabled = enabled
        lock.unlock()
    }

    func isQuietModeEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return quietModeEnabled
    }

    func reset() {
        lock.lock()
        entries.removeAll()
        cookiesBySender.removeAll()
        quietModeEnabled = false
        persistTimer?.invalidate()
        persistTimer = nil
        lock.unlock()
    }

    // MARK: - ディスク永続化（SSP sp_cookie.obj 互換フォーマット）

    /// 永続化の有効フラグ。既定はオフ（テストでは実ファイルへの書込を避ける）。
    /// アプリ起動時（`loadFromDisk` と合わせて）にオンにする。
    private var persistenceEnabled = false

    func enablePersistence() {
        lock.lock()
        persistenceEnabled = true
        lock.unlock()
    }

    /// SSP の Cookie 永続化ファイルパス。
    /// 既定は Application Support/Ourin/sstp_cookie.txt。テストから差し替え可能にするため、
    /// 保存先は `cookieFileURL` で差し替えられる。
    var cookieFileURL: URL = SstpSessionStore.defaultCookieFileURL()

    static func defaultCookieFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Ourin", isDirectory: true)
            .appendingPathComponent("sstp_cookie.txt")
    }

    private var persistTimer: Timer?
    private var isPersisting = false

    private func persistIfNeeded() {
        // 変更ごとの即時書込は高頻度になるため、短い遅延で集約する。
        lock.lock()
        let needsTimer = persistTimer == nil
        if needsTimer {
            persistTimer = Timer(timeInterval: 1.0, repeats: false) { [weak self] _ in
                self?.lock.lock()
                self?.persistTimer = nil
                self?.lock.unlock()
                self?.saveToDisk()
            }
            RunLoop.main.add(persistTimer!, forMode: .default)
        }
        lock.unlock()
    }

    func saveToDisk() {
        lock.lock()
        let cookies = cookiesBySender
        lock.unlock()

        guard !cookies.isEmpty else {
            // 空ならファイルを残さない。
            if FileManager.default.fileExists(atPath: cookieFileURL.path) {
                try? FileManager.default.removeItem(at: cookieFileURL)
            }
            return
        }

        var lines: [String] = ["#charset,UTF-8"]
        for sender in cookies.keys.sorted() {
            let cookieSet = cookies[sender] ?? [:]
            // クライアント名（Sender）行。IP は Ourin では接続元を保持しないため 0.0.0.0 で扱う。
            lines.append("#cookie,0.0.0.0,\(escape(sender))")
            lines.append("\(escape(sender)),")
            for name in cookieSet.keys.sorted() {
                lines.append("\(escape(name)),\(escape(cookieSet[name] ?? "")),")
            }
        }
        let content = lines.joined(separator: "\r\n")

        do {
            try FileManager.default.createDirectory(
                at: cookieFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.data(using: .utf8)?.write(to: cookieFileURL, options: .atomic)
        } catch {
            Log.info("[SstpSessionStore] Cookie save failed: \(error)")
        }
    }

    /// 起動時または明示的な load 要求で SSP 互換ファイルから復元する。
    func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: cookieFileURL.path),
              let data = try? Data(contentsOf: cookieFileURL),
              let content = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .shiftJIS) else { return }

        var restored: [String: [String: String]] = [:]
        var currentSender: String?
        var currentName: String?

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let tokens = splitEscaped(line, separator: ",")

            if tokens.first == "#charset" {
                continue
            }
            if tokens.first == "#cookie" {
                // #cookie,<IP>,<クライアント名>
                if tokens.count >= 3 {
                    currentSender = unescape(tokens[2])
                    currentName = currentSender
                    if restored[currentSender ?? ""] == nil {
                        restored[currentSender ?? ""] = [:]
                    }
                }
                continue
            }
            // クライアント名行: <name>,
            if let name = currentName,
               tokens.count == 2, tokens[1].isEmpty,
               unescape(tokens[0]) == name {
                continue
            }
            // クッキー行: <key>,<value>,
            if let sender = currentSender, tokens.count >= 2 {
                restored[sender]?[unescape(tokens[0])] = unescape(tokens[1])
            }
        }

        guard !restored.isEmpty else { return }
        lock.lock()
        for (sender, cookies) in restored {
            var merged = cookiesBySender[sender] ?? [:]
            for (name, value) in cookies {
                merged[name] = value
            }
            cookiesBySender[sender] = merged
        }
        lock.unlock()
    }

    /// `\` でエスケープされた区切り文字は分割しないトークナイザ。
    private func splitEscaped(_ value: String, separator: Character) -> [String] {
        var tokens: [String] = []
        var current = ""
        var index = value.startIndex
        while index < value.endIndex {
            let ch = value[index]
            if ch == "\\", index < value.index(before: value.endIndex) {
                let next = value[value.index(after: index)]
                current.append(ch)
                current.append(next)
                index = value.index(after: index)
            } else if ch == separator {
                tokens.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            index = value.index(after: index)
        }
        tokens.append(current)
        return tokens
    }

    private func escape(_ value: String) -> String {
        // カンマ・改行・空白をエスケープして1行トークンとして復元可能にする。
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func unescape(_ value: String) -> String {
        var result = ""
        var index = value.startIndex
        while index < value.endIndex {
            if value[index] == "\\", index < value.index(before: value.endIndex) {
                let next = value[value.index(after: index)]
                switch next {
                case "\\": result.append("\\")
                case ",": result.append(",")
                case "r": result.append("\r")
                case "n": result.append("\n")
                default: result.append(next)
                }
                index = value.index(after: index)
            } else {
                result.append(value[index])
            }
            index = value.index(after: index)
        }
        return result
    }
}
