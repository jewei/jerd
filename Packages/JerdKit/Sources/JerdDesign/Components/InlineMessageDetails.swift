/// Lines that an `InlineMessage` shows below its text behind a disclosure, for example the last
/// lines of a server log. The message itself stays one short line.
public struct InlineMessageDetails: Equatable, Sendable {
    /// The disclosure label, for example "Last log lines".
    public let title: String
    public let lines: [String]
    /// True when the disclosure starts open, for example in a snapshot.
    public let isExpanded: Bool

    public init(title: String, lines: [String], isExpanded: Bool = false) {
        self.title = title
        self.lines = lines
        self.isExpanded = isExpanded
    }
}
