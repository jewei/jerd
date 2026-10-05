/// The command-line options of `jerd-snapshots [--output DIR] [--filter NAME...] [--list]`.
package struct SnapshotOptions: Equatable, Sendable {
    /// The default output folder, relative to the current directory.
    package static let defaultOutput = ".build/snapshots"

    package static let usage = """
        Usage: jerd-snapshots [--output DIR] [--filter NAME...] [--list]
          --output DIR       Write PNG files to DIR (default: \(defaultOutput)).
          --filter NAME...   Render only entries named NAME or NAME-<suffix>.
          --list             Print the entry names and sizes, then stop.
          --help             Print this help.
        """

    package var output = defaultOutput
    package var filters: [String] = []
    package var listOnly = false
    package var showHelp = false

    package init(
        output: String = defaultOutput, filters: [String] = [], listOnly: Bool = false, showHelp: Bool = false
    ) {
        self.output = output
        self.filters = filters
        self.listOnly = listOnly
        self.showHelp = showHelp
    }

    /// Parses arguments without the program name. Names after `--filter` continue until the
    /// next option, so `--filter a b` selects two entries.
    package static func parse(_ arguments: [String]) throws(SnapshotOptionsError) -> SnapshotOptions {
        var options = SnapshotOptions()
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            index += 1
            switch argument {
            case "--output":
                guard index < arguments.endIndex, !arguments[index].hasPrefix("--") else {
                    throw .missingValue(argument)
                }
                options.output = arguments[index]
                index += 1
            case "--filter":
                let names = arguments[index...].prefix { !$0.hasPrefix("--") }
                guard !names.isEmpty else { throw .missingValue(argument) }
                options.filters += names
                index += names.count
            case "--list": options.listOnly = true
            case "--help", "-h": options.showHelp = true
            default: throw .unknownArgument(argument)
            }
        }
        return options
    }
}
