import Foundation
import Testing

@testable import JerdCLICore

/// Runs the launcher logic against a fake PHP script, and runs its plan with the exact C vectors
/// that the launcher gives `execve`.
@Suite struct CLILauncherSmokeTests {
    /// A fake PHP that prints each argument and `PATH` and `LC_JERD` as hexadecimal bytes.
    private static let hexPHP = """
        #!/bin/sh
        hex() { printf '%s' "$1" | /usr/bin/od -An -tx1 | /usr/bin/tr -d ' \\n'; printf '\\n'; }
        for argument in "$@"; do hex "$argument"; done
        hex "$PATH"
        hex "$LC_JERD"

        """

    private func launcher(_ fixture: CLIFixture, image: RecordingProcessImage) -> CLILauncher {
        CLILauncher(
            layout: fixture.layout, caBundles: FakeCABundles(.success(nil)), processImage: image,
            diagnostics: RecordingDiagnostics())
    }

    @Test func plannedCommandRunsWithItsArgumentsEnvironmentAndExitStatus() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let php = try fixture.installPHP("8.5")
        try fixture.saveDefault(php)
        let companions = try fixture.installCompanions()
        let image = RecordingProcessImage()
        let status = launcher(fixture, image: image).run(
            CLIInvocation(
                arguments: ["composer", "require", "a b/c"],
                environment: ["PATH": "/usr/bin:/bin", "HOME": fixture.home.path], workingDirectory: "/"))
        #expect(status == CLILauncher.failureStatus)
        let result = try spawn(try #require(image.recorded.first))
        let bin = fixture.layout.binDirectory.path
        #expect(result.status == 7)
        #expect(
            String(decoding: result.output, as: UTF8.self) == """
                arg=\(php.cliPath)
                arg=-c
                arg=\(fixture.layout.runtimes.cliINIFile.path)
                arg=\(companions.composerPath)
                arg=require
                arg=a b/c
                PATH=\(bin):/usr/bin:/bin
                SCAN=\(fixture.layout.runtimes.cliEmptyINIDirectory.path)

                """)
    }

    @Test func argumentsAndEnvironmentThatAreNotUTF8ReachPHPByteForByte() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let script = try fixture.directory.file("hex-php", Self.hexPHP, mode: 0o700)
        try fixture.saveDefault(fixture.runtime("8.5", cliPath: script.path))
        let argument: [UInt8] = [0xFF, 0xFE, 0x41]
        let pathEntry = Array("/opt/caf".utf8) + [0xE9] + Array("/bin".utf8)
        let variable = Array("LC_JERD=".utf8) + [0xC3, 0x28]
        let path = Array("PATH=/usr/bin:".utf8) + pathEntry
        let invocation = CLIInvocation(
            arguments: [Array("php".utf8), Array("-n".utf8), argument],
            environment: CLIEnvironment(entries: [path, variable]), workingDirectory: "/")
        let image = RecordingProcessImage()
        _ = launcher(fixture, image: image).run(invocation)

        let result = try spawn(try #require(image.recorded.first))
        let bin = Array(fixture.layout.binDirectory.path.utf8)
        let colon = Array(":".utf8)
        let expected = [
            [0x2D, 0x6E], argument, bin + colon + Array("/usr/bin".utf8) + colon + pathEntry, [0xC3, 0x28],
        ].map(hex)
        #expect(String(decoding: result.output, as: UTF8.self) == expected.joined(separator: "\n") + "\n")
    }

    @Test func cStringVectorsKeepEveryByte() {
        let items: [[UInt8]] = [[0xFF], [], Array("é".utf8), [0x80, 0x0A, 0xC0]]
        #expect(CStrings.withVector(items) { CStrings.list($0) } == items)
    }

    private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
}
