import Foundation
import Testing
@testable import JerdCore

struct AppUpdateConfigurationTests {
    private let key = Data(repeating: 42, count: 32).base64EncodedString()

    @Test func acceptsHTTPSFeedAndEd25519Key() throws {
        let config = try AppUpdateConfiguration(feedURL: "https://raw.githubusercontent.com/jewei/jerd/main/appcast.xml", publicKey: key)
        #expect(config.feedURL.host == "raw.githubusercontent.com")
        #expect(config.publicKey == key)
    }

    @Test(arguments: ["", "http://example.com/appcast.xml", "file:///tmp/appcast.xml", "https:///appcast.xml",
                      "https://user:secret@example.com/appcast.xml", "https://example.com/appcast.xml#fragment",
                      "https://example.com/app cast.xml", "$(JERD_UPDATE_FEED_URL)"])
    func rejectsInvalidFeed(feed: String) {
        #expect(throws: AppUpdateConfiguration.ConfigurationError.self) {
            try AppUpdateConfiguration(feedURL: feed, publicKey: key)
        }
    }

    @Test(arguments: ["", "not-base64", Data(repeating: 0, count: 31).base64EncodedString(),
                      Data(repeating: 0, count: 64).base64EncodedString(), "$(JERD_UPDATE_PUBLIC_KEY)"])
    func rejectsInvalidKey(publicKey: String) {
        #expect(throws: AppUpdateConfiguration.ConfigurationError.self) {
            try AppUpdateConfiguration(feedURL: "https://example.com/appcast.xml", publicKey: publicKey)
        }
    }

    @Test func rejectsMissingSettings() {
        #expect(throws: AppUpdateConfiguration.ConfigurationError.self) {
            try AppUpdateConfiguration(feedURL: nil, publicKey: key)
        }
        #expect(throws: AppUpdateConfiguration.ConfigurationError.self) {
            try AppUpdateConfiguration(feedURL: "https://example.com/appcast.xml", publicKey: nil)
        }
    }
}
