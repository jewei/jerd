import JerdManifest

/// Everything that the release commands use: the `./dev` context, the clock, the feed fetcher, and
/// the feed verifier. Tests give a recording runner, a fixed clock, a fake feed, and a test key.
struct ReleaseEnvironment: Sendable {
    let context: DevContext
    let clock: any ReleaseClock
    let feedFetcher: any FeedFetching
    /// Verifies feeds and disk images with the public key: the official key in every live command.
    let verifier: AppcastVerifier

    var shell: ReleaseShell { ReleaseShell(context: context) }
    var repository: Repository { context.repository }
    var console: Console { context.console }

    static func live(_ context: DevContext) throws -> ReleaseEnvironment {
        ReleaseEnvironment(
            context: context, clock: SystemReleaseClock(), feedFetcher: URLSessionFeedFetcher(),
            verifier: try AppcastVerifier.official())
    }
}
