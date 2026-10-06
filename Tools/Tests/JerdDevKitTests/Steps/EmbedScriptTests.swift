import Foundation
import Testing

@testable import JerdDevKit

/// Runs the Xcode embed phase script in a temporary source root with fake build products and a fake
/// `./dev` that records its arguments and environment. The script is a shell script by nature, so the
/// test starts `/bin/sh` with it. `RuntimesEmbedStepTests` test the verification itself.
@Suite("Embed phase script")
struct EmbedScriptTests {
    static let script = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Scripts/embed-app-contents.sh")

    /// A source root with the helper plist, fake products, and a fake tool that exits with `status`.
    private func makeRoot(toolStatus: Int = 0) throws -> URL {
        let root = try TestFixtures.temporaryFolder()
        try TestFixtures.write("<plist/>", to: "Apps/JerdHelper/dev.jerd.helper.plist", in: root)
        try TestFixtures.write("helper", to: "products/JerdHelper", in: root)
        try TestFixtures.write("cli", to: "products/JerdCLI", in: root)
        let tool = """
            #!/bin/sh
            printf '%s\\n' "$@" > "\(root.path)/tool-arguments"
            /usr/bin/env > "\(root.path)/tool-environment"
            exit \(toolStatus)
            """
        try TestFixtures.write(tool, to: "fake-dev", in: root)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path + "/fake-dev")
        return root
    }

    private func addReceipt(in root: URL) throws {
        try TestFixtures.write("{}", to: ".build/runtimes/payloads/mail/mailpit-1/payload-receipt.json", in: root)
    }

    private func run(root: URL, requireRuntimes: Bool) async throws -> InvocationResult {
        let environment = [
            "PATH": "/usr/bin:/bin",
            "SRCROOT": root.path,
            "TARGET_BUILD_DIR": root.appending(path: "products").path,
            "BUILT_PRODUCTS_DIR": root.appending(path: "products").path,
            "CONTENTS_FOLDER_PATH": "Jerd.app/Contents",
            "UNLOCALIZED_RESOURCES_FOLDER_PATH": "Jerd.app/Contents/Resources",
            "JERD_REQUIRE_RUNTIMES": requireRuntimes ? "YES" : "NO",
            "JERD_DEV_COMMAND": root.appending(path: "fake-dev").path,
            "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer",
            "SDKROOT": "macosx",
        ]
        let invocation = Invocation(
            executable: URL(filePath: "/bin/sh"), arguments: [Self.script.path], environment: environment,
            timeout: .seconds(60))
        return try await ProcessRunner(output: RecordingTextOutput(), groups: ChildProcessGroups())
            .run(invocation, output: .capture)
    }

    private func destination(in root: URL) -> String {
        root.appending(path: "products/Jerd.app/Contents/Resources/RuntimePayloads").path
    }

    private func recorded(_ name: String, in root: URL) throws -> [String] {
        try String(contentsOf: root.appending(path: name), encoding: .utf8)
            .split(separator: "\n").map(String.init)
    }

    @Test("Release always asks the verified embed for every payload")
    func releaseRequiresEveryPayload() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await run(root: root, requireRuntimes: true)
        #expect(result.status == 0)
        #expect(
            try recorded("tool-arguments", in: root) == ["runtimes", "embed", destination(in: root), "--require-all"])
        let helper = root.appending(path: "products/Jerd.app/Contents/Library/LaunchServices/JerdHelper")
        #expect(FileManager.default.fileExists(atPath: helper.path))
    }

    @Test("Debug with payloads runs the verified embed in a minimal environment")
    func debugEmbedsPreparedPayloads() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try addReceipt(in: root)
        #expect(try await run(root: root, requireRuntimes: false).status == 0)
        #expect(try recorded("tool-arguments", in: root) == ["runtimes", "embed", destination(in: root)])
        let environment = try recorded("tool-environment", in: root)
        #expect(environment.contains("DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer"))
        #expect(environment.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin"))
        #expect(!environment.contains { $0.hasPrefix("SDKROOT=") || $0.hasPrefix("SRCROOT=") })
    }

    @Test("A failed verification fails the build")
    func verificationFailureFailsTheBuild() async throws {
        let root = try makeRoot(toolStatus: 1)
        defer { try? FileManager.default.removeItem(at: root) }
        try addReceipt(in: root)
        #expect(try await run(root: root, requireRuntimes: false).status == 1)
    }

    @Test("Debug and the check build warn, remove old payloads, and build without payloads")
    func debugWarnsWithoutPayloads() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try TestFixtures.write("old", to: "products/Jerd.app/Contents/Resources/RuntimePayloads/x", in: root)
        let result = try await run(root: root, requireRuntimes: false)
        #expect(result.status == 0)
        #expect(result.standardError.contains("warning: Runtime payloads are missing."))
        #expect(!FileManager.default.fileExists(atPath: destination(in: root)))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "tool-arguments").path))
    }
}
