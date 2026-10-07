import Foundation
import JerdFoundation
import JerdManifest

@testable import JerdDevKit

/// A workspace whose tools answer like a release Mac that is ready: `main` equals `origin/main`, CI
/// passed, no tag or release of 0.2.0 exists, the keys and the identity are in the Keychain, and every
/// payload is prepared. A test changes one answer to prove one refusal.
enum ReadyReleaseMac {
    static let checkRuns = "repos/jewei/jerd/commits/\(ReleaseFixtures.commit)/check-runs?per_page=100"
    static let success = #"{"name":"./dev check","status":"completed","conclusion":"success"}"#

    static let diskImage = Data("disk image".utf8)
    static let symbols = Data("symbols".utf8)

    /// The asset answer of GitHub for the files that the fake local step writes.
    static var assets: String {
        [("Jerd-0.2.0.dmg", diskImage), ("Jerd-0.2.0-3.dSYMs.zip", symbols)].map { name, data in
            #"{"name":"\#(name)","size":\#(data.count),"digest":"sha256:\#(FileDigest.hexSHA256(of: data))"}"#
        }.joined(separator: "\n")
    }

    static func workspace() throws -> ReleaseWorkspace {
        let workspace = try ReleaseWorkspace()
        try PayloadFixture.write(to: workspace.path(".build/runtimes/payloads"))
        let runner = workspace.runner
        runner.on("git", ["status"], output: "")
        runner.on("git", ["rev-parse", "HEAD"], output: ReleaseFixtures.commit + "\n")
        runner.on("git", ["branch", "--show-current"], output: "main\n")
        runner.on("git", ["remote", "get-url", "origin"], output: "git@github.com:jewei/jerd.git\n")
        runner.on("git", ["rev-parse", "refs/remotes/origin/main"], output: ReleaseFixtures.commit + "\n")
        runner.on("git", ["tag", "--list"], output: "")
        runner.on("git", ["ls-remote"], status: 2)
        runner.on("gh", ["api", "repos/jewei/jerd/releases"], output: "")
        runner.on("gh", ["api", checkRuns], output: success + "\n")
        runner.on("generate_keys", output: AppUpdateSettings.officialPublicKey + "\n")
        runner.on("security", ["find-identity"], output: ReleaseFixtures.identities)
        runner.on("gh", ["api", "repos/jewei/jerd/releases/tags/v0.2.0"], output: assets)
        return workspace
    }

    static func preconditions(_ workspace: ReleaseWorkspace, prepareOnly: Bool = false) throws -> ReleasePreconditions {
        ReleasePreconditions(
            environment: try workspace.environment(), inputs: try ReleaseFixtures.inputs(prepareOnly: prepareOnly))
    }

    /// A releaser whose local steps only write the candidate files, so nothing is built or notarized.
    static func releaser(
        _ workspace: ReleaseWorkspace, prepareOnly: Bool = false, failLocal: Bool = false
    ) throws
        -> Releaser
    {
        var releaser = Releaser(
            environment: try workspace.environment(),
            request: ReleaseFixtures.request(prepareOnly: prepareOnly))
        releaser.localSteps = { builder in
            [
                ReleaseStep("Build the candidate") {
                    try builder.makeFolder()
                    let layout = builder.layout
                    try diskImage.write(to: layout.file(builder.inputs.diskImageName))
                    try symbols.write(to: layout.file(builder.inputs.symbolsName))
                    try Data(builder.source.notes.utf8).write(to: layout.notes)
                    try Data("signed candidate feed\n".utf8).write(to: layout.feed)
                    if failLocal { throw DevFailure.checkFailed("Apple did not accept app (Invalid).") }
                }
            ]
        }
        releaser.setInterruptNote = { _ in }
        return releaser
    }

    /// The text of the tracked files that the release commit may change.
    static func trackedFiles(_ workspace: ReleaseWorkspace) throws -> [Data] {
        try ReleaseCommitFiles.paths.map { try Data(contentsOf: workspace.path($0)) }
    }
}
