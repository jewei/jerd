import Foundation
import Testing

@testable import JerdDevKit

@Suite("App signing and signature checks")
struct AppSigningTests {
    static let signing = try! SigningIdentity(identity: ReleaseFixtures.identity, team: ReleaseFixtures.team)

    static let goodDisplay = """
        Identifier=dev.jerd.cli
        CodeDirectory v=20500 size=1 flags=0x10000(runtime) hashes=1+7 location=embedded
        Timestamp=Oct 6, 2026 at 12:00:00
        TeamIdentifier=ABCDE12345
        """

    @Test("Signs Sparkle innermost first with its own identifiers, then the launcher, helper, and app")
    func signingOrder() async throws {
        let workspace = try ReleaseWorkspace()
        defer { workspace.remove() }
        workspace.runner.on("codesign", ["-d", "--verbose=2"]) { invocation in
            let name = URL(filePath: invocation.arguments.last!).lastPathComponent
            return .init(standardError: "Identifier=org.sparkle-project.\(name)\n")
        }
        try await AppSigner(shell: workspace.shell(), signing: Self.signing).run(app: URL(filePath: "/c/Jerd.app"))
        let signed = workspace.runner.calls("codesign", ["--force"])
        let names = signed.map { URL(filePath: $0.last!).lastPathComponent }
        #expect(
            names == [
                "Installer.xpc", "Downloader.xpc", "Autoupdate", "Updater.app", "Sparkle.framework", "JerdCLI",
                "JerdHelper", "Jerd.app",
            ])
        let identifiers = signed.map { $0[$0.firstIndex(of: "--identifier")! + 1] }
        #expect(identifiers.suffix(3) == ["dev.jerd.cli", "dev.jerd.helper", "dev.jerd.app"])
        #expect(identifiers[0] == "org.sparkle-project.Installer.xpc")
        #expect(signed[1].contains("--preserve-metadata=entitlements"))
        #expect(signed.filter { $0.contains("--preserve-metadata=entitlements") }.count == 1)
    }

    @Test("A signature passes with the team, hardened runtime, timestamp, and identifier")
    func verifies() async throws {
        let workspace = try ReleaseWorkspace()
        defer { workspace.remove() }
        workspace.runner.on("codesign", ["-d", "--verbose=4"], error: Self.goodDisplay)
        let verifier = SignatureVerifier(shell: try workspace.shell(), team: ReleaseFixtures.team)
        try await verifier.verify(URL(filePath: "/c/JerdCLI"), identifier: .exact("dev.jerd.cli"))
        let requirement = try #require(workspace.runner.calls("codesign", ["--verify"]).first)
        #expect(requirement.contains(SigningIdentity.requirement(team: ReleaseFixtures.team)))
    }

    @Test("Refuses a wrong identifier, an ad hoc signature, another team, and a debug entitlement")
    func refuses() async throws {
        let cases: [(display: String, entitlements: String, rule: SignatureVerifier.IdentifierRule)] = [
            (Self.goodDisplay, "", .exact("JerdCLI")),
            (Self.goodDisplay.replacingOccurrences(of: "flags=0x10000(runtime)", with: "flags=0x2(adhoc)"), "", .any),
            (Self.goodDisplay.replacingOccurrences(of: "Timestamp=", with: "Signed Time="), "", .any),
            (Self.goodDisplay.replacingOccurrences(of: "ABCDE12345", with: "ZZZZZ99999"), "", .any),
            (
                Self.goodDisplay,
                String(decoding: try EntitlementPolicy.plist([EntitlementPolicy.getTaskAllow: true]), as: UTF8.self),
                .any
            ),
        ]
        for item in cases {
            let workspace = try ReleaseWorkspace()
            defer { workspace.remove() }
            workspace.runner.on("codesign", ["-d", "--verbose=4"], error: item.display)
            workspace.runner.on("codesign", ["-d", "--entitlements"], output: item.entitlements)
            let verifier = SignatureVerifier(shell: try workspace.shell(), team: ReleaseFixtures.team)
            await #expect(throws: DevFailure.self) {
                try await verifier.verify(URL(filePath: "/c/JerdCLI"), identifier: item.rule)
            }
        }
    }

    @Test("Identifier rules")
    func identifierRules() {
        #expect(
            SignatureVerifier.IdentifierRule.prefix("org.sparkle-project.").accepts(
                "org.sparkle-project.Sparkle.Autoupdate"))
        #expect(!SignatureVerifier.IdentifierRule.prefix("org.sparkle-project.").accepts("Autoupdate"))
        #expect(!SignatureVerifier.IdentifierRule.any.accepts(nil))
    }

    @Test("The archive uses the pinned packages, manual signing, and no version overrides")
    func archiveArguments() throws {
        let workspace = try ReleaseWorkspace()
        defer { workspace.remove() }
        let inputs = try ReleaseInputs.parse(
            version: "0.2.0", build: "3", minimumMacOS: "14.0", identity: ReleaseFixtures.identity,
            team: ReleaseFixtures.team, notaryProfile: "p", keychain: nil)
        let arguments = AppArchiver(
            shell: try workspace.shell(), inputs: inputs, layout: CandidateLayout(root: workspace.path("c"))
        )
        .arguments()
        #expect(arguments.contains("-onlyUsePackageVersionsFromResolvedFile"))
        #expect(arguments.contains("CODE_SIGN_STYLE=Manual") && arguments.contains("DEVELOPMENT_TEAM=ABCDE12345"))
        #expect(!arguments.contains { $0.hasPrefix("MARKETING_VERSION") || $0.hasPrefix("CURRENT_PROJECT_VERSION") })
    }

    @Test("The minimum macOS version is written into the exported Info.plist")
    func writesMinimumSystem() throws {
        let workspace = try ReleaseWorkspace()
        defer { workspace.remove() }
        let app = workspace.path("Jerd.app")
        try workspace.write(
            "<plist><dict><key>CFBundleIdentifier</key><string>dev.jerd.app</string></dict></plist>",
            to: "Jerd.app/Contents/Info.plist")
        try AppArchiver.setMinimumSystem(#require(ReleaseVersion("15.2")), in: app)
        let info = try AppInfoCheck.read(app)
        #expect(info["LSMinimumSystemVersion"] as? String == "15.2")
        #expect(info["CFBundleIdentifier"] as? String == "dev.jerd.app")
    }
}
