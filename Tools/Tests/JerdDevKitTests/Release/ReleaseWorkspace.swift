import Darwin
import Foundation
import JerdManifest

@testable import JerdDevKit

/// A temporary repository with the files that a release reads, a fake runner, a fixed clock, a fake
/// feed URL, and a test feed key. The committed feed is a channel without items, signed with the key.
final class ReleaseWorkspace: Sendable {
    static let changelog = """
        # Changelog

        ## [Unreleased]

        - New thing.

        """

    static let emptyFeed = """
        <?xml version="1.0" encoding="utf-8" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <title>Jerd updates</title>
          </channel>
        </rss>
        """

    let root: URL
    let runner = FakeReleaseRunner()
    let output = RecordingTextOutput()
    let clock = FixedReleaseClock()
    let key = TestFeedKey()

    init(version: String = "0.1.0", build: String = "2") throws {
        root = try TestFixtures.temporaryFolder()
        try write(
            "// The app version.\nMARKETING_VERSION = \(version)\nCURRENT_PROJECT_VERSION = \(build)\n",
            to: "Configuration/Version.xcconfig")
        try write("MACOSX_DEPLOYMENT_TARGET = 14.0\n", to: "Configuration/Base.xcconfig")
        try write(Self.changelog, to: "CHANGELOG.md")
        try key.signedFeed(Data(Self.emptyFeed.utf8)).write(to: path("appcast.xml"))
        try write(String(decoding: PayloadFixture.catalogData(), as: UTF8.self), to: "Runtimes/runtimes.json")
        for tool in ["sign_update", "generate_keys"] {
            try write("#!/bin/sh\n", to: ".build/SourcePackages/artifacts/sparkle/Sparkle/bin/\(tool)")
            chmod(path(".build/SourcePackages/artifacts/sparkle/Sparkle/bin/\(tool)").path, 0o755)
        }
    }

    deinit { remove() }

    /// Removes the temporary repository. Each test calls it, so that a fake runner closure that keeps
    /// the workspace alive cannot leave the folder in `$TMPDIR`.
    func remove() { try? FileManager.default.removeItem(at: root) }

    var repository: Repository { Repository(root: root) }

    func path(_ relative: String) -> URL { root.appending(path: relative) }

    func write(_ text: String, to relative: String) throws {
        let url = path(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func environment(feed: [Data?] = [nil]) throws -> ReleaseEnvironment {
        var toolchain = TestFixtures.toolchain
        toolchain.gh = URL(filePath: "/opt/tools/gh")
        let context = DevContext(
            repository: repository, toolchain: toolchain, runner: runner,
            console: Console(output: output, verbose: false), environment: ["PATH": "/usr/bin", "JERD_PHP_CLI": "/x"])
        return ReleaseEnvironment(
            context: context, clock: clock, feedFetcher: FakeFeedFetcher(feed), verifier: try key.verifier)
    }

    func shell() throws -> ReleaseShell { try environment().shell }
}
