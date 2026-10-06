import JerdWeb

/// The PHP runtime of one command and the registered site that selected it (nil outside sites).
package struct CLIRuntimeSelection: Equatable, Sendable {
    package let runtime: DevelopmentRuntime
    package let site: Site?

    package init(runtime: DevelopmentRuntime, site: Site?) {
        self.runtime = runtime
        self.site = site
    }

    /// The selector in messages: the site hostname, or "the default".
    package var selectorName: String { site?.hostname ?? "the default" }
}
