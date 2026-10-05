import Foundation

/// Builds small zip archives with stored (uncompressed) entries in memory.
struct ZipBuilder {
    struct Entry {
        var name: String
        var data: Data
        var mode: UInt32
    }

    var entries: [Entry] = []

    mutating func file(_ name: String, _ text: String, mode: UInt32 = 0o100_644) {
        entries.append(Entry(name: name, data: Data(text.utf8), mode: mode))
    }

    var data: Data {
        var result = Data()
        var central = Data()
        for entry in entries {
            let offset = UInt32(result.count)
            let crc = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)
            result.append(le32(0x0403_4b50))
            result.append(common(entry, crc: crc, size: size))
            result.append(le16(0))
            result.append(Data(entry.name.utf8))
            result.append(entry.data)
            central.append(le32(0x0201_4b50))
            central.append(le16(3 << 8 | 20))
            central.append(common(entry, crc: crc, size: size))
            central.append(le16(0) + le16(0) + le16(0) + le16(0))
            central.append(le32(entry.mode << 16) + le32(offset))
            central.append(Data(entry.name.utf8))
        }
        let centralOffset = UInt32(result.count)
        result.append(central)
        let count = UInt16(entries.count)
        result.append(le32(0x0605_4b50) + le16(0) + le16(0) + le16(count) + le16(count))
        result.append(le32(UInt32(central.count)) + le32(centralOffset) + le16(0))
        return result
    }

    /// Version needed, flags, method, time, date, CRC, both sizes, and the name length.
    private func common(_ entry: Entry, crc: UInt32, size: UInt32) -> Data {
        le16(20) + le16(0) + le16(0) + le16(0) + le16(0x21) + le32(crc) + le32(size) + le32(size)
            + le16(UInt16(entry.name.utf8.count))
    }

    private func le16(_ value: UInt16) -> Data { Data([UInt8(value & 0xFF), UInt8(value >> 8)]) }

    private func le32(_ value: UInt32) -> Data {
        Data((0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
}

/// The CRC-32 of zip files (polynomial 0xEDB88320).
enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

/// Compresses `source` with `/usr/bin/gzip -n` into `destination`.
func gzip(_ source: URL, to destination: URL) throws {
    FileManager.default.createFile(atPath: destination.path, contents: nil)
    let output = try FileHandle(forWritingTo: destination)
    defer { try? output.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
    process.arguments = ["-n", "-c", source.path]
    process.standardOutput = output
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
}
