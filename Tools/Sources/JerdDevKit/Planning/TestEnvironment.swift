/// Builds the child environment for `swift test`. Inherited `JERD_*` values never reach the tests by
/// accident: only the variables of the selected integration groups pass through.
enum TestEnvironment {
    static let prefix = "JERD_"

    static func make(inherited: [String: String], groups: [IntegrationGroup]) throws -> [String: String] {
        var environment = inherited.filter { !$0.key.hasPrefix(prefix) }
        for group in groups {
            let missing = group.requiredVariables.filter { (inherited[$0] ?? "").isEmpty }
            guard missing.isEmpty else {
                throw DevFailure.missingPrerequisite(
                    "The \(group.rawValue) integration tests need \(missing.joined(separator: ", ")). "
                        + "Set each one to an absolute runtime path. See Tools/README.md.")
            }
            for name in group.requiredVariables + group.optionalVariables {
                if let value = inherited[name], !value.isEmpty {
                    environment[name] = value
                }
            }
            environment.merge(group.switchVariables) { _, new in new }
        }
        return environment
    }
}
