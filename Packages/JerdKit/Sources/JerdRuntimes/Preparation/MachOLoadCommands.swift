import Foundation
import JerdFoundation

/// Reads and rewrites the library references of a thin 64-bit Mach-O file. Pure; works on bytes.
///
/// It replaces an install name in place, inside its own load command, so the file layout and every
/// offset stay the same. A new name must fit in the space of the old command.
package enum MachOLoadCommands {
    /// One library reference: the install name and where its bytes are.
    package struct LibraryReference: Equatable, Sendable {
        package let name: String
        /// The offset of the first name byte in the file.
        package let offset: Int
        /// The bytes available for the name and its NUL terminators.
        package let capacity: Int
    }

    package static let magic64: UInt32 = 0xFEED_FACF
    /// LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB, LC_LAZY_LOAD_DYLIB, LC_LOAD_UPWARD_DYLIB.
    package static let libraryCommands: Set<UInt32> = [0xC, 0x8000_0018, 0x8000_001F, 0x20, 0x8000_0023]
    private static let headerSize = 32

    /// Every library that the file loads.
    /// - Throws: `.invalid` for a fat, 32-bit, or malformed file.
    package static func libraries(in data: Data) throws -> [LibraryReference] {
        let bytes = [UInt8](data)
        guard read(bytes, at: 0) == magic64, let count = read(bytes, at: 16), let size = read(bytes, at: 20),
            headerSize + Int(size) <= bytes.count
        else { throw invalid }
        var references: [LibraryReference] = []
        var offset = headerSize
        for _ in 0..<count {
            guard let command = read(bytes, at: offset), let commandSize = read(bytes, at: offset + 4),
                commandSize >= 8, offset + Int(commandSize) <= headerSize + Int(size)
            else { throw invalid }
            if libraryCommands.contains(command) {
                references.append(try reference(bytes, command: offset, size: Int(commandSize)))
            }
            offset += Int(commandSize)
        }
        return references
    }

    /// The file with `reference` renamed to `name`.
    package static func rename(_ reference: LibraryReference, to name: String, in data: Data) throws -> Data {
        let newBytes = Array(name.utf8)
        guard newBytes.count < reference.capacity, !newBytes.contains(0) else { throw invalid }
        var bytes = [UInt8](data)
        let padding = [UInt8](repeating: 0, count: reference.capacity - newBytes.count)
        bytes.replaceSubrange(reference.offset..<(reference.offset + reference.capacity), with: newBytes + padding)
        return Data(bytes)
    }

    private static func reference(_ bytes: [UInt8], command: Int, size: Int) throws -> LibraryReference {
        guard let nameOffset = read(bytes, at: command + 8), nameOffset >= 24, Int(nameOffset) < size else {
            throw invalid
        }
        let start = command + Int(nameOffset)
        let end = command + size
        guard let terminator = bytes[start..<end].firstIndex(of: 0),
            let name = String(bytes: bytes[start..<terminator], encoding: .utf8)
        else { throw invalid }
        return LibraryReference(name: name, offset: start, capacity: end - start)
    }

    private static func read(_ bytes: [UInt8], at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
    }

    private static var invalid: JerdError { .invalid("The runtime executable is not a supported Mach-O file.") }
}
