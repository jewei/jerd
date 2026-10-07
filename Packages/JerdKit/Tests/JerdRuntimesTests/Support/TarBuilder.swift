import Foundation

/// Builds small ustar archives in memory, including unsafe entries that real tools refuse to write.
struct TarBuilder {
    /// One archive member. `type` is the ustar type flag: "0" file, "1" hard link, "2" symbolic link,
    /// "5" folder, "6" FIFO.
    struct Entry {
        var name: String
        var type: String = "0"
        var link: String = ""
        var data = Data()
        var mode = "0000644"
    }

    var entries: [Entry] = []

    mutating func file(_ name: String, _ text: String = "", mode: String = "0000644") {
        entries.append(Entry(name: name, data: Data(text.utf8), mode: mode))
    }

    mutating func file(_ name: String, bytes: Int, mode: String = "0000644") {
        entries.append(Entry(name: name, data: Data(repeating: 7, count: bytes), mode: mode))
    }

    mutating func folder(_ name: String) {
        entries.append(Entry(name: name, type: "5", mode: "0000755"))
    }

    mutating func symlink(_ name: String, to target: String) {
        entries.append(Entry(name: name, type: "2", link: target, mode: "0000777"))
    }

    mutating func hardlink(_ name: String, to target: String) {
        entries.append(Entry(name: name, type: "1", link: target))
    }

    mutating func special(_ name: String, type: String) {
        entries.append(Entry(name: name, type: type))
    }

    /// The archive bytes: 512-byte headers, padded data, and two zero blocks.
    var data: Data {
        var result = Data()
        for entry in entries {
            result.append(contentsOf: header(entry))
            result.append(entry.data)
            if entry.data.count % 512 != 0 { result.append(Data(count: 512 - entry.data.count % 512)) }
        }
        result.append(Data(count: 1024))
        return result
    }

    func write(to url: URL) throws {
        try data.write(to: url)
    }

    private func header(_ entry: Entry) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: 512)
        func field(_ value: String, _ offset: Int) {
            for (index, byte) in value.utf8.enumerated() { header[offset + index] = byte }
        }
        field(entry.name, 0)
        field(entry.mode, 100)
        field("0000000", 108)
        field("0000000", 116)
        field(String(format: "%011o", entry.data.count), 124)
        field("00000000000", 136)
        field("        ", 148)
        field(entry.type, 156)
        field(entry.link, 157)
        field("ustar", 257)
        field("00", 263)
        let checksum = header.reduce(0) { $0 + Int($1) }
        field(String(format: "%06o", checksum), 148)
        header[154] = 0
        header[155] = 32
        return header
    }
}
