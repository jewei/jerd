/// The result of the last runtime installation of a service page (Storage, Mail): why it failed,
/// or that the user cancelled it. A success needs no notice: the page shows the installed version.
public struct ServiceRuntimeNotice: Equatable, Sendable {
    public let message: String
    public let isFailure: Bool

    public init(message: String, isFailure: Bool) {
        self.message = message
        self.isFailure = isFailure
    }
}
