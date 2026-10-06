import Foundation

/// Runs the isolated Sparkle installation test: it compiles the test app, makes a temporary key, runs
/// every `UpdateCase` in order, records the evidence, and removes its work folder.
enum UpdateCheckStep {
    static let check = "updates"

    static func run(_ context: DevContext, identity: String, effects: UpdateCheckEffects) async throws {
        let plan = UpdateFixturePlan(repository: context.repository, toolchain: context.toolchain)
        try requireSparkle(plan)
        let jerdInfoPlist = try RepositoryPolicy.read(SparkleInfoPlistPolicy.file, in: context.repository)
        let work = context.repository.path(".build/check-updates-\(UUID().uuidString.lowercased())")
        let harness = HarnessRun(check: check, identity: identity, context: context, clock: effects.clock)
        do {
            try await harness.run { cases in
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                let fixture = try await makeFixture(
                    context, plan: plan, work: work, identity: identity, jerdInfoPlist: jerdInfoPlist)
                let runner = UpdateCaseRun(context: context, plan: plan, effects: effects, fixture: fixture)
                for testCase in UpdateCase.allCases {
                    context.console.detail("Case \(testCase.rawValue)…")
                    cases.append(try await runner.run(testCase, in: work))
                }
            }
        } catch {
            try removeWork(work)
            throw error
        }
        try removeWork(work)
    }

    /// Sparkle comes from the package that `./dev build` resolves into `.build/SourcePackages`.
    static func requireSparkle(_ plan: UpdateFixturePlan) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: plan.framework.path), manager.isExecutableFile(atPath: plan.signUpdate.path)
        else {
            throw DevFailure.missingPrerequisite(
                "Sparkle is not resolved in .build/SourcePackages. Run ./dev build first, then run this check again.")
        }
    }

    /// Compiles the test app and makes the temporary key.
    static func makeFixture(
        _ context: DevContext, plan: UpdateFixturePlan, work: URL, identity: String, jerdInfoPlist: Data
    ) async throws -> UpdateFixture {
        let binary = work.appending(path: UpdateTestBundle.executableName)
        try await context.runChecked(plan.compile(to: binary), output: .capture)
        let key = work.appending(path: "test-key")
        let generated = try await context.runChecked(
            plan.generateKey(binary: binary, key: key, inherited: context.environment), output: .capture)
        let publicKey = generated.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Data(base64Encoded: publicKey)?.count == 32 else {
            throw DevFailure.checkFailed("The test app printed no valid public key.")
        }
        return UpdateFixture(
            binary: binary, key: key, publicKey: publicKey, identity: identity, jerdInfoPlist: jerdInfoPlist)
    }

    /// Removes the work folder with the test apps and the private test key.
    static func removeWork(_ work: URL) throws {
        guard FileManager.default.fileExists(atPath: work.path) else { return }
        do {
            try FileManager.default.removeItem(at: work)
        } catch {
            throw DevFailure.checkFailed("Cannot remove the work folder \(work.path): \(error.localizedDescription)")
        }
    }
}
