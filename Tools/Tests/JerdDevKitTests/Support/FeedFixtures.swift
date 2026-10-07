import Foundation

/// Fixed app update feeds. Tests with exact expectations use these, not the repository `appcast.xml`,
/// because each release adds an item to that file.
enum FeedFixtures {
    /// The repository `appcast.xml` before the first release, byte for byte: a channel without items,
    /// signed with the Jerd feed key.
    static let signedChannel =
        "<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\"?><!-- sparkle-sign-warning:\n"
        + "IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires re-signing this "
        + "file with generate_appcast or sign_update! The signed signature will be embedded at the end of this file.\n"
        + "--><rss xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\" version=\"2.0\">\n"
        + "  <channel>\n"
        + "    <title>Jerd updates</title>\n"
        + "    <link>https://github.com/jewei/jerd</link>\n"
        + "    <description>Signed updates for Jerd on macOS.</description>\n"
        + "    <language>en</language>\n"
        + "  </channel>\n"
        + "</rss><!-- sparkle-signatures:\n"
        + "edSignature: 74JGYRhmmNYgDEHLsZgwy4xjiLuRksJ9s9hunH76T9IJlSaFsYX8r16i8CyXbSZSBG4M9kTFQPxP9J0x/PFTDw==\n"
        + "length: 582\n"
        + "-->\n"

    /// The repository `appcast.xml` as it is now. Only checks that hold after every release use it.
    static func repositoryFeed() throws -> Data {
        try Data(contentsOf: ReleaseFixtures.repositoryRoot.appending(path: "appcast.xml"))
    }
}
