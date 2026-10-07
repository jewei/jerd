/// One case of `./dev check updates`. Each case installs version 1 of a temporary test app and
/// offers version 2 (or nothing) through a signed loopback feed.
enum UpdateCase: String, CaseIterable, Sendable {
    /// The feed has no item. Sparkle must report that no update exists.
    case noUpdate = "no-update"
    /// The feed text changes after signing. Sparkle must refuse the feed.
    case alteredFeed = "altered-feed"
    /// One bit of the archive changes after signing. Sparkle must refuse the archive.
    case alteredArchive = "altered-archive"
    /// Sparkle installs version 2 after the app approves its deferred quit.
    case success
    /// The app refuses the first quit; Sparkle keeps version 1 and installs after the retry.
    case refusedQuit = "refused-quit"

    /// True when the feed offers version 2.
    var offersUpdate: Bool { self != .noUpdate }

    /// True when version 1 refuses its first quit (`TestRefuseFirstQuit`).
    var refusesFirstQuit: Bool { self == .refusedQuit }

    /// True when the events show that the case reached its end.
    static func isComplete(_ events: String) -> Bool {
        events.contains("quit-approved:2") || events.contains("failed") || events.contains("no-update")
    }

    /// Every broken expectation of the case. Empty means that the case passed.
    /// - Parameters:
    ///   - events: the lines that the test app wrote.
    ///   - installedVersion: `CFBundleVersion` of the installed app after the case.
    func failures(events: String, installedVersion: String?) -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        switch self {
        case .success, .refusedQuit:
            expect(installedVersion == "2", "The installed app is not version 2.")
            expect(events.contains("updated"), "Version 2 did not start.")
            expect(
                Self.order(events, "quit-approved:1", before: "launched:2"), "Version 2 started before version 1 quit.")
            if self == .refusedQuit {
                expect(events.contains("quit-refused"), "Version 1 did not refuse its first quit.")
                expect(events.contains("version-after-refusal:1"), "Sparkle replaced the app after a refused quit.")
            }
        case .noUpdate:
            expect(events.contains("no-update"), "Sparkle did not report that no update exists.")
            expect(installedVersion == "1", "The installed app changed.")
        case .alteredFeed, .alteredArchive:
            expect(events.contains("failed"), "Sparkle did not fail.")
            expect(installedVersion == "1", "The installed app changed.")
            expect(!events.contains("ready"), "Sparkle prepared an installation.")
            expect(
                events.contains("error:SUSparkleErrorDomain:3002:")
                    && events.contains("EdDSA signature does not match"),
                "Sparkle did not report an EdDSA signature mismatch.")
            if self == .alteredFeed {
                expect(events.contains("error:SUSparkleErrorDomain:1000:"), "Sparkle did not refuse the feed.")
                expect(!events.contains("found:"), "Sparkle accepted an item of the altered feed.")
            }
        }
        return failures
    }

    private static func order(_ events: String, _ first: String, before second: String) -> Bool {
        guard let one = events.range(of: first), let two = events.range(of: second) else { return false }
        return one.lowerBound < two.lowerBound
    }
}
