import Darwin
import Foundation

/// Recognizes Mach-O files by their first four bytes and reads `lipo -archs` output.
enum MachOFile {
    /// The thin and fat magic numbers in both byte orders.
    static let magicNumbers: Set<[UInt8]> = [
        [0xFE, 0xED, 0xFA, 0xCE], [0xCE, 0xFA, 0xED, 0xFE], [0xFE, 0xED, 0xFA, 0xCF], [0xCF, 0xFA, 0xED, 0xFE],
        [0xCA, 0xFE, 0xBA, 0xBE], [0xBE, 0xBA, 0xFE, 0xCA], [0xCA, 0xFE, 0xBA, 0xBF], [0xBF, 0xBA, 0xFE, 0xCA],
    ]

    static func hasMachOMagic(_ bytes: [UInt8]) -> Bool { magicNumbers.contains(Array(bytes.prefix(4))) }

    /// True for a regular file (not a link) that starts with a Mach-O magic number.
    static func isMachO(_ url: URL) -> Bool {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var bytes = [UInt8](repeating: 0, count: 4)
        let count = bytes.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, 4) }
        return count == 4 && hasMachOMagic(bytes)
    }

    /// The architectures that `lipo -archs` printed, for example `["x86_64", "arm64"]`.
    static func architectures(_ output: String) -> [String] {
        output.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
