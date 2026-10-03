import Foundation
import Testing
@testable import JerdCore

struct RedactedProcessLogTests {
    @Test func credentialsSplitAtEveryBoundaryStayPrivate() {
        let secret = "token-α-1234567890"
        let bytes = Data(secret.utf8)
        for split in 0...bytes.count {
            var redactor = LogRedactor(values: [secret])
            var output = redactor.append(Data("before ".utf8))
            output += redactor.append(bytes.prefix(split))
            output += redactor.append(bytes.dropFirst(split))
            output += redactor.append(Data(" after".utf8), final: true)
            #expect(String(decoding: output, as: UTF8.self) == "before [REDACTED] after")
        }
    }

    @Test func overlappingAndRepeatedCredentialsAreRedacted() {
        var redactor = LogRedactor(values: ["abc", "abcdef", "secret", "", "secret"])
        let output = redactor.append(Data("abcdef abc secretsecret okay".utf8), final: true)
        #expect(String(decoding: output, as: UTF8.self) == "[REDACTED] [REDACTED] [REDACTED][REDACTED] okay")
    }

    @Test func ordinaryMessagesAreVisibleBeforeTheProcessExits() {
        var redactor = LogRedactor(values: ["very-long-secret-value"])
        #expect(String(decoding: redactor.append(Data("Connected\n".utf8)), as: UTF8.self) == "Connected\n")
        #expect(redactor.append(Data("very-long-".utf8)).isEmpty)
        #expect(String(decoding: redactor.append(Data("secret-value\n".utf8)), as: UTF8.self) == "[REDACTED]\n")
    }

    @Test func overlappingPrefixesAcrossWritesStayPrivate() {
        var redactor = LogRedactor(values: ["abc", "abcdef"])
        #expect(redactor.append(Data("abc".utf8)).isEmpty)
        #expect(String(decoding: redactor.append(Data("def!".utf8)), as: UTF8.self) == "[REDACTED]!")
    }

    @Test func streamedOutputDoesNotGrowWithoutBoundOrLoseOrdinaryBytes() {
        var redactor = LogRedactor(values: ["private-token"])
        let chunk = Data(repeating: 65, count: 16_384)
        var count = 0
        for _ in 0..<100 {
            let output = redactor.append(chunk)
            count += output.count
            #expect(output.count >= chunk.count - "private-token".utf8.count)
        }
        count += redactor.append(Data(), final: true).count
        #expect(count == chunk.count * 100)
    }

    @Test func processOutputIsRedactedBeforeItReachesDisk() async throws {
        let root = try temporaryDirectory(" redacted-process")
        defer { try? FileManager.default.removeItem(at: root) }
        let secret = "test-only-private-value-12345"
        let supervisor = ProcessSupervisor()
        let log = root.appendingPathComponent("process.log")
        let id = try await supervisor.start(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/printenv"),
            arguments: ["TEST_CREDENTIAL"], directory: root, environment: ["TEST_CREDENTIAL": secret],
            redactedValues: [secret]), log: log)
        let deadline = ContinuousClock.now + .seconds(5)
        while await supervisor.isRunning(id), ContinuousClock.now < deadline {
            if let bytes = try? Data(contentsOf: log) { #expect(!String(decoding: bytes, as: UTF8.self).contains(secret)) }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await supervisor.stopGracefully(id))
        let output = try String(contentsOf: log, encoding: .utf8)
        #expect(output == "[REDACTED]\n")
    }

    @Test func commandRunnerReturnsOnlyFilteredDiagnostics() async throws {
        let root = try temporaryDirectory(" redacted-command")
        defer { try? FileManager.default.removeItem(at: root) }
        let secret = "another-test-credential"
        let result = try await LocalCommandRunner().run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/printenv"),
            arguments: ["TEST_CREDENTIAL"], directory: root, environment: ["TEST_CREDENTIAL": secret],
            redactedValues: [secret]), timeout: .seconds(5))
        #expect(result.status == 0)
        #expect(result.output == "[REDACTED]\n")
        #expect(!result.diagnosticOutput.contains(secret))
    }
}
