/// Everything that the release commands use: the `./dev` context, the clock, and the feed fetcher.
/// Tests give a recording runner, a fixed clock, and a fake feed.
struct ReleaseEnvironment: Sendable {
    let context: DevContext
    let clock: any ReleaseClock
    let feedFetcher: any FeedFetching

    var shell: ReleaseShell { ReleaseShell(context: context) }
    var repository: Repository { context.repository }
    var console: Console { context.console }

    static func live(_ context: DevContext) -> ReleaseEnvironment {
        ReleaseEnvironment(context: context, clock: SystemReleaseClock(), feedFetcher: URLSessionFeedFetcher())
    }
}
