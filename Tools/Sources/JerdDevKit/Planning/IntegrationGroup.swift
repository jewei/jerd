import Foundation

/// An opt-in group of integration tests that need real runtimes. Each group has switch variables that
/// `./dev test --integration` sets, and path variables that come from the payloads of
/// `./dev runtimes prepare` (`IntegrationRuntimePaths`) unless the user sets all of them.
enum IntegrationGroup: String, CaseIterable, Sendable {
    case web
    case database
    case mail
    case storage

    /// Variables that enable the group's tests.
    var switchVariables: [String: String] {
        switch self {
        case .web: ["JERD_INTEGRATION": "1"]
        case .database: ["JERD_INTEGRATION": "1", "JERD_DATABASE_INTEGRATION": "1"]
        case .mail: ["JERD_INTEGRATION": "1", "JERD_MAIL_INTEGRATION": "1"]
        case .storage: ["JERD_INTEGRATION": "1", "JERD_STORAGE_INTEGRATION": "1"]
        }
    }

    /// Absolute runtime paths that the tests cannot run without.
    var requiredVariables: [String] {
        switch self {
        case .web: ["JERD_PHP_CLI", "JERD_PHP_FPM", "JERD_CADDY"]
        case .database: ["JERD_DATABASE_RUNTIMES"]
        case .mail: ["JERD_MAIL_RUNTIME"]
        case .storage: ["JERD_STORAGE_RUNTIME"]
        }
    }

    /// Variables that extend the tests when they are set.
    var optionalVariables: [String] {
        switch self {
        case .web: ["JERD_SECOND_PHP_CLI", "JERD_SECOND_PHP_FPM", "JERD_KEEP_TEST_FILES"]
        case .database: ["JERD_OCCUPIED_DATABASE_PORT", "JERD_RUNTIME_DOWNLOADS", "JERD_ON_DEMAND_ENGINE"]
        case .mail, .storage: []
        }
    }

    /// Parses a comma-separated list such as `web,database`. The result has no duplicates and keeps
    /// the order of `allCases`.
    static func parseList(_ text: String) throws -> [IntegrationGroup] {
        var selected: Set<IntegrationGroup> = []
        for name in text.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            guard let group = IntegrationGroup(rawValue: name) else {
                let valid = allCases.map(\.rawValue).joined(separator: ", ")
                throw DevFailure.usage("Unknown integration group \"\(name)\". Use one or more of: \(valid).")
            }
            selected.insert(group)
        }
        guard !selected.isEmpty else {
            throw DevFailure.usage("Name at least one integration group, for example --integration web.")
        }
        return allCases.filter(selected.contains)
    }
}
