import Foundation
import JerdFoundation
import JerdProcess
import Testing

@Suite struct LogRedactorTests {
    private func string(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    @Test func aSecretSplitAtEveryByteBoundaryStaysPrivate() throws {
        let secret = "token-α-1234567890"
        let bytes = Data(secret.utf8)
        for split in 0...bytes.count {
            var redactor = try LogRedactor(values: [secret])
            var output = redactor.append(Data("before ".utf8))
            output += redactor.append(bytes.prefix(split))
            output += redactor.append(bytes.dropFirst(split))
            output += redactor.append(Data(" after".utf8), final: true)
            #expect(string(output) == "before [redacted] after")
        }
    }

    @Test func overlappingRepeatedDuplicateAndEmptyValuesAreHandled() throws {
        var redactor = try LogRedactor(values: ["abc", "abcdef", "secret", "", "secret"])
        let output = redactor.append(Data("abcdef abc secretsecret okay".utf8), final: true)
        #expect(string(output) == "[redacted] [redacted] [redacted][redacted] okay")
    }

    @Test func ordinaryTextIsReleasedAtOnceAndOnlyAPossibleSecretIsHeld() throws {
        var redactor = try LogRedactor(values: ["very-long-secret-value"])
        #expect(string(redactor.append(Data("Connected\n".utf8))) == "Connected\n")
        #expect(redactor.append(Data("very-long-".utf8)).isEmpty)
        #expect(string(redactor.append(Data("secret-value\n".utf8))) == "[redacted]\n")
    }

    @Test func aShortSecretThatPrefixesALongOneDoesNotReleaseIt() throws {
        var redactor = try LogRedactor(values: ["abc", "abcdef"])
        #expect(redactor.append(Data("abc".utf8)).isEmpty)
        #expect(string(redactor.append(Data("def!".utf8))) == "[redacted]!")
    }

    @Test func aFinalChunkReleasesAHeldPartialSecretAsText() throws {
        var redactor = try LogRedactor(values: ["secret"])
        #expect(redactor.append(Data("sec".utf8)).isEmpty)
        #expect(string(redactor.append(Data(), final: true)) == "sec")
    }

    @Test func streamedOutputStaysBoundedAndLosesNoOrdinaryByte() throws {
        var redactor = try LogRedactor(values: ["private-token"])
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

    @Test func theConfigurationLimitsAreInclusive() throws {
        let message = JerdError.invalid("The log redaction configuration is too large.")
        _ = try LogRedactor(values: (0..<32).map { "secret-\($0)" })
        #expect(throws: message) { try LogRedactor(values: (0..<33).map { "secret-\($0)" }) }
        _ = try LogRedactor(values: [String(repeating: "x", count: 65_536)])
        #expect(throws: message) { try LogRedactor(values: [String(repeating: "x", count: 65_537)]) }
    }

    @Test func completeTextUsesTheSameMarker() {
        #expect(
            LogRedactor.redact("password=abc123 and abc123", values: ["abc123", ""])
                == "password=[redacted] and [redacted]")
        #expect(LogRedactor.marker == "[redacted]")
    }
}
