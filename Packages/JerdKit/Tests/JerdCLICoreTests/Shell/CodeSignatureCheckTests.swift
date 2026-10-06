import Foundation
import JerdFoundation
import Testing

@testable import JerdCLICore

@Suite struct CodeSignatureCheckTests {
    private static let team = CodeSignatureCheck(expected: .team("ABCDE12345"))
    private static let adHoc = CodeSignatureCheck(expected: .adHoc)

    /// A copy of `/usr/bin/true` with a fresh ad hoc signature, like a local Debug launcher.
    private static func adHocLauncher(in directory: TemporaryDirectory) throws -> URL {
        let file = try directory.file("JerdCLI", try Data(contentsOf: URL(fileURLWithPath: "/usr/bin/true")), mode: 0o700)
        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--sign", "-", "--force", file.path]
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        try #require(codesign.terminationStatus == 0)
        return file
    }

    private static func isInvalid(_ error: any Error) -> Bool { (error as? JerdError)?.kind == .invalid }

    /// Review cli-r1 L3: a development app accepts its ad hoc launcher.
    @Test func adHocLauncherPassesForAnAdHocApp() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try Self.adHoc.checkSignature(of: try Self.adHocLauncher(in: directory))
    }

    /// Review cli-r1 L3: a signed app refuses a launcher that any other signer, also ad hoc, made.
    @Test func adHocLauncherIsRefusedForATeamSignedApp() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let launcher = try Self.adHocLauncher(in: directory)
        #expect { try Self.team.checkSignature(of: launcher) } throws: { Self.isInvalid($0) }
    }

    /// Review cli-r1 L3: an Apple-signed tool has no matching Team ID, and it is not ad hoc.
    @Test func validSignatureOfAnotherSignerIsRefused() {
        let tool = URL(fileURLWithPath: "/usr/bin/true")
        #expect { try Self.team.checkSignature(of: tool) } throws: { Self.isInvalid($0) }
        #expect { try Self.adHoc.checkSignature(of: tool) } throws: { Self.isInvalid($0) }
    }

    @Test func unsignedFileIsRefused() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let file = try directory.file("JerdCLI", "test launcher", mode: 0o700)
        #expect { try Self.adHoc.checkSignature(of: file) } throws: { Self.isInvalid($0) }
    }

    @Test func changedCopyOfASignedLauncherIsRefused() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let launcher = try Self.adHocLauncher(in: directory)
        var bytes = try Data(contentsOf: launcher)
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: launcher)
        #expect { try Self.adHoc.checkSignature(of: launcher) } throws: { Self.isInvalid($0) }
    }

    @Test func malformedTeamIDIsRefusedBeforeItGoesIntoARequirement() throws {
        let check = CodeSignatureCheck(expected: .team("X\" or anchor apple"))
        #expect { try check.checkSignature(of: URL(fileURLWithPath: "/usr/bin/true")) } throws: { Self.isInvalid($0) }
        #expect(CodeSignatureCheck.isTeamIdentifier("ABCDE12345"))
        #expect(!CodeSignatureCheck.isTeamIdentifier("abcde12345"))
    }

    /// Review cli-r1 L3: the app's own signature selects the rule; ad hoc only without a Team ID.
    @Test func signerFollowsTheAppSignature() {
        #expect(SigningInformation(teamIdentifier: "ABCDE12345", isAdHoc: false).signer == .team("ABCDE12345"))
        #expect(SigningInformation(teamIdentifier: nil, isAdHoc: true).signer == .adHoc)
        #expect(SigningInformation(teamIdentifier: nil, isAdHoc: false).signer == .adHoc)
        #expect(SigningInformation(teamIdentifier: "", isAdHoc: false).signer == .adHoc)
    }
}
