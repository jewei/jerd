import JerdFoundation
import JerdProcess
import JerdWeb

/// The web objects of one app run: the site registry, the environment coordinator, the system
/// setup gateway, and the one site change transaction that every site edit goes through.
package struct WebDomain: Sendable {
    package let registry: SiteRegistry
    package let coordinator: EnvironmentCoordinator
    package let gateway: SystemSetupGateway
    package let transaction: SiteChangeTransaction
    package let system: HelperSystemSetup

    /// - Parameter engine: The web effects. Its default supervisor has the forceful ceiling,
    ///   because Caddy and PHP-FPM hold no user data; data services never use it.
    package init(
        layout: DataLayout, helper: any HelperControlling, engine: EngineServices = Self.engineServices()
    ) {
        system = HelperSystemSetup(helper: helper)
        registry = SiteRegistry(store: ConfigurationStore(layout: layout))
        coordinator = EnvironmentCoordinator(layout: layout, system: system, engine: EngineRunner(services: engine))
        gateway = SystemSetupGateway(layout: layout, system: system, coordinator: coordinator)
        transaction = SiteChangeTransaction(registry: registry, coordinator: coordinator, gateway: gateway)
    }

    /// The JerdWeb defaults (`ProcessSupervisor(ceiling: .forceful)`), with the macOS trust
    /// decision named explicitly: the PHP CA bundle includes the local CA only while macOS
    /// trusts it for server TLS.
    package static func engineServices() -> EngineServices {
        EngineServices(caBundle: PHPCABundleBuilder(trust: SystemTrustDecision()))
    }
}
