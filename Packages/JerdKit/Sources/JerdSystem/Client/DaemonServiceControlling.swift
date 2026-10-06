/// The launchd registration of the helper daemon (`SMAppService` in the app; a fake in tests).
public protocol DaemonServiceControlling: Sendable {
    var status: HelperAvailability { get }
    func register() throws
    func unregister() async throws
}
