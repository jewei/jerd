/// Builds the child environment for `swift test`. Inherited `JERD_*` values never reach the tests by
/// accident: only the variables of the selected integration groups pass through.
///
/// The runtime paths of a group come from the prepared payloads (`prepared`). When every required
/// path of a group is set explicitly, those explicit paths win, so a developer can test another
/// trusted runtime.
enum TestEnvironment {
    static let prefix = "JERD_"

    static func make(
        inherited: [String: String], groups: [IntegrationGroup],
        prepared: (IntegrationGroup) throws -> [String: String] = { _ in [:] }
    ) throws -> [String: String] {
        var environment = inherited.filter { !$0.key.hasPrefix(prefix) }
        for group in groups {
            let isExplicit = group.requiredVariables.allSatisfy { !(inherited[$0] ?? "").isEmpty }
            let paths = isExplicit ? inherited : try preparedPaths(group, prepared: prepared)
            let missing = group.requiredVariables.filter { (paths[$0] ?? "").isEmpty }
            guard missing.isEmpty else {
                throw DevFailure.missingPrerequisite(
                    "The \(group.rawValue) integration tests need \(missing.joined(separator: ", ")). "
                        + "Run ./dev runtimes prepare, or set each one to an absolute runtime path.")
            }
            for name in group.requiredVariables {
                environment[name] = paths[name]
            }
            for name in group.optionalVariables {
                if let value = inherited[name], !value.isEmpty {
                    environment[name] = value
                }
            }
            environment.merge(group.switchVariables) { _, new in new }
        }
        return environment
    }

    /// The database group also installs the on-demand engines through the app pipeline, the mail
    /// group the on-demand Mailpit, and the storage group the on-demand RustFS, from the verified
    /// downloads of `./dev runtimes prepare` (`downloads`, when that folder exists). RustFS also needs
    /// the prepared XZ library (`xzSupport`), which the test puts into its app bundle. Explicit values
    /// win.
    static func addingOnDemandDownloads(
        _ environment: [String: String], groups: [IntegrationGroup], downloads: String?, xzSupport: String? = nil
    ) -> [String: String] {
        guard groups.contains(where: [.database, .mail, .storage].contains) else { return environment }
        var result = environment
        if (result["JERD_RUNTIME_DOWNLOADS"] ?? "").isEmpty, let downloads {
            result["JERD_RUNTIME_DOWNLOADS"] = downloads
        }
        guard !(result["JERD_RUNTIME_DOWNLOADS"] ?? "").isEmpty else { return result }
        if groups.contains(.database) {
            result["JERD_ON_DEMAND_INTEGRATION"] = "1"
        }
        if groups.contains(.mail) {
            result["JERD_ON_DEMAND_MAIL_INTEGRATION"] = "1"
        }
        if groups.contains(.storage) {
            if (result["JERD_XZ_SUPPORT"] ?? "").isEmpty, let xzSupport {
                result["JERD_XZ_SUPPORT"] = xzSupport
            }
            if !(result["JERD_XZ_SUPPORT"] ?? "").isEmpty {
                result["JERD_ON_DEMAND_STORAGE_INTEGRATION"] = "1"
            }
        }
        return result
    }

    private static func preparedPaths(
        _ group: IntegrationGroup, prepared: (IntegrationGroup) throws -> [String: String]
    ) throws -> [String: String] {
        do {
            return try prepared(group)
        } catch let failure as DevFailure where failure.status == .missingPrerequisite {
            let names = group.requiredVariables.joined(separator: ", ")
            throw DevFailure.missingPrerequisite(
                "\(failure.message) Or set \(names) to absolute paths of trusted local runtimes.")
        }
    }
}
