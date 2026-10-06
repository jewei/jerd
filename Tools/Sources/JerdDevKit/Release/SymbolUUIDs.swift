/// The debug UUIDs of a binary or its dSYM, from `dwarfdump --uuid`: `UUID: <uuid> (<arch>) <path>`.
enum SymbolUUIDs {
    struct Entry: Hashable, Sendable {
        var uuid: String
        var architecture: String
    }

    static func parse(_ output: String) -> Set<Entry> {
        var entries: Set<Entry> = []
        for line in output.split(separator: "\n") {
            let words = line.split(separator: " ")
            guard words.count >= 3, words[0] == "UUID:", words[2].hasPrefix("("), words[2].hasSuffix(")") else {
                continue
            }
            entries.insert(Entry(uuid: words[1].uppercased(), architecture: String(words[2].dropFirst().dropLast())))
        }
        return entries
    }

    /// The binaries of the app and their dSYM bundles.
    static let pairs: [(binary: String, symbols: String)] = [
        ("Contents/MacOS/Jerd", "Jerd.app.dSYM/Contents/Resources/DWARF/Jerd"),
        ("Contents/MacOS/JerdCLI", "JerdCLI.dSYM/Contents/Resources/DWARF/JerdCLI"),
        ("Contents/Library/LaunchServices/JerdHelper", "JerdHelper.dSYM/Contents/Resources/DWARF/JerdHelper"),
    ]
}
