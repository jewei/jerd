import Foundation
import JerdManifest

/// Runs the JerdKit tests with every integration group against the signed payloads inside the
/// candidate app. The paths come from the receipts, not from file names. The app does not embed the
/// pins that it installs on demand (MySQL and PostgreSQL), so those come from the verified payloads
/// of `./dev runtimes prepare`.
struct ReleaseRuntimeTests: Sendable {
    let shell: ReleaseShell
    let layout: CandidateLayout

    /// The child environment: the inherited one without any `JERD_*` value, plus the switch and path
    /// variables of all groups.
    func environment() throws -> [String: String] {
        let root = layout.appPayloads
        let catalog = try PayloadInventory.catalog(at: root.appending(path: RuntimePinCatalog.fileName))
        let paths = IntegrationRuntimePaths(
            inventory: PayloadInventory(root: root, catalog: catalog), indexRoot: layout.integration,
            onDemandInventory: PayloadInventory(root: shell.repository.payloads, catalog: catalog))
        var environment = shell.context.environment.filter { !$0.key.hasPrefix(TestEnvironment.prefix) }
        for group in IntegrationGroup.allCases {
            environment.merge(group.switchVariables) { _, new in new }
            environment.merge(try paths.variables(for: group)) { _, new in new }
        }
        return environment
    }

    func run() async throws {
        shell.console.detail("Test the signed runtimes with private data and loopback ports.")
        var invocation = TestPlan.kitTests(
            repository: shell.repository, toolchain: shell.context.toolchain, testTargets: [], filter: nil,
            environment: try environment())
        invocation.timeout = TimeLimit.runtimeTests
        try await shell.run(
            invocation.executable, invocation.arguments, limit: invocation.timeout, log: layout.log("runtime-tests"),
            environment: invocation.environment, directory: invocation.workingDirectory)
    }
}
