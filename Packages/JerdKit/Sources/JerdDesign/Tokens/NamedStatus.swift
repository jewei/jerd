/// A status and the subject that it describes, for example "Site status" and "Ready".
/// A page header takes this type, so a header badge can never be read only as "Status".
public struct NamedStatus: Hashable, Sendable {
    /// The spoken subject, for example "Site status" or "Mail status".
    public let subject: String
    public let status: DisplayStatus

    public init(_ subject: String, _ status: DisplayStatus) {
        self.subject = subject
        self.status = status
    }

    /// The text that VoiceOver reads, for example "Site status, Ready".
    public var spokenDescription: String {
        status.spokenDescription(subject: subject)
    }
}
