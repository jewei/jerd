/// An on-demand runtime installation of a service page (RustFS, Mailpit) that waits for the user to
/// confirm it.
public struct ServiceRuntimeRequest: Equatable, Sendable {
    public let offer: ServiceRuntimeOffer
    /// True when Start asked for it: the service starts after the install.
    public let startsService: Bool

    public init(offer: ServiceRuntimeOffer, startsService: Bool) {
        self.offer = offer
        self.startsService = startsService
    }
}
