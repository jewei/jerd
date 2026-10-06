/// The selected Composer and Laravel installer of the `composer` and `laravel` commands:
/// `runtimes/cli-tools.json`.
///
/// The keys and the default `JSONEncoder` form (compact, escaped slashes, nil versions omitted) are
/// a compatibility contract with installed copies and the CLI launcher.
public struct CLICompanions: Codable, Equatable, Sendable {
    /// The absolute path of `composer.phar`.
    public let composerPath: String
    /// The absolute path of the Laravel installer script.
    public let laravelPath: String
    public let composerVersion: String?
    public let laravelVersion: String?

    public init(
        composerPath: String, laravelPath: String, composerVersion: String? = nil, laravelVersion: String? = nil
    ) {
        self.composerPath = composerPath
        self.laravelPath = laravelPath
        self.composerVersion = composerVersion
        self.laravelVersion = laravelVersion
    }

    /// True when both tools have a recorded version.
    public var hasVersions: Bool { composerVersion != nil && laravelVersion != nil }
}
