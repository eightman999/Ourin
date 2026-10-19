import Foundation

struct RSSFeedItem: Equatable {
    let title: String
    let url: String
    let publishedAt: Date?
    let author: String
    let summary: String

    /// RSS/Atom の Reference に入れる標準形式。
    var wireValue: String {
        let date = publishedAt.map(Self.referenceDateFormatter.string) ?? ""
        return [title, url, date, author, summary].joined(separator: "\u{1}")
    }

    private static let referenceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy,MM,dd,HH,mm,ss"
        return formatter
    }()
}

enum RSSFeedParserError: Error, CustomStringConvertible {
    case invalidXML(String)
    case noFeedItems

    var description: String {
        switch self {
        case .invalidXML(let message): return message
        case .noFeedItems: return "RSS/Atom の項目を解析できません"
        }
    }
}

/// 外部依存のない RSS 2.x / Atom 1.0 の最小共通パーサー。
final class RSSFeedParser: NSObject, XMLParserDelegate {
    private var items: [RSSFeedItem] = []
    private var currentItem: Item?
    private var currentField: Field?
    private var currentText = ""
    private var linkHref = ""
    private var sawFeedRoot = false

    private enum Field {
        case title
        case link
        case published
        case author
        case summary
    }

    private struct Item {
        var title = ""
        var url = ""
        var publishedAt: Date?
        var publishedText = ""
        var author = ""
        var summary = ""
    }

    func parse(_ data: Data) throws -> [RSSFeedItem] {
        reset()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = true
        guard parser.parse() else {
            throw RSSFeedParserError.invalidXML(parser.parserError?.localizedDescription ?? "XML解析に失敗しました")
        }
        guard sawFeedRoot else {
            throw RSSFeedParserError.invalidXML("RSS/Atom のルート要素がありません")
        }
        return items
    }

    private func reset() {
        items.removeAll(keepingCapacity: true)
        currentItem = nil
        currentField = nil
        currentText = ""
        linkHref = ""
        sawFeedRoot = false
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let name = localName(elementName, qualifiedName: qName)
        switch name {
        case "rss", "rdf", "feed":
            sawFeedRoot = true
        case "item", "entry":
            if currentItem != nil {
                finishItem()
            }
            currentItem = Item()
        case "title" where currentItem != nil:
            begin(.title)
        case "link" where currentItem != nil:
            linkHref = attributeDict["href"] ?? attributeDict["url"] ?? ""
            begin(.link)
        case "pubdate", "published", "updated", "date":
            guard currentItem != nil else { break }
            begin(.published)
        case "author", "creator", "name":
            guard currentItem != nil else { break }
            begin(.author)
        case "description", "summary", "content", "encoded":
            guard currentItem != nil else { break }
            begin(.summary)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentField != nil else { return }
        currentText.append(string)
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = localName(elementName, qualifiedName: qName)
        switch name {
        case "title" where currentField == .title:
            assignCurrentText { $0.title = normalizedText($1) }
        case "link" where currentField == .link:
            assignCurrentText { item, text in
                let value = linkHref.isEmpty ? text : linkHref
                item.url = normalizedText(value)
            }
            linkHref = ""
        case "pubdate", "published", "updated", "date":
            guard currentField == .published else { break }
            assignCurrentText { item, text in
                item.publishedText = normalizedText(text)
                item.publishedAt = Self.parseDate(item.publishedText)
            }
        case "author", "creator", "name":
            guard currentField == .author else { break }
            assignCurrentText { $0.author = normalizedText($1) }
        case "description", "summary", "content", "encoded":
            guard currentField == .summary else { break }
            assignCurrentText { $0.summary = normalizedText($1) }
        case "item", "entry":
            finishItem()
        default:
            break
        }
    }

    private func begin(_ field: Field) {
        currentField = field
        currentText = ""
    }

    private func assignCurrentText(_ assign: (inout Item, String) -> Void) {
        guard currentItem != nil else { return }
        var item = currentItem!
        assign(&item, currentText)
        currentItem = item
        currentField = nil
        currentText = ""
    }

    private func finishItem() {
        guard let item = currentItem else { return }
        let title = normalizedText(item.title)
        let summary = item.summary.isEmpty ? title : item.summary
        guard !title.isEmpty || !item.url.isEmpty else {
            currentItem = nil
            currentField = nil
            currentText = ""
            return
        }
        items.append(RSSFeedItem(
            title: title,
            url: normalizedText(item.url),
            publishedAt: item.publishedAt ?? Self.parseDate(item.publishedText),
            author: normalizedText(item.author),
            summary: summary
        ))
        currentItem = nil
        currentField = nil
        currentText = ""
    }

    private func localName(_ elementName: String, qualifiedName: String?) -> String {
        let raw = qualifiedName ?? elementName
        return raw.split(separator: ":").last.map(String.init)?.lowercased() ?? raw.lowercased()
    }

    private func normalizedText(_ value: String) -> String {
        let withoutTags = value.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        return withoutTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func parseDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }

        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd HH:mm:ss Z",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd HH:mm:ss"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
