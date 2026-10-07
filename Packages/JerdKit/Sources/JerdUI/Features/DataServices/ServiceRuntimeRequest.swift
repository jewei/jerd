/// A RustFS installation that waits for the user to confirm it.
public struct StorageRuntimeRequest: Equatable, Sendable {
    public let offer: StorageRuntimeOffer
    /// True when Start asked for it: storage starts after the install.
    public let startsStorage: Bool

    public init(offer: StorageRuntimeOffer, startsStorage: Bool) {
        self.offer = offer
        self.startsStorage = startsStorage
    }
}
