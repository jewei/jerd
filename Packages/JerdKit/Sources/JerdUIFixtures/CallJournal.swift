/// An ordered record of calls across several fixtures, for order tests.
@MainActor
public final class CallJournal {
    public private(set) var entries: [String] = []

    public init() {}

    public func record(_ entry: String) {
        entries.append(entry)
    }
}
