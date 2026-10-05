import Foundation
import JerdFoundation
import JerdRuntimes
import Security
import Testing

@Suite struct PinnedRSAVerifierTests {
    private typealias Builder = SignaturePacketBuilder
    private let oracle = PinnedRSAVerifier(key: .mysqlRelease2025)

    private func oracleSignature() throws -> OpenPGPSignature {
        let key = PinnedRSAKey.mysqlRelease2025
        return try OpenPGPSignatureParser.parse(
            armored: OracleSignatureFixture.armored, expectedFingerprint: key.fingerprint, rejecting: key.failure)
    }

    @Test func realOracleSignatureMatchesThePinnedKeyForTheArchiveDigest() throws {
        let digest = Data(Builder.bytes(hex: OracleSignatureFixture.digestHex))
        try oracle.verify(digest: digest, signature: oracleSignature())
    }

    @Test func realOracleSignatureFailsForAChangedDigest() throws {
        var bytes = Builder.bytes(hex: OracleSignatureFixture.digestHex)
        bytes[31] ^= 0x01
        #expect(throws: PinnedRSAKey.mysqlRelease2025.failure) {
            try oracle.verify(digest: Data(bytes), signature: oracleSignature())
        }
    }

    @Test func failureUsesTheMySQLMessage() {
        #expect(
            PinnedRSAKey.mysqlRelease2025.failureMessage
                == "The MySQL publisher signature is invalid or uses an unsupported signing key.")
    }

    @Test func fileSignedByThePinnedKeyVerifiesAndATamperedFileFails() throws {
        let signer = try TestSigner()
        let file = try TestSigner.temporaryFile(Data("runtime archive".utf8))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let armored = try signer.sign(file)
        let verifier = PinnedRSAVerifier(key: signer.pinnedKey)
        try verifier.verify(file: file, armoredSignature: armored)
        try Data("runtime archivf".utf8).write(to: file)
        #expect(throws: signer.pinnedKey.failure) { try verifier.verify(file: file, armoredSignature: armored) }
    }

    @Test func wrongHashPrefixIsRejectedBeforeTheRSACheck() throws {
        let signer = try TestSigner()
        let file = try TestSigner.temporaryFile(Data("runtime archive".utf8))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let armored = try signer.sign(file) { $0.hashPrefix[0] ^= 0xFF }
        #expect(throws: signer.pinnedKey.failure) {
            try PinnedRSAVerifier(key: signer.pinnedKey).verify(file: file, armoredSignature: armored)
        }
    }

    @Test func signatureOfAnotherKeyWithTheSameFingerprintIsRejected() throws {
        let signer = try TestSigner()
        let impostor = try TestSigner()
        let file = try TestSigner.temporaryFile(Data("runtime archive".utf8))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(throws: signer.pinnedKey.failure) {
            try PinnedRSAVerifier(key: signer.pinnedKey).verify(file: file, armoredSignature: impostor.sign(file))
        }
    }

    @Test func unreadableFileKeepsItsReadError() throws {
        let missing = URL(fileURLWithPath: "/nonexistent/jerd-\(UUID().uuidString)")
        let error = #expect(throws: JerdError.self) {
            try oracle.verify(file: missing, armoredSignature: OracleSignatureFixture.armored)
        }
        #expect(error?.kind == .unavailable)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["JERD_MYSQL_ARCHIVE"] != nil))
    func realArchiveVerifiesAndATamperedCopyFails() throws {
        let path = try #require(ProcessInfo.processInfo.environment["JERD_MYSQL_ARCHIVE"])
        try oracle.verify(file: URL(fileURLWithPath: path), armoredSignature: OracleSignatureFixture.armored)
        let tampered = try TestSigner.temporaryFile(Data("changed archive".utf8))
        defer { try? FileManager.default.removeItem(at: tampered.deletingLastPathComponent()) }
        #expect(throws: PinnedRSAKey.mysqlRelease2025.failure) {
            try oracle.verify(file: tampered, armoredSignature: OracleSignatureFixture.armored)
        }
    }
}
