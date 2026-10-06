import JerdStorage

/// The fields of the Add Bucket sheet and their rules. New buckets are private unless the user
/// turns on public read, which allows anonymous reads only.
public struct BucketDraft: Equatable, Sendable {
    static let nameRule =
        "Use 3–63 lowercase letters, numbers, dots, or hyphens. Start and end with a letter or number."

    public var name = ""
    public var publicRead = false

    public init(name: String = "", publicRead: Bool = false) {
        self.name = name
        self.publicRead = publicRead
    }

    /// The name without spaces around it. Spaces alone never make a name (spec F 7.2.12).
    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The inline message under the name, or nil. An empty name shows no message; Save stays off.
    public func issue(in settings: StorageSettings) -> String? {
        let name = trimmedName
        guard !name.isEmpty else { return nil }
        guard BucketName.isValid(name) else { return Self.nameRule }
        if settings.bucket(name)?.setupComplete == true {
            return "A bucket named \(name) is already registered."
        }
        return nil
    }

    public func canSave(in settings: StorageSettings) -> Bool {
        !trimmedName.isEmpty && issue(in: settings) == nil
    }
}
