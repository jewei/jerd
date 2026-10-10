/// Reads the public hostnames of registered tunnels without connecting them.
public protocol SitePublicHostsLoading: Sendable {
    func loadPublicHosts() async throws -> Set<SitePublicHost>
}
