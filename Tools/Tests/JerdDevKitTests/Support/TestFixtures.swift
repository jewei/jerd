import Foundation

@testable import JerdDevKit

/// Fixed values for plans and steps. Paths are fixed, so plans are compared as plain values.
enum TestFixtures {
    static let repository = Repository(root: URL(filePath: "/work/jerd"))

    static let toolchain = Toolchain(
        xcrun: URL(filePath: "/usr/bin/xcrun"),
        xcodebuild: URL(filePath: "/usr/bin/xcodebuild"),
        git: URL(filePath: "/usr/bin/git"),
        xcodegen: URL(filePath: "/opt/tools/xcodegen"),
        gh: nil)

    static func context(
        repository: Repository = repository,
        toolchain: Toolchain = toolchain,
        runner: any ProcessRunning = RecordingProcessRunner(),
        output: RecordingTextOutput = RecordingTextOutput(),
        verbose: Bool = false,
        environment: [String: String] = [:]
    ) -> DevContext {
        DevContext(
            repository: repository, toolchain: toolchain, runner: runner,
            console: Console(output: output, verbose: verbose), environment: environment)
    }

    /// A new temporary folder that the test removes at the end.
    static func temporaryFolder() throws -> URL {
        try FileTree.makeTemporaryFolder(prefix: "jerd-dev-tests")
    }

    static func write(_ text: String, to relativePath: String, in root: URL) throws {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
}
