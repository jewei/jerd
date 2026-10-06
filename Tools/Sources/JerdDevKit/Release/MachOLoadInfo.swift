/// The load commands of one Mach-O file that the release checks, parsed from `otool -arch arm64 -l`.
struct MachOLoadInfo: Equatable, Sendable {
    /// `LC_LOAD_DYLIB`, `LC_LOAD_WEAK_DYLIB`, `LC_REEXPORT_DYLIB`, `LC_LAZY_LOAD_DYLIB`, `LC_LOAD_UPWARD_DYLIB`.
    static let dependencyCommands: Set<String> = [
        "LC_LOAD_DYLIB", "LC_LOAD_WEAK_DYLIB", "LC_REEXPORT_DYLIB", "LC_LAZY_LOAD_DYLIB", "LC_LOAD_UPWARD_DYLIB",
    ]

    var dependencies: [String] = []
    var rpaths: [String] = []
    /// `LC_BUILD_VERSION.minos` or `LC_VERSION_MIN_MACOSX.version`; `0.0` when neither exists.
    var minimumSystem = "0.0"
    /// True when the file has `LC_ID_DYLIB`, that is, it is a library. Its own name is not a dependency.
    var isLibrary = false

    static func parse(_ output: String) -> MachOLoadInfo {
        var info = MachOLoadInfo()
        var command: String?
        for line in output.split(separator: "\n") {
            let fields = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard fields.count == 2 else { continue }
            let key = String(fields[0])
            let value = fields[1].trimmingCharacters(in: .whitespaces)
            switch (key, command) {
            case ("cmd", _):
                command = value
                info.isLibrary = info.isLibrary || value == "LC_ID_DYLIB"
            case ("name", let current?) where dependencyCommands.contains(current):
                info.dependencies.append(withoutOffset(value))
            case ("path", "LC_RPATH"):
                info.rpaths.append(withoutOffset(value))
            case ("minos", "LC_BUILD_VERSION"), ("version", "LC_VERSION_MIN_MACOSX"):
                info.minimumSystem = value
            default:
                break
            }
        }
        return info
    }

    /// `otool` prints `name /usr/lib/libSystem.B.dylib (offset 24)`.
    private static func withoutOffset(_ value: String) -> String {
        guard let range = value.range(of: " (offset ") else { return value }
        return String(value[..<range.lowerBound])
    }
}
