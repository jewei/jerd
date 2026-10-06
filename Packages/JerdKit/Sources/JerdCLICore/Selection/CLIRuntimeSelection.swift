import JerdWeb

/// The PHP runtime of one command and the registered site that selected it (nil outside sites).
public struct CLIRuntimeSelection: Equatable, Sendable {
    public let runtime: DevelopmentRuntime
    public let site: Site?

    public init(runtime: DevelopmentRuntime, site: Site?) {
        self.runtime = runtime
        self.site = site
    }

    /// The selector in messages: the site hostname, or "the default".
    public var selectorName: String { site?.hostname ?? "the default" }
}
