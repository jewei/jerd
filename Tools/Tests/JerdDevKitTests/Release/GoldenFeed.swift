/// The exact feed that `AppcastWriter` makes from `FeedFixtures.signedChannel` and `AppcastWriterTests.item`.
/// `sign_update` signs these bytes, so a change of the format must be deliberate.
enum GoldenFeed {
    static let withItem = """
        <?xml version="1.0" encoding="utf-8" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
            <channel>
                <title>Jerd updates</title>
                <link>https://github.com/jewei/jerd</link>
                <description>Signed updates for Jerd on macOS.</description>
                <language>en</language>
                <item>
                    <title>Jerd 0.2.0</title>
                    <pubDate>Tue, 06 Oct 2026 12:00:00 GMT</pubDate>
                    <sparkle:version>3</sparkle:version>
                    <sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>
                    <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
                    <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
                    <description sparkle:format="plain-text">• First line.
        • Second &lt;line&gt; &amp; more.
        </description>
                    <enclosure url="https://github.com/jewei/jerd/releases/download/v0.2.0/Jerd-0.2.0.dmg" \
        length="1234" type="application/octet-stream" sparkle:edSignature="\
        AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="/>
                </item>
            </channel>
        </rss>
        """
}
