/// Everything that one connector launch needs. The token travels only inside this value.
public struct TunnelLaunch: Equatable, Sendable {
    public let runtime: TunnelRuntime
    public let registration: TunnelRegistration
    public let token: TunnelToken

    package init(runtime: TunnelRuntime, registration: TunnelRegistration, token: TunnelToken) {
        self.runtime = runtime
        self.registration = registration
        self.token = token
    }
}
