import Foundation
import Testing

@testable import JerdCLICore

@Suite struct CLIRuntimeOriginTests {
    @Test func executablesBelowTheRuntimeFoldersAreManaged() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let bundled = try fixture.installPHP("8.5")
        let update = fixture.layout.runtimes.managedRuntimesDirectory.appendingPathComponent("php-8.4/php")
        #expect(CLIRuntimeOrigin(executable: URL(fileURLWithPath: bundled.cliPath), layout: fixture.layout) == .managed)
        #expect(CLIRuntimeOrigin(executable: update, layout: fixture.layout) == .managed)
    }

    @Test func executablesElsewhereAreImported() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let runtimes = fixture.layout.runtimes.developmentRuntimesDirectory
        let sibling = runtimes.deletingLastPathComponent().appendingPathComponent(runtimes.lastPathComponent + "-x/php")
        #expect(CLIRuntimeOrigin(executable: sibling, layout: fixture.layout) == .imported)
        #expect(CLIRuntimeOrigin(executable: runtimes, layout: fixture.layout) == .imported)
        #expect(
            CLIRuntimeOrigin(executable: URL(fileURLWithPath: "/opt/homebrew/bin/php"), layout: fixture.layout)
                == .imported)
    }

    @Test func aLinkIsJudgedByItsTarget() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let managed = try fixture.installPHP("8.5")
        let outside = fixture.directory.path("php-link")
        try FileManager.default.createSymbolicLink(
            at: outside, withDestinationURL: URL(fileURLWithPath: managed.cliPath))
        #expect(CLIRuntimeOrigin(executable: outside, layout: fixture.layout) == .managed)
    }
}
