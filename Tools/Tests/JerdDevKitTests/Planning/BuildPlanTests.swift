import Testing

@testable import JerdDevKit

@Suite("Build plan")
struct BuildPlanTests {
    @Test("plans one quiet, unsigned Debug build with fixed package and product folders")
    func plansDefaultBuild() {
        let invocation = BuildPlan.invocation(
            repository: TestFixtures.repository, toolchain: TestFixtures.toolchain, options: BuildOptions())
        #expect(invocation.executable.path == "/usr/bin/xcodebuild")
        #expect(
            invocation.arguments == [
                "-project", "/work/jerd/Jerd.xcodeproj", "-scheme", "Jerd", "-configuration", "Debug",
                "-destination", "platform=macOS",
                "-derivedDataPath", "/work/jerd/.build/xcode",
                "-clonedSourcePackagesDirPath", "/work/jerd/.build/SourcePackages",
                "-onlyUsePackageVersionsFromResolvedFile", "-quiet", "CODE_SIGNING_ALLOWED=NO", "build",
            ])
    }

    @Test("verbose builds show the full log")
    func verboseBuildIsNotQuiet() {
        let options = BuildOptions(verbose: true)
        let invocation = BuildPlan.invocation(
            repository: TestFixtures.repository, toolchain: TestFixtures.toolchain, options: options)
        #expect(!invocation.arguments.contains("-quiet"))
    }

    @Test("signed Release builds use manual signing with the identity and team")
    func plansSignedRelease() {
        let options = BuildOptions(
            configuration: .release, signing: .init(identity: "Developer ID Application", team: "TEAM123"))
        let invocation = BuildPlan.invocation(
            repository: TestFixtures.repository, toolchain: TestFixtures.toolchain, options: options)
        #expect(invocation.arguments.contains("Release"))
        #expect(!invocation.arguments.contains("CODE_SIGNING_ALLOWED=NO"))
        #expect(
            BuildPlan.signingSettings(options.signing) == [
                "CODE_SIGN_STYLE=Manual", "CODE_SIGN_IDENTITY=Developer ID Application", "DEVELOPMENT_TEAM=TEAM123",
            ])
    }

    @Test("accepts --sign and --team only together")
    func requiresSigningPair() throws {
        #expect(try BuildOptions.signing(identity: nil, team: nil) == nil)
        #expect(try BuildOptions.signing(identity: "A", team: "T") == .init(identity: "A", team: "T"))
        #expect(throws: DevFailure.usage("Use --sign IDENTITY and --team TEAM together.")) {
            try BuildOptions.signing(identity: "A", team: nil)
        }
        #expect(throws: DevFailure.self) { try BuildOptions.signing(identity: nil, team: "T") }
        #expect(throws: DevFailure.self) { try BuildOptions.signing(identity: "", team: "T") }
    }

    @Test("names the app in the products folder of the configuration")
    func namesAppPath() {
        let app = BuildPlan.appURL(repository: TestFixtures.repository, configuration: .release)
        #expect(app.path == "/work/jerd/.build/xcode/Build/Products/Release/Jerd.app")
    }

    @Test(
        "a quiet build shows only diagnostics",
        arguments: [
            ("/a/B.swift:3:1: error: no such module", true),
            ("/a/B.swift:3:1: warning: unused value", true),
            ("warning: Runtime payloads are missing.", true),
            ("** BUILD FAILED **", true),
            ("CompileSwift normal arm64 /a/B.swift", false),
            ("", false),
        ])
    func filtersDiagnostics(line: String, shown: Bool) {
        #expect(BuildPlan.isDiagnostic(line) == shown)
    }
}
