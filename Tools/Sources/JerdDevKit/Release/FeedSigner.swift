import Foundation

/// Makes and signs the candidate feed. Both signatures come from Sparkle's `sign_update`, which reads
/// the private key from the Keychain; the key never leaves it.
struct FeedSigner: Sendable {
    let shell: ReleaseShell
    let layout: CandidateLayout

    func run(item: AppcastWriter.Item, diskImage: URL, check: CandidateFeedCheck) async throws {
        let tool = try shell.sparkleTool("sign_update")
        let signature = try await shell.output(
            tool, ["--account", ReleaseNames.sparkleAccount, "-p", diskImage.path], limit: TimeLimit.codeSigning)
        var signed = item
        signed.archiveSignature = signature
        let source = try Data(contentsOf: layout.sourceFeed)
        try AppcastWriter.feed(from: source, adding: signed).write(to: layout.feed)
        try await shell.run(
            tool, ["--account", ReleaseNames.sparkleAccount, layout.feed.path], limit: TimeLimit.codeSigning)
        try check.verify(feed: Data(contentsOf: layout.feed), diskImage: diskImage)
    }
}
