/// One site of a serving plan with its resolved PHP runtime.
public struct PlannedSite: Equatable, Sendable {
    public let site: Site
    public let runtime: DevelopmentRuntime

    public init(site: Site, runtime: DevelopmentRuntime) {
        self.site = site
        self.runtime = runtime
    }

    /// True when both serve the same way. The name, the start flag, the PHP selection, and the
    /// inspection time do not change what is served.
    public func servesLike(_ other: PlannedSite) -> Bool {
        site.id == other.site.id && site.hostname == other.site.hostname
            && site.projectPath == other.site.projectPath && site.documentRoot == other.site.documentRoot
            && runtime.servesLike(other.runtime)
    }
}
