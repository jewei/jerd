import Foundation
import JerdFoundation
import Testing

@testable import JerdCLICore

@Suite struct CodeSignatureCheckTests {
    @Test func signedSystemToolPasses() throws {
        try CodeSignatureCheck().checkSignature(of: URL(fileURLWithPath: "/usr/bin/true"))
    }

    @Test func unsignedFileIsRefused() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let file = try directory.file("JerdCLI", "test launcher", mode: 0o700)
        #expect { try CodeSignatureCheck().checkSignature(of: file) } throws: { error in
            (error as? JerdError)?.kind == .invalid
        }
    }

    @Test func changedCopyOfASignedToolIsRefused() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        var bytes = try Data(contentsOf: URL(fileURLWithPath: "/usr/bin/true"))
        bytes.append(contentsOf: [0, 1, 2, 3])
        let index = bytes.count / 2
        bytes[index] ^= 0xFF
        let file = try directory.file("JerdCLI", bytes, mode: 0o700)
        #expect(throws: JerdError.self) { try CodeSignatureCheck().checkSignature(of: file) }
    }
}
