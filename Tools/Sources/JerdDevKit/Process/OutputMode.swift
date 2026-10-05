/// One of the two output streams of a process.
enum OutputChannel: Hashable, Sendable {
    case standardOutput
    case standardError
}

/// How the runner treats the output of a child while it runs. It always captures the output.
enum OutputMode: Sendable {
    /// Keep the output for the result and print nothing.
    case capture
    /// Also print every line when it arrives.
    case stream
    /// Also print the lines that the predicate accepts, for example only compiler diagnostics.
    case streamMatching(@Sendable (String) -> Bool)

    func shouldPrint(_ line: String) -> Bool {
        switch self {
        case .capture: false
        case .stream: true
        case .streamMatching(let accepts): accepts(line)
        }
    }

    var prints: Bool {
        if case .capture = self { return false }
        return true
    }
}
