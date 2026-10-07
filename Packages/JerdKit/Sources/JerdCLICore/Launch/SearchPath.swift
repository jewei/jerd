import Darwin

/// The `PATH` rule of the launcher, on raw bytes, so an entry that is not UTF-8 keeps its bytes.
///
/// Rules:
/// - Jerd's `bin` folder is first, exactly once. An entry is the same folder when its canonical
///   form is the same: symbolic links resolved (`/tmp` and `/private/tmp`), and `//`, `.`, and a
///   trailing `/` removed.
/// - Every other entry stays, in its order, also an empty entry of a non-empty `PATH`: it is the
///   user's choice.
/// - A missing or empty `PATH` becomes `<bin>:/usr/bin:/bin`, never the current folder.
enum SearchPath {
    /// Turns a folder path into the form that identifies it.
    typealias Canonicalizer = @Sendable ([UInt8]) -> [UInt8]

    static let variable = "PATH"
    /// The search path when the environment has no `PATH` or an empty one.
    static let fallback = Array("/usr/bin:/bin".utf8)

    private static let separator = UInt8(ascii: ":")
    private static let slash = UInt8(ascii: "/")

    /// `directory` first, then every other entry of `path` in its order. Idempotent.
    static func prepending(
        _ directory: [UInt8], to path: [UInt8]?, canonicalize: Canonicalizer = canonical
    ) -> [UInt8] {
        guard let path, !path.isEmpty else { return directory + [separator] + fallback }
        let target = canonicalize(directory)
        let others = path.split(separator: separator, omittingEmptySubsequences: false).filter { entry in
            entry.isEmpty || canonicalize(Array(entry)) != target
        }
        return ([directory] + others.map(Array.init)).joined(separator: [separator]).map { $0 }
    }

    /// The live canonical form: `realpath` for a folder that exists, else the lexical form.
    static let canonical: Canonicalizer = { path in
        CStrings.withVector([path]) { vector -> [UInt8] in
            guard let input = vector[0], let resolved = realpath(input, nil) else { return lexical(path) }
            defer { free(resolved) }
            return CStrings.bytes(resolved)
        }
    }

    /// `path` without empty components, `.` components, and a trailing slash. `/` stays `/`.
    static func lexical(_ path: [UInt8]) -> [UInt8] {
        let parts = path.split(separator: slash).filter { $0 != [UInt8(ascii: ".")][...] }
        let joined = parts.map(Array.init).joined(separator: [slash]).map { $0 }
        return path.first == slash ? [slash] + joined : joined
    }
}
