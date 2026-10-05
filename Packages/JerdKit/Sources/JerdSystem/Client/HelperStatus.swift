/// The app's view of the helper: whether the daemon is enabled, and the setup it reports.
///
/// "No setup" and "helper disabled" are now different (fixed problem 24): a disabled helper gives
/// its availability with an empty setup, because no XPC call is possible.
public struct HelperStatus: Equatable, Sendable {
    public let availability: HelperAvailability
    public let setup: SystemSetupStatus

    public init(availability: HelperAvailability, setup: SystemSetupStatus) {
        self.availability = availability
        self.setup = setup
    }
}
