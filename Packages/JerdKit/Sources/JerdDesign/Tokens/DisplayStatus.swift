/// A status as the user sees it: a short label such as "Ready" and its tone.
public struct DisplayStatus: Hashable, Sendable {
    public let label: String
    public let tone: StatusTone

    public init(_ label: String, tone: StatusTone) {
        self.label = label
        self.tone = tone
    }

    /// The text that VoiceOver reads for a status of `subject`, for example
    /// "Site status, Ready". Each status names its subject, so two statuses on one page differ.
    public func spokenDescription(subject: String) -> String {
        "\(subject), \(label)"
    }
}
