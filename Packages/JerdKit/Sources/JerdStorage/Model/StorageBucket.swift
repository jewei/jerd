/// One registered bucket in `storage/settings.json`.
///
/// A record with `setupComplete == false` is a saved intent: Jerd may still create the bucket
/// and apply its access policy. Only a verified bucket is complete. Its `id` is computed and
/// never saved.
public struct StorageBucket: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let name: String
    /// Anonymous clients may read objects. They can never write, delete, or list.
    public var publicRead: Bool
    public var setupComplete: Bool

    public init(name: String, publicRead: Bool = false, setupComplete: Bool = false) {
        self.name = name
        self.publicRead = publicRead
        self.setupComplete = setupComplete
    }

    public var id: String { name }

    private enum CodingKeys: String, CodingKey {
        case name, publicRead, setupComplete
    }
}
