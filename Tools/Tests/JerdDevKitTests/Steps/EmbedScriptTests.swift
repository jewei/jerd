import Foundation
import Testing

@testable import JerdDevKit

/// Runs the Xcode embed phase script in a temporary source root with fake build products. The script
/// is a shell script by nature, so the test starts `/bin/sh` with it.
@Suite("Embed phase script")
struct EmbedScriptTests {
    static let script = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Scripts/embed-app-contents.sh")

    static let groups = ["Database", "Development", "Mail", "Storage"]

    /// A source root with the four pinned runtime groups and the helper plist, and fake products.
    private func makeRoot() throws -> URL {
        let root = try TestFixtures.temporaryFolder()
        for group in Self.groups {
            let pin = group == "Mail" || group == "Storage" ? "pin.json" : "pins.json"
            try TestFixtures.write("{}", to: "Runtimes/\(group)/\(pin)", in: root)
        }
        try TestFixtures.write("{}", to: "Runtimes/Support/xz.json", in: root)
        try TestFixtures.write("<plist/>", to: "Apps/JerdHelper/dev.jerd.helper.plist", in: root)
        try TestFixtures.write("helper", to: "products/JerdHelper", in: root)
        try TestFixtures.write("cli", to: "products/JerdCLI", in: root)
        return root
    }

    private func addPayloads(_ groups: [String], in root: URL) throws {
        for group in groups {
            try TestFixtures.write("binary", to: ".build/runtimes/payloads/\(group)/runtime-1/bin/tool", in: root)
        }
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
        ]
        let invocation = Invocation(
            executable: URL(filePath: "/bin/sh"), arguments: [Self.script.path], environment: environment,
            timeout: .seconds(60))
        return try await ProcessRunner(output: RecordingTextOutput(), groups: ChildProcessGroups())
            .run(invocation, output: .capture)
    }

    private func embeddedPayloads(in root: URL) -> URL {
        root.appending(path: "products/Jerd.app/Contents/Resources/RuntimePayloads")
    }

    @Test("Release refuses a missing or an empty payload folder")
    func releaseRefusesMissingPayloads() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = try await run(root: root, requireRuntimes: true)
        #expect(missing.status == 1)
        #expect(missing.standardError.contains("missing: Database Development Mail Storage"))
        try FileManager.default.createDirectory(
            at: root.appending(path: ".build/runtimes/payloads"), withIntermediateDirectories: true)
        #expect(try await run(root: root, requireRuntimes: true).status == 1)
    }

    @Test("Release refuses a payload folder without every pinned group")
    func releaseRefusesIncompletePayloads() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try addPayloads(["Database", "Development", "Mail"], in: root)
        try FileManager.default.createDirectory(
            at: root.appending(path: ".build/runtimes/payloads/Storage/empty"), withIntermediateDirectories: true)
        let result = try await run(root: root, requireRuntimes: true)
        #expect(result.status == 1)
        #expect(result.standardError.contains("(missing: Storage)"))
    }

    @Test("Release embeds the payloads when every pinned group has files")
    func releaseEmbedsCompletePayloads() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try addPayloads(Self.groups, in: root)
        let result = try await run(root: root, requireRuntimes: true)
        #expect(result.status == 0)
        let embedded = embeddedPayloads(in: root).appending(path: "Mail/runtime-1/bin/tool")
        #expect(FileManager.default.fileExists(atPath: embedded.path))
        let helper = root.appending(path: "products/Jerd.app/Contents/Library/LaunchServices/JerdHelper")
        #expect(FileManager.default.fileExists(atPath: helper.path))
    }

    @Test("Debug and the check build warn and build without payloads")
    func debugWarnsWithoutPayloads() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await run(root: root, requireRuntimes: false)
        #expect(result.status == 0)
        #expect(result.standardError.contains("warning: Runtime payloads are missing."))
        #expect(!FileManager.default.fileExists(atPath: embeddedPayloads(in: root).path))
    }
}
