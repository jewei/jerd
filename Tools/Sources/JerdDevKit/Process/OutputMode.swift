/// How the runner treats the output of a child while it runs. It always captures the output.
enum OutputMode: Sendable {
    /// Keep the output for the result and print nothing.
    case capture
    /// Also print every line when it arrives.
    case stream
    /// Also print the lines that the filter accepts. Each channel starts with its own copy of the filter.
    case streamFiltered(any LineFiltering)

    /// Also print the lines that the predicate accepts, for example only compiler diagnostics.
    static func streamMatching(_ accepts: @escaping @Sendable (String) -> Bool) -> OutputMode {
        .streamFiltered(PredicateLineFilter(accepts: accepts))
    }

    var prints: Bool {
        if case .capture = self { return false }
        return true
    }

    /// The filter for one channel, or `nil` when the mode prints every line or none.
    var filter: (any LineFiltering)? {
        if case .streamFiltered(let filter) = self { return filter }
        return nil
    }
}
