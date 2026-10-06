import Foundation
import JerdWeb

/// The PHP and Caddy registrations of the site configuration, for Advanced.
public struct LocalRuntimeRegistrations: Equatable, Sendable {
    public var php: [DevelopmentRuntime]
    public var defaultPHPID: UUID?
    /// The version of the registered Caddy, or nil when none is registered.
    public var caddyVersion: String?
    /// The result of the bundled runtime setup at launch, for example
    /// "PHP, Caddy, Composer, and the Laravel installer are installed and managed by Jerd."
    public var setupMessage: String?

    public init(
        php: [DevelopmentRuntime] = [], defaultPHPID: UUID? = nil, caddyVersion: String? = nil,
        setupMessage: String? = nil
    ) {
        self.php = php
        self.defaultPHPID = defaultPHPID
        self.caddyVersion = caddyVersion
        self.setupMessage = setupMessage
    }
}
