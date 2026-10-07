import Foundation
import Testing

@testable import JerdDevKit

@Suite("Smoke test of the signed runtimes")
struct RuntimeSmokeTestTests {
    static func candidate() throws -> (ReleaseWorkspace, CandidateLayout) {
        let workspace = try ReleaseWorkspace()
        let layout = CandidateLayout(root: workspace.path("candidate"))
        try PayloadFixture.write(to: layout.appPayloads, embeddedOnly: true)
        return (workspace, layout)
    }

    @Test("Each embedded executable runs once, PHP also lists its modules, and PHP programs run with the embedded PHP")
    func commands() throws {
        let (workspace, layout) = try Self.candidate()
        defer { workspace.remove() }
        let payloads = try PayloadSigner.verifiedPayloads(in: layout.appPayloads)
        let commands = try RuntimeSmokeTest.commands(payloads)
        let php = layout.appPayloads.appending(path: "development/php-8.5.11-arm64/bin/tool").path
        #expect(commands.filter { $0.executable.path == php }.map(\.arguments).prefix(2) == [["-v"], ["-m"]])
        #expect(commands.contains { $0.executable.path.hasSuffix("/bin/php-fpm") && $0.arguments == ["-v"] })
        let composer = try #require(commands.first { $0.arguments.first?.contains("/composer-") == true })
        #expect(composer.executable.path == php && composer.arguments.suffix(2) == ["--version", "--no-interaction"])
        #expect(commands.contains { $0.executable.path.contains("/caddy-") && $0.arguments == ["version"] })
        #expect(commands.contains { $0.executable.path.contains("/rustfs-") && $0.arguments == ["--version"] })
        // Every payload gets at least one command; PHP gets three.
        #expect(commands.count >= payloads.count + 2)
    }

    @Test("PHP programs without an embedded PHP are refused")
    func needsPHP() throws {
        let (workspace, layout) = try Self.candidate()
        defer { workspace.remove() }
        let payloads = try PayloadSigner.verifiedPayloads(in: layout.appPayloads).filter { $0.receipt.kind != .php }
        #expect(throws: DevFailure.self) { try RuntimeSmokeTest.commands(payloads) }
    }

    @Test(
        "The commands run with a private temporary home, a minimal PATH, and a time limit; a failure stops the release")
    func runs() async throws {
        let (workspace, layout) = try Self.candidate()
        defer { workspace.remove() }
        try await RuntimeSmokeTest(shell: workspace.shell(), layout: layout).run()
        let runs = workspace.runner.recorded
        #expect(!runs.isEmpty)
        let home = try #require(runs.first?.environment?["HOME"])
        #expect(home.contains("jerd-release-smoke") && !FileManager.default.fileExists(atPath: home))
        #expect(
            runs.allSatisfy { $0.environment?["PATH"] == "/usr/bin:/bin" && $0.environment?["JERD_PHP_CLI"] == nil })
        #expect(runs.allSatisfy { $0.timeout == TimeLimit.probe && $0.workingDirectory?.path == home })
        workspace.runner.on("tool", ["-m"], status: 1, error: "dyld: Library not loaded")
        await #expect(throws: DevFailure.self) {
            try await RuntimeSmokeTest(shell: workspace.shell(), layout: layout).run()
        }
    }
}
