import Foundation
import JerdFoundation
import JerdTestSupport
import Testing
import os

@testable import JerdCLICore

@Suite struct CodeSignatureCheckTests {
    private static let team = CodeSignatureCheck(expected: .team("ABCDE12345"))
    private static let adHoc = CodeSignatureCheck(expected: .adHoc)

    /// A copy of `/usr/bin/true` with a fresh ad hoc signature, like a local Debug launcher.
    private static func adHocLauncher(in directory: TemporaryDirectory) throws -> URL {
        let file = try directory.file(
            "JerdCLI", try Data(contentsOf: URL(fileURLWithPath: "/usr/bin/true")), mode: 0o700)
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

    /// The app makes the check on the main actor at launch. The Security code-signing calls must
    /// not run there, so the app's signer is read only by a check, once per check.
    @Test func theRunningAppSignerIsReadOnlyWhenACheckRuns() throws {
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let check = CodeSignatureCheck.forRunningApp {
            reads.withLock { $0 += 1 }
            return .adHoc
        }
        _ = ShellSetupInstaller(
            layout: DataLayout(root: URL(fileURLWithPath: "/nonexistent/jerd")),
            home: URL(fileURLWithPath: "/nonexistent"),
            launcher: URL(fileURLWithPath: "/nonexistent/JerdCLI"), signatures: check)
        #expect(reads.withLock { $0 } == 0)
        let directory = try TemporaryDirectory(" cli café")
        defer { directory.remove() }
        try check.checkSignature(of: try Self.adHocLauncher(in: directory))
        #expect(reads.withLock { $0 } == 1)
    }

    /// A development app accepts its ad hoc launcher.
    @Test func adHocLauncherPassesForAnAdHocApp() throws {
        let directory = try TemporaryDirectory(" cli café")
        defer { directory.remove() }
        try Self.adHoc.checkSignature(of: try Self.adHocLauncher(in: directory))
    }

    /// A signed app refuses a launcher that any other signer, also ad hoc, made.
    @Test func adHocLauncherIsRefusedForATeamSignedApp() throws {
        let directory = try TemporaryDirectory(" cli café")
        defer { directory.remove() }
        let launcher = try Self.adHocLauncher(in: directory)
        #expect { try Self.team.checkSignature(of: launcher) } throws: { Self.isInvalid($0) }
    }

    /// An Apple-signed tool has no matching Team ID, and it is not ad hoc.
    @Test func validSignatureOfAnotherSignerIsRefused() {
        let tool = URL(fileURLWithPath: "/usr/bin/true")
        #expect { try Self.team.checkSignature(of: tool) } throws: { Self.isInvalid($0) }
        #expect { try Self.adHoc.checkSignature(of: tool) } throws: { Self.isInvalid($0) }
    }

    @Test func unsignedFileIsRefused() throws {
        let directory = try TemporaryDirectory(" cli café")
        defer { directory.remove() }
        let file = try directory.file("JerdCLI", "test launcher", mode: 0o700)
        #expect { try Self.adHoc.checkSignature(of: file) } throws: { Self.isInvalid($0) }
    }

    @Test func changedCopyOfASignedLauncherIsRefused() throws {
        let directory = try TemporaryDirectory(" cli café")
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

    /// The app's own signature selects the rule; ad hoc only without a Team ID.
    @Test func signerFollowsTheAppSignature() {
        #expect(SigningInformation(teamIdentifier: "ABCDE12345", isAdHoc: false).signer == .team("ABCDE12345"))
        #expect(SigningInformation(teamIdentifier: nil, isAdHoc: true).signer == .adHoc)
        #expect(SigningInformation(teamIdentifier: nil, isAdHoc: false).signer == .adHoc)
        #expect(SigningInformation(teamIdentifier: "", isAdHoc: false).signer == .adHoc)
    }
}
