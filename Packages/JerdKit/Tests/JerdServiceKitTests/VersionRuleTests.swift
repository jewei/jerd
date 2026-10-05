import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import Testing

@Suite struct VersionRuleTests {
    @Test(arguments: [
        ("/opt/mysql/bin/mysqld  Ver 8.4.11 for macos15 on arm64 (MySQL Community Server - GPL)", true),
        ("postgres (PostgreSQL) 18.6", false),
        ("Redis server v=8.4.11 sha=00000000", true),
        ("mysqld Ver 8.4.111", false),
        ("mysqld Ver 18.4.11", false),
        ("mysqld Ver 8.4.11.2", false),
        ("mysqld Ver 8x4y11", false),
    ])
    func aStandaloneVersionMatchesOnlyAWholeToken(output: String, matches: Bool) {
        #expect(VersionRule.standalone(version: "8.4.11").matches(output) == matches)
    }

    @Test func aVersionInsideTheExecutablePathDoesNotMatch() {
        let path = "/Users/me/mail-runtimes/mailpit-1.31.3/mailpit"
        let rule = VersionRule.labelledLine(label: path, version: "1.31.3")
        #expect(rule.matches("\(path) v1.31.3 darwin/arm64"))
        #expect(rule.matches("noise\n\(path) 1.31.3\n"))
        #expect(!rule.matches("\(path) v1.30.0 darwin/arm64"))
        #expect(!rule.matches("\(path) v1.31.30"))
        #expect(!rule.matches("other \(path) v1.31.3"))
    }

    @Test func aFirstLineRuleIgnoresLaterLines() {
        let rule = VersionRule.firstLine(label: "rustfs", version: "1.0.0")
        #expect(rule.matches("rustfs 1.0.0\nbuild abc"))
        #expect(rule.matches("rustfs v1.0.0"))
        #expect(!rule.matches("banner\nrustfs 1.0.0"))
        #expect(!rule.matches("rustfs 1.0.01"))
    }

    @Test func aProbeRequiresSuccessAndAMatchingOutput() async throws {
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/fake/bin/server"), arguments: ["--version"],
            workingDirectory: URL(fileURLWithPath: "/tmp"))
        let probe = VersionProbe(request: request, rule: .standalone(version: "1.2.3"), mismatchMessage: "Mismatch.")
        let good = ScriptedCommands { _ in CommandResult(status: 0, output: "server 1.2.3") }
        try await probe.verify(using: good)
        let failing = ScriptedCommands { _ in CommandResult(status: 1, output: "server 1.2.3") }
        await #expect(throws: JerdError.unavailable("Mismatch.")) { try await probe.verify(using: failing) }
        let other = ScriptedCommands { _ in CommandResult(status: 0, output: "server 1.2.4") }
        await #expect(throws: JerdError.unavailable("Mismatch.")) { try await probe.verify(using: other) }
        #expect(good.requests.first?.arguments == ["--version"])
    }
}
