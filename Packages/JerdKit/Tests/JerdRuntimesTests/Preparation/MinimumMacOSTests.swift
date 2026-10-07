import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

/// A thin 64-bit Mach-O header with one command that declares a minimum macOS.
enum MinimumMachO {
    /// `14.0` packed as `xxxx.yy.zz`.
    static let fourteen: UInt32 = 0x000E_0000
    static let twentySeven: UInt32 = 0x001B_0000

    static func file(packed: UInt32, command: UInt32 = 0x32, platform: UInt32 = 1) -> Data {
        let body: [UInt32] =
            command == 0x32 ? [command, 24, platform, packed, packed, 0] : [command, 16, packed, packed]
        let header: [UInt32] = [0xFEED_FACF, 0x0100_000C, 0, 2, 1, UInt32(body.count * 4), 0, 0]
        return Data((header + body).flatMap { value in (0..<4).map { UInt8((value >> (8 * UInt32($0))) & 0xFF) } })
    }
}

@Suite struct MinimumMacOSTests {
    @Test(arguments: [("14", "14.0"), ("14.0", "14.0"), ("15.2", "15.2"), ("14.0.1", "14.0.1")])
    func versionsParseAndPrintInTheDeploymentTargetForm(_ text: String, _ printed: String) throws {
        #expect(try #require(MinimumMacOS(text)).description == printed)
    }

    @Test(arguments: ["", "14.", ".0", "14.0.0.0", "latest", "-14", "14.a", "12345"])
    func invalidVersionsAreRefused(_ text: String) {
        #expect(MinimumMacOS(text) == nil)
    }

    @Test func versionsCompareByNumberNotText() throws {
        #expect(try #require(MinimumMacOS("14.10")) > MinimumMacOS(major: 14, minor: 9))
        #expect(MinimumMacOS(major: 27, minor: 0) > .jerdKitMinimum)
        #expect(MinimumMacOS("14") == .jerdKitMinimum)
        #expect(MinimumMacOS.jerdKitMinimum.compilerFlag == "-mmacosx-version-min=14.0")
    }

    @Test func aBundleWithoutTheKeyGetsTheJerdKitMinimum() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let bundle = try #require(Bundle(url: folder.url))
        #expect(MinimumMacOS.of(bundle) == .jerdKitMinimum)
    }

    @Test func theAppMinimumComesFromLSMinimumSystemVersion() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let app = folder.path("Fixture.app")
        try OwnedDirectory.create(app.appendingPathComponent("Contents"))
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "dev.jerd.fixture", "LSMinimumSystemVersion": "15.4"],
            format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        let bundle = try #require(Bundle(url: app))
        #expect(MinimumMacOS.of(bundle) == MinimumMacOS(major: 15, minor: 4))
    }

    @Test func machOMinimumIsReadFromEitherCommand() throws {
        #expect(
            try MachOLoadCommands.minimumMacOS(in: MinimumMachO.file(packed: 0x000F_0201)) == MinimumMacOS("15.2.1"))
        let legacy = MinimumMachO.file(packed: MinimumMachO.fourteen, command: 0x24)
        #expect(try MachOLoadCommands.minimumMacOS(in: legacy) == .jerdKitMinimum)
        #expect(
            try MachOLoadCommands.minimumMacOS(in: MachOBuilder.thin(libraries: ["/usr/lib/libSystem.B.dylib"])) == nil)
    }

    @Test func aBuildVersionForAnotherPlatformIsNotTheMacOSMinimum() throws {
        let iOS = MinimumMachO.file(packed: MinimumMachO.twentySeven, platform: 2)
        #expect(try MachOLoadCommands.minimumMacOS(in: iOS) == nil)
    }

    @Test func aTruncatedBuildVersionIsRefused() {
        let file = MinimumMachO.file(packed: MinimumMachO.fourteen)
        #expect(throws: JerdError.self) { try MachOLoadCommands.minimumMacOS(in: file.prefix(40)) }
    }
}
