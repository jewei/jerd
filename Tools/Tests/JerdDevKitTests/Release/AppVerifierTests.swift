import Foundation
import JerdFoundation
import JerdManifest
import Testing

@testable import JerdDevKit

@Suite("Release app verification")
struct AppVerifierTests {
    static let sparkle = "export/Jerd.app/Contents/Frameworks/Sparkle.framework/Versions/B"

    /// An exported app with Sparkle's bundles, one extra framework binary, and signed payloads.
    static func app(_ workspace: ReleaseWorkspace) throws -> URL {
        func plist(_ identifier: String) -> String {
            "<plist><dict><key>CFBundleIdentifier</key><string>\(identifier)</string></dict></plist>"
        }
        try workspace.write(
            plist("org.sparkle-project.InstallerLauncher"),
            to: "\(sparkle)/XPCServices/Installer.xpc/Contents/Info.plist")
        try workspace.write(
            plist("org.sparkle-project.DownloaderService"),
            to: "\(sparkle)/XPCServices/Downloader.xpc/Contents/Info.plist")
        try workspace.write(
            plist("org.sparkle-project.Sparkle.Updater"), to: "\(sparkle)/Updater.app/Contents/Info.plist")
        try workspace.write(plist("org.sparkle-project.Sparkle"), to: "\(sparkle)/Resources/Info.plist")
        try Data(PayloadFixture.machO).write(to: workspace.path("\(sparkle)/Sparkle"))
        try workspace.write("text", to: "\(sparkle)/Resources/notes.txt")
        let app = workspace.path("export/Jerd.app")
        let payloads = app.appending(path: "Contents/Resources/RuntimePayloads")
        try PayloadFixture.write(to: payloads)
        for payload in try PayloadSigner.verifiedPayloads(in: payloads) {
            let signed = payload.receipt.replacingFiles(
                payload.receipt.fileRecords,
                signing: PayloadSigning(
                    teamID: ReleaseFixtures.team, sourceReceiptSHA256: String(repeating: "a", count: 64)))
            try signed.encoded().write(to: payload.origin.appending(path: PayloadReceipt.fileName))
        }
        return app
    }

    @Test("Every nested code has its identifier rule: own IDs, Sparkle bundle IDs, and Autoupdate's prefix")
    func codeList() throws {
        let workspace = try ReleaseWorkspace()
        defer { workspace.remove() }
        let code = try AppVerifier.bundleCode(Self.app(workspace))
        let rules = Dictionary(
            code.map { ($0.file.lastPathComponent, $0.identifier) }, uniquingKeysWith: { first, _ in first })
        #expect(rules["Jerd.app"] == .exact("dev.jerd.app"))
        #expect(rules["JerdCLI"] == .exact("dev.jerd.cli"))
        #expect(rules["JerdHelper"] == .exact("dev.jerd.helper"))
        #expect(rules["Installer.xpc"] == .exact("org.sparkle-project.InstallerLauncher"))
        #expect(rules["Sparkle.framework"] == .exact("org.sparkle-project.Sparkle"))
        #expect(rules["Autoupdate"] == .prefix("org.sparkle-project."))
        #expect(rules["Sparkle"] == .any)
        #expect(rules["notes.txt"] == nil)
    }

    @Test("Payload binaries must run on the minimum macOS and need only bundled libraries")
    func payloadChecks() async throws {
        let workspace = try ReleaseWorkspace()
        defer { workspace.remove() }
        let app = try Self.app(workspace)
        let check = AppPayloadCheck(
            shell: try workspace.shell(), team: ReleaseFixtures.team, minimumMacOS: ReleaseVersion("14.0")!)
        let root = app.appending(path: "Contents/Resources/RuntimePayloads")
        workspace.runner.on(
            "otool",
            output: "cmd LC_BUILD_VERSION\nminos 14.0\ncmd LC_LOAD_DYLIB\nname /usr/lib/libSystem.B.dylib (offset 24)\n"
        )
        let code = try await check.verify(root)
        // The eight embedded payloads; the app has no MySQL and PostgreSQL payloads.
        #expect(code.count == 8)
        #expect(code.allSatisfy { $0.identifier == .exact($0.file.lastPathComponent) })
        workspace.runner.on("otool", output: "cmd LC_BUILD_VERSION\nminos 15.0\n")
        await #expect(throws: DevFailure.self) { _ = try await check.verify(root) }
        workspace.runner.on(
            "otool", output: "cmd LC_LOAD_DYLIB\nname /opt/homebrew/opt/xz/lib/liblzma.5.dylib (offset 24)\n")
        await #expect(throws: DevFailure.self) { _ = try await check.verify(root) }
        let otherTeam = AppPayloadCheck(
            shell: try workspace.shell(), team: "ZZZZZ99999", minimumMacOS: ReleaseVersion("14.0")!)
        await #expect(throws: DevFailure.self) { _ = try await otherTeam.verify(root) }
    }
}
