import JerdFoundation
import JerdUI

/// The command-line tools installer in memory. A successful install changes the state to
/// installed and returns the report.
public actor InMemoryCommandLineTools: CommandLineToolsPort {
    public var current: CommandLineToolsStatus
    public var failure: String?
    public private(set) var installCount = 0

    public static let report = [
        "php, composer, and laravel now select the registered site's PHP, or the Jerd default outside a site.",
        "Shell backups: /Users/developer/Library/Application Support/Jerd/shell-backups/2026-10-06-094100",
        "Run exec zsh -l in an existing terminal to load the PATH change.",
    ]

    public init(state: CommandLineToolsStatus = .notInstalled) {
        current = state
    }

    public func configure(_ change: @Sendable (isolated InMemoryCommandLineTools) -> Void) {
        change(self)
    }

    public func status() async -> CommandLineToolsStatus { current }

    public func install() async throws -> [String] {
        installCount += 1
        if let failure { throw JerdError.unavailable(failure) }
        current = .installed
        return Self.report
    }
}
