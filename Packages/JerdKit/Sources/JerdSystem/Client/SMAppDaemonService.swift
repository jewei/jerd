import ServiceManagement

/// The live daemon registration through `SMAppService.daemon(plistName: "dev.jerd.helper.plist")`.
public struct SMAppDaemonService: DaemonServiceControlling {
    public init() {}

    private var service: SMAppService { SMAppService.daemon(plistName: HelperServiceIdentity.plistName) }

    public var status: HelperAvailability {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .notRegistered
        default: .notFound
        }
    }

    public func register() throws { try service.register() }

    public func unregister() async throws { try await service.unregister() }
}
