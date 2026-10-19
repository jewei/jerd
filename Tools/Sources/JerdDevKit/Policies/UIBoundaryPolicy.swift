/// `JerdUI` calls side effects only through its own port protocols, which `JerdLive` implements
/// (Docs/Architecture.md). `Package.swift` lets `JerdUI` import the domain targets for their value
/// types, so the compiler cannot check this rule. The policy reports two signs of a direct side
/// effect in `JerdUI` code: a name of an actor that another target declares, and a file, process,
/// network, or Keychain API. Comments and string literals do not count.
enum UIBoundaryPolicy {
    static let uiFolder = "Packages/JerdKit/Sources/JerdUI"
    static let sourcesFolder = "Packages/JerdKit/Sources"

    /// APIs that do file, process, network, Keychain, or workspace work. A port protocol wraps each.
    static let sideEffectAPIs: Set<String> = [
        "FileHandle", "FileManager", "NSWorkspace", "Process", "URLSession", "posix_spawn",
        "SecItemAdd", "SecItemCopyMatching", "SecItemDelete", "SecItemUpdate",
    ]

    /// - Parameters:
    ///   - uiFiles: The Swift files of `JerdUI`, with paths relative to the root.
    ///   - otherFiles: The Swift files of every other target in `Sources`.
    static func findings(
        uiFiles: [(path: String, text: String)], otherFiles: [(path: String, text: String)]
    ) -> [PolicyFinding] {
        let actors = Set(otherFiles.flatMap { actorNames(in: $0.text) })
        let forbidden = actors.union(sideEffectAPIs)
        return uiFiles.flatMap { file in
            SwiftCodeText(file.text).lines.enumerated().flatMap { index, line in
                identifiers(in: line).filter(forbidden.contains).map { name in
                    PolicyFinding(
                        file: file.path,
                        message: "line \(index + 1): JerdUI uses `\(name)` directly; "
                            + (actors.contains(name) ? "call the actor" : "call the API")
                            + " through a port protocol that JerdLive implements.")
                }
            }
        }
    }

    /// The names that `actor Name` declarations in the text introduce.
    static func actorNames(in text: String) -> [String] {
        SwiftCodeText(text).lines.flatMap { line -> [String] in
            let words = identifiers(in: line)
            return zip(words, words.dropFirst()).compactMap { $0 == "actor" ? $1 : nil }
        }
    }

    /// The identifiers of a code line, in order, without duplicates removed.
    static func identifiers(in line: String) -> [String] {
        line.split { !($0.isLetter || $0.isNumber || $0 == "_") }.map(String.init)
    }
}
