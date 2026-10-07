import Foundation
import Testing

@testable import JerdDevKit

@Suite("Sparkle installation check flow")
struct UpdateCheckStepTests {
    /// A repository with Jerd's Info.plist and a resolved Sparkle package.
    private func makeRepository() throws -> URL {
        let root = try TestFixtures.temporaryFolder()
        let plist = try Data(contentsOf: UpdateFixtureTests.jerdInfoPlist)
        try FileManager.default.createDirectory(
            at: root.appending(path: "Apps/Jerd/Resources"), withIntermediateDirectories: true)
        try plist.write(to: root.appending(path: SparkleInfoPlistPolicy.file))
        let sparkle = ".build/SourcePackages/artifacts/sparkle/Sparkle"
        try TestFixtures.write(
            "", to: "\(sparkle)/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Sparkle", in: root)
        try TestFixtures.write("#!/bin/sh\n", to: "\(sparkle)/bin/sign_update", in: root)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: root.appending(path: "\(sparkle)/bin/sign_update").path)
        return root
    }

    private struct Run {
        let root: URL
        let simulation: SimulatedSparkle
        let server = FakeFileServer()
        let clock = FakeHarnessClock()

        var runner: RecordingProcessRunner { simulation.runner }

        func effects() -> UpdateCheckEffects {
            let server = server
            return UpdateCheckEffects(
                clock: clock, inspector: simulation.inspector, makeServer: { server },
                home: root.appending(path: "home"))
        }

        func record() throws -> EvidenceRecord {
            let folder = root.appending(path: ".build/evidence")
            let name = try #require(try FileManager.default.contentsOfDirectory(atPath: folder.path).first)
            return try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: folder.appending(path: name)))
        }

        func leftovers() throws -> [String] {
            let build = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: ".build").path)
            let library = ["Caches", "HTTPStorages", "Preferences"].flatMap { folder in
                let path = root.appending(path: "home/Library/\(folder)").path
                return ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).map { "\(folder)/\($0)" }
            }
            return build.filter { $0.hasPrefix("check-updates-") } + library
        }
    }

    private func makeRun(overrides: [UpdateCase: [String]] = [:]) throws -> Run {
        let root = try makeRepository()
        let simulation = SimulatedSparkle(
            inspector: FakeProcessInspector(), home: root.appending(path: "home"), overrides: overrides)
        return Run(root: root, simulation: simulation)
    }

    @Test("Runs the five cases, records them as passed, and removes every temporary file")
    func passesEveryCase() async throws {
        let run = try makeRun()
        defer { try? FileManager.default.removeItem(at: run.root) }
        let runner = run.runner
        let context = TestFixtures.context(repository: Repository(root: run.root), runner: runner)
        try await UpdateCheckStep.run(context, identity: "Developer ID", effects: run.effects())
        let record = try run.record()
        #expect(record.passed && record.check == "updates" && record.identity == "Developer ID")
        #expect(record.cases.map(\.name) == UpdateCase.allCases.map(\.rawValue))
        #expect(try run.leftovers().isEmpty)
        #expect(run.server.started.count == 5 && run.server.stops == 5)
        let defaults = runner.recorded.filter { $0.executable == SystemProgram.defaults }
        #expect(defaults.count == 5 && Set(defaults.map { $0.arguments[1] }).count == 5)
        #expect(defaults.allSatisfy { $0.arguments[1].hasPrefix("dev.jerd.updater-test.") })
    }

    @Test("Signs each test app with the identity and the feed and archive with the test key")
    func signsWithTheGivenIdentity() async throws {
        let run = try makeRun()
        defer { try? FileManager.default.removeItem(at: run.root) }
        let runner = run.runner
        let context = TestFixtures.context(repository: Repository(root: run.root), runner: runner)
        try await UpdateCheckStep.run(context, identity: "Developer ID", effects: run.effects())
        let signing = runner.recorded.filter {
            $0.executable == SystemProgram.codesign && $0.arguments.first == "--force"
        }
        // Ten test apps: five Sparkle parts with the release signer, then the app.
        #expect(signing.count == 60 && signing.allSatisfy { $0.arguments.contains("Developer ID") })
        let autoupdate = signing.map(\.arguments).filter { $0.last?.hasSuffix("/Autoupdate") == true }
        #expect(autoupdate.count == 10)
        #expect(autoupdate.allSatisfy { $0.contains("org.sparkle-project.Sparkle.Autoupdate") })
        let sparkle = runner.recorded.filter { $0.executable.lastPathComponent == "sign_update" }
        #expect(sparkle.count == 10 && sparkle.allSatisfy { $0.arguments.first == "--ed-key-file" })
    }

    @Test("A broken expectation fails the check, and the record names the case")
    func recordsAFailedCase() async throws {
        let run = try makeRun(overrides: [.success: ["pid:101", "launched:1", "quit-approved:1", "quit-approved:2"]])
        defer { try? FileManager.default.removeItem(at: run.root) }
        let context = TestFixtures.context(repository: Repository(root: run.root), runner: run.runner)
        await #expect(throws: DevFailure.self) {
            try await UpdateCheckStep.run(context, identity: "ID", effects: run.effects())
        }
        let record = try run.record()
        let failed = record.cases.filter { !$0.passed }
        #expect(record.result == "failed" && failed.map(\.name) == ["success"])
        #expect(failed.first?.detail.contains("Version 2 did not start.") == true)
        #expect(try run.leftovers().isEmpty)
    }

    @Test("A case that never ends fails after the bounded wait")
    func boundedWait() async throws {
        let run = try makeRun(overrides: [.noUpdate: ["pid:101", "launched:1"]])
        defer { try? FileManager.default.removeItem(at: run.root) }
        let context = TestFixtures.context(repository: Repository(root: run.root), runner: run.runner)
        await #expect(throws: DevFailure.self) {
            try await UpdateCheckStep.run(context, identity: "ID", effects: run.effects())
        }
        let detail = try run.record().cases.first { $0.name == "no-update" }?.detail ?? ""
        #expect(detail.contains("did not end within 60 s"))
        #expect(run.clock.now().timeIntervalSince(FakeHarnessClock.start) >= 60)
    }

    @Test("Without the resolved Sparkle package the check asks for ./dev build")
    func needsSparkle() async throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let context = TestFixtures.context(repository: Repository(root: root))
        let effects = UpdateCheckEffects(
            clock: FakeHarnessClock(), inspector: FakeProcessInspector(), makeServer: { FakeFileServer() }, home: root)
        await #expect(throws: DevFailure.self) {
            try await UpdateCheckStep.run(context, identity: "ID", effects: effects)
        }
        do {
            try UpdateCheckStep.requireSparkle(
                UpdateFixturePlan(repository: Repository(root: root), toolchain: TestFixtures.toolchain))
        } catch let failure as DevFailure {
            #expect(failure.status == .missingPrerequisite && failure.message.contains("./dev build"))
        }
    }
}
