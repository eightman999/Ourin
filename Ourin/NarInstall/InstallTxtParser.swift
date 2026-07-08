// Ourin/NarInstall/InstallTxtParser.swift
import Foundation

struct InstallManifest {
    var type: String = ""
    var directory: String = ""
    var accept: String?
    /// install.txt の charset 宣言値（宣言されていた場合のみ）
    var charset: String?
    /// refresh,1 でインストール前に既存インストール先を削除する（更新インストール）
    var refresh: Bool = false
    /// refresh 時に残すパスを表す正規表現の集合（UKADOC: コロン区切り。互換のためカンマも許容）
    var refreshUndeleteMask: [String] = []
    /// type=ghost に同梱されたバルーンのインストール先ディレクトリ名
    var balloonDirectory: String?
    /// 同梱バルーンの NAR 内ソースディレクトリ名（既定は balloonDirectory）
    var balloonSourceDirectory: String?
    /// type=ghost / type=shell に同梱された付属コンポーネント（*.directory 系）の構造化リスト。
    /// UKADOC install.txt: balloon/headline/plugin/calendar.skin/calendar.plugin を同時インストール可能。
    /// 後方互換のため balloonDirectory / balloonSourceDirectory とも同期する。
    var attachedComponents: [AttachedComponent] = []
    var extras: [String: String] = [:] // shell.directory, *.source.directory etc.
}

/// install.txt の `*.directory` 系フィールドで表現される「同時インストールされる付属コンポーネント」。
/// UKADOC（https://ssp.shillest.net/ukadoc/manual/descript_install.html）準拠。
///
/// `*.directory` は type=ghost / type=shell の場合のみ設定可能。
/// `*` 部分は `balloon`, `headline`, `plugin`, `calendar.skin`, `calendar.plugin` のいずれかで、
/// 同種を複数同梱する場合は `balloon0`, `balloon1` ... のように末尾に数字をつける。
struct AttachedComponent {
    /// install.txt の `*.directory` の `*` 部分（末尾の数字込みの生トークン。"balloon0" 等）。
    let kindToken: String
    /// kindToken から末尾の数字を除去して小文字化した正規 type。
    /// 例: "balloon0" → "balloon", "calendar.skin1" → "calendar.skin"
    let type: String
    /// インストール後のディレクトリ名（`*.directory` の値）。
    var directory: String
    /// アーカイブ内でのソースディレクトリ名（`*.source.directory` の値。未指定なら nil = directory と同義）。
    var sourceDirectory: String?
    /// `*.refresh,1` の値。
    var refresh: Bool
    /// `*.refreshundeletemask` の値（コロン/カンマ区切りで分割済み）。
    var refreshUndeleteMask: [String]
}

enum TextEncodingDetector {
    /// Windows 互換 Shift_JIS (CP932)
    static let shiftJIS = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)))

    static func decode(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        // Try Shift_JIS (CP932)
        if let s = String(data: data, encoding: shiftJIS) { return s }
        return nil
    }

    /// `charset,<value>` / `charset:<value>` の宣言値（小文字）を String.Encoding へ写像する。
    /// 未対応・不明な値は nil を返す。
    static func encoding(forCharset declared: String) -> String.Encoding? {
        let v = declared.lowercased().trimmingCharacters(in: .whitespaces)
        switch v {
        case "utf-8", "utf8":
            return .utf8
        case "shift_jis", "shift-jis", "shiftjis", "sjis", "cp932", "windows-31j", "ms932":
            return shiftJIS
        default:
            return nil
        }
    }

    /// install.txt 等の生バイト列の先頭行を走査し、`charset` 宣言を探す。
    /// 宣言があれば対応するエンコーディング、なければ nil を返す。
    static func declaredCharset(in data: Data) -> String.Encoding? {
        // 先頭部分だけを ASCII 互換として安全に走査する（最大 4KB）。
        let probeCount = min(data.count, 4096)
        let probe = data.prefix(probeCount)
        guard let ascii = String(data: probe, encoding: .isoLatin1) else { return nil }
        let lines = ascii.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            // `charset,<value>` または `charset:<value>` の両表記を許容する。
            let lower = line.lowercased()
            guard lower.hasPrefix("charset") else { continue }
            let afterKey = line.dropFirst("charset".count)
            guard let sep = afterKey.first, sep == "," || sep == ":" else { continue }
            let value = afterKey.dropFirst().trimmingCharacters(in: .whitespaces)
            if let enc = encoding(forCharset: value) { return enc }
        }
        return nil
    }
}

struct InstallTxtParser {
    /// install.txt の生バイト列を解析する。
    /// 先頭行に `charset` 宣言があればそのエンコーディングで優先的にデコードし、
    /// 宣言が無い／デコード失敗時は従来の推定（UTF-8 → Shift_JIS）へフォールバックする。
    static func parse(data: Data) throws -> InstallManifest {
        var text: String?
        if let declared = TextEncodingDetector.declaredCharset(in: data) {
            text = String(data: data, encoding: declared)
        }
        if text == nil {
            text = TextEncodingDetector.decode(data)
        }
        guard let str = text else { throw NarInstaller.Error.installTxtDecodeFailed }
        return try parse(str)
    }

    static func parse(_ text: String) throws -> InstallManifest {
        var manifest = InstallManifest()
        // kindToken → attachedComponents のインデックス。
        // *.directory / *.source.directory / *.refresh / *.refreshundeletemask を同じ要素へマージするため。
        var attachedIndex: [String: Int] = [:]

        /// 指定した kindToken の AttachedComponent を（無ければ生成して）インデックスを返す。
        func ensureAttached(_ kindToken: String) -> Int {
            if let idx = attachedIndex[kindToken] { return idx }
            let type = Self.attachedType(fromKindToken: kindToken)
            manifest.attachedComponents.append(AttachedComponent(
                kindToken: kindToken,
                type: type,
                directory: "",
                sourceDirectory: nil,
                refresh: false,
                refreshUndeleteMask: []
            ))
            let idx = manifest.attachedComponents.count - 1
            attachedIndex[kindToken] = idx
            return idx
        }

        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            let parts = line.split(separator: ",", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts[1]
            switch key {
            case "charset": manifest.charset = value
            case "type": manifest.type = value
            case "directory": manifest.directory = value
            case "accept": manifest.accept = value
            case "refresh":
                manifest.refresh = (value == "1" || value.lowercased() == "true")
            case "refreshundeletemask":
                // UKADOC では `refreshundeletemask,ファイル名1:ファイル名2...` のコロン区切り。
                // 既存データ互換のためカンマ区切りも寛容に受ける。
                manifest.refreshUndeleteMask = value
                    .split(whereSeparator: { $0 == ":" || $0 == "," })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            case "balloon.directory":
                // 後方互換: 既存の balloonDirectory プロパティを維持しつつ、構造化リストにも反映。
                manifest.balloonDirectory = value
                manifest.extras[key] = value
                let idx = ensureAttached("balloon")
                manifest.attachedComponents[idx].directory = value
            case "balloon.source.directory":
                manifest.balloonSourceDirectory = value
                manifest.extras[key] = value
                let idx = ensureAttached("balloon")
                manifest.attachedComponents[idx].sourceDirectory = value
            default:
                // UKADOC 汎用付属コンポーネントフィールド（*.directory / *.source.directory / *.refresh / *.refreshundeletemask）。
                // type=ghost / type=shell の同梱 balloon / headline / plugin / calendar.skin / calendar.plugin 等。
                if key.hasSuffix(".source.directory") {
                    let token = String(key.dropLast(".source.directory".count))
                    let idx = ensureAttached(token)
                    manifest.attachedComponents[idx].sourceDirectory = value
                    manifest.extras[key] = value
                } else if key.hasSuffix(".refreshundeletemask") {
                    let token = String(key.dropLast(".refreshundeletemask".count))
                    let idx = ensureAttached(token)
                    manifest.attachedComponents[idx].refreshUndeleteMask = value
                        .split(whereSeparator: { $0 == ":" || $0 == "," })
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    manifest.extras[key] = value
                } else if key.hasSuffix(".refresh") {
                    let token = String(key.dropLast(".refresh".count))
                    let idx = ensureAttached(token)
                    manifest.attachedComponents[idx].refresh = (value == "1" || value.lowercased() == "true")
                    manifest.extras[key] = value
                } else if key.hasSuffix(".directory") {
                    let token = String(key.dropLast(".directory".count))
                    let idx = ensureAttached(token)
                    manifest.attachedComponents[idx].directory = value
                    manifest.extras[key] = value
                } else {
                    manifest.extras[key] = value
                }
            }
        }
        guard !manifest.type.isEmpty else { throw NarInstaller.Error.installTxtMissingKey("type") }
        // UKADOC: directory は supplement / package では任意、それ以外では必須。
        let typeLower = manifest.type.lowercased()
        let directoryOptional = (typeLower == "supplement" || typeLower == "package")
        if !directoryOptional {
            guard !manifest.directory.isEmpty else { throw NarInstaller.Error.installTxtMissingKey("directory") }
        }
        return manifest
    }

    /// kindToken（`*.directory` の `*` 部分）から正規 type を抽出する。
    /// 末尾の数字（同種複数指定用インデックス）を除去して小文字化する。
    /// 例: "balloon0" → "balloon", "calendar.skin1" → "calendar.skin", "headline" → "headline"
    static func attachedType(fromKindToken token: String) -> String {
        var t = token
        while let last = t.last, last.isNumber {
            t.removeLast()
        }
        return t.lowercased()
    }
}

struct UpdateDescriptorParser {
    static func parse(_ text: String, baseURL: URL) -> [URL] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var results: [URL] = []

        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix(";"), !line.hasPrefix("#"), !line.hasPrefix("//") else { continue }

            let components = line
                .replacingOccurrences(of: "\u{0001}", with: ",")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            guard let rawTarget = components.first(where: { !$0.isEmpty }) else { continue }
            let candidate = rawTarget.replacingOccurrences(of: "\\", with: "/")

            if let absolute = URL(string: candidate), let scheme = absolute.scheme?.lowercased(),
               scheme == "https" || scheme == "http" {
                results.append(absolute)
                continue
            }
            if let relative = URL(string: candidate, relativeTo: baseURL)?.absoluteURL {
                results.append(relative)
            }
        }

        return Array(Set(results)).sorted { $0.absoluteString < $1.absoluteString }
    }
}
