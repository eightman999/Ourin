import Foundation
import Testing
@testable import Ourin

struct RSSFeedParserTests {
    @Test
    func parsesRSSItemsIntoExecuteRSSWireFields() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
          <title>Example</title>
          <item>
            <title>First &amp; foremost</title>
            <link>https://example.test/1</link>
            <pubDate>Tue, 11 Aug 2026 12:34:56 +0000</pubDate>
            <author>author@example.test</author>
            <description><![CDATA[<p>Summary one</p>]]></description>
          </item>
          <item>
            <title>Second</title>
            <link>https://example.test/2</link>
            <description>Summary two</description>
          </item>
        </channel></rss>
        """

        let items = try RSSFeedParser().parse(Data(xml.utf8))

        #expect(items.count == 2)
        #expect(items[0].title == "First & foremost")
        #expect(items[0].url == "https://example.test/1")
        #expect(items[0].author == "author@example.test")
        #expect(items[0].summary == "Summary one")
        #expect(items[0].publishedAt != nil)
        #expect(items[0].wireValue.split(separator: "\u{1}").count == 5)
        #expect(items[1].title == "Second")
        #expect(items[1].summary == "Summary two")
    }

    @Test
    func parsesAtomEntryLinkAndNestedAuthor() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Example Atom</title>
          <entry>
            <title>Atom entry</title>
            <link rel="alternate" href="https://example.test/atom" />
            <updated>2026-08-12T03:04:05Z</updated>
            <author><name>Atom Author</name></author>
            <summary>Atom summary</summary>
          </entry>
        </feed>
        """

        let items = try RSSFeedParser().parse(Data(xml.utf8))

        #expect(items == [RSSFeedItem(
            title: "Atom entry",
            url: "https://example.test/atom",
            publishedAt: items.first?.publishedAt,
            author: "Atom Author",
            summary: "Atom summary"
        )])
        #expect(items.first?.publishedAt != nil)
    }

    @Test
    func acceptsValidEmptyFeed() throws {
        let xml = "<rss version=\"2.0\"><channel><title>Empty</title></channel></rss>"
        #expect(try RSSFeedParser().parse(Data(xml.utf8)).isEmpty)
    }
}
