import Foundation
import JerdFoundation
import JerdRuntimes
import Testing

@Suite struct MachOLoadCommandsTests {
    static let homebrew = "/opt/homebrew/opt/xz/lib/liblzma.5.dylib"

    @Test func libraryReferencesAreRead() throws {
        let file = MachOBuilder.thin(libraries: ["/usr/lib/libSystem.B.dylib", Self.homebrew])
        let names = try MachOLoadCommands.libraries(in: file).map(\.name)
        #expect(names == ["/usr/lib/libSystem.B.dylib", Self.homebrew])
    }

    @Test func renameKeepsTheLayoutAndChangesOnlyTheName() throws {
        let file = MachOBuilder.thin(libraries: [Self.homebrew])
        let reference = try #require(try MachOLoadCommands.libraries(in: file).first)
        let renamed = try MachOLoadCommands.rename(reference, to: LZMALinker.bundledReference, in: file)
        #expect(renamed.count == file.count)
        #expect(try MachOLoadCommands.libraries(in: renamed).map(\.name) == [LZMALinker.bundledReference])
    }

    @Test func aLongerNameThanTheCommandHoldsIsRefused() throws {
        let file = MachOBuilder.thin(libraries: ["/a.dylib"])
        let reference = try #require(try MachOLoadCommands.libraries(in: file).first)
        #expect(throws: JerdError.self) {
            try MachOLoadCommands.rename(reference, to: String(repeating: "x", count: 200), in: file)
        }
    }

    @Test(arguments: [Data(), Data([0xCA, 0xFE, 0xBA, 0xBE]), Data(repeating: 0, count: 64)])
    func otherFilesAreRefused(_ data: Data) {
        #expect(throws: JerdError.invalid("The runtime executable is not a supported Mach-O file.")) {
            try MachOLoadCommands.libraries(in: data)
        }
    }

    @Test func truncatedLoadCommandsAreRefused() {
        let file = MachOBuilder.thin(libraries: [Self.homebrew])
        #expect(throws: JerdError.self) { try MachOLoadCommands.libraries(in: file.prefix(60)) }
    }

    @Test func onlySystemAndPayloadReferencesAreProvided() {
        #expect(LZMALinker.isProvided("/usr/lib/libobjc.A.dylib"))
        #expect(LZMALinker.isProvided("/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit"))
        #expect(LZMALinker.isProvided("@loader_path/liblzma.5.dylib"))
        #expect(!LZMALinker.isProvided(Self.homebrew))
        #expect(!LZMALinker.isProvided("/usr/local/lib/libssl.dylib"))
    }

    /// Opt-in: the real upstream RustFS binary (`JERD_RUSTFS_BINARY=/path/to/rustfs`).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["JERD_RUSTFS_BINARY"] != nil))
    func realRustFSReferenceCanPointIntoThePayload() throws {
        let path = try #require(ProcessInfo.processInfo.environment["JERD_RUSTFS_BINARY"])
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let homebrew = try #require(try MachOLoadCommands.libraries(in: data).first { $0.name == Self.homebrew })
        let renamed = try MachOLoadCommands.rename(homebrew, to: LZMALinker.bundledReference, in: data)
        #expect(try MachOLoadCommands.libraries(in: renamed).contains { $0.name == LZMALinker.bundledReference })
    }
}

/// Builds a minimal thin 64-bit Mach-O header with `LC_LOAD_DYLIB` commands.
enum MachOBuilder {
    static func thin(libraries: [String]) -> Data {
        let commands = libraries.map(command)
        var bytes = [UInt8]()
        append(&bytes, 0xFEED_FACF)
        append(&bytes, 0x0100_000C)
        append(&bytes, 0)
        append(&bytes, 2)
        append(&bytes, UInt32(commands.count))
        append(&bytes, UInt32(commands.reduce(0) { $0 + $1.count }))
        append(&bytes, 0)
        append(&bytes, 0)
        return Data(bytes + commands.flatMap { $0 })
    }

    private static func command(_ name: String) -> [UInt8] {
        var nameBytes = Array(name.utf8) + [0]
        while (24 + nameBytes.count) % 8 != 0 { nameBytes.append(0) }
        var bytes = [UInt8]()
        append(&bytes, 0xC)
        append(&bytes, UInt32(24 + nameBytes.count))
        append(&bytes, 24)
        append(&bytes, 2)
        append(&bytes, 0x10000)
        append(&bytes, 0x10000)
        return bytes + nameBytes
    }

    private static func append(_ bytes: inout [UInt8], _ value: UInt32) {
        bytes += (0..<4).map { UInt8((value >> (8 * UInt32($0))) & 0xFF) }
    }
}
