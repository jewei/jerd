import Foundation
import JerdFoundation
import JerdManifest
import Testing

@Suite struct AppUpdateSettingsTests {
    private let feed = AppUpdateSettings.officialFeedURL
    private let key = AppUpdateSettings.officialPublicKey

    @Test func officialFeedAndKeyAreAccepted() throws {
        let settings = try AppUpdateSettings(feedURL: feed, publicKey: key)
        #expect(settings.feedURL.absoluteString == "https://raw.githubusercontent.com/jewei/jerd/main/appcast.xml")
        #expect(settings.publicKeyBytes.count == 32)
        #expect(try AppUpdateSettings.official() == settings)
    }

    @Test(arguments: [
        "http://example.com/appcast.xml", "file:///tmp/appcast.xml", "https:///appcast.xml",
        "https://user:secret@example.com/appcast.xml", "https://example.com/appcast.xml#fragment",
        "https://example.com/app cast.xml", "$(JERD_UPDATE_FEED_URL)",
    ])
    func malformedFeedsAreRefused(_ value: String) {
        #expect(throws: JerdError.invalid("This build has an invalid app update feed.")) {
            try AppUpdateSettings(feedURL: value, publicKey: key)
        }
    }

    @Test(arguments: [
        "https://example.com/appcast.xml", "https://raw.githubusercontent.com/jewei/jerd/main/appcast.xml?x=1",
        "https://raw.githubusercontent.com/other/jerd/main/appcast.xml",
    ])
    func anotherWellFormedFeedIsRefusedBecauseOnlyTheOfficialFeedIsAllowed(_ value: String) {
        #expect(throws: JerdError.invalid("This build has an unexpected app update feed. Use the official Jerd feed."))
        {
            try AppUpdateSettings(feedURL: value, publicKey: key)
        }
    }

    @Test(arguments: [
        "not-base64", Data(repeating: 0, count: 31).base64EncodedString(),
        Data(repeating: 0, count: 64).base64EncodedString(), "$(JERD_UPDATE_PUBLIC_KEY)",
    ])
    func malformedKeysAreRefused(_ value: String) {
        #expect(throws: JerdError.invalid("This build has an invalid app update verification key.")) {
            try AppUpdateSettings(feedURL: feed, publicKey: value)
        }
    }

    @Test func anotherValidKeyIsRefused() {
        let other = Data(repeating: 42, count: 32).base64EncodedString()
        #expect(throws: JerdError.invalid("This build has an unexpected app update verification key.")) {
            try AppUpdateSettings(feedURL: feed, publicKey: other)
        }
    }

    @Test func missingValuesAreReportedAsMissing() {
        #expect(throws: JerdError.unavailable("This build has no app update feed.")) {
            try AppUpdateSettings(feedURL: nil, publicKey: key)
        }
        #expect(throws: JerdError.unavailable("This build has no app update feed.")) {
            try AppUpdateSettings(feedURL: "", publicKey: key)
        }
        #expect(throws: JerdError.unavailable("This build has no app update verification key.")) {
            try AppUpdateSettings(feedURL: feed, publicKey: nil)
        }
    }
}
