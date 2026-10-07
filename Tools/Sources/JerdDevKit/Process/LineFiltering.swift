/// Decides which lines of a child's output to print. A filter may keep state, for example to show the
/// details that follow a failure line. Each output channel gets its own copy.
protocol LineFiltering: Sendable {
    mutating func shows(_ line: String) -> Bool
}

/// A filter without state: one predicate for each line.
struct PredicateLineFilter: LineFiltering {
    let accepts: @Sendable (String) -> Bool

    func shows(_ line: String) -> Bool {
        accepts(line)
    }
}
