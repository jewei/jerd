/// Plans the swift-format runs over all Swift code that the repository formats.
enum FormatPlan {
    /// The formatted folders. `Package.swift` manifests keep their own aligned layout.
    static let formattedPaths = [
        "Packages/JerdKit/Sources",
        "Packages/JerdKit/Tests",
        "Apps",
        "Tools/Sources",
        "Tools/Tests",
        "Tools/Fixtures",
    ]

    /// Rewrites the files in place.
    static func format(repository: Repository, toolchain: Toolchain) -> Invocation {
        invocation("format", extraArguments: ["--in-place"], repository: repository, toolchain: toolchain)
    }

    /// Reports every difference from the configured format as an error and changes nothing.
    static func check(repository: Repository, toolchain: Toolchain) -> Invocation {
        invocation("lint", extraArguments: ["--strict"], repository: repository, toolchain: toolchain)
    }

    private static func invocation(
        _ subcommand: String,
        extraArguments: [String],
        repository: Repository,
        toolchain: Toolchain
    ) -> Invocation {
        let arguments =
            ["swift-format", subcommand, "--configuration", repository.formatConfiguration.path]
            + extraArguments + ["--recursive", "--parallel"]
            + formattedPaths.map { repository.path($0).path }
        return Invocation(
            executable: toolchain.xcrun, arguments: arguments,
            workingDirectory: repository.root, timeout: TimeLimit.format)
    }
}
