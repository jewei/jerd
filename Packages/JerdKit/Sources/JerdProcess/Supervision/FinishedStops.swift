/// The results of recently completed stops, so that a repeated stop or a late log check gives the
/// same answer. It keeps at most `capacity` entries and forgets the oldest first.
struct FinishedStops: Sendable {
    /// One completed stop.
    struct Entry: Equatable, Sendable {
        var outcome: StopOutcome
        /// The last log problem of the child: a failed final trim or a failed redacted write.
        var logProblem: String?
    }

    /// Enough for every process of one app session to be stopped again by a slow caller.
    static let defaultCapacity = 256

    let capacity: Int
    private var entries: [ProcessToken: Entry] = [:]
    private var order: [ProcessToken] = []

    init(capacity: Int = defaultCapacity) { self.capacity = max(1, capacity) }

    subscript(token: ProcessToken) -> Entry? { entries[token] }

    var count: Int { entries.count }

    mutating func record(_ token: ProcessToken, _ entry: Entry) {
        if entries.updateValue(entry, forKey: token) == nil { order.append(token) }
        while order.count > capacity { entries[order.removeFirst()] = nil }
    }
}
