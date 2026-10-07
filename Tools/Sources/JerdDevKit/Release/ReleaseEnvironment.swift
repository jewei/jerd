import JerdManifest

/// Everything that the release command uses: the `./dev` context, the clock, and the feed verifier.
/// Tests give a recording runner, a fixed clock, and a test key.
struct ReleaseEnvironment: Sendable {
    let context: DevContext
    let clock: any ReleaseClock
    /// Verifies feeds and disk images with the public key: the official key in every live command.
    let verifier: AppcastVerifier

    var shell: ReleaseShell { ReleaseShell(context: context) }
    var repository: Repository { context.repository }
    var console: Console { context.console }

    static func live(_ context: DevContext) throws -> ReleaseEnvironment {
        ReleaseEnvironment(context: context, clock: SystemReleaseClock(), verifier: try AppcastVerifier.official())
    }
}
