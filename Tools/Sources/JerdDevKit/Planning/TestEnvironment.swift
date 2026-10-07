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
