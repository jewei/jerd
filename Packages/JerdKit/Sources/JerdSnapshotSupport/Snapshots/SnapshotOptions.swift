/// The command-line options of `jerd-snapshots [--output DIR] [--list] [NAME...]`.
/// `./dev snapshots PAGE...` passes page names as positional arguments.
package struct SnapshotOptions: Equatable, Sendable {
    /// The default output folder, relative to the current directory.
    package static let defaultOutput = ".build/snapshots"

    package static let usage = """
        Usage: jerd-snapshots [--output DIR] [--list] [NAME...] [--filter NAME...]
          NAME               Render only entries named NAME or NAME-<suffix>. No names render all.
          --output DIR       Write PNG files to DIR (default: \(defaultOutput)).
          --filter NAME...   The same as NAME arguments.
          --list             Print the entry names and sizes, then stop.
          --contrast-pass    Render only the Increase Contrast variants. The command starts
                             this pass itself, in a second process.
          --help             Print this help.
        Cocoa arguments such as -AppleLanguages (en) are accepted. The renderer replaces the
        settings that change drawing; see JerdSnapshotSupport/README.md.
        """

    package var output = defaultOutput
    package var filters: [String] = []
    package var listOnly = false
    package var showHelp = false
    package var contrast = SnapshotContrast.standard

    package init(
        output: String = defaultOutput, filters: [String] = [], listOnly: Bool = false, showHelp: Bool = false,
        contrast: SnapshotContrast = .standard
    ) {
        self.output = output
        self.filters = filters
        self.listOnly = listOnly
        self.showHelp = showHelp
        self.contrast = contrast
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
                options.output = try value(of: argument, in: arguments, at: &index)
            case "--filter":
                let names = arguments[index...].prefix { !$0.hasPrefix("-") }
                guard !names.isEmpty else { throw .missingValue(argument) }
                options.filters += names
                index += names.count
            case "--list": options.listOnly = true
            case "--help", "-h": options.showHelp = true
            case "--contrast-pass": options.contrast = .increased
            default:
                if isCocoaArgument(argument) {
                    // Foundation reads `-Key value` pairs into the argument domain itself.
                    _ = try value(of: argument, in: arguments, at: &index)
                } else if argument.hasPrefix("-") {
                    throw .unknownArgument(argument)
                } else {
                    options.filters.append(argument)
                }
            }
        }
        return options
    }

    private static func value(
        of option: String, in arguments: [String], at index: inout Int
    ) throws(SnapshotOptionsError) -> String {
        guard index < arguments.endIndex, !arguments[index].hasPrefix("--") else {
            throw .missingValue(option)
        }
        defer { index += 1 }
        return arguments[index]
    }

    /// `-Name` with a letter after one hyphen, as Cocoa defaults arguments are written.
    private static func isCocoaArgument(_ argument: String) -> Bool {
        guard argument.hasPrefix("-"), !argument.hasPrefix("--"), argument.count > 2 else { return false }
        return argument.dropFirst().first?.isLetter == true
    }
}
